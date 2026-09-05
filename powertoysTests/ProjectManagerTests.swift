import XCTest
@testable import powertoys

@MainActor
final class ProjectManagerTests: XCTestCase {
    func testSessionSearchMatchesTitleIDAndProjectCaseInsensitively() {
        let manager = ProjectManager()
        let alpha = session(id: "alpha-id", title: "Fix Cloud Sync")
        let beta = session(id: "beta-needle", title: "Ruler work")
        manager.projects = [
            CCProject(folderName: "-Users-me-MacPowerToys", sessions: [alpha]),
            CCProject(folderName: "-Users-me-Utilities", sessions: [beta])
        ]

        XCTAssertEqual(manager.searchSessions(query: "CLOUD").map(\.id), [alpha.id])
        XCTAssertEqual(manager.searchSessions(query: "needle").map(\.id), [beta.id])
        XCTAssertEqual(manager.searchSessions(query: "macpowertoys").map(\.id), [alpha.id])
        XCTAssertTrue(manager.searchSessions(query: "").isEmpty)
    }

    func testShallowGlobalSearchUsesMetadataOnly() async {
        let manager = ProjectManager()
        let match = session(id: "one", title: "Color history")
        manager.projects = [CCProject(folderName: "-Users-me-Tools", sessions: [match])]

        let results = await manager.searchGlobally(query: "color", deepSearch: false)

        XCTAssertEqual(results.map(\.id), [match.id])
        XCTAssertFalse(results[0].isContentMatch)
        XCTAssertEqual(results[0].preview, "Color history")
    }

    func testDeepSearchFindsMessageContentAndMarksResult() async throws {
        let file = try jsonl([
            line(id: "message-1", type: "user", content: "A hidden regression needle")
        ])
        defer { try? FileManager.default.removeItem(at: file) }
        let target = CCSession(id: "session", filePath: file, firstUserMessage: "Unrelated title")
        let manager = ProjectManager()
        manager.projects = [CCProject(folderName: "-Users-me-Project", sessions: [target])]

        let results = await manager.searchGlobally(query: "regression needle", deepSearch: true)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, target.id)
        XCTAssertTrue(results[0].isContentMatch)
        XCTAssertTrue(results[0].preview.localizedCaseInsensitiveContains("regression needle"))
    }

    func testLoadMessagesUpdatesSelectionAndProjectMessageCount() async throws {
        let file = try jsonl([
            line(id: "one", type: "user", content: "Hello"),
            line(id: "two", type: "assistant", content: "Hi")
        ])
        defer { try? FileManager.default.removeItem(at: file) }
        let target = CCSession(id: "session", filePath: file, firstUserMessage: "Hello", messageCount: 0)
        let manager = ProjectManager()
        manager.projects = [CCProject(folderName: "-Users-me-Project", sessions: [target])]

        await manager.loadMessages(for: target)

        XCTAssertEqual(manager.currentMessages.map(\.id), ["one", "two"])
        XCTAssertEqual(manager.selectedSession?.id, target.id)
        XCTAssertEqual(manager.selectedSession?.messageCount, 2)
        XCTAssertEqual(manager.projects[0].sessions[0].messageCount, 2)
        XCTAssertFalse(manager.isLoadingMessages)
    }

    func testRefreshUpdatesExistingMessagesAndAppendsOnlyNewOnes() async throws {
        let file = try jsonl([line(id: "one", type: "user", content: "Before")])
        defer { try? FileManager.default.removeItem(at: file) }
        let target = CCSession(id: "session", filePath: file, firstUserMessage: "Before")
        let manager = ProjectManager()
        await manager.loadMessages(for: target)

        try [
            line(id: "one", type: "user", content: "After"),
            line(id: "two", type: "assistant", content: "New")
        ].joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        await manager.loadMessages(for: target, isRefresh: true)

        XCTAssertEqual(manager.currentMessages.map(\.id), ["one", "two"])
        XCTAssertEqual(manager.currentMessages.map(\.content), ["After", "New"])
    }

    func testJSONLParserStopsBeforeReadingWhenTaskIsCancelled() async throws {
        let file = try jsonl([line(id: "one", type: "user", content: "Should not load")])
        defer { try? FileManager.default.removeItem(at: file) }

        let task = Task.detached { CCHistoryParser.parseJSONLFile(at: file) }
        task.cancel()
        let messages = await task.value

        XCTAssertTrue(messages.isEmpty)
    }

    private func session(id: String, title: String) -> CCSession {
        CCSession(id: id, filePath: URL(fileURLWithPath: "/tmp/\(id).jsonl"), firstUserMessage: title)
    }

    private func jsonl(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("project-manager-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func line(id: String, type: String, content: String) -> String {
        let timestamp = "2026-07-13T10:20:30Z"
        return #"{"uuid":"\#(id)","type":"\#(type)","timestamp":"\#(timestamp)","message":{"content":"\#(content)"}}"#
    }
}
