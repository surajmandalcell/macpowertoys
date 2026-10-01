//
//  DevSyncPage.swift
//  powertoys
//

import SwiftUI
import OnePlusUI

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
        OnePlusSectionTitle(title)
    }
}

struct DevSyncStateBadge: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .onePlusText(.caption)
            Text(title)
                .onePlusText(.caption)
        }
        .foregroundStyle(tint)

        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

struct DevSyncIconButton: View {
    let icon: String
    let label: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: icon).foregroundStyle(tint) }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .accessibilityLabel(label)
            .help(label)
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
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .onePlusText(.caption)
                }
                Text(value)
                    .onePlusText(.caption)
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
        .sheet(isPresented: $manager.isPresentingSetup) {
            DevSyncSetupSheet()
        }
        .sheet(item: $manager.previewPlan) { plan in
            OnePlusSheet("Pending Changes", width: .medium, close: { manager.previewPlan = nil }) {
                Text(plan.summary.primaryActionTitle).onePlusText(.cardTitle)
                if !plan.scanComplete {
                    Text("The scan is incomplete. Deletions are blocked.").onePlusText(.caption, color: OnePlusColor.warn)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if plan.actions.isEmpty {
                            Text("No pending changes.").onePlusText(.row)
                        }
                        ForEach(plan.actions) { action in
                            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                                Text(action.relativePath).onePlusText(.mono).lineLimit(1).truncationMode(.middle)
                                Text(action.reason).onePlusText(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                            .onePlusTableRow()
                        }
                    }
                }
                .onePlusScrollIndicators()
                .frame(height: OnePlusMetrics.spacing[8] * 12)
            } footer: {
                Button("Done") { manager.previewPlan = nil }
                    .buttonStyle(OnePlusButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task { await manager.loadIfNeeded() }
    }

    private var emptyState: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Dev Sync", subtitle: "Review every change before files move")
        } content: {
            OnePlusEmptyState("No Dev Sync pair yet", systemImage: "externaldrive.badge.plus", caption: "Pair an internal development folder with an external drive.") {
                Button {
                    manager.isPresentingSetup = true
                } label: {
                    Label("Set Up Dev Sync", systemImage: "plus")
                }
                .buttonStyle(OnePlusButtonStyle(.neutral))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Pair page

private struct DevSyncPairPage: View {
    @State private var isConfirmingRemoval = false

    let pair: DevSyncPair
    let manager: DevSyncManager

    private var status: DevPairStatus { manager.status(for: pair.id) }
    private var subtitle: String {
        [
            status.state.displayName,
            "\(pair.externalRoot.volumeName.isEmpty ? "External drive" : pair.externalRoot.volumeName) \(status.volumeOnline ? "online" : "offline")",
            "synced \(DevSyncFormat.relative(status.lastSuccessAt, fallback: "never"))"
        ].joined(separator: " · ")
    }

    var body: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: pair.displayName) {
                Text(subtitle).onePlusText(.caption).lineLimit(1).help(subtitle)
                DevSyncPairActions(pair: pair, manager: manager, isConfirmingRemoval: $isConfirmingRemoval)
            }
        } content: {
            if let banner = manager.errorBanner {
                DevSyncErrorBanner(message: banner) { manager.errorBanner = nil }
            }

            DevSyncStatusCard(pair: pair, status: status)

            DevSyncProjectsList(pair: pair, manager: manager)
                .frame(maxHeight: .infinity)

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

    private var safetyCard: some View {
        HStack(spacing: OnePlusMetrics.spacing[3]) {
            Text(manager.safetyStoreURL(for: pair).path)
                .onePlusText(.mono).lineLimit(1).truncationMode(.middle)
                .help(manager.safetyStoreURL(for: pair).path)
            Spacer(minLength: OnePlusMetrics.spacing[3])
            Text(RcloneFormat.bytes(status.safetyStoreBytes)).onePlusText(.mono)
            Button("Open Safety Store") { manager.reveal(manager.safetyStoreURL(for: pair)) }
                .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
        }
        .frame(height: OnePlusMetrics.settingRow)
    }
}

private struct DevSyncProjectsList: View {
    let pair: DevSyncPair
    let manager: DevSyncManager

    @State private var projection = DevSyncProjectsProjection.empty
    @State private var projectionTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DevSyncSectionHeader(title: "Projects")
                if projection.groups.isEmpty {
                    Text("No projects discovered yet.")
                        .onePlusText(.caption)
                        .foregroundStyle(OnePlusColor.secondary)
                } else {
                    ForEach(projection.groups) { group in
                        if !group.title.isEmpty {
                            DevSyncSectionHeader(title: group.title)
                        }
                        ForEach(group.projects) { project in
                            DevSyncProjectRow(pair: pair, project: project, manager: manager)
                        }
                    }
                }

                if !projection.conflicts.isEmpty {
                    DevSyncSectionHeader(title: "Conflicts")
                    ForEach(projection.conflicts) { conflict in
                        DevSyncConflictCard(pair: pair, conflict: conflict, manager: manager)
                    }
                }
            }
        }
        .onePlusScrollIndicators()
        .task(id: pair.id) { rebuildProjection() }
        .onChange(of: manager.projects(for: pair.id)) { rebuildProjection() }
        .onChange(of: manager.conflicts[pair.id] ?? []) { rebuildProjection() }
        .onChange(of: manager.focusedConflictProjectID) { rebuildProjection() }
        .onDisappear {
            projectionTask?.cancel()
            projectionTask = nil
        }
    }

    private func rebuildProjection() {
        projectionTask?.cancel()
        let projects = manager.projects(for: pair.id)
        let conflicts = manager.conflicts[pair.id] ?? []
        let focusedProjectID = manager.focusedConflictProjectID

        projectionTask = Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                DevSyncProjectsProjection.make(
                    projects: projects,
                    conflicts: conflicts,
                    focusedProjectID: focusedProjectID
                )
            }.value
            guard !Task.isCancelled else { return }
            projection = prepared
        }
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
            OnePlusSelect(
                choices: manager.pairs.map { (Optional($0.id), $0.displayName) },
                selection: $manager.selectedPairID,
                width: OnePlusMetrics.wideControlColumn,
                accessibilityLabel: "Selected pair"
            )
        }

        Button("Sync Now") {
            Task { await manager.syncNow(pairID: pair.id) }
        }
        .buttonStyle(OnePlusButtonStyle(.primary))
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

        OnePlusMenuButton("More Dev Sync actions", variant: .borderedIcon, items: [
            .item(.init("Preview Pending") { Task { await manager.previewPending(pairID: pair.id) } }),
            .item(.init("Verify Now") { Task { await manager.verifyNow(pairID: pair.id) } }),
            .separator(),
            .item(.init("Open External Root") { manager.open(manager.externalRootURL(for: pair)) }),
            .item(.init("Open Safety Store") { manager.reveal(manager.safetyStoreURL(for: pair)) }),
            .item(.init("Repair Links") { Task { await manager.repairLinks(pairID: pair.id) } }),
            .separator(),
            .item(.init("Pair Settings") { manager.isShowingPairSettings = true }),
            .item(.init("Remove Pair…", role: .destructive) { isConfirmingRemoval = true })
        ])
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
        OnePlusCard {
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[3]) {
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
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.warn)
                    .textSelection(.enabled)
            }
            }
            .padding(OnePlusMetrics.cardPadding)
        }
    }
}

struct DevSyncProgressCapsule: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(OnePlusColor.track)
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
                .foregroundStyle(OnePlusColor.danger)
            Text(message)
                .onePlusText(.row)
                .foregroundStyle(.red.opacity(0.9))
                .textSelection(.enabled)
            Spacer()
            DevSyncIconButton(icon: "xmark", label: "Dismiss", action: dismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(OnePlusColor.dangerFill))
    }
}

#Preview {
    DevSyncPage(manager: DevSyncPreviewFixture.manager())
        .frame(width: 760, height: 720)
}

nonisolated struct DevSyncProjectsProjection: Sendable {
    let groups: [DevSyncProjectGrouping]
    let conflicts: [DevConflict]

    static let empty = DevSyncProjectsProjection(groups: [], conflicts: [])

    static func make(
        projects: [DevProject],
        conflicts: [DevConflict],
        focusedProjectID: UUID?
    ) -> DevSyncProjectsProjection {
        DevSyncProjectsProjection(
            groups: DevSyncProjectGrouping.groups(projects),
            conflicts: conflicts
                .filter { !$0.isResolved }
                .sorted { left, right in
                    let leftFocused = left.projectID == focusedProjectID
                    let rightFocused = right.projectID == focusedProjectID
                    if leftFocused != rightFocused { return leftFocused }
                    return left.createdAt < right.createdAt
                }
        )
    }
}

nonisolated struct DevSyncProjectGrouping: Identifiable, Sendable {
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
