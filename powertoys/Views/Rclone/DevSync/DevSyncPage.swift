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
    static func count(_ count: Int) -> Int? {
        count > 0 ? count : nil
    }
}

struct DevSyncSectionHeader: View {
    let title: String

    var body: some View {
        OnePlusLinearSectionCaption(title)
    }
}

struct DevSyncStateBadge: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .linearText(OnePlusLinearMetrics.control, color: tint)
            Text(title)
                .linearText(OnePlusLinearMetrics.control, color: tint)
        }
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
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: OnePlusLinearMetrics.control))
                .foregroundStyle(tint)
                .frame(width: OnePlusLinearMetrics.appletRowAction, height: OnePlusLinearMetrics.appletRowAction)
        }
        .buttonStyle(OnePlusLinearButtonStyle())
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
                .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .linearText(OnePlusLinearMetrics.control, color: tint)
                }
                Text(value)
                    .linearText(OnePlusLinearMetrics.control, color: tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Page

struct DevSyncPage: View {
    var manager: DevSyncManager = .shared

    static func title(for manager: DevSyncManager) -> String {
        guard let pair = manager.selectedPair else { return "Dev Sync" }
        return manager.isShowingPairSettings ? "\(pair.displayName) Settings" : pair.displayName
    }

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
            OnePlusLinearSheet("Pending Changes", width: .medium, close: { manager.previewPlan = nil }) {
                Text(plan.summary.primaryActionTitle)
                    .font(.system(size: OnePlusLinearMetrics.body, weight: .semibold))
                    .foregroundStyle(OnePlusLinearColor.ink)
                if !plan.scanComplete {
                    Text("The scan is incomplete. Deletions are blocked.").linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.warning)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if plan.actions.isEmpty {
                            Text("No pending changes.").linearText()
                        }
                        ForEach(Array(zip(plan.actions.indices, plan.actions)), id: \.1.id) { index, action in
                            HStack(spacing: OnePlusLinearMetrics.appletActionGap) {
                                Text(action.relativePath)
                                    .font(.system(size: OnePlusLinearMetrics.control, design: .monospaced))
                                    .foregroundStyle(OnePlusLinearColor.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).help(action.relativePath)
                                Text(action.reason).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary).lineLimit(1).help(action.reason)
                            }
                            .onePlusTableRow(index: index)
                        }
                    }
                }
                .onePlusScrollIndicators()
                .frame(height: OnePlusLinearSpace.page * 12)
            } footer: {
                Button("Done") { manager.previewPlan = nil }
                    .buttonStyle(OnePlusLinearButtonStyle(.soft))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task { await manager.loadIfNeeded() }
    }

    private var emptyState: some View {
        RSyncFixedPane {
            OnePlusLinearEmptyState("No Dev Sync pair yet", systemImage: "externaldrive.badge.plus", message: "Pair an internal development folder with an external drive. Review every change before files move.") {
                Button {
                    manager.isPresentingSetup = true
                } label: {
                    Label("Set Up Dev Sync", systemImage: "plus")
                }
                .buttonStyle(OnePlusLinearButtonStyle(.soft))
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
        RSyncFixedPane {
            RSyncPageToolbar {
                LinearCaption(subtitle)
            } trailing: {
                DevSyncPairActions(pair: pair, manager: manager, isConfirmingRemoval: $isConfirmingRemoval)
            }

            if let banner = manager.errorBanner {
                DevSyncErrorBanner(message: banner) { manager.errorBanner = nil }
            }

            DevSyncStatusCard(pair: pair, status: status)

            DevSyncProjectsList(pair: pair, manager: manager)
                .frame(maxHeight: .infinity)

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
        OnePlusLinearAppletSection("Safety") {
            OnePlusLinearAppletRow(manager.safetyStoreURL(for: pair).path) {
                LinearCaption(RcloneFormat.bytes(status.safetyStoreBytes), monospaced: true)
                Button("Open Safety Store") { manager.reveal(manager.safetyStoreURL(for: pair)) }
                    .buttonStyle(OnePlusLinearButtonStyle(.soft))
            }
            .help(manager.safetyStoreURL(for: pair).path)
        }
    }
}

private struct DevSyncProjectsList: View {
    let pair: DevSyncPair
    let manager: DevSyncManager

    @State private var projection = DevSyncProjectsProjection.empty
    @State private var projectionTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OnePlusLinearEditorialMetrics.blockGap) {
                if projection.groups.isEmpty {
                    OnePlusLinearAppletSection("Projects") {
                        OnePlusLinearAppletRow("No projects discovered yet.") { EmptyView() }
                    }
                } else {
                    ForEach(projection.groups) { group in
                        OnePlusLinearAppletSection(group.title.isEmpty ? "Projects" : group.title) {
                            ForEach(group.projects) { project in
                                DevSyncProjectRow(pair: pair, project: project, manager: manager)
                            }
                        }
                    }
                }

                if !projection.conflicts.isEmpty {
                    VStack(alignment: .leading, spacing: OnePlusLinearSpace.group) {
                        Text("Conflicts")
                            .linearText(OnePlusLinearMetrics.control, weight: .semibold, color: OnePlusLinearColor.secondary)
                            .padding(.leading, OnePlusLinearMetrics.appletRowPadding)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(projection.conflicts) { conflict in
                            DevSyncConflictCard(pair: pair, conflict: conflict, manager: manager)
                        }
                    }
                }
            }
            .padding(.bottom, OnePlusLinearEditorialMetrics.bottom)
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
            OnePlusLinearSelect(
                choices: manager.pairs.map { (Optional($0.id), $0.displayName) },
                selection: $manager.selectedPairID,
                accessibilityLabel: "Selected pair",
                width: OnePlusLinearControlWidth.wide
            )
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

        Button(isPaused ? "Resume" : "Pause") {
            Task {
                if isPaused {
                    await manager.resume(pairID: pair.id)
                } else {
                    await manager.pause(pairID: pair.id)
                }
            }
        }
        .buttonStyle(OnePlusLinearButtonStyle(.soft))

        Button("Sync Now") {
            Task { await manager.syncNow(pairID: pair.id) }
        }
        .buttonStyle(OnePlusLinearButtonStyle(.soft))
        .disabled(!status.volumeOnline)
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
        OnePlusLinearAppletGroup {
            VStack(alignment: .leading, spacing: OnePlusLinearSpace.row) {
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
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.warning)
                    .textSelection(.enabled)
            }
            }
            .padding(OnePlusLinearMetrics.appletRowPadding)
        }
    }
}

struct DevSyncProgressCapsule: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(OnePlusLinearColor.barTrack)
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
        OnePlusLinearBanner(.error, title: message) {
            DevSyncIconButton(icon: "xmark", label: "Dismiss", action: dismiss)
        }
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
