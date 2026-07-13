import XCTest
@testable import powertoys

@MainActor
final class CoreModelTests: XCTestCase {
    func testTextExtractorSettingsAndRecognitionTitles() {
        XCTAssertEqual(TextRecognitionSpeed.allCases.map(\.title), ["Accurate", "Fast"])
        let settings = TextExtractorSettings()
        XCTAssertEqual(settings.speed, .accurate)
        XCTAssertTrue(settings.languageCorrection)
        XCTAssertTrue(settings.preferredLanguages.isEmpty)
    }

    func testCachedMessageMapsKnownAndUnknownTypes() {
        let date = Date(timeIntervalSince1970: 123)
        XCTAssertEqual(CachedMessage(messageId: "1", type: "user", content: "Hi", timestamp: date).toCCMessage(sessionId: "s").type, .user)
        XCTAssertEqual(CachedMessage(messageId: "2", type: "assistant", content: "Hello", timestamp: date).toCCMessage(sessionId: "s").type, .assistant)
        XCTAssertEqual(CachedMessage(messageId: "3", type: "future", content: "Notice", timestamp: date).toCCMessage(sessionId: "s").type, .system)
    }

    func testCachedMessageDecodesToolUseAndIgnoresMalformedJSON() throws {
        let block = ToolUseBlock(id: "tool-1", name: "Read", input: "file", output: "contents")
        let json = String(data: try JSONEncoder().encode([block]), encoding: .utf8)
        let valid = CachedMessage(messageId: "1", type: "assistant", content: "", timestamp: Date(), toolUseJSON: json)
        XCTAssertEqual(valid.toCCMessage(sessionId: "session").toolUse, [block])

        let malformed = CachedMessage(messageId: "2", type: "assistant", content: "", timestamp: Date(), toolUseJSON: "not json")
        XCTAssertTrue(malformed.toCCMessage(sessionId: "session").toolUse.isEmpty)
    }

    func testTransferRecordSnapshotsJobAndComputesDurationAndSpeed() {
        let started = Date(timeIntervalSince1970: 100)
        let job = TransferJob(
            operation: .move,
            kind: .file,
            sourceFs: "/source/file",
            destinationFs: "remote:file",
            sourceDisplay: "file",
            destinationDisplay: "remote",
            excludePatterns: ["*.tmp"],
            maxRetries: 3,
            createdAt: Date(timeIntervalSince1970: 50)
        )
        job.state = .completed
        job.startedAt = started
        job.finishedAt = started.addingTimeInterval(4)
        job.stats.bytes = 400
        job.stats.totalBytes = 500
        job.stats.transfers = 1
        job.stats.totalTransfers = 1
        job.attempt = 2

        let record = TransferRecord(job: job)
        XCTAssertEqual(record.operation, .move)
        XCTAssertEqual(record.kind, .file)
        XCTAssertEqual(record.state, .completed)
        XCTAssertEqual(record.duration, 4)
        XCTAssertEqual(record.averageSpeed, 100)
        XCTAssertEqual(record.excludePatterns, "*.tmp")
        XCTAssertEqual(record.attempts, 2)
    }

    func testTransferRecordFallbacksAndMissingDuration() {
        let job = TransferJob(
            operation: .copy,
            sourceFs: "/source",
            destinationFs: "remote:dest",
            sourceDisplay: "source",
            destinationDisplay: "dest",
            excludePatterns: [],
            maxRetries: 1
        )
        let record = TransferRecord(job: job)
        record.operationRaw = "future"
        record.kindRaw = "future"
        record.stateRaw = "future"

        XCTAssertEqual(record.operation, .copy)
        XCTAssertEqual(record.kind, .directory)
        XCTAssertEqual(record.state, .completed)
        XCTAssertNil(record.duration)
        XCTAssertEqual(record.averageSpeed, 0)
    }
}
