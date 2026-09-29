import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class DiskExplorerViewTests: XCTestCase {
    func testFoldedFilesStayVisibleAndCannotBeRemoved() throws {
        let root = entry("/tmp/Diskman", kind: .directory)
        let aggregate = entry("/tmp/Diskman/folded", kind: .aggregate, bytes: 1, files: 9936)
        let files = (0..<81).map { entry("/tmp/Diskman/file-\($0)", bytes: Int64($0 + 10)) }
        root.replaceChildren(files + [aggregate])
        XCTAssertEqual(DiskEntryPresentation.name(aggregate), "\(9936.formatted()) smaller files")
        XCTAssertEqual(DiskEntryPresentation.symbol(aggregate), "square.stack.3d.up")
        XCTAssertFalse(DiskRemoval.isAllowed(aggregate, under: root.url))
        for complete in [false, true] {
            let map = DiskTreemapView(directory: root, apparent: false, measure: .space, scanComplete: complete, select: { _ in })
            XCTAssertTrue(map.tiles.contains { $0.entry?.kind == .aggregate })
            let rings = DiskSunburstView.segments(for: root, apparent: false, measure: .space, radius: 200, scanComplete: complete)
            XCTAssertTrue(rings.contains { $0.entry?.kind == .aggregate })
        }
    }

    func testTableSortsBytesRatherThanFormattedSizeAndKeepsTiesStable() {
        let small = entry("/tmp/Diskman/small", bytes: 900_000)
        let big = entry("/tmp/Diskman/big", bytes: 10_000_000)
        let same = entry("/tmp/Diskman/equal", bytes: 10_000_000)
        XCTAssertEqual(DiskEntryTable.sorted([small, same, big], column: 2, ascending: false, apparent: false).map(\.name),
                       ["big", "equal", "small"])
        XCTAssertEqual(DiskEntryTable.sorted([small, same, big], column: 2, ascending: true, apparent: false).map(\.name),
                       ["small", "big", "equal"])
        let grouped = entry("/tmp/Diskman/grouped", kind: .aggregate, files: 20)
        XCTAssertTrue(DiskEntryTable.sorted([small, grouped], column: 4, ascending: false, apparent: false).first === grouped)
    }

    func testBreadcrumbsAndKeyboardSelectionStayWithinTheScan() throws {
        let leaf = entry("/tmp/Diskman/Projects/App", kind: .directory)
        let sibling = entry("/tmp/Diskman/Projects-old", kind: .directory)
        let folder = entry("/tmp/Diskman/Projects", kind: .directory)
        folder.replaceChildren([leaf])
        let root = entry("/tmp/Diskman", kind: .directory)
        root.replaceChildren([sibling, folder])
        XCTAssertEqual(DiskEntryPresentation.breadcrumbs(to: leaf, root: root).map(\.name), ["Diskman", "Projects", "App"])
        XCTAssertTrue(DiskEntryPresentation.find(leaf.id, in: root) === leaf)
        XCTAssertNil(DiskEntryPresentation.find("/tmp/Elsewhere", in: root))
        XCTAssertNil(DiskChartNavigation.next([], selected: nil, direction: .right))
        XCTAssertTrue(DiskChartNavigation.next([folder, sibling], selected: folder.id, direction: .left) === folder)
        XCTAssertTrue(DiskChartNavigation.next([folder, sibling], selected: folder.id, direction: .right) === sibling)
        XCTAssertTrue(DiskChartNavigation.next([folder, sibling], selected: sibling.id, direction: .right) === sibling)
    }

    private func entry(_ path: String, kind: DiskEntryKind = .file, bytes: Int64 = 0, files: Int = 1) -> DiskEntry {
        DiskEntry(url: URL(fileURLWithPath: path), kind: kind, allocatedBytes: bytes, apparentBytes: bytes,
                  fileCount: kind == .directory ? 0 : files, directoryCount: kind == .directory ? 1 : 0,
                  modifiedAt: .distantPast, device: 1, inode: 1)
    }
}
