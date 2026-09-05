//
//  DevSyncPage.swift
//  powertoys
//

import SwiftUI

enum DevSyncFormat {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relative(_ date: Date?, fallback: String = "Never") -> String {
        guard let date else { return fallback }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func count(_ value: Int, singular: String, plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

enum DevSyncSidebarBadge {
    static func text(_ count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}

struct DevSyncSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .utilitySectionHeader()
    }
}

struct DevSyncStateBadge: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

struct DevSyncIconButton: View {
    let icon: String
    let label: String
    var tint: Color = .secondary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .utilityAnimation(value: isHovering)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

struct DevSyncValueRow: View {
    let label: String
    let value: String
    var icon: String?
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                }
                Text(value)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Page

struct DevSyncPage: View {
    var manager: DevSyncManager = .shared

    var body: some View {
        @Bindable var manager = manager

        return Group {
            if let pair = manager.selectedPair {
                if manager.isShowingPairSettings {
                    DevSyncPairSettingsPage(pair: pair, manager: manager)
                } else {
                    DevSyncPairPage(pair: pair, manager: manager)
                }
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .utilityAnimation(value: manager.isShowingPairSettings)
        .sheet(isPresented: $manager.isPresentingSetup) {
            DevSyncSetupSheet()
        }
        .task { await manager.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            EmptyStateView(icon: "externaldrive.badge.plus", message: "No Dev Sync pair yet")
            Button {
                manager.isPresentingSetup = true
            } label: {
                Label("Set Up Dev Sync", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pair page

private struct DevSyncPairPage: View {
    @State private var isConfirmingRemoval = false

    let pair: DevSyncPair
    let manager: DevSyncManager

    private var status: DevPairStatus { manager.status(for: pair.id) }
    private var unresolvedConflicts: [DevConflict] { manager.unresolvedConflicts(for: pair.id) }

    private var subtitle: String {
        [
            status.state.displayName,
            "\(pair.externalRoot.volumeName.isEmpty ? "External drive" : pair.externalRoot.volumeName) \(status.volumeOnline ? "online" : "offline")",
            "synced \(DevSyncFormat.relative(status.lastSuccessAt, fallback: "never"))"
        ].joined(separator: " · ")
    }

    var body: some View {
        WorkspacePage(pair.displayName, subtitle: subtitle) {
            DevSyncPairActions(pair: pair, manager: manager, isConfirmingRemoval: $isConfirmingRemoval)
        } content: {
            if let banner = manager.errorBanner {
                DevSyncErrorBanner(message: banner) { manager.errorBanner = nil }
            }

            DevSyncStatusCard(pair: pair, status: status)

            DevSyncSectionHeader(title: "Projects")
            projectList

            if !unresolvedConflicts.isEmpty {
                DevSyncSectionHeader(title: "Conflicts")
                ForEach(unresolvedConflicts) { conflict in
                    DevSyncConflictCard(pair: pair, conflict: conflict, manager: manager)
                }
            }

            DevSyncSectionHeader(title: "Safety")
            safetyCard
        }
        .confirmationDialog("Remove \"\(pair.displayName)\"?", isPresented: $isConfirmingRemoval) {
            Button("Remove Pair, Keep Safety Store", role: .destructive) {
                Task { await manager.removePair(pairID: pair.id, deleteSafetyStore: false) }
            }
            Button("Remove Pair and Delete Safety Store", role: .destructive) {
                Task { await manager.removePair(pairID: pair.id, deleteSafetyStore: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing the pair stops syncing and keeps every project file on both drives. The safety store holds retained versions and conflict copies in .cloudsync-system on the external drive.")
        }
    }

    @ViewBuilder
    private var projectList: some View {
        let projects = manager.projects(for: pair.id)
        if projects.isEmpty {
            Text("No projects discovered yet.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            let groups = DevSyncProjectGrouping.groups(projects)
            ForEach(groups) { group in
                if !group.title.isEmpty {
                    DevSyncSectionHeader(title: group.title)
                }
                ForEach(group.projects) { project in
                    DevSyncProjectRow(pair: pair, project: project, manager: manager)
                }
            }
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DevSyncValueRow(label: "Safety store", value: RcloneFormat.bytes(status.safetyStoreBytes))
            HStack {
                Text(manager.safetyStoreURL(for: pair).path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Open Safety Store") {
                    manager.reveal(manager.safetyStoreURL(for: pair))
                }
                .controlSize(.small)
            }
        }
        .utilitySectionCard()
    }
}

// MARK: - Actions

private struct DevSyncPairActions: View {
    let pair: DevSyncPair
    let manager: DevSyncManager
    @Binding var isConfirmingRemoval: Bool

    private var status: DevPairStatus { manager.status(for: pair.id) }
    private var isPaused: Bool { status.state == .paused }

    var body: some View {
        @Bindable var manager = manager

        if manager.pairs.count > 1 {
            Picker("Pair", selection: $manager.selectedPairID) {
                ForEach(manager.pairs) { pair in
                    Text(pair.displayName).tag(Optional(pair.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            .accessibilityLabel("Selected pair")
        }

        Button("Sync Now") {
            Task { await manager.syncNow(pairID: pair.id) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!status.volumeOnline)

        Button(isPaused ? "Resume" : "Pause") {
            Task {
                if isPaused {
                    await manager.resume(pairID: pair.id)
                } else {
                    await manager.pause(pairID: pair.id)
                }
            }
        }

        Menu {
            Button("Preview Pending") { Task { await manager.previewPending(pairID: pair.id) } }
            Button("Verify Now") { Task { await manager.verifyNow(pairID: pair.id) } }
            Divider()
            Button("Open External Root") { manager.open(manager.externalRootURL(for: pair)) }
            Button("Open Safety Store") { manager.reveal(manager.safetyStoreURL(for: pair)) }
            Button("Repair Links") { Task { await manager.repairLinks(pairID: pair.id) } }
            Divider()
            Button("Pair Settings") { manager.isShowingPairSettings = true }
            Button("Remove Pair…", role: .destructive) { isConfirmingRemoval = true }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More Dev Sync actions")
        .accessibilityLabel("More Dev Sync actions")
    }
}

// MARK: - Status card

private struct DevSyncStatusCard: View {
    let pair: DevSyncPair
    let status: DevPairStatus

    private let columns = [
        GridItem(.flexible(minimum: 160), spacing: 20, alignment: .leading),
        GridItem(.flexible(minimum: 160), spacing: 20, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                DevSyncValueRow(
                    label: "Drive",
                    value: status.volumeOnline ? "Online" : "Offline",
                    icon: status.volumeOnline ? "externaldrive.fill" : "externaldrive.badge.xmark",
                    tint: status.volumeOnline ? .green : .orange
                )
                DevSyncValueRow(
                    label: "Phase",
                    value: status.phaseDetail ?? status.state.displayName,
                    icon: status.state.icon,
                    tint: status.state.tint
                )
                DevSyncValueRow(label: "Last sync", value: DevSyncFormat.relative(status.lastSuccessAt))
                DevSyncValueRow(label: "Next checkpoint", value: DevSyncFormat.relative(status.nextCheckpointAt, fallback: "On change"))
                DevSyncValueRow(
                    label: "Pending",
                    value: "\(DevSyncFormat.count(status.pendingProjectCount, singular: "project", plural: "projects")) · \(RcloneFormat.bytes(status.pendingBytes))"
                )
                DevSyncValueRow(label: "Written today", value: RcloneFormat.bytes(status.bytesWrittenToday))
                DevSyncValueRow(
                    label: "Conflicts",
                    value: "\(status.conflictCount)",
                    icon: status.conflictCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle",
                    tint: status.conflictCount > 0 ? .red : .green
                )
                DevSyncValueRow(
                    label: "Drift",
                    value: "\(status.driftCount)",
                    icon: status.driftCount > 0 ? "arrow.triangle.branch" : "checkmark.circle",
                    tint: status.driftCount > 0 ? .orange : .green
                )
                DevSyncValueRow(label: "Safety store", value: RcloneFormat.bytes(status.safetyStoreBytes))
                DevSyncValueRow(label: "rsync", value: status.rsyncSummary ?? "Not checked")
            }

            if let fraction = status.progressFraction {
                DevSyncProgressCapsule(fraction: fraction, tint: status.state.tint)
                    .frame(height: 6)
                    .accessibilityLabel("Sync progress")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            }

            if let error = status.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .utilitySectionCard()
        .utilityAnimation(value: status)
    }
}

struct DevSyncProgressCapsule: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
    }
}

struct DevSyncErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red.opacity(0.9))
                .textSelection(.enabled)
            Spacer()
            DevSyncIconButton(icon: "xmark", label: "Dismiss", action: dismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
    }
}

#Preview {
    DevSyncPage(manager: DevSyncPreviewFixture.manager())
        .frame(width: 760, height: 720)
}

struct DevSyncProjectGrouping: Identifiable {
    var title: String
    var projects: [DevProject]
    var id: String { title }

    static func groups(_ projects: [DevProject]) -> [DevSyncProjectGrouping] {
        var order: [String] = []
        var byTitle: [String: [DevProject]] = [:]
        for project in projects {
            let title = project.isRootUnit ? "" : (project.relativePath.split(separator: "/").count > 1 ? String(project.relativePath.split(separator: "/")[0]) : "")
            if byTitle[title] == nil { order.append(title) }
            byTitle[title, default: []].append(project)
        }
        let sorted = order.sorted { left, right in
            if left.isEmpty != right.isEmpty { return left.isEmpty }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
        return sorted.map { title in
            DevSyncProjectGrouping(title: title, projects: (byTitle[title] ?? []).sorted { left, right in
                if left.isRootUnit != right.isRootUnit { return left.isRootUnit }
                return left.relativePath.localizedStandardCompare(right.relativePath) == .orderedAscending
            })
        }
    }
}
