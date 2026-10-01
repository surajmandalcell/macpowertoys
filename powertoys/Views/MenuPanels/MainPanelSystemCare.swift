import OnePlusUI
import SwiftUI

nonisolated struct SystemCareStartupDiskSnapshot: Sendable {
    let capacity: Int64
    let free: Int64
    let purgeable: Int64?
    var used: Int64 { capacity - free - (purgeable ?? 0) }

    init?(capacity: Int64, free: Int64, availableForImportantUsage: Int64?) {
        guard capacity > 0 else { return nil }
        self.capacity = capacity
        let boundedFree = min(max(free, 0), capacity)
        self.free = boundedFree
        purgeable = availableForImportantUsage.map { max(min(max($0, 0), capacity) - boundedFree, 0) }
    }

    static func load() -> Self? {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]), let capacity = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity else { return nil }
        return Self(capacity: Int64(capacity), free: Int64(free),
                    availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage)
    }
}

nonisolated struct SystemCareTraySnapshot: Sendable {
    var groups: [SystemCareCategoryID: [SystemCareCleanupRow]] = [:]
    var totals: [(category: SystemCareCategoryID, size: Int64)] = []
    var isPrepared = false
    var totalSize: Int64 { totals.reduce(0) { $0 + $1.size } }

    static func prepare(_ candidates: [CleanupCandidate]) -> Self {
        let groups = Dictionary(grouping: SystemCarePresentationRows.cleanup(candidates)) { $0.candidate.category }
        let totals = SystemCareCategoryID.allCases.compactMap { category -> (SystemCareCategoryID, Int64)? in
            guard let rows = groups[category] else { return nil }
            return (category, rows.reduce(0) { $0 + $1.candidate.size })
        }
        return Self(groups: groups, totals: totals, isPrepared: true)
    }
}

struct SystemCareTrayView: View {
    enum Region { case all, toolbar, rows, footer }
    @State private var manager = SystemCareManager.shared
    @Environment(\.onePlusIsVisible) private var isVisible
    @AppStorage("systemCare.defaultMode") private var savedMode = SystemCareMode.quick.rawValue
    @Binding var snapshot: SystemCareTraySnapshot
    let disk: SystemCareStartupDiskSnapshot?
    let diskLoaded: Bool
    var region: Region = .all
    @State private var expandedCategories = Set<SystemCareCategoryID>()
    @State private var confirmTrash = false
    @State private var startedScan = false

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            if region == .all || region == .toolbar { toolbar }
            if region == .all || region == .rows { rows }
            if region == .all || region == .footer { footer }
        }
        .confirmationDialog("Move selected items to Trash?", isPresented: $confirmTrash) {
            Button("Move \(manager.selectedCandidateIDs.count) Items to Trash", role: .destructive) {
                manager.moveSelectedToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Self.bytes(manager.selectedSize)) estimated. Items remain recoverable in macOS Trash.")
        }
        .onChange(of: isVisible) {
            if !isVisible && startedScan && manager.canCancel { manager.cancel() }
        }
        .onDisappear {
            if startedScan && manager.canCancel { manager.cancel() }
        }
        .onChange(of: manager.isWorking) { if !manager.isWorking { startedScan = false } }
        .task(id: manager.cleanupCandidates) {
            guard region == .all || region == .rows else { return }
            let candidates = manager.cleanupCandidates
            let prepared = await Task.detached(priority: .utility) { SystemCareTraySnapshot.prepare(candidates) }.value
            guard !Task.isCancelled else { return }
            snapshot = prepared
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            OnePlusMenuCard(textured: true) { SystemCareDiskSummary(disk: disk, loaded: diskLoaded) }
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Button(manager.hasCleanupScan ? "Rescan" : "Scan", systemImage: "arrow.clockwise") {
                    startedScan = true
                    manager.scanCleanup(categories: Set(SystemCareCategoryID.allCases))
                }
                .buttonStyle(OnePlusButtonStyle(manager.hasCleanupScan ? .neutral : .primary, size: .small))
                .disabled(manager.isWorking)
                Spacer(minLength: 0)
                if manager.hasCleanupScan {
                    Button("Clear Scan") { manager.clearCleanupScan() }
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small)).disabled(manager.isWorking)
                }
                if manager.canCancel {
                    Button(manager.isCancelling ? "Canceling…" : "Cancel") { manager.cancel() }
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small)).disabled(manager.isCancelling)
                }
            }
            if manager.isWorking {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(manager.progressMessage ?? "Working…").onePlusText(.caption)
                }
            }
            if let error = manager.errorMessage {
                Text(error).onePlusText(.caption, color: OnePlusColor.danger).textSelection(.enabled)
            }
            if manager.hasCleanupScan && !manager.cleanupCandidates.isEmpty {
                OnePlusMenuCard(textured: true) {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Cleanup candidates").onePlusText(.cardTitle)
                            Spacer()
                            Text("\(manager.cleanupCandidates.count) items / \(snapshot.totals.count) locations")
                                .onePlusText(.caption)
                        }
                        Text(snapshot.isPrepared ? Self.bytes(snapshot.totalSize) : "—")
                            .onePlusText(.metric)
                        OnePlusSegmentBar(values: snapshot.totals.map { Double($0.size) },
                                          colors: snapshot.totals.map { categoryColor($0.category) })
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if manager.cleanupScanOutcome != nil || manager.hasCleanupScan {
            SystemCareScanCoverage(manager: manager)
        }
        if !manager.hasCleanupScan {
            Text(manager.cleanupScanOutcome == nil ? "Scan to review cleanup candidates." : "No saved scan. Retry to review these locations.").onePlusText(.caption)
        } else if manager.cleanupCandidates.isEmpty {
            Text(manager.cleanupScanOutcome == .completed ? "No items in these locations." : "No candidates in retained results. Review scan coverage.").onePlusText(.caption)
        } else {
            OnePlusMenuCard(padded: false) {
                HStack {
                    Text("Review selection").onePlusText(.cardTitle)
                    Spacer()
                    Button("All") { manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: true) }
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    Button("None") { manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: false) }
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                }.padding(.horizontal, OnePlusMenuMetrics.bodyInset).disabled(manager.isWorking)
                ForEach(SystemCareCategoryID.allCases) { category in categorySection(category) }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if manager.hasCleanupScan && !manager.cleanupCandidates.isEmpty {
            HStack {
                Text("\(Self.bytes(manager.selectedSize)) selected").onePlusText(.caption)
                Spacer(minLength: OnePlusMetrics.spacing[1])
                Button("Move to Trash", systemImage: "trash") { confirmTrash = true }
                    .buttonStyle(OnePlusButtonStyle(.destructive, size: .small))
                    .disabled(manager.isWorking || manager.selectedCandidateIDs.isEmpty || savedMode == SystemCareMode.analysis.rawValue)
                    .help(savedMode == SystemCareMode.analysis.rawValue ? "Analysis Only disables removal." : "Move reviewed items to Trash.")
            }
        }
        if let result = manager.lastTrashResult {
            HStack {
                Text("\(result.movedCount) moved to Trash, estimated").onePlusText(.caption)
                Spacer()
                Text(Self.bytes(result.movedBytes)).onePlusText(.mono)
            }
            if !result.failures.isEmpty {
                HStack {
                    SystemCareTrashFailures(failures: result.failures)
                    Spacer()
                    Button("Retry Failed Items") { confirmTrash = true }
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                        .disabled(manager.isWorking || manager.selectedCandidateIDs.isEmpty || savedMode == SystemCareMode.analysis.rawValue)
                }
            }
        }
    }

    private func categorySection(_ category: SystemCareCategoryID) -> some View {
        let rows = snapshot.groups[category] ?? []
        let total = snapshot.totals.first { $0.category == category }?.size ?? 0
        return Group {
            if !rows.isEmpty {
                HStack(spacing: OnePlusMetrics.spacing[1]) {
                    Button {
                        if expandedCategories.contains(category) { expandedCategories.remove(category) }
                        else { expandedCategories.insert(category) }
                    } label: {
                        Image(systemName: expandedCategories.contains(category) ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .help("Expand or collapse \(category.title)")
                    .accessibilityLabel("Expand or collapse \(category.title)")
                    Toggle("Select \(category.title)", isOn: Binding(
                        get: { rows.allSatisfy { manager.selectedCandidateIDs.contains($0.id) } },
                        set: { manager.setCandidates(Set(rows.map(\.id)), selected: $0) }
                    ))
                    .labelsHidden().toggleStyle(OnePlusCheckboxStyle()).disabled(manager.isWorking)
                    Text(category.title).onePlusText(.row).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(String(rows.count)).onePlusText(.caption)
                    Text(Self.bytes(total)).onePlusText(.mono)
                }
                .padding(.horizontal, OnePlusMenuMetrics.bodyInset)
                .frame(height: OnePlusMenuMetrics.tab + OnePlusMetrics.spacing[1])
                .onePlusRowHover()
                if expandedCategories.contains(category) {
                    ForEach(rows) { row in SystemCareCandidateRow(row: row, manager: manager) }
                }
            }
        }
    }

    private func categoryColor(_ category: SystemCareCategoryID) -> Color {
        switch category {
        case .caches: OnePlusColor.dataBlue
        case .logs: OnePlusColor.ok
        case .installers: OnePlusColor.warn
        case .developer: OnePlusColor.accent
        }
    }

    private static func bytes(_ value: Int64) -> String { TrayPopoverLayout.diskBytes(value) }
}
