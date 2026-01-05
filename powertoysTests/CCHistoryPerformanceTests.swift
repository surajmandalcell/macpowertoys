//
//  CCHistoryPerformanceTests.swift
//  powertoysTests
//
//  E2E performance tests for CCHistory to verify no regressions.
//

import XCTest
@testable import powertoys

final class CCHistoryPerformanceTests: XCTestCase {

    // MARK: - Session Metadata Cache Tests

    func testSessionMetadataCacheReadWrite() async throws {
        let cache = SessionMetadataCache.shared

        let metadata = SessionMetadata(
            sessionId: "test-session-\(UUID().uuidString)",
            projectPath: "test-project",
            firstUserMessage: "Hello, this is a test message",
            fileModificationDate: Date(),
            messageCount: 10
        )

        await cache.set(metadata)

        let retrieved = await cache.get(metadata.sessionId)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.sessionId, metadata.sessionId)
        XCTAssertEqual(retrieved?.firstUserMessage, metadata.firstUserMessage)
    }

    func testSessionMetadataCacheValidation() async throws {
        let cache = SessionMetadataCache.shared
        let now = Date()

        let metadata = SessionMetadata(
            sessionId: "validation-test-\(UUID().uuidString)",
            projectPath: "test-project",
            firstUserMessage: "Test",
            fileModificationDate: now,
            messageCount: 5
        )

        await cache.set(metadata)

        let isValidSameDate = await cache.isValid(metadata.sessionId, fileModDate: now)
        XCTAssertTrue(isValidSameDate)

        let futureDate = now.addingTimeInterval(10)
        let isValidDifferentDate = await cache.isValid(metadata.sessionId, fileModDate: futureDate)
        XCTAssertFalse(isValidDifferentDate)
    }

    // MARK: - JSONL Parser Tests

    func testJSONLParserChunkedReading() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).jsonl")

        var lines: [String] = []
        for i in 0..<100 {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = """
            {"uuid":"\(UUID().uuidString)","type":"user","timestamp":"\(timestamp)","message":{"content":"Message \(i)"}}
            """
            lines.append(line)
        }

        try lines.joined(separator: "\n").write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: testFile)
        XCTAssertEqual(messages.count, 100)
    }

    func testJSONLParserPerformance() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("perf-test-\(UUID().uuidString).jsonl")

        var lines: [String] = []
        for i in 0..<1000 {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let longContent = String(repeating: "x", count: 500)
            let line = """
            {"uuid":"\(UUID().uuidString)","type":"\(i % 2 == 0 ? "user" : "assistant")","timestamp":"\(timestamp)","message":{"content":"\(longContent)"}}
            """
            lines.append(line)
        }

        try lines.joined(separator: "\n").write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        measure {
            let messages = CCHistoryParser.parseJSONLFile(at: testFile)
            XCTAssertEqual(messages.count, 1000)
        }
    }

    // MARK: - First User Message Extraction Tests

    func testFirstUserMessageExtraction() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("first-msg-\(UUID().uuidString).jsonl")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"uuid":"1","type":"system","timestamp":"\(timestamp)","message":{"content":"System message"}}
        {"uuid":"2","type":"user","timestamp":"\(timestamp)","message":{"content":"First user message here"}}
        {"uuid":"3","type":"assistant","timestamp":"\(timestamp)","message":{"content":"Response"}}
        """

        try content.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        guard let handle = FileHandle(forReadingAtPath: testFile.path),
              let chunk = try? handle.read(upToCount: 8192),
              let text = String(data: chunk, encoding: .utf8) else {
            XCTFail("Could not read file")
            return
        }
        try? handle.close()

        var firstUserMessage: String?
        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "user",
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                continue
            }
            firstUserMessage = String(content.prefix(100))
            break
        }

        XCTAssertEqual(firstUserMessage, "First user message here")
    }

    // MARK: - Timestamp Formatter Performance

    func testTimestampFormatterPerformance() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let timestamps = (0..<1000).map { _ in
            formatter.string(from: Date())
        }

        measure {
            for ts in timestamps {
                _ = formatter.date(from: ts)
            }
        }
    }

    // MARK: - Search Performance

    func testSearchPerformance() async throws {
        var sessions: [CCSession] = []
        for i in 0..<500 {
            let session = CCSession(
                id: UUID().uuidString,
                filePath: URL(fileURLWithPath: "/tmp/test-\(i).jsonl"),
                firstUserMessage: "Test message \(i) with some content",
                timestamp: Date(),
                messageCount: 10
            )
            sessions.append(session)
        }

        let projects = [CCProject(folderName: "test-project", sessions: sessions)]

        measure {
            let query = "test"
            let lowercasedQuery = query.lowercased()
            var results: [String] = []

            for project in projects {
                for session in project.sessions {
                    if session.firstUserMessage?.lowercased().contains(lowercasedQuery) ?? false {
                        results.append(session.id)
                    }
                }
            }

            XCTAssertGreaterThan(results.count, 0)
        }
    }

    // MARK: - Memory Tests

    func testLargeFileMemoryUsage() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("large-\(UUID().uuidString).jsonl")

        var lines: [String] = []
        for i in 0..<5000 {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let content = String(repeating: "Content block \(i) ", count: 50)
            let line = """
            {"uuid":"\(UUID().uuidString)","type":"assistant","timestamp":"\(timestamp)","message":{"content":"\(content)"}}
            """
            lines.append(line)
        }

        try lines.joined(separator: "\n").write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let beforeMemory = getMemoryUsage()

        let messages = CCHistoryParser.parseJSONLFile(at: testFile)

        let afterMemory = getMemoryUsage()
        let memoryIncrease = afterMemory - beforeMemory

        XCTAssertEqual(messages.count, 5000)
        XCTAssertLessThan(memoryIncrease, 200 * 1024 * 1024)
    }

    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
