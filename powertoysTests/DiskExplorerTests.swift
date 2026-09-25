import XCTest
import Darwin
@testable import powertoys

final class DiskExplorerTests: XCTestCase {
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
}
