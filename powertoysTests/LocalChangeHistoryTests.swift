import CoreServices
import XCTest
@testable import powertoys

@MainActor
final class LocalChangeHistoryTests: XCTestCase {
    func testHistoryKeepsAndRestoresLatestOneHundredChangesPerTransfer() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("changes.json")
        let firstJobID = UUID()
        let secondJobID = UUID()
        let firstRecords = (0..<105).map { index in
            LocalChangeRecord(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                jobID: firstJobID,
                operation: .copy,
                sourceDisplay: "NVMe",
                relativePath: "file-\(index).txt",
                kind: .modified
            )
        }
        let secondRecords = (0..<102).map { index in
            LocalChangeRecord(
                timestamp: Date(timeIntervalSince1970: Double(1_000 + index)),
                jobID: secondJobID,
                operation: .sync,
                sourceDisplay: "Photos",
                relativePath: "photo-\(index).jpg",
                kind: .created
            )
        }

        let history = LocalChangeHistory(storageURL: storageURL)
        history.record(firstRecords)
        history.record(secondRecords)
        XCTAssertEqual(history.entries.count, 200)
        XCTAssertEqual(history.entries.filter { $0.jobID == firstJobID }.count, 100)
        XCTAssertEqual(history.entries.filter { $0.jobID == secondJobID }.count, 100)
        XCTAssertEqual(history.entries.first?.relativePath, "photo-101.jpg")
        XCTAssertEqual(history.entries.last?.relativePath, "file-5.txt")
        await history.flush()

        let restored = LocalChangeHistory(storageURL: storageURL)
        await restored.restore()
        XCTAssertEqual(restored.entries, history.entries)

        restored.removeEntries(for: [firstJobID])
        XCTAssertEqual(restored.entries.count, 100)
        XCTAssertTrue(restored.entries.allSatisfy { $0.jobID == secondJobID })
    }

    func testFSEventFlagsMapToReadableChangeKinds() {
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)), .created)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)), .modified)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)), .removed)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)), .renamed)
    }
}
