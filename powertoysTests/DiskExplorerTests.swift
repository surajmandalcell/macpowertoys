import XCTest
import Darwin
import SwiftUI
@testable import powertoys

final class DiskExplorerTests: XCTestCase {
    func testEntryIdentityIsCompactAndDoesNotRebuildFromParents() {
        let fileURL = URL(fileURLWithPath: "/tmp/diskman-identity/original.bin")
        let first = DiskEntry(url: fileURL, kind: .file, allocatedBytes: 1,
                              apparentBytes: 1, fileCount: 1, directoryCount: 0,
                              modifiedAt: .distantPast, device: 7, inode: 42)
        let same = DiskEntry(url: fileURL, kind: .file, allocatedBytes: 1,
                             apparentBytes: 1, fileCount: 1, directoryCount: 0,
                             modifiedAt: .distantPast, device: 7, inode: 42)
        let hardLink = DiskEntry(url: fileURL.deletingLastPathComponent().appendingPathComponent("link.bin"),
                                 kind: .file, allocatedBytes: 0, apparentBytes: 0,
                                 fileCount: 1, directoryCount: 0, modifiedAt: .distantPast,
                                 device: 7, inode: 42)
        let storedID = first.id
        let newParent = DiskEntry(url: URL(fileURLWithPath: "/tmp/elsewhere"), kind: .directory,
                                  allocatedBytes: 0, apparentBytes: 0, fileCount: 0,
                                  directoryCount: 1, modifiedAt: .distantPast,
                                  device: 7, inode: 9, children: [first])

        XCTAssertEqual(first.id, storedID)
        XCTAssertEqual(first.id, same.id)
        XCTAssertNotEqual(first.id, hardLink.id)
        XCTAssertLessThanOrEqual(first.id.utf8.count, 16)
        XCTAssertTrue(first.parentEntry === newParent)
    }

    func testLiveChartsKeepVisibleItemsWhenMeasuredSizesCross() {
        func directory(lastWeight: Int64) -> DiskEntry {
            let url = URL(fileURLWithPath: "/tmp/diskman-chart-membership")
            let children = (0..<81).map { index in
                let weight = index == 80 ? lastWeight : Int64(200 - index)
                return DiskEntry(url: url.appendingPathComponent(String(format: "item-%03d", index)),
                                 kind: .file, allocatedBytes: weight, apparentBytes: weight,
                                 fileCount: 1, directoryCount: 0, modifiedAt: .distantPast,
                                 device: 1, inode: UInt64(index + 2))
            }
            let total = children.reduce(Int64(0)) { $0 + $1.allocatedBytes }
            return DiskEntry(url: url, kind: .directory, allocatedBytes: total,
                             apparentBytes: total, fileCount: 81, directoryCount: 1,
                             modifiedAt: .distantPast, device: 1, inode: 1, children: children)
        }

        let before = directory(lastWeight: 1)
        let after = directory(lastWeight: 1_000)
        func treemapIDs(_ root: DiskEntry, complete: Bool) -> Set<String> {
            let view = DiskTreemapView(directory: root, apparent: false, measure: .space,
                                       scanComplete: complete, select: { _ in })
            return Set(view.tiles.compactMap { $0.entry?.id })
        }
        func ringIDs(_ root: DiskEntry, complete: Bool) -> Set<String> {
            Set(DiskSunburstView.segments(for: root, apparent: false, measure: .space,
                                          radius: 200, scanComplete: complete)
                .compactMap { $0.entry?.id })
        }
        XCTAssertEqual(treemapIDs(before, complete: false), treemapIDs(after, complete: false))
        XCTAssertEqual(ringIDs(before, complete: false), ringIDs(after, complete: false))
        let largest = after.children[80].id
        XCTAssertFalse(treemapIDs(after, complete: false).contains(largest))
        XCTAssertFalse(ringIDs(after, complete: false).contains(largest))
        XCTAssertTrue(treemapIDs(after, complete: true).contains(largest))
        XCTAssertTrue(ringIDs(after, complete: true).contains(largest))
    }

    func testTreemapKeepsTileGroupsWhenMeasuredSizesCross() {
        func tiles(_ weights: [Int64]) -> [DiskChartTile] {
            weights.enumerated().map { index, weight in
                DiskChartTile(entry: nil, label: String(index), weight: weight,
                              detail: "", style: .storage(0))
            }
        }
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let before = DiskTreemapView.layout(tiles([8, 6, 3, 2]), in: frame)
        let after = DiskTreemapView.layout(tiles([30, 1, 1, 1]), in: frame)
        XCTAssertEqual(before[0].rect.minX, before[1].rect.minX)
        XCTAssertEqual(after[0].rect.minX, after[1].rect.minX)
        XCTAssertGreaterThan(after[2].rect.minX, after[1].rect.minX)
    }

    @MainActor func testPartialResultsCannotBeMarkedForRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 7, count: 8192).write(to: root.appendingPathComponent("data.bin"))

        let snapshots = DiskSnapshotRecorder()
        let final = try DiskExplorerScanner.scan(root) { snapshots.append($0) }
        let partial = try XCTUnwrap(snapshots.values.first { !$0.isComplete && !$0.root.children.isEmpty })
        let model = DiskExplorerModel(preview: partial)
        model.toggleMark(try XCTUnwrap(partial.root.children.first))
        XCTAssertTrue(model.markedEntries.isEmpty)

        let completeModel = DiskExplorerModel(preview: final)
        completeModel.toggleMark(try XCTUnwrap(final.root.children.first))
        XCTAssertEqual(completeModel.markedEntries.count, 1)
    }

    func testScannerPublishesMeasuredFoldersBeforeItFinishes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["first", "second"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 8192).write(to: folder.appendingPathComponent("data.bin"))
        }

        let snapshots = DiskSnapshotRecorder()
        let final = try DiskExplorerScanner.scan(root) { snapshots.append($0) }
        let partial = snapshots.values
        XCTAssertTrue(partial.contains { !$0.isComplete && $0.root.children.count == 2 })
        XCTAssertTrue(partial.contains { !$0.isComplete && $0.root.allocatedBytes > 0 &&
            $0.root.children.contains(where: { $0.allocatedBytes > 0 }) })
        XCTAssertTrue(partial.contains { !$0.isComplete && $0.root.children.count == 2 &&
            $0.root.fileCount == 0 && $0.root.children.allSatisfy { $0.allocatedBytes > 0 } })
        XCTAssertTrue(final.isComplete)
        XCTAssertEqual(final.root.allocatedBytes, try duBytes(root))
    }

    func testDirectoryFoldingKeeps64LargestFilesAndOneExactAggregate() throws {
        let fixture = syntheticFoldedDirectory(fileCount: 10_000)
        let files = fixture.directory.children.filter { $0.kind == .file }
        let aggregate = try XCTUnwrap(fixture.directory.children.first { $0.kind == .aggregate })

        XCTAssertEqual(files.count, 64)
        XCTAssertEqual(files.map(\.allocatedBytes).min(), 9_937)
        XCTAssertEqual(files.map(\.allocatedBytes).max(), 10_000)
        XCTAssertEqual(aggregate.name, "9936 smaller files")
        XCTAssertEqual(aggregate.fileCount, 9_936)
        XCTAssertEqual(aggregate.allocatedBytes, (1...9_936).reduce(Int64(0)) { $0 + Int64($1) })
        XCTAssertEqual(aggregate.apparentBytes, aggregate.allocatedBytes * 3)
        XCTAssertEqual(aggregate.modifiedAt, Date(timeIntervalSince1970: 20_000))
        XCTAssertFalse(DiskRemoval.isAllowed(aggregate, under: fixture.directory.url))
        XCTAssertEqual(fixture.largestFiles.count, 100)
        XCTAssertEqual(fixture.largestFiles.first?.allocatedBytes, 10_000)
        XCTAssertEqual(fixture.largestFiles.last?.allocatedBytes, 9_901)
        XCTAssertFalse(files.contains { $0.allocatedBytes == 9_901 })
    }

    func testFoldedDirectoryTotalsEqualUnfoldedTotals() {
        let fixture = syntheticFoldedDirectory(fileCount: 10_000)

        XCTAssertEqual(fixture.directory.allocatedBytes, fixture.allocatedBytes)
        XCTAssertEqual(fixture.directory.apparentBytes, fixture.apparentBytes)
        XCTAssertEqual(fixture.directory.fileCount, 10_000)
        XCTAssertEqual(fixture.directory.directoryCount, 1)
        XCTAssertEqual(fixture.directory.modifiedAt, Date(timeIntervalSince1970: 20_000))
    }

    func testScannerMatchesDuAndDoesNotFollowLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = folder.appendingPathComponent("data.bin")
        try Data(repeating: 7, count: 8192).write(to: data)
        XCTAssertEqual(link(data.path, folder.appendingPathComponent("hard-link.bin").path), 0)
        try Data(repeating: 8, count: 4096).write(to: root.appendingPathComponent(".hidden"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let newestWrite = Date().addingTimeInterval(3_600)
        try FileManager.default.setAttributes([.modificationDate: newestWrite], ofItemAtPath: data.path)

        let result = try DiskExplorerScanner.scan(root)
        XCTAssertEqual(result.root.fileCount, 4)
        XCTAssertEqual(result.root.directoryCount, 2)
        XCTAssertEqual(result.unreadableCount, 0)
        XCTAssertEqual(result.root.allocatedBytes, try duBytes(root))
        XCTAssertEqual(result.root.modifiedAt.timeIntervalSince1970,
                       newestWrite.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(DiskChartMeasure.files.weight(result.root, apparent: false), 4)

        let withoutHidden = try DiskExplorerScanner.scan(root, includeHidden: false)
        XCTAssertFalse(withoutHidden.root.children.contains { $0.name == ".hidden" })
        XCTAssertEqual(withoutHidden.root.fileCount, 3)
    }

    func testRemovalRejectsRootAndChangedEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("item")
        try Data("first".utf8).write(to: child)
        let scan = try DiskExplorerScanner.scan(root)
        let entry = try XCTUnwrap(scan.root.children.first)
        XCTAssertFalse(DiskRemoval.isAllowed(scan.root, under: root))
        XCTAssertTrue(DiskRemoval.isAllowed(entry, under: root))
        XCTAssertEqual(DiskRemoval.topLevel([entry, scan.root]).map(\.id), [scan.root.id])

        try FileManager.default.moveItem(at: child, to: root.appendingPathComponent("old-item"))
        try Data("replacement".utf8).write(to: child)
        let outcome = DiskRemoval.remove([entry], under: scan.root, permanently: true)
        XCTAssertEqual(outcome.removed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))

        let refreshed = try DiskExplorerScanner.scan(root)
        let original = try XCTUnwrap(refreshed.root.children.first { $0.name == "old-item" })
        let validOutcome = DiskRemoval.remove([original], under: refreshed.root, permanently: true)
        XCTAssertEqual(validOutcome.removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.url.path))
    }

    private func duBytes(_ url: URL) throws -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-s", url.path]
        process.environment = ["BLOCKSIZE": "512"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return try XCTUnwrap(Int64(text.split(whereSeparator: \.isWhitespace).first ?? "")) * 512
    }

    private func syntheticFoldedDirectory(fileCount: Int) ->
        (directory: DiskEntry, allocatedBytes: Int64, apparentBytes: Int64,
         largestFiles: [DiskEntry]) {
        let url = URL(fileURLWithPath: "/tmp/diskman-folding")
        let directory = DiskEntry(url: url, kind: .directory, allocatedBytes: 0,
                                  apparentBytes: 0, fileCount: 0, directoryCount: 1,
                                  modifiedAt: .distantPast, device: 1, inode: 1)
        var accumulator = DiskDirectoryAccumulator(parent: directory)
        var allocatedBytes: Int64 = 0
        var apparentBytes: Int64 = 0
        for index in 0..<fileCount {
            let allocated = Int64(index + 1)
            let apparent = allocated * 3
            allocatedBytes += allocated
            apparentBytes += apparent
            accumulator.add(DiskEntry(
                url: url.appendingPathComponent("item-\(index)"),
                kind: .file,
                allocatedBytes: allocated,
                apparentBytes: apparent,
                fileCount: 1,
                directoryCount: 0,
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(20_000 - index)),
                device: 1,
                inode: UInt64(index + 2)
            ))
        }
        directory.replaceChildren(accumulator.children)
        return (directory, allocatedBytes, apparentBytes, accumulator.largestCandidates)
    }
}

private final class DiskSnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [DiskScanResult] = []
    func append(_ snapshot: DiskScanResult) { lock.withLock { snapshots.append(snapshot) } }
    var values: [DiskScanResult] { lock.withLock { snapshots } }
}
