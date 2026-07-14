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

    func testTextExtractorPersistsAndMaintainsHistory() {
        let suiteName = "TextExtractorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = TextExtractorService(defaults: defaults)
        let firstDate = Date(timeIntervalSince1970: 100)
        service.record("First", createdAt: firstDate)
        service.record("Second", createdAt: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(service.history.map(\.text), ["Second", "First"])

        let restored = TextExtractorService(defaults: defaults)
        XCTAssertEqual(restored.history, service.history)
        restored.remove(restored.history[0].id)
        XCTAssertEqual(restored.history.map(\.text), ["First"])
        restored.clearHistory()
        XCTAssertTrue(restored.history.isEmpty)

        for index in 0...50 {
            restored.record("Item \(index)")
        }
        XCTAssertEqual(restored.history.count, 50)
        XCTAssertEqual(restored.history.first?.text, "Item 50")
        XCTAssertEqual(restored.history.last?.text, "Item 1")
    }

    func testLongTextExtractionNeedsExpandedView() {
        XCTAssertFalse(TextExtraction(text: "Short text").needsExpandedView)
        XCTAssertTrue(TextExtraction(text: String(repeating: "A", count: 181)).needsExpandedView)
        XCTAssertTrue(TextExtraction(text: "One\nTwo\nThree\nFour\nFive").needsExpandedView)
    }

    func testTextExtractionRelativeTimestampOmitsSeconds() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(TextExtraction(text: "", createdAt: now.addingTimeInterval(-30)).relativeTimestamp(at: now), "Just now")
        XCTAssertFalse(
            TextExtraction(text: "", createdAt: now.addingTimeInterval(-90))
                .relativeTimestamp(at: now)
                .localizedCaseInsensitiveContains("sec")
        )
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
