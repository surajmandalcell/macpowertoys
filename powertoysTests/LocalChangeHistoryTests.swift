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

    func testFailedHistoryFlushRetainsRecordsForRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = LocalChangeHistory(storageURL: root.appendingPathComponent("history.json"))
        history.record([LocalChangeRecord(jobID: UUID(), operation: .copy, sourceDisplay: "Fixture", relativePath: "file", kind: .created)])
        do {
            try await history.flushReportingErrors()
            XCTFail("Missing parent must fail")
        } catch {}
        XCTAssertEqual(history.entries.count, 1)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await history.flushReportingErrors()
        let restored = LocalChangeHistory(storageURL: root.appendingPathComponent("history.json"))
        await restored.restore()
        XCTAssertEqual(restored.entries, history.entries)
    }

    func testRestoreMergesNewRecordsAndCannotReplaceUnsavedState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.json")
        let old = LocalChangeRecord(jobID: UUID(), operation: .copy, sourceDisplay: "Fixture", relativePath: "old", kind: .created)
        let new = LocalChangeRecord(jobID: old.jobID, operation: .copy, sourceDisplay: "Fixture", relativePath: "new", kind: .modified)
        try JSONEncoder().encode([old]).write(to: url)
        let history = LocalChangeHistory(storageURL: url)
        async let first: Void = history.restore()
        async let second: Void = history.restore()
        history.record([new, old])
        await first
        await second
        XCTAssertEqual(Set(history.entries.map(\.id)), [old.id, new.id])
        XCTAssertEqual(history.entries.count, 2)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        do {
            try await history.flushReportingErrors()
            XCTFail("A directory cannot be overwritten with JSON")
        } catch {}
        await history.restore()
        XCTAssertEqual(Set(history.entries.map(\.id)), [old.id, new.id])
    }

    func testFSEventFlagsMapToReadableChangeKinds() {
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)), .created)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)), .modified)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)), .removed)
        XCTAssertEqual(FileChangeKind.resolve(FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)), .renamed)
    }
}
