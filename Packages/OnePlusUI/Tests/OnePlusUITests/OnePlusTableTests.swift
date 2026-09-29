import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusTableTests: XCTestCase {
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
        XCTAssertEqual(table.gridColor, NSColor(OnePlusColor.lineSoft))
        XCTAssertTrue(table.gridStyleMask.isEmpty)
        XCTAssertTrue(table.subviews.contains { $0 is OnePlusTableLines })
        XCTAssertTrue(table.headerView is OnePlusTableHeaderView)
        }
    }
}
