import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class DiskExplorerViewTests: XCTestCase {
    func testVolumeSidebarLoadsOffMainAndDiscardsCancelledRefresh() async {
        let model = DiskExplorerModel()
        let volume = DiskVolume(url: URL(fileURLWithPath: "/"), name: "Startup Disk", capacity: 100, available: 50)
        await model.refreshVolumes {
            XCTAssertFalse(Thread.isMainThread)
            return [volume]
        }
        XCTAssertEqual(model.volumes.map(\.name), ["Startup Disk"])
        let task = Task { await model.refreshVolumes { [] } }
        task.cancel()
        await task.value
        XCTAssertEqual(model.volumes.map(\.name), ["Startup Disk"])
    }

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

    func testTableSortsAndFormatsOutsideTheMainThread() async {
        let small = entry("/tmp/Diskman/small", bytes: 900_000)
        let big = entry("/tmp/Diskman/big", bytes: 10_000_000)
        let same = entry("/tmp/Diskman/equal", bytes: 10_000_000)
        XCTAssertEqual(DiskEntryTable.sorted([small, same, big], column: 2, ascending: false, apparent: false).map(\.name),
                       ["big", "equal", "small"])
        XCTAssertEqual(DiskEntryTable.sorted([small, same, big], column: 2, ascending: true, apparent: false).map(\.name),
                       ["small", "big", "equal"])
        let grouped = entry("/tmp/Diskman/grouped", kind: .aggregate, files: 20)
        XCTAssertTrue(DiskEntryTable.sorted([small, grouped], column: 4, ascending: false, apparent: false).first === grouped)
        let request = DiskEntryTableRequest(revision: .distantPast, sourceID: "/tmp/Diskman", search: "",
                                            column: 2, ascending: false, apparent: false, showsFileCount: true)
        let projection = await Task.detached {
            DiskEntryTable.project([small, same, big, grouped], request: request)
        }.value
        XCTAssertEqual(projection.rows.map(\.entry.name), ["big", "equal", "small", "grouped"])
        XCTAssertEqual(projection.rows.first?.cells.count, 5)
        XCTAssertNil(projection.rows.last?.url)
        XCTAssertTrue(projection.entriesByID[big.id] === big)
    }

    func testTableKeepsItsPresentationAcrossScanRevisions() {
        let original = DiskEntryTableRequest(revision: .distantPast, sourceID: "largest-files", search: "",
                                             column: 2, ascending: false, apparent: false, showsFileCount: false)
        let refreshed = DiskEntryTableRequest(revision: Date(), sourceID: "largest-files", search: "",
                                              column: 2, ascending: false, apparent: false, showsFileCount: false)
        let searched = DiskEntryTableRequest(revision: refreshed.revision, sourceID: "largest-files", search: "Library",
                                             column: 2, ascending: false, apparent: false, showsFileCount: false)
        XCTAssertTrue(original.hasSamePresentation(as: refreshed))
        XCTAssertFalse(original.hasSamePresentation(as: searched))
    }

    func testDiskLockPresentationUsesCachedState() {
        let disk = ManagedDisk(id: "disk12", name: "Test card", size: 1_000_000, bus: "USB", scheme: "GPT",
                               devicePath: "test", writable: true, manageable: true, mediaRegistryID: 9, partitions: [])
        let model = DiskManagementModel()
        model.updateDisks([disk])
        XCTAssertTrue(model.isLocked(disk))
        model.updateDisks([disk], lockStates: [disk.identity: false])
        XCTAssertFalse(model.isLocked(disk))
    }

    func testChartCacheSeparatesRevisionTabMeasureAndSize() {
        let root = entry("/tmp/Diskman", kind: .directory, bytes: 100)
        let revision = Date(timeIntervalSince1970: 1_000)
        let mapKey = DiskChartCacheKey(revision: revision, tab: .treemap,
                                       directoryID: root.id, measure: .space,
                                       apparent: false, scanComplete: true,
                                       width: 800, height: 500)
        let ringKey = DiskChartCacheKey(revision: revision, tab: .sunburst,
                                        directoryID: root.id, measure: .space,
                                        apparent: false, scanComplete: true,
                                        width: 800, height: 500)
        let cache = DiskChartLayoutCache()
        cache.store([DiskChartTile(entry: root, label: root.name, weight: 100,
                                   detail: "100 bytes", color: .blue)], for: mapKey)
        cache.store([DiskRingSegment(id: root.id, entry: root, label: root.name,
                                     detail: "100 bytes", start: 0, end: 1,
                                     inner: 1, outer: 2, color: .blue)], for: ringKey)

        XCTAssertTrue(cache.treemap(for: mapKey)?.first?.entry === root)
        XCTAssertTrue(cache.rings(for: ringKey)?.first?.entry === root)
        XCTAssertNil(cache.treemap(for: DiskChartCacheKey(
            revision: revision, tab: .treemap, directoryID: root.id,
            measure: .files, apparent: false, scanComplete: true,
            width: 800, height: 500)))
        XCTAssertNil(cache.rings(for: DiskChartCacheKey(
            revision: revision, tab: .sunburst, directoryID: root.id,
            measure: .space, apparent: false, scanComplete: true,
            width: 801, height: 500)))
        let nextRevisionKey = DiskChartCacheKey(
            revision: revision.addingTimeInterval(1), tab: .treemap,
            directoryID: root.id, measure: .space, apparent: false,
            scanComplete: true, width: 800, height: 500)
        XCTAssertNil(cache.treemap(for: nextRevisionKey))
        cache.store([DiskChartTile](), for: nextRevisionKey)
        XCTAssertNil(cache.rings(for: ringKey))
    }

    func testCompletedChartsFoldTinyTargetsWithoutChangingLiveMembership() throws {
        let root = entry("/tmp/Diskman", kind: .directory)
        let large = entry("/tmp/Diskman/other", kind: .directory, bytes: 1_000_000)
        let small = (0..<60).map { entry("/tmp/Diskman/tiny-\($0)", bytes: 1) }
        let aggregate = entry("/tmp/Diskman/folded", kind: .aggregate, bytes: 40, files: 100)
        root.replaceChildren([large, aggregate] + small)
        let bounds = CGRect(x: 0, y: 0, width: 860, height: 500)
        let live = DiskTreemapView(directory: root, apparent: false, measure: .space, scanComplete: false, select: { _ in })
        XCTAssertEqual(live.tiles(in: bounds).map(\.id), live.tiles.map(\.id))
        let complete = DiskTreemapView(directory: root, apparent: false, measure: .space, scanComplete: true, select: { _ in })
        let tiles = complete.tiles(in: bounds)
        XCTAssertEqual(Set(tiles.map(\.id)), Set([large.id, aggregate.id, "other"]))
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.weight }, 1_000_100)
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }, bounds.width * bounds.height, accuracy: 0.001)
        XCTAssertTrue(tiles.filter { $0.entry?.kind != .aggregate && $0.entry != nil }
            .allSatisfy { min($0.rect.width, $0.rect.height) >= 28 })
        let rings = DiskSunburstView.segments(for: root, apparent: false, measure: .space, radius: 250, scanComplete: true)
        XCTAssertEqual(Set(rings.map(\.id)), Set([large.id, aggregate.id, root.id + "\0other"]))
        XCTAssertEqual(Set(rings.map(\.id)).count, rings.count)
        XCTAssertEqual(rings.reduce(0) { $0 + $1.end - $1.start }, 2 * .pi, accuracy: 0.000001)
        let segment = try XCTUnwrap(rings.first { $0.entry === large })
        let angle = (segment.start + segment.end) / 2
        let radius = (segment.inner + segment.outer) / 2
        let hit = DiskSunburstView.hitTest(rings, at: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius), center: .zero)
        XCTAssertTrue(hit?.entry === large)
        XCTAssertEqual(hit?.label, "other")
        XCTAssertEqual(hit?.detail, large.allocatedBytes.diskSize)
    }

    func testLiveRingBandsStayFixedWhenDeeperFoldersArrive() throws {
        let root = entry("/tmp/Diskman", kind: .directory)
        let folder = entry("/tmp/Diskman/Library", kind: .directory, bytes: 1_000)
        root.replaceChildren([folder])
        let before = try XCTUnwrap(DiskSunburstView.segments(for: root, apparent: false, measure: .space, radius: 250, scanComplete: false).first)
        let child = entry("/tmp/Diskman/Library/Caches", kind: .directory, bytes: 1_000)
        child.replaceChildren([entry("/tmp/Diskman/Library/Caches/File", bytes: 1_000)])
        folder.replaceChildren([child])
        let after = try XCTUnwrap(DiskSunburstView.segments(for: root, apparent: false, measure: .space, radius: 250, scanComplete: false).first)
        XCTAssertEqual(before.id, after.id)
        XCTAssertEqual(before.inner, after.inner)
        XCTAssertEqual(before.outer, after.outer)
    }

    func testLiveRingShowsTheLargestTopLevelFolders() {
        let root = entry("/tmp/Diskman", kind: .directory)
        let small = (0..<30).map { entry("/tmp/Diskman/small-\($0)", bytes: 1) }
        let largest = entry("/tmp/Diskman/Library", bytes: 1_000)
        let second = entry("/tmp/Diskman/.codex", bytes: 900)
        root.replaceChildren(small + [largest, second])

        let rings = DiskSunburstView.segments(for: root, apparent: false, measure: .space,
                                              radius: 250, scanComplete: false)
        let visible = Set(rings.compactMap(\.entry?.id))
        XCTAssertTrue(visible.contains(largest.id))
        XCTAssertTrue(visible.contains(second.id))
        XCTAssertTrue(rings.contains { $0.entry == nil && $0.label == "Other items" })
    }

    func testEmptyAndZeroTotalChartsKeepFiniteGeometry() {
        let empty = entry("/tmp/Empty", kind: .directory)
        let zero = entry("/tmp/Zero", kind: .directory)
        zero.replaceChildren([entry("/tmp/Zero/file", files: 0), entry("/tmp/Zero/folder", kind: .directory)])
        let bounds = CGRect(x: 0, y: 0, width: 860, height: 500)
        for root in [empty, zero] {
            for complete in [false, true] {
                for measure in DiskChartMeasure.allCases {
                    let map = DiskTreemapView(directory: root, apparent: false, measure: measure, scanComplete: complete, select: { _ in })
                    let tiles = map.tiles(in: bounds)
                    XCTAssertEqual(tiles.count, root.children.count)
                    XCTAssertTrue(tiles.allSatisfy { DiskChartGeometry.isDrawable($0.rect) && bounds.contains($0.rect) })
                    let rings = DiskSunburstView.segments(for: root, apparent: false, measure: measure, radius: 200, scanComplete: complete)
                    XCTAssertEqual(rings.count, root.children.count)
                    for ring in rings {
                        XCTAssertTrue(ring.start.isFinite && ring.end.isFinite && ring.end > ring.start)
                        XCTAssertTrue(ring.inner.isFinite && ring.outer.isFinite && ring.inner >= 0 && ring.outer > ring.inner)
                        let path = DiskRingShape(start: ring.start, end: ring.end, inner: ring.inner, outer: ring.outer).path(in: bounds)
                        XCTAssertFalse(path.isEmpty)
                        XCTAssertTrue(DiskChartGeometry.isDrawable(path.boundingRect))
                    }
                }
            }
        }
        XCTAssertEqual(DiskChartGeometry.fraction(0, of: 0), 0)
        XCTAssertEqual(DiskChartGeometry.partitionWidth(bytes: 0, total: 0, available: 800), 0)
        XCTAssertEqual(DiskChartGeometry.partitionWidth(bytes: 25, total: 100, available: 800), 200)
    }

    func testChartsRejectInvalidBoundsAndClampFractions() {
        let root = entry("/tmp/Diskman", kind: .directory)
        root.replaceChildren([entry("/tmp/Diskman/file", bytes: 100)])
        let map = DiskTreemapView(directory: root, apparent: false, measure: .space, scanComplete: true, select: { _ in })
        let shape = DiskRingShape(start: -.pi / 2, end: 3 * .pi / 2, inner: 60, outer: 198)
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let invalid: [CGFloat] = [.nan, .infinity, -.infinity, -1, 0]
        for dimension in invalid {
            for rect in [CGRect(x: 0, y: 0, width: dimension, height: 500),
                         CGRect(x: 0, y: 0, width: 500, height: dimension)] {
                XCTAssertTrue(map.tiles(in: rect).isEmpty)
                XCTAssertTrue(shape.path(in: rect).isEmpty)
            }
            XCTAssertTrue(DiskSunburstView.segments(for: root, apparent: false, measure: .space, radius: dimension, scanComplete: false).isEmpty)
            XCTAssertEqual(DiskChartGeometry.partitionWidth(bytes: 25, total: 100, available: dimension), 0)
        }
        for origin in [CGFloat.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            let rect = CGRect(x: origin, y: origin, width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            XCTAssertTrue(map.tiles(in: rect).isEmpty)
            XCTAssertTrue(shape.path(in: rect).isEmpty)
        }
        XCTAssertTrue(DiskSunburstView.segments(for: root, apparent: false, measure: .space, radius: 1, scanComplete: true).isEmpty)
        for ring in [DiskRingShape(start: .nan, end: 1, inner: 0, outer: 10),
                     DiskRingShape(start: 0, end: .infinity, inner: 0, outer: 10),
                     DiskRingShape(start: -.greatestFiniteMagnitude, end: .greatestFiniteMagnitude, inner: 0, outer: 10),
                     DiskRingShape(start: 0, end: 1, inner: .nan, outer: 10),
                     DiskRingShape(start: 0, end: 1, inner: -1, outer: 10),
                     DiskRingShape(start: 0, end: 1, inner: 0, outer: .infinity),
                     DiskRingShape(start: 0, end: 1, inner: 0, outer: -2),
                     DiskRingShape(start: 1, end: 1, inner: 10, outer: 10)] {
            XCTAssertTrue(ring.path(in: bounds).isEmpty)
        }
        for (value, total, expected) in [(0.0, 0.0, 0.0), (1, 0, 0), (1, -1, 0), (-1, 1, 0),
                                       (.nan, 1, 0), (1, .nan, 0), (.infinity, 1, 0), (1, .infinity, 0),
                                       (2, 1, 1), (0.25, 1, 0.25), (.greatestFiniteMagnitude, .leastNonzeroMagnitude, 1)] {
            XCTAssertEqual(DiskChartGeometry.fraction(value, of: total), expected)
        }
        XCTAssertNil(DiskSunburstView.hitTest([], at: CGPoint(x: CGFloat.nan, y: 0), center: .zero))
        let extreme = DiskChartTile(entry: nil, label: "Large", weight: .max, detail: "", color: .clear)
        XCTAssertEqual(DiskTreemapView.layout([extreme, extreme], in: bounds).count, 2)
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
