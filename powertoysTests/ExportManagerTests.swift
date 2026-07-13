import XCTest
@testable import powertoys

final class ExportManagerTests: XCTestCase {
    func testMarkdownExportIncludesRolesContentAndToolDetails() {
        let output = ExportManager.formatMessages([message()], format: .markdown)

        XCTAssertTrue(output.hasPrefix("# Conversation Export"))
        XCTAssertTrue(output.contains("## Claude"))
        XCTAssertTrue(output.contains("Answer text"))
        XCTAssertTrue(output.contains("**Read**"))
        XCTAssertTrue(output.contains("```json\n{\"path\":\"file\"}\n```"))
        XCTAssertTrue(output.contains("Output:\n```\ncontents\n```"))
    }

    func testPlainTextExportIncludesRoleAndToolSummary() {
        let output = ExportManager.formatMessages([message()], format: .plainText)

        XCTAssertTrue(output.hasPrefix("Conversation Export"))
        XCTAssertTrue(output.contains("[CLAUDE]"))
        XCTAssertTrue(output.contains("Tool Calls:\n  - Read"))
    }

    func testJSONExportProducesStructuredPortableData() throws {
        let data = try XCTUnwrap(ExportManager.formatMessages([message()], format: .json).data(using: .utf8))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let row = try XCTUnwrap(rows.first)

        XCTAssertEqual(row["id"] as? String, "message-1")
        XCTAssertEqual(row["type"] as? String, "assistant")
        XCTAssertEqual(row["content"] as? String, "Answer text")
        XCTAssertEqual(row["thinking"] as? String, "Reasoning")
        XCTAssertEqual((row["toolUse"] as? [[String: Any]])?.first?["output"] as? String, "contents")
        XCTAssertNotNil(ISO8601DateFormatter().date(from: try XCTUnwrap(row["timestamp"] as? String)))
    }

    func testEmptyExportsRemainValid() throws {
        XCTAssertTrue(ExportManager.formatMessages([], format: .markdown).hasPrefix("# Conversation Export"))
        XCTAssertTrue(ExportManager.formatMessages([], format: .plainText).hasPrefix("Conversation Export"))
        let data = try XCTUnwrap(ExportManager.formatMessages([], format: .json).data(using: .utf8))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        XCTAssertTrue(rows.isEmpty)
    }

    private func message() -> CCMessage {
        CCMessage(
            id: "message-1",
            type: .assistant,
            content: "Answer text",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            parentUuid: "parent",
            toolUse: [ToolUseBlock(id: "tool-1", name: "Read", input: "{\"path\":\"file\"}", output: "contents")],
            thinking: "Reasoning",
            sessionId: "session"
        )
    }
}
