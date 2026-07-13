import CoreServices
import XCTest
@testable import powertoys

@MainActor
final class LocalChangeHistoryTests: XCTestCase {
    func testHistoryKeepsAndRestoresLatestOneHundredChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("changes.json")
        let jobID = UUID()
        let records = (0..<105).map { index in
            LocalChangeRecord(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                jobID: jobID,
                operation: .copy,
                sourceDisplay: "NVMe",
                relativePath: "file-\(index).txt",
                kind: .modified
            )
        }

        let history = LocalChangeHistory(storageURL: storageURL)
        history.record(records)
        XCTAssertEqual(history.entries.count, 100)
        XCTAssertEqual(history.entries.first?.relativePath, "file-104.txt")
        XCTAssertEqual(history.entries.last?.relativePath, "file-5.txt")
        await history.flush()

        let restored = LocalChangeHistory(storageURL: storageURL)
        await restored.restore()
        XCTAssertEqual(restored.entries, history.entries)
    }

    func testFSEventFlagsMapToReadableChangeKinds() {
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)), .created)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)), .modified)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)), .removed)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)), .renamed)
    }
}
