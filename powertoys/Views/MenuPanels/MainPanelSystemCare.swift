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
    @State private var manager = SystemCareManager.shared
    @Environment(\.onePlusIsVisible) private var isVisible
    @Binding var snapshot: SystemCareTraySnapshot
    let disk: SystemCareStartupDiskSnapshot?
    let diskLoaded: Bool
    @State private var expandedCategories = Set<SystemCareCategoryID>()
    @State private var confirmTrash = false
    @State private var startedScan = false

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            TrayToolHeader(tab: .systemCare)
            startupDiskSummary
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                Button(manager.hasCleanupScan ? "Scan Again" : "Scan for Cleanup", systemImage: "magnifyingglass") {
                    startedScan = true
                    manager.scanCleanup(categories: Set(SystemCareCategoryID.allCases))
                }
                .buttonStyle(OnePlusButtonStyle(.primary, size: .small))
                .disabled(manager.isWorking)
                if manager.hasCleanupScan {
                    TrayQuietActionButton(title: "Clear Scan", symbol: "xmark.circle", disabled: manager.isWorking) {
                        manager.clearCleanupScan()
                        expandedCategories.removeAll()
                    }
                }
                if startedScan && manager.isWorking {
                    TrayQuietActionButton(title: "Cancel", symbol: "stop") { manager.cancel() }
                }
                Spacer(minLength: 0)
                if manager.isWorking {
                    ProgressView().controlSize(.small)
                }
            }


            if manager.isWorking {
                Text(manager.progressMessage ?? "Analyzing cleanup locations…")
                    .onePlusText(.caption)

            }
            if let error = manager.errorMessage {
                Text(error)
                    .onePlusText(.caption, color: OnePlusColor.danger)

            }

            if !manager.hasCleanupScan {
                Text("Scan to measure reclaimable storage").onePlusText(.caption)
            } else if manager.cleanupCandidates.isEmpty {
                Text("0 bytes reclaimable in the saved scan").onePlusText(.caption)
            } else if !snapshot.isPrepared {
                ProgressView("Preparing saved scan…")
            } else {
                cleanupSummary
                selectionBar
                ForEach(SystemCareCategoryID.allCases) { category in
                    categorySection(category)
                }
            }
        }

        .confirmationDialog("Move selected items to Trash?", isPresented: $confirmTrash) {
            Button("Move \(manager.selectedCandidateIDs.count) Items to Trash", role: .destructive) {
                manager.moveSelectedToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Self.bytes(manager.selectedSize)) will remain recoverable in macOS Trash.")
        }
        .onDisappear {
            if startedScan && manager.isWorking { manager.cancel() }
        }
        .onChange(of: isVisible) {
            if !isVisible && startedScan && manager.isWorking { manager.cancel() }
        }
        .onChange(of: manager.isWorking) {
            if !manager.isWorking { startedScan = false }
        }
        .task(id: manager.cleanupCandidates) {
            let candidates = manager.cleanupCandidates
            let prepared = await Task.detached(priority: .utility) { SystemCareTraySnapshot.prepare(candidates) }.value
            guard !Task.isCancelled else { return }
            snapshot = prepared
        }
    }

    private var startupDiskSummary: some View {
        OnePlusMenuCard(textured: true) {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack {
                    Label("Startup disk", systemImage: "internaldrive").onePlusText(.caption)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    Text(disk.map { Self.bytes($0.capacity) } ?? (diskLoaded ? "Unavailable" : "Loading…"))
                        .onePlusText(.mono)
                }
                OnePlusSegmentBar(values: disk.map { [Double($0.used), Double($0.purgeable ?? 0), Double($0.free)] } ?? [],
                                  colors: [OnePlusColor.dataBlue, OnePlusColor.warn, OnePlusColor.ok])
                HStack(spacing: OnePlusMenuMetrics.tileGap) {
                    diskValue("Used", bytes: disk?.used, color: OnePlusColor.dataBlue)
                    diskValue("Purgeable", bytes: disk?.purgeable, color: OnePlusColor.warn)
                        .help("Space macOS can make available when needed")
                    diskValue("Free", bytes: disk?.free, color: OnePlusColor.ok)
                }
            }
        }
    }

    private func diskValue(_ title: String, bytes: Int64?, color: Color) -> some View {
        HStack(spacing: OnePlusMetrics.navRowGap) {
            Text(title).onePlusText(.caption, color: color)
            Text(bytes.map { Self.bytes($0) } ?? "—").onePlusText(.mono)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cleanupSummary: some View {
        OnePlusMenuCard(textured: true) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                        Text("Reclaimable storage").onePlusText(.caption)
                        Text(Self.bytes(snapshot.totalSize)).onePlusText(.metric, color: OnePlusColor.warn)
                    }
                    Spacer()
                    Text("\(manager.cleanupCandidates.count) items").onePlusText(.caption)
                }
                OnePlusSegmentBar(values: snapshot.totals.map { Double($0.size) },
                                  colors: snapshot.totals.map { categoryColor($0.category) })
                ForEach(snapshot.totals, id: \.category) { item in
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Image(systemName: item.category.icon).foregroundStyle(categoryColor(item.category))
                        Text(item.category.title)
                        Spacer()
                        Text(Self.bytes(item.size)).monospacedDigit()
                    }.onePlusText(.caption)
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: OnePlusMenuMetrics.tileGap) {
            Button("Move to Trash", systemImage: "trash") { confirmTrash = true }
                .buttonStyle(OnePlusButtonStyle(.destructive, size: .small))
                .disabled(manager.selectedCandidateIDs.isEmpty)
            Button("Select All") {
                manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: true)
            }
            .buttonStyle(OnePlusButtonStyle(.link, size: .small, horizontalPadding: 0))
            Button("Select None") {
                manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: false)
            }
            .buttonStyle(OnePlusButtonStyle(.link, size: .small, horizontalPadding: 0))
            Spacer(minLength: 0)
            Text("\(manager.selectedCandidateIDs.count) selected · \(Self.bytes(manager.selectedSize))")
                .onePlusText(.caption).monospacedDigit().lineLimit(1)
                .help("\(manager.selectedCandidateIDs.count) selected · \(Self.bytes(manager.selectedSize))")
        }
        .disabled(manager.isWorking)
    }

    private func categorySection(_ category: SystemCareCategoryID) -> some View {
        let rows = snapshot.groups[category] ?? []
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Button {
                            if expandedCategories.contains(category) { expandedCategories.remove(category) }
                            else { expandedCategories.insert(category) }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "chevron.right")
                                    .onePlusText(.caption)
                                    .rotationEffect(.degrees(expandedCategories.contains(category) ? 90 : 0))
                                    .frame(width: OnePlusMetrics.compactControlHeight, height: OnePlusMetrics.compactControlHeight)
                                Image(systemName: category.icon).onePlusText(.row, color: categoryColor(category))
                                Text(category.title).onePlusText(.row).lineLimit(1).help("\(category.title): \(category.detail)")
                                Spacer(minLength: OnePlusMenuMetrics.tileGap)
                                Text("\(rows.count)").onePlusText(.caption).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.controlRadius))
                        .accessibilityLabel(expandedCategories.contains(category) ? "Collapse \(category.title)" : "Expand \(category.title)")
                        Toggle("Select \(category.title)", isOn: Binding(
                            get: { rows.allSatisfy { manager.selectedCandidateIDs.contains($0.id) } },
                            set: { manager.setCandidates(Set(rows.map(\.id)), selected: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    .padding(OnePlusMenuMetrics.bodyInset)
                    .onePlusRowHover(radius: OnePlusMetrics.menuTileRadius)
                    if expandedCategories.contains(category) {
                        LazyVStack(spacing: 2) {
                            ForEach(rows) { row in
                                Toggle(isOn: Binding(
                                    get: { manager.selectedCandidateIDs.contains(row.id) },
                                    set: { manager.setCandidate(row.id, selected: $0) }
                                )) {
                                    HStack(spacing: 6) {
                                        Text(row.candidate.name).onePlusText(.caption, color: OnePlusColor.ink)
                                            .lineLimit(1).truncationMode(.middle).help(row.candidate.url.path)
                                        Spacer(minLength: 4)
                                        Text(row.size)
                                            .onePlusText(.caption)
                                            .monospacedDigit()
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .padding(.leading, 29)
                                .padding(.vertical, 2)
                                .onePlusRowHover(radius: OnePlusMetrics.controlRadius)
                            }
                        }
                        .padding(.horizontal, OnePlusMenuMetrics.bodyInset)
                        .padding(.bottom, OnePlusMenuMetrics.bodyInset)
                    }
                }
                .disabled(manager.isWorking)
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

    private static func bytes(_ value: Int64) -> String {
        TrayPopoverLayout.diskBytes(value)
    }
}
