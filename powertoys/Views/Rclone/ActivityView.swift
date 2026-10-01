import AppKit
import OnePlusUI
import SwiftData
import SwiftUI

nonisolated private struct ActivitySnapshot: Sendable {
    let id: String
    let createdAt: Date
    let operation: String
    let source: String
    let destination: String
    let bytes: Int64
    let duration: TimeInterval
    let state: String
    let symbol: String

    @MainActor init(_ record: TransferRecord) {
        id = record.id.uuidString
        createdAt = record.createdAt
        operation = record.operation.displayName
        source = record.sourceDisplay
        destination = record.destinationDisplay
        bytes = record.bytes
        duration = record.duration ?? 0
        state = record.state.displayName
        symbol = record.state.icon
    }
}

nonisolated private struct ActivityDisplayRow: Sendable {
    let id: String
    let cells: [String]
    let symbol: String
}

nonisolated private struct PreparedActivity: Sendable {
    let rows: [ActivityDisplayRow]
    let totalBytes: Int64
}

nonisolated private struct ActivityVersion: Equatable, Sendable {
    let count: Int
    let firstID: UUID?
}

struct ActivityView: View {
    @Environment(\.isEnabled) private var isEnabled
    @Query(sort: \TransferRecord.createdAt, order: .reverse) private var records: [TransferRecord]
    @State private var search = ""
    @State private var searchFocus = 0
    @State private var selection: Set<String> = []
    @State private var sortColumn = 0
    @State private var ascending = false
    @State private var details: TransferDetails?
    @State private var showDetails = false
    @State private var rows: [OnePlusTableItem] = []
    @State private var aggregateBytes: Int64 = 0
    @State private var projectionTask: Task<Void, Never>?

    private var recordVersion: ActivityVersion {
        ActivityVersion(count: records.count, firstID: records.first?.id)
    }

    var body: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(
                title: "Activity"
            ) {
                Text("\(records.count) transfers · \(RcloneFormat.bytes(aggregateBytes)) moved")
                    .onePlusText(.caption)
                OnePlusSearchField(
                    prompt: "Search activity",
                    text: $search,
                    width: OnePlusMetrics.wideControlColumn,
                    focusTrigger: searchFocus,
                    shortcutHint: "⌘F"
                )
            }
        } content: {
            if records.isEmpty {
                OnePlusEmptyState("No activity yet", systemImage: "clock.arrow.circlepath")
                    .frame(maxHeight: .infinity)
            } else {
                OnePlusCard {
                    OnePlusNativeTable(
                        columns: [
                            OnePlusGridColumn("Time", width: 176, textRole: .mono),
                            OnePlusGridColumn("Operation", width: 88),
                            OnePlusGridColumn("Source", width: 188, textRole: .mono, textColor: OnePlusColor.ink),
                            OnePlusGridColumn("Destination", width: 200, textRole: .mono),
                            OnePlusGridColumn("Size", width: 88, trailing: true),
                            OnePlusGridColumn("Duration", width: 88, trailing: true),
                            OnePlusGridColumn("Result", width: 108)
                        ],
                        rows: rows,
                        selection: $selection,
                        sortColumn: sortColumn,
                        ascending: ascending,
                        sort: { sortColumn = $0; ascending = $1 },
                        open: showDetails,
                        preview: showDetails,
                        actions: actions
                    )
                }
                .frame(maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showDetails) {
            if let details { TransferInfoSheet(details: details) }
        }
        .task { rebuildRows() }
        .onChange(of: recordVersion) { rebuildRows() }
        .onChange(of: search) { rebuildRows() }
        .onChange(of: sortColumn) { rebuildRows() }
        .onChange(of: ascending) { rebuildRows() }
        .onDisappear {
            projectionTask?.cancel()
            projectionTask = nil
        }
        .focusedSceneValue(\.appFind, showDetails || !isEnabled ? nil : AppCommandAction(title: "Find in Activity", perform: { searchFocus &+= 1 }))
        .accessibilityIdentifier("rclone.activity")
    }

    private func rebuildRows() {
        projectionTask?.cancel()
        let snapshots = records.map(ActivitySnapshot.init)
        let search = search
        let sortColumn = sortColumn
        let ascending = ascending

        projectionTask = Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.prepare(snapshots, search: search, sortColumn: sortColumn, ascending: ascending)
            }.value
            guard !Task.isCancelled else { return }
            rows = prepared.rows.map { OnePlusTableItem(id: $0.id, cells: $0.cells, symbol: $0.symbol) }
            aggregateBytes = prepared.totalBytes
        }
    }

    nonisolated private static func prepare(
        _ snapshots: [ActivitySnapshot],
        search: String,
        sortColumn: Int,
        ascending: Bool
    ) -> PreparedActivity {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d HH:mm")
        let filtered = snapshots.filter {
            search.isEmpty
                || $0.source.localizedCaseInsensitiveContains(search)
                || $0.destination.localizedCaseInsensitiveContains(search)
                || $0.operation.localizedCaseInsensitiveContains(search)
                || $0.state.localizedCaseInsensitiveContains(search)
        }
        let sorted = filtered.sorted { left, right in
            let result: ComparisonResult = switch sortColumn {
            case 1: left.operation.localizedStandardCompare(right.operation)
            case 2: left.source.localizedStandardCompare(right.source)
            case 3: left.destination.localizedStandardCompare(right.destination)
            case 4: compare(left.bytes, right.bytes)
            case 5: compare(left.duration, right.duration)
            case 6: left.state.localizedStandardCompare(right.state)
            default: left.createdAt.compare(right.createdAt)
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return PreparedActivity(
            rows: sorted.map {
                ActivityDisplayRow(
                    id: $0.id,
                    cells: [
                        formatter.string(from: $0.createdAt),
                        $0.operation,
                        $0.source,
                        $0.destination,
                        RcloneProjectionFormat.bytes($0.bytes),
                        RcloneProjectionFormat.duration($0.duration),
                        $0.state
                    ],
                    symbol: $0.symbol
                )
            },
            totalBytes: snapshots.reduce(0) { $0 + $1.bytes }
        )
    }

    nonisolated private static func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }

    private func record(for id: String) -> TransferRecord? {
        records.first { $0.id.uuidString == id }
    }

    private func showDetails(_ ids: Set<String>) {
        guard let id = ids.first, let record = record(for: id) else { return }
        details = TransferDetails(record: record)
        showDetails = true
    }

    private func actions(_ ids: Set<String>) -> [OnePlusTableAction] {
        guard let id = ids.first, let record = record(for: id) else { return [] }
        return [
            OnePlusTableAction("Transfer Info…") {
                details = TransferDetails(record: record)
                showDetails = true
            },
            OnePlusTableAction("Copy Row") {
                copy("\(record.operation.displayName) · \(record.sourceDisplay) → \(record.destinationDisplay) · \(record.state.displayName)")
            },
            OnePlusTableAction("Copy Source") { copy(record.sourceDisplay) },
            OnePlusTableAction("Copy Destination") { copy(record.destinationDisplay) }
        ]
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
