import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusTableTests: XCTestCase {
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
        let primary = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        let action = try XCTUnwrap(table.view(atColumn: 2, row: 0, makeIfNecessary: true) as? NSButton)
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
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
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
