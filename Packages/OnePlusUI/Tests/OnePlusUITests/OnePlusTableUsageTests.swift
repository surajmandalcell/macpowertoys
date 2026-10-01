import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusTableUsageTests: XCTestCase {
    func testUsageCellKeepsBytesAndReloadsWhenOnlyShareChanges() throws {
        func view(_ value: Double?) -> OnePlusNativeTable {
            OnePlusNativeTable(columns: [.init("Name", width: 180), .init("Size", width: 180, trailing: true)],
                rows: [.init(id: "file", cells: ["File", "128 MB"], symbol: "doc", usage: value.map { [1: $0] } ?? [:])],
                selection: .constant(["file"]), sort: { _, _ in }, actions: { _ in [] })
        }
        let initial = view(1)
        let coordinator = initial.makeCoordinator()
        let table = UsageReloadTable(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        table.delegate = coordinator; table.dataSource = coordinator
        for index in 0..<2 { table.addTableColumn(NSTableColumn(identifier: .init(String(index)))) }
        coordinator.update(initial, in: table, density: .regular)
        let column = table.tableColumns[1]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            table.appearance = NSAppearance(named: appearance)
            let cell = try XCTUnwrap(coordinator.tableView(table, viewFor: column, row: 0) as? NSTableCellView)
            cell.appearance = NSAppearance(named: appearance)
            cell.frame = NSRect(x: 0, y: 0, width: 180, height: 34)
            cell.layoutSubtreeIfNeeded()
            let bar = try XCTUnwrap(cell.subviews.compactMap { $0 as? OnePlusTableUsageBar }.first)
            XCTAssertEqual(bar.frame.width, 55, accuracy: 0.01)
            XCTAssertEqual(bar.frame.height, 3, accuracy: 0.01)
            XCTAssertEqual(bar.frame.midY, cell.bounds.midY, accuracy: 0.5)
            let text = try XCTUnwrap(cell.textField)
            XCTAssertGreaterThanOrEqual(text.alignmentRect(forFrame: text.frame).minX - bar.frame.maxX, 8)
            XCTAssertEqual(cell.textField?.stringValue, "128 MB")
        }
        table.reloads.removeAll()
        coordinator.update(view(0.5), in: table, density: .regular)
        XCTAssertEqual(table.reloads, [IndexSet(integer: 1)])
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))
        let changed = try XCTUnwrap(coordinator.tableView(table, viewFor: column, row: 0) as? NSTableCellView)
        XCTAssertEqual(changed.subviews.compactMap { $0 as? OnePlusTableUsageBar }.first?.value, 0.5)
        coordinator.update(view(nil), in: table, density: .regular)
        let plain = try XCTUnwrap(coordinator.tableView(table, viewFor: column, row: 0) as? NSTableCellView)
        XCTAssertFalse(plain.subviews.contains { $0 is OnePlusTableUsageBar })
    }

    func testUsagePaintClampsInvalidFractions() throws {
        let bar = OnePlusTableUsageBar(frame: NSRect(x: 0, y: 0, width: 55, height: 3))
        func pixel(_ value: Double) throws -> NSColor {
            bar.value = value
            let bitmap = try XCTUnwrap(bar.bitmapImageRepForCachingDisplay(in: bar.bounds))
            bar.cacheDisplay(in: bar.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        }
        let empty = try pixel(0)
        for invalid in [Double.nan, .infinity, -1] { XCTAssertEqual(try pixel(invalid), empty) }
        let full = try pixel(1)
        XCTAssertNotEqual(full, empty)
        XCTAssertEqual(try pixel(2), full)
    }
}

@MainActor private final class UsageReloadTable: NSTableView {
    var reloads: [IndexSet] = []
    override func rows(in rect: NSRect) -> NSRange { NSRange(location: 0, length: 1) }
    override func reloadData(forRowIndexes rows: IndexSet, columnIndexes columns: IndexSet) {
        reloads.append(columns)
        super.reloadData(forRowIndexes: rows, columnIndexes: columns)
    }
}
