import AppKit
import OnePlusUI
import SwiftData
import SwiftUI

struct ActivityView: View {
    @Query(sort: \TransferRecord.createdAt, order: .reverse) private var records: [TransferRecord]
    @State private var search = ""
    @State private var searchFocus = 0
    @State private var selection: Set<String> = []
    @State private var sortColumn = 0
    @State private var ascending = false
    @State private var details: TransferDetails?
    @State private var showDetails = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var visibleRecords: [TransferRecord] {
        records
            .filter {
                search.isEmpty
                    || $0.sourceDisplay.localizedCaseInsensitiveContains(search)
                    || $0.destinationDisplay.localizedCaseInsensitiveContains(search)
                    || $0.operation.displayName.localizedCaseInsensitiveContains(search)
                    || $0.state.displayName.localizedCaseInsensitiveContains(search)
            }
            .sorted { left, right in
                let result: ComparisonResult = switch sortColumn {
                case 1: left.operation.displayName.localizedStandardCompare(right.operation.displayName)
                case 2: left.sourceDisplay.localizedStandardCompare(right.sourceDisplay)
                case 3: left.destinationDisplay.localizedStandardCompare(right.destinationDisplay)
                case 4: left.bytes == right.bytes ? .orderedSame : left.bytes < right.bytes ? .orderedAscending : .orderedDescending
                case 5: compare(left.duration ?? 0, right.duration ?? 0)
                case 6: left.state.displayName.localizedStandardCompare(right.state.displayName)
                default: left.createdAt.compare(right.createdAt)
                }
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
    }

    private func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }

    private var rows: [OnePlusTableItem] {
        visibleRecords.map {
            OnePlusTableItem(
                id: $0.id.uuidString,
                cells: [
                    Self.timeFormatter.string(from: $0.createdAt),
                    $0.operation.displayName,
                    $0.sourceDisplay,
                    $0.destinationDisplay,
                    RcloneFormat.bytes($0.bytes),
                    RcloneFormat.duration($0.duration),
                    $0.state.displayName
                ],
                symbol: $0.state.icon
            )
        }
    }

    var body: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(
                title: "Activity",
                subtitle: "\(records.count) transfers · \(RcloneFormat.bytes(records.reduce(0) { $0 + $1.bytes })) moved"
            ) {
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
                OnePlusCard {
                    OnePlusEmptyState("No activity yet", systemImage: "clock.arrow.circlepath")
                        .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            } else {
                OnePlusCard {
                    OnePlusNativeTable(
                        columns: [
                            OnePlusGridColumn("Time", width: 140),
                            OnePlusGridColumn("Operation", width: 88),
                            OnePlusGridColumn("Source", width: 200),
                            OnePlusGridColumn("Destination", width: 200),
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
                        remove: { _ in },
                        actions: actions
                    )
                }
                .frame(maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showDetails) {
            if let details { TransferInfoSheet(details: details) }
        }
        .background { Button("") { searchFocus &+= 1 }.keyboardShortcut("f").hidden() }
        .accessibilityIdentifier("rclone.activity")
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
