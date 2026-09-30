import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusTableTests: XCTestCase {
    func testLiveUpdatesReloadOnlyChangedVisibleCellsAndKeepSelectionAndActions() throws {
        var selection: Set<String> = ["1"]
        var opened: Set<String> = []
        func view(_ rows: [OnePlusTableItem], ascending: Bool = true) -> OnePlusNativeTable {
            OnePlusNativeTable(columns: [.init("Name", width: 200), .init("Size", width: 100)], rows: rows,
                selection: Binding(get: { selection }, set: { selection = $0 }), ascending: ascending,
                sort: { _, _ in }, open: { opened = $0 }, preview: { _ in }, remove: { _ in },
                actions: { ids in [.init("Open") { opened = ids }] })
        }
        var rows = (0..<1000).map { OnePlusTableItem(id: String($0), cells: ["File \($0)", "1 MB"], symbol: "doc") }
        let coordinator = view(rows).makeCoordinator()
        let table = ReloadCountingTable(frame: CGRect(x: 0, y: 0, width: 340, height: 100))
        table.dataSource = coordinator
        for index in 0..<3 {
            let column = NSTableColumn(identifier: .init(index == 2 ? "actions" : String(index)))
            column.width = index == 0 ? 200 : 100
            table.addTableColumn(column)
        }
        coordinator.update(view(rows), in: table, density: .regular)
        let fullReloads = table.fullReloads
        rows[1] = .init(id: "1", cells: ["File 1", "2 MB"], symbol: "doc")
        rows[900] = .init(id: "900", cells: ["File 900", "9 MB"], symbol: "doc")
        coordinator.update(view(rows), in: table, density: .regular)
        XCTAssertEqual(table.fullReloads, fullReloads)
        XCTAssertEqual(table.cellReloads.count, 1)
        XCTAssertEqual(table.cellReloads.first?.0, IndexSet(integer: 1))
        XCTAssertEqual(table.cellReloads.first?.1, IndexSet(integer: 1))
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 1))
        XCTAssertEqual(selection, ["1"])
        let menu = try XCTUnwrap(coordinator.menu(["1"]))
        let action = try XCTUnwrap(menu.items.first)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(action.action), to: action.target, from: action))
        XCTAssertEqual(opened, ["1"])
        coordinator.update(view(rows), in: table, density: .regular)
        XCTAssertEqual(table.cellReloads.count, 1)
        coordinator.update(view(rows, ascending: false), in: table, density: .regular)
        XCTAssertEqual(table.fullReloads, fullReloads + 1)
        coordinator.update(view(rows.reversed()), in: table, density: .regular)
        XCTAssertEqual(table.fullReloads, fullReloads + 2)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 998))
        coordinator.update(view(Array(rows.dropLast())), in: table, density: .regular)
        XCTAssertEqual(table.fullReloads, fullReloads + 3)
    }
    func testHeaderLabelsAndCellTextShareEachAlignmentOrigin() throws {
        let columns: [OnePlusGridColumn] = [
            .init("Name", width: 180),
            .init("State", width: 120, alignment: .center),
            .init("Size", width: 100, alignment: .trailing)
        ]
        let host = NSHostingView(rootView: OnePlusNativeTable(
            columns: columns,
            rows: [.init(id: "1", cells: ["Workstation", "Ready", "42 MB"], symbol: "desktopcomputer")],
            selection: .constant([]), sort: { _, _ in }, open: { _ in }, preview: { _ in },
            remove: { _ in }, actions: { _ in [] }
        ).frame(width: 480, height: 100))
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 480, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(findTable(in: host))
        for index in columns.indices {
            let column = table.tableColumns[index]
            let header = try XCTUnwrap(column.headerCell as? OnePlusTableHeaderCell)
            let cell = try XCTUnwrap(table.view(atColumn: index, row: 0, makeIfNecessary: true) as? NSTableCellView)
            cell.layoutSubtreeIfNeeded()
            let text = try XCTUnwrap(cell.textField)
            let textFrame = text.convert(text.bounds, to: table)
            let headerBounds = try XCTUnwrap(table.headerView).headerRect(ofColumn: index)
            let headerFrame = header.labelRect(for: headerBounds)
            switch columns[index].alignment {
            case .leading: XCTAssertEqual(headerFrame.minX, textFrame.minX, accuracy: 0.5)
            case .center: XCTAssertEqual(headerFrame.midX, textFrame.midX, accuracy: 0.5)
            case .trailing: XCTAssertEqual(headerFrame.maxX, textFrame.maxX, accuracy: 0.5)
            }
        }
    }

    func testNativeTableCellsHaveReuseIdentifiersWithoutRowTooltips() throws {
        let rows = [OnePlusTableItem(id: "1", cells: ["Workstation", "Apple"], symbol: "desktopcomputer")]
        let tableView = OnePlusNativeTable(
            columns: [.init("Name", width: 180), .init("Vendor", width: 120)],
            rows: rows,
            selection: .constant([]),
            sort: { _, _ in },
            open: { _ in },
            preview: { _ in },
            remove: { _ in },
            actions: { _ in [] }
        )
        let host = NSHostingView(rootView: tableView.frame(width: 380, height: 100))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        func find(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let table = try XCTUnwrap(find(host))
        let row = try XCTUnwrap(table.rowView(atRow: 0, makeIfNecessary: true))
        let primary = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        let action = try XCTUnwrap(table.view(atColumn: 2, row: 0, makeIfNecessary: true) as? NSButton)
        XCTAssertEqual(row.identifier?.rawValue, "OnePlusNativeTable.row")
        XCTAssertEqual(primary.identifier?.rawValue, "OnePlusNativeTable.primary")
        XCTAssertEqual(action.identifier?.rawValue, "OnePlusNativeTable.action")
        XCTAssertNil(primary.textField?.toolTip)
        XCTAssertNil(action.toolTip)
        XCTAssertEqual(action.accessibilityLabel(), "File actions")
    }

    func testSwiftUIOwnsTableStyleAndGridColorDuringRowUpdates() throws {
        let model = TableRows()
        let host = NSHostingView(rootView: UpdatingTable(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        func find(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        for count in [4, 3, 4, 2, 4] {
            model.rows = (1...count).reversed().map {
                OnePlusTableItem(id: String($0), cells: ["Workstation \($0)", "Apple", "Completed"], symbol: "doc")
            }
            let deadline = Date(timeIntervalSinceNow: 1)
            repeat {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                if let table = find(host), table.numberOfRows == count,
                   table.headerView is OnePlusTableHeaderView { break }
            } while Date() < deadline
            let table = try XCTUnwrap(find(host))
            XCTAssertEqual(table.numberOfRows, count)
            XCTAssertNotEqual(table.style, .plain, "Do not change SwiftUI's native style during row updates")
            XCTAssertNotEqual(table.gridColor, NSColor(OnePlusColor.lineSoft), "Custom gridColor breaks SwiftUI row creation")
            XCTAssertTrue(table.headerView is OnePlusTableHeaderView)
            let row = try XCTUnwrap(table.rowView(atRow: 0, makeIfNecessary: true))
            XCTAssertEqual(row.numberOfColumns, 3)
        }
    }

    func testSwiftUITableHeaders() throws {
        for density in OnePlusDensity.allCases {
        let rows = [OnePlusTableItem(id: "1", cells: ["Complete"], symbol: "doc")]
        let host = NSHostingView(rootView: HStack {
            Table(rows) { TableColumn("Unstyled", value: \.id) }.frame(width: 120, height: 160)
            Table(rows) {
                TableColumn("Completed", value: \.id).width(160)
            }.onePlusNativeTable().onePlusDensity(density).frame(width: 300, height: 160)
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 428, height: 160),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        func find(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.tableColumns.first?.title == "Completed" { return table }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let table = try XCTUnwrap(find(host))
        let column = try XCTUnwrap(table.tableColumns.first)
        let header = try XCTUnwrap(column.headerCell as? OnePlusTableHeaderCell)
        XCTAssertEqual(header.label.string, "COMPLETED")
        XCTAssertEqual((header.label.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 9)
        XCTAssertLessThan(header.cellSize.width, column.width)
        XCTAssertEqual(table.rowHeight, OnePlusTable.rowHeight(density))
        XCTAssertEqual(table.intercellSpacing, .zero)
        XCTAssertTrue(table.gridStyleMask.isEmpty)
        XCTAssertTrue(table.subviews.contains { $0 is OnePlusTableLines })
        XCTAssertTrue(table.headerView is OnePlusTableHeaderView)
        }
    }
}

@MainActor private final class ReloadCountingTable: NSTableView {
    var fullReloads = 0
    var cellReloads: [(IndexSet, IndexSet)] = []
    override func reloadData() { fullReloads += 1; super.reloadData() }
    override func reloadData(forRowIndexes rows: IndexSet, columnIndexes columns: IndexSet) {
        cellReloads.append((rows, columns))
        super.reloadData(forRowIndexes: rows, columnIndexes: columns)
    }
    override func rows(in rect: NSRect) -> NSRange { NSRange(location: 0, length: 3) }
}

@MainActor private func findTable(in view: NSView) -> NSTableView? {
    if let table = view as? NSTableView { return table }
    return view.subviews.lazy.compactMap { findTable(in: $0) }.first
}

@MainActor private final class TableRows: ObservableObject {
    @Published var rows: [OnePlusTableItem] = []
}

@MainActor private struct UpdatingTable: View {
    @ObservedObject var model: TableRows
    var body: some View {
        Table(model.rows) {
            TableColumn("Name") { Text($0.cells[0]) }
            TableColumn("MAC vendor") { Text($0.cells[1]) }
            TableColumn("Completed") { Text($0.cells[2]) }
        }.onePlusNativeTable().frame(width: 600, height: 200)
    }
}
