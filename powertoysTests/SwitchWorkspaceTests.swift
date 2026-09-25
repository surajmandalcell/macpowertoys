import AIManagerCore
import XCTest
@testable import powertoys

@MainActor
final class SwitchWorkspaceTests: XCTestCase {
    func testWorkspaceLoadsIsolatedCoreStoreWithoutStandaloneApp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpt-switch-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path])
        let model = SwitchWorkspaceModel(paths: paths)
        await model.load()

        XCTAssertNotNil(model.snapshot)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(
            model.snapshot?.status.sharedRoot,
            root.appending(path: "default-home", directoryHint: .isDirectory)
        )
        XCTAssertEqual(ToolRegistry.tool(for: "switch")?.logoAsset, "SwitchLogo")
        XCTAssertEqual(
            UtilityLayout.minimumContentSize(for: "switch"),
            NSSize(width: 880, height: 600)
        )
    }

    func testCleanupPreservesActivityBeforeMovingConversationToTrash() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-cleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path])
        let sessions = paths.sharedRoot.appending(path: "sessions", directoryHint: .isDirectory)
        try files.createDirectory(at: paths.sharedRoot, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        try files.createDirectory(at: sessions, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let source = sessions.appending(path: "synthetic.jsonl")
        let records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "synthetic", "cwd": "/Projects/Synthetic"]],
            ["type": "response_item", "payload": ["type": "message", "role": "user",
                "content": [["type": "input_text", "text": "Synthetic conversation"]]]],
            ["timestamp": "2026-09-18T12:00:00Z", "type": "event_msg",
                "payload": ["type": "token_count", "info": ["total_token_usage": ["total_tokens": 123]]]]
        ]
        var transcript = Data()
        for record in records {
            transcript.append(try JSONSerialization.data(withJSONObject: record))
            transcript.append(10)
        }
        try transcript.write(to: source)

        let model = SwitchWorkspaceModel(paths: paths)
        await model.load()
        await model.loadCleanup()
        let item = try XCTUnwrap(model.cleanupItems.first)
        XCTAssertEqual(item.title, "Synthetic conversation")
        XCTAssertNil(item.exclusionReason)
        await model.reviewCleanup(ids: [item.id])
        XCTAssertNotNil(model.cleanupPlan)
        await model.moveReviewedConversationsToTrash()

        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(files.fileExists(atPath: source.path))
        XCTAssertEqual(model.cleanupTrash.count, 1)
        let activity = try CodexUsageStatisticsCache(
            databaseURL: paths.applicationSupport.appending(path: "cache/account-usage.sqlite"),
            activityDatabaseURL: paths.applicationSupport.appending(path: "activity/daily.sqlite")
        )
        let projects = try await activity.projectActivity(on: "2026-09-18")
        XCTAssertEqual(projects.reduce(0) { $0 + $1.tokens }, 123)

        let batch = try XCTUnwrap(model.cleanupTrash.first)
        await model.restoreTrash(batch.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(files.fileExists(atPath: source.path))
        XCTAssertEqual(model.cleanupItems.first?.title, "Synthetic conversation")
    }
}
