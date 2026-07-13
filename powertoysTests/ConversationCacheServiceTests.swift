import SwiftData
import XCTest
@testable import powertoys

@MainActor
final class ConversationCacheServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var service: ConversationCacheService!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: CachedConversation.self, CachedMessage.self, CachedSessionMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        service = ConversationCacheService()
        service.setModelContext(container.mainContext)
    }

    func testMetadataLifecycleUpdatesValidatesSortsAndInvalidates() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        service.cacheMetadata(
            sessionId: "older", projectPath: "one", filePath: URL(fileURLWithPath: "/tmp/one"),
            fileModDate: old, firstUserMessage: "Old", messageCount: 1, timestamp: old
        )
        service.cacheMetadata(
            sessionId: "newer", projectPath: "two", filePath: URL(fileURLWithPath: "/tmp/two"),
            fileModDate: new, firstUserMessage: "New", messageCount: 2, timestamp: new
        )

        XCTAssertEqual(service.getAllCachedMetadata().map(\.sessionId), ["newer", "older"])
        XCTAssertTrue(service.isMetadataValid(sessionId: "newer", currentModDate: new.addingTimeInterval(0.9)))
        XCTAssertFalse(service.isMetadataValid(sessionId: "newer", currentModDate: new.addingTimeInterval(1)))

        service.cacheMetadata(
            sessionId: "newer", projectPath: "updated", filePath: URL(fileURLWithPath: "/tmp/updated"),
            fileModDate: new, firstUserMessage: "Updated", messageCount: 3, timestamp: new
        )
        XCTAssertEqual(service.getCachedMetadata(sessionId: "newer")?.projectPath, "updated")
        XCTAssertEqual(service.getCachedMetadata(sessionId: "newer")?.messageCount, 3)

        service.invalidateMetadata("newer")
        XCTAssertNil(service.getCachedMetadata(sessionId: "newer"))
    }

    func testMetadataProjectionUsesTimestampOrModificationDateFallback() {
        let modified = Date(timeIntervalSince1970: 100)
        service.cacheMetadata(
            sessionId: "fallback", projectPath: "project", filePath: URL(fileURLWithPath: "/tmp/file"),
            fileModDate: modified, firstUserMessage: nil, messageCount: 0, timestamp: nil
        )

        let projection = service.getCachedSessionMetadata()

        XCTAssertEqual(projection.count, 1)
        XCTAssertEqual(projection[0].sessionId, "fallback")
        XCTAssertEqual(projection[0].timestamp, modified)
    }

    func testConversationRoundTripPreservesOrderToolsAndThinking() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let messages = [
            message(id: "one", type: .user, content: "Question"),
            message(
                id: "two", type: .assistant, content: "Answer", thinking: "Reasoning",
                tools: [ToolUseBlock(id: "tool", name: "Read", input: "{}", output: "done")]
            )
        ]

        service.cacheConversation(sessionId: "session", projectPath: "project", filePath: file, messages: messages)
        let restored = try XCTUnwrap(service.getCachedMessages(sessionId: "session", filePath: file))

        XCTAssertEqual(restored.map(\.id), ["one", "two"])
        XCTAssertEqual(restored[1].thinking, "Reasoning")
        XCTAssertEqual(restored[1].toolUse, messages[1].toolUse)
    }

    func testChangedOrMissingSourceInvalidatesConversationCache() throws {
        let file = try temporaryFile()
        let messages = [message(id: "one", type: .user, content: "Question")]
        service.cacheConversation(sessionId: "session", projectPath: "project", filePath: file, messages: messages)

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        XCTAssertNil(service.getCachedMessages(sessionId: "session", filePath: file))

        service.cacheConversation(sessionId: "session", projectPath: "project", filePath: file, messages: messages)
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(service.getCachedMessages(sessionId: "session", filePath: file))
    }

    func testInvalidateRemovesMetadataAndConversationTogether() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let modified = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        service.cacheMetadata(
            sessionId: "session", projectPath: "project", filePath: file,
            fileModDate: modified, firstUserMessage: "Question", messageCount: 1, timestamp: modified
        )
        service.cacheConversation(
            sessionId: "session", projectPath: "project", filePath: file,
            messages: [message(id: "one", type: .user, content: "Question")]
        )

        service.invalidate("session")

        XCTAssertNil(service.getCachedMetadata(sessionId: "session"))
        XCTAssertNil(service.getCachedMessages(sessionId: "session", filePath: file))
    }

    private func temporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString).jsonl")
        try Data("content".utf8).write(to: url)
        return url
    }

    private func message(
        id: String,
        type: MessageType,
        content: String,
        thinking: String? = nil,
        tools: [ToolUseBlock] = []
    ) -> CCMessage {
        CCMessage(
            id: id, type: type, content: content, timestamp: Date(), parentUuid: nil,
            toolUse: tools, thinking: thinking, sessionId: "session"
        )
    }
}
