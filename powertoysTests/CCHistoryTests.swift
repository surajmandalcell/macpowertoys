//
//  CCHistoryTests.swift
//  powertoysTests
//
//  Comprehensive unit tests for CCHistory functionality.
//

import XCTest
@testable import powertoys

final class CCHistoryTests: XCTestCase {

    // MARK: - FilterOptions Tests

    func testFilterOptionsDefaultValues() {
        let options = FilterOptions()
        XCTAssertTrue(options.showUser)
        XCTAssertTrue(options.showAssistant)
        XCTAssertFalse(options.showSystem)
        XCTAssertFalse(options.showToolCalls)
        XCTAssertFalse(options.showToolOutputs)
        XCTAssertFalse(options.showThinking)
        XCTAssertFalse(options.showEmptyMessages)
    }

    func testFilterOptionsShowsUserMessages() {
        let options = FilterOptions(showUser: true, showAssistant: false, showSystem: false)
        let userMessage = makeMessage(type: .user, content: "Hello")
        let assistantMessage = makeMessage(type: .assistant, content: "Hi")
        let systemMessage = makeMessage(type: .system, content: "System")

        XCTAssertTrue(options.shouldShow(message: userMessage))
        XCTAssertFalse(options.shouldShow(message: assistantMessage))
        XCTAssertFalse(options.shouldShow(message: systemMessage))
    }

    func testFilterOptionsShowsAssistantMessages() {
        let options = FilterOptions(showUser: false, showAssistant: true, showSystem: false)
        let userMessage = makeMessage(type: .user, content: "Hello")
        let assistantMessage = makeMessage(type: .assistant, content: "Hi")

        XCTAssertFalse(options.shouldShow(message: userMessage))
        XCTAssertTrue(options.shouldShow(message: assistantMessage))
    }

    func testFilterOptionsShowsSystemMessages() {
        let options = FilterOptions(showUser: false, showAssistant: false, showSystem: true)
        let systemMessage = makeMessage(type: .system, content: "System init")

        XCTAssertTrue(options.shouldShow(message: systemMessage))
    }

    func testFilterOptionsHidesEmptyMessages() {
        let options = FilterOptions(showUser: true, showAssistant: true, showEmptyMessages: false)
        let emptyMessage = makeMessage(type: .user, content: "")
        let whitespaceMessage = makeMessage(type: .user, content: "   \n\t  ")
        let contentMessage = makeMessage(type: .user, content: "Hello")

        XCTAssertFalse(options.shouldShow(message: emptyMessage))
        XCTAssertFalse(options.shouldShow(message: whitespaceMessage))
        XCTAssertTrue(options.shouldShow(message: contentMessage))
    }

    func testFilterOptionsShowsEmptyMessagesWhenEnabled() {
        let options = FilterOptions(showUser: true, showAssistant: true, showEmptyMessages: true)
        let emptyMessage = makeMessage(type: .user, content: "")
        let whitespaceMessage = makeMessage(type: .assistant, content: "   ")

        XCTAssertTrue(options.shouldShow(message: emptyMessage))
        XCTAssertTrue(options.shouldShow(message: whitespaceMessage))
    }

    func testFilterOptionsEmptyCheckOnlyAffectsMatchingTypes() {
        let options = FilterOptions(showUser: true, showAssistant: false, showEmptyMessages: false)
        let emptyUserMessage = makeMessage(type: .user, content: "")
        let emptyAssistantMessage = makeMessage(type: .assistant, content: "")

        XCTAssertFalse(options.shouldShow(message: emptyUserMessage))
        XCTAssertFalse(options.shouldShow(message: emptyAssistantMessage))
    }

    func testFilterOptionsCombinedFilters() {
        let options = FilterOptions(
            showUser: true,
            showAssistant: true,
            showSystem: false,
            showEmptyMessages: false
        )

        XCTAssertTrue(options.shouldShow(message: makeMessage(type: .user, content: "Hello")))
        XCTAssertTrue(options.shouldShow(message: makeMessage(type: .assistant, content: "Hi")))
        XCTAssertFalse(options.shouldShow(message: makeMessage(type: .system, content: "System")))
        XCTAssertFalse(options.shouldShow(message: makeMessage(type: .user, content: "")))
    }

    // MARK: - CCMessage Tests

    func testCCMessageInitialization() {
        let timestamp = Date()
        let message = CCMessage(
            id: "test-id",
            type: .user,
            content: "Test content",
            timestamp: timestamp,
            parentUuid: "parent-id",
            toolUse: [],
            thinking: "thinking content",
            sessionId: "session-1"
        )

        XCTAssertEqual(message.id, "test-id")
        XCTAssertEqual(message.type, .user)
        XCTAssertEqual(message.content, "Test content")
        XCTAssertEqual(message.timestamp, timestamp)
        XCTAssertEqual(message.parentUuid, "parent-id")
        XCTAssertEqual(message.thinking, "thinking content")
        XCTAssertEqual(message.sessionId, "session-1")
    }

    func testCCMessageWithToolUse() {
        let tool = ToolUseBlock(
            id: "tool-1",
            name: "read_file",
            input: "{\"path\": \"/test.txt\"}",
            output: "file contents"
        )
        let message = makeMessage(type: .assistant, content: "Response", toolUse: [tool])

        XCTAssertEqual(message.toolUse.count, 1)
        XCTAssertEqual(message.toolUse.first?.name, "read_file")
    }

    func testCCMessageTypeIcon() {
        XCTAssertEqual(MessageType.user.icon, "person.fill")
        XCTAssertEqual(MessageType.assistant.icon, "brain")
        XCTAssertEqual(MessageType.system.icon, "gearshape.fill")
    }

    // MARK: - CCSession Tests

    func testCCSessionDisplayTitle() {
        let session1 = CCSession(
            id: "session-1",
            filePath: URL(fileURLWithPath: "/test/session.jsonl"),
            firstUserMessage: "Hello, how are you?",
            timestamp: Date(),
            messageCount: 10
        )
        XCTAssertEqual(session1.displayTitle, "Hello, how are you?")

        let session2 = CCSession(
            id: "session-2",
            filePath: URL(fileURLWithPath: "/test/session.jsonl"),
            firstUserMessage: nil,
            timestamp: Date(),
            messageCount: 5
        )
        XCTAssertEqual(session2.displayTitle, "session-2")
    }

    func testCCSessionDisplayTitleTruncation() {
        let longMessage = String(repeating: "a", count: 200)
        let session = CCSession(
            id: "session-1",
            filePath: URL(fileURLWithPath: "/test/session.jsonl"),
            firstUserMessage: longMessage,
            timestamp: Date(),
            messageCount: 10
        )
        XCTAssertEqual(session.displayTitle.count, 53)
        XCTAssertTrue(session.displayTitle.hasSuffix("..."))
    }

    func testCCSessionDisplayTitleWithWhitespace() {
        let session = CCSession(
            id: "session-1",
            filePath: URL(fileURLWithPath: "/test/session.jsonl"),
            firstUserMessage: "   ",
            timestamp: Date(),
            messageCount: 10
        )
        XCTAssertEqual(session.displayTitle, "   ")
    }

    // MARK: - CCProject Tests

    func testCCProjectDisplayName() {
        let project1 = CCProject(
            folderName: "-Users-john-projects-myapp",
            sessions: []
        )
        XCTAssertEqual(project1.displayName, "projects/myapp")

        let project2 = CCProject(
            folderName: "-root",
            sessions: []
        )
        XCTAssertEqual(project2.displayName, "root")
    }

    func testCCProjectDisplayNameWithEmptySessions() {
        let project = CCProject(
            folderName: "-Users-test-project",
            sessions: []
        )
        XCTAssertEqual(project.sessions.count, 0)
        XCTAssertEqual(project.displayName, "test/project")
    }

    func testCCProjectIdentifiable() {
        let project = CCProject(folderName: "test-folder", sessions: [])
        XCTAssertEqual(project.id, "test-folder")
    }

    // MARK: - ToolUseBlock Tests

    func testToolUseBlockEquality() {
        let tool1 = ToolUseBlock(id: "1", name: "read", input: "{}", output: nil)
        let tool2 = ToolUseBlock(id: "1", name: "write", input: "{}", output: "done")
        let tool3 = ToolUseBlock(id: "2", name: "read", input: "{}", output: nil)

        XCTAssertEqual(tool1, tool2)
        XCTAssertNotEqual(tool1, tool3)
    }

    func testToolUseBlockIdentifiable() {
        let tool = ToolUseBlock(id: "unique-id", name: "test", input: "{}", output: nil)
        XCTAssertEqual(tool.id, "unique-id")
    }

    // MARK: - ExportFormat Tests

    func testExportFormatFileExtension() {
        XCTAssertEqual(ExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ExportFormat.plainText.fileExtension, "txt")
    }

    func testExportFormatIdentifiable() {
        XCTAssertEqual(ExportFormat.markdown.id, "Markdown")
        XCTAssertEqual(ExportFormat.json.id, "JSON")
        XCTAssertEqual(ExportFormat.plainText.id, "Plain Text")
    }

    // MARK: - Edge Cases

    func testFilterOptionsAllDisabled() {
        let options = FilterOptions(
            showUser: false,
            showAssistant: false,
            showSystem: false,
            showEmptyMessages: false
        )

        XCTAssertFalse(options.shouldShow(message: makeMessage(type: .user, content: "Hello")))
        XCTAssertFalse(options.shouldShow(message: makeMessage(type: .assistant, content: "Hi")))
        XCTAssertFalse(options.shouldShow(message: makeMessage(type: .system, content: "System")))
    }

    func testFilterOptionsAllEnabled() {
        let options = FilterOptions(
            showUser: true,
            showAssistant: true,
            showSystem: true,
            showEmptyMessages: true
        )

        XCTAssertTrue(options.shouldShow(message: makeMessage(type: .user, content: "Hello")))
        XCTAssertTrue(options.shouldShow(message: makeMessage(type: .assistant, content: "Hi")))
        XCTAssertTrue(options.shouldShow(message: makeMessage(type: .system, content: "System")))
        XCTAssertTrue(options.shouldShow(message: makeMessage(type: .user, content: "")))
    }

    func testMessageWithOnlyWhitespaceContent() {
        let options = FilterOptions(showUser: true, showEmptyMessages: false)
        let tabMessage = makeMessage(type: .user, content: "\t\t\t")
        let newlineMessage = makeMessage(type: .user, content: "\n\n\n")
        let mixedMessage = makeMessage(type: .user, content: " \t\n \t\n ")

        XCTAssertFalse(options.shouldShow(message: tabMessage))
        XCTAssertFalse(options.shouldShow(message: newlineMessage))
        XCTAssertFalse(options.shouldShow(message: mixedMessage))
    }

    func testMessageWithUnicodeContent() {
        let options = FilterOptions(showUser: true, showEmptyMessages: false)
        let emojiMessage = makeMessage(type: .user, content: "Hello! 👋")
        let chineseMessage = makeMessage(type: .user, content: "你好")
        let mixedMessage = makeMessage(type: .user, content: "Test 🔥 Hola")

        XCTAssertTrue(options.shouldShow(message: emojiMessage))
        XCTAssertTrue(options.shouldShow(message: chineseMessage))
        XCTAssertTrue(options.shouldShow(message: mixedMessage))
    }

    func testSessionWithZeroMessageCount() {
        let session = CCSession(
            id: "empty-session",
            filePath: URL(fileURLWithPath: "/test/empty.jsonl"),
            firstUserMessage: nil,
            timestamp: nil,
            messageCount: 0
        )
        XCTAssertEqual(session.messageCount, 0)
        XCTAssertEqual(session.displayTitle, "empty-session")
    }

    func testProjectWithSpecialCharactersInPath() {
        let project = CCProject(
            folderName: "-Users-john-my%20project-test",
            sessions: []
        )
        XCTAssertEqual(project.displayName, "my%20project/test")
    }

    func testToolUseBlockWithEmptyInput() {
        let tool = ToolUseBlock(id: "1", name: "list_files", input: "", output: "[]")
        XCTAssertEqual(tool.input, "")
        XCTAssertEqual(tool.output, "[]")
    }

    func testToolUseBlockWithNilOutput() {
        let tool = ToolUseBlock(id: "1", name: "pending_tool", input: "{}", output: nil)
        XCTAssertNil(tool.output)
    }

    // MARK: - Helper Methods

    private func makeMessage(
        type: MessageType,
        content: String,
        toolUse: [ToolUseBlock] = [],
        thinking: String? = nil
    ) -> CCMessage {
        CCMessage(
            id: UUID().uuidString,
            type: type,
            content: content,
            timestamp: Date(),
            parentUuid: nil,
            toolUse: toolUse,
            thinking: thinking,
            sessionId: "test-session"
        )
    }
}

// MARK: - JSONL Parser Tests

final class CCHistoryParserTests: XCTestCase {

    func testParseEmptyFile() throws {
        let tempFile = createTempFile(content: "")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.count, 0)
    }

    func testParseValidUserMessage() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"uuid":"1","type":"user","timestamp":"\(timestamp)","message":{"content":"Hello world"}}
        """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.type, .user)
        XCTAssertEqual(messages.first?.content, "Hello world")
    }

    func testParseValidAssistantMessage() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"uuid":"1","type":"assistant","timestamp":"\(timestamp)","message":{"content":"Hi there!"}}
        """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.type, .assistant)
    }

    func testParseMessageWithThinking() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"uuid":"1","type":"assistant","timestamp":"\(timestamp)","message":{"content":[{"type":"thinking","thinking":"I need to think about this..."},{"type":"text","text":"Response"}]}}
        """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.first?.thinking, "I need to think about this...")
    }

    func testParseInvalidJSON() throws {
        let content = "not valid json\n{invalid}"
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.count, 0)
    }

    func testParseMixedValidInvalidLines() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        invalid line
        {"uuid":"1","type":"user","timestamp":"\(timestamp)","message":{"content":"Valid"}}
        another invalid
        {"uuid":"2","type":"assistant","timestamp":"\(timestamp)","message":{"content":"Also valid"}}
        """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.count, 2)
    }

    func testParseMultipleMessages() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []
        for i in 0..<50 {
            let type = i % 2 == 0 ? "user" : "assistant"
            lines.append("""
            {"uuid":"\(i)","type":"\(type)","timestamp":"\(timestamp)","message":{"content":"Message \(i)"}}
            """)
        }
        let tempFile = createTempFile(content: lines.joined(separator: "\n"))
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.count, 50)
    }

    func testParseMessageWithToolUse() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"uuid":"1","type":"assistant","timestamp":"\(timestamp)","message":{"content":[{"type":"tool_use","id":"tool1","name":"read_file","input":{"path":"/test.txt"}},{"type":"text","text":"Using tool"}]}}
        """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.first?.toolUse.count, 1)
        XCTAssertEqual(messages.first?.toolUse.first?.name, "read_file")
    }

    func testParseMessageWithToolResult() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"uuid":"1","type":"tool_result","timestamp":"\(timestamp)","toolUseId":"tool1","message":{"content":"file contents here"}}
        """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.count, 0)
    }

    func testParseEmptyLines() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """

        {"uuid":"1","type":"user","timestamp":"\(timestamp)","message":{"content":"Hello"}}

        {"uuid":"2","type":"assistant","timestamp":"\(timestamp)","message":{"content":"Hi"}}

        """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertEqual(messages.count, 2)
    }

    func testParseMessageWithSpecialCharacters() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"uuid":"1","type":"user","timestamp":"\(timestamp)","message":{"content":"Hello\\nworld\\twith\\\"quotes\\\""}}
        """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let messages = CCHistoryParser.parseJSONLFile(at: tempFile)
        XCTAssertTrue(messages.first?.content.contains("\\n") == true || messages.first?.content.contains("\n") == true)
    }

    func testParseNonExistentFile() {
        let fakePath = URL(fileURLWithPath: "/nonexistent/path/file.jsonl")
        let messages = CCHistoryParser.parseJSONLFile(at: fakePath)
        XCTAssertEqual(messages.count, 0)
    }

    // MARK: - Helper Methods

    private func createTempFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).jsonl")
        try? content.write(to: testFile, atomically: true, encoding: .utf8)
        return testFile
    }
}

// MARK: - Session Metadata Tests

final class SessionMetadataTests: XCTestCase {

    func testSessionMetadataInit() {
        let date = Date()
        let metadata = SessionMetadata(
            sessionId: "test-123",
            projectPath: "/path/to/project",
            firstUserMessage: "Hello",
            fileModificationDate: date,
            messageCount: 42
        )

        XCTAssertEqual(metadata.sessionId, "test-123")
        XCTAssertEqual(metadata.projectPath, "/path/to/project")
        XCTAssertEqual(metadata.firstUserMessage, "Hello")
        XCTAssertEqual(metadata.fileModificationDate, date)
        XCTAssertEqual(metadata.messageCount, 42)
    }

    func testSessionMetadataWithNilFirstMessage() {
        let metadata = SessionMetadata(
            sessionId: "test-456",
            projectPath: "/path",
            firstUserMessage: nil,
            fileModificationDate: Date(),
            messageCount: 0
        )

        XCTAssertNil(metadata.firstUserMessage)
    }
}

// MARK: - Search Result Tests

final class SearchResultTests: XCTestCase {

    func testSearchResultInit() {
        let session = CCSession(
            id: "session-1",
            filePath: URL(fileURLWithPath: "/test.jsonl"),
            firstUserMessage: "Test",
            timestamp: Date(),
            messageCount: 5
        )
        let project = CCProject(folderName: "-test-project", sessions: [session])

        let result = SearchResult(
            id: "result-1",
            project: project,
            session: session,
            matchingMessages: [],
            preview: "matching preview text",
            isContentMatch: true
        )

        XCTAssertEqual(result.session.id, "session-1")
        XCTAssertEqual(result.project.displayName, "test/project")
        XCTAssertEqual(result.preview, "matching preview text")
        XCTAssertTrue(result.isContentMatch)
    }

    func testSearchResultTitleMatch() {
        let session = CCSession(
            id: "session-2",
            filePath: URL(fileURLWithPath: "/test.jsonl"),
            firstUserMessage: "Matching title",
            timestamp: Date(),
            messageCount: 10
        )
        let project = CCProject(folderName: "project", sessions: [session])

        let result = SearchResult(
            id: "result-2",
            project: project,
            session: session,
            matchingMessages: [],
            preview: "",
            isContentMatch: false
        )

        XCTAssertFalse(result.isContentMatch)
        XCTAssertEqual(result.preview, "")
    }
}
