import AIManagerCore
import AppKit
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class SwitchWorkspaceTests: XCTestCase {
    func testWorkspaceRendersSyntheticPagesInLightAndDark() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path])
        let model = SwitchWorkspaceModel(paths: paths)
        await model.load()

        let source = root.appending(path: "source")
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        let claims = try JSONSerialization.data(withJSONObject: [
            "email": "switch@example.test", "chatgpt_user_id": "render-user",
            "chatgpt_account_id": "render-account", "workspace_id": "render-workspace"
        ])
        let payload = claims.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let auth = try JSONSerialization.data(withJSONObject: ["tokens": [
            "id_token": "header.\(payload).signature",
            "access_token": "synthetic-access", "refresh_token": "synthetic-refresh",
            "account_id": "render-account"
        ]])
        try auth.write(to: source.appending(path: "auth.json"))
        await model.reviewImport(source: source, mode: .full)
        await model.commitImport(decisions: [:])
        XCTAssertEqual(model.accounts.count, 1)

        let sessions = paths.sharedRoot.appending(path: "sessions")
        try files.createDirectory(at: sessions, withIntermediateDirectories: true)
        let records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "render", "cwd": "/Projects/Example"]],
            ["type": "response_item", "payload": ["type": "message", "role": "user",
                "content": [["type": "input_text", "text": "How do I organize my projects?"]]]],
            ["type": "response_item", "payload": ["type": "message", "role": "assistant",
                "content": [["type": "output_text", "text": "Start with a small set of clear folders."]]]]
        ]
        let transcript = try records.map { try JSONSerialization.data(withJSONObject: $0) }
            .reduce(into: Data()) { data, line in
                data.append(line)
                data.append(10)
            }
        try transcript.write(to: sessions.appending(path: "render.jsonl"))
        await model.loadHistory()
        if let id = model.history.threads.first?.id {
            await model.selectThread(id, query: "", filter: .all)
        }
        await model.loadCleanup()
        XCTAssertNil(model.errorMessage)

        for size in [NSSize(width: 1_024, height: 720), NSSize(width: 880, height: 600)] {
            for scheme in [ColorScheme.light, .dark] {
                for page in SwitchPage.allCases {
                    let host = NSHostingView(rootView: SwitchWindowView(model: model, initialPage: page)
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme))
                    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    host.frame = NSRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(200))
                    host.layoutSubtreeIfNeeded()

                    let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: representation)
                    let image = NSImage(size: size)
                    image.addRepresentation(representation)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Switch — \(page.rawValue) — \(scheme == .dark ? "Dark" : "Light") — \(Int(size.width))"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

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
        await model.reviewCleanup(ids: ["missing"])
        XCTAssertNil(model.cleanupPlan)
        XCTAssertTrue(model.errorMessage?.contains("Select conversations") == true)
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

    func testAccountImportSwitchAndRemovalUseIsolatedCoreStore() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-accounts-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path])
        let model = SwitchWorkspaceModel(paths: paths)
        await model.load()

        for name in ["first", "second"] {
            let source = root.appending(path: "source-\(name)")
            try files.createDirectory(at: source, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])
            let claims = try JSONSerialization.data(withJSONObject: [
                "email": "\(name)@example.test", "chatgpt_user_id": "user-\(name)",
                "chatgpt_account_id": "account-\(name)", "workspace_id": "workspace-\(name)"
            ])
            let payload = claims.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let auth = try JSONSerialization.data(withJSONObject: ["tokens": [
                "id_token": "header.\(payload).signature",
                "access_token": "synthetic-access", "refresh_token": "synthetic-refresh",
                "account_id": "account-\(name)"
            ]])
            let authFile = source.appending(path: "auth.json")
            try auth.write(to: authFile, options: .atomic)
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
            await model.reviewImport(source: source, mode: .full)
            XCTAssertEqual(model.importPlan?.identity.email, "\(name)@example.test")
            await model.commitImport(decisions: [:])
            XCTAssertNil(model.errorMessage)
        }

        XCTAssertEqual(model.accounts.count, 2)
        let first = try XCTUnwrap(model.accounts.first { $0.identity.email == "first@example.test" })
        let second = try XCTUnwrap(model.accounts.first { $0.identity.email == "second@example.test" })
        await model.makeDefault(second.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.snapshot?.status.firstDefaultAccountID, second.id)
        await model.removeAccount(second.id, replacement: first.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.accounts.map(\.id), [first.id])
        XCTAssertEqual(model.snapshot?.status.firstDefaultAccountID, first.id)
    }

    func testConversationSearchFiltersAndPagesBeyondFirstMessages() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-messages-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path])
        let sessions = paths.sharedRoot.appending(path: "sessions")
        try files.createDirectory(at: sessions, withIntermediateDirectories: true)
        var records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "paged", "cwd": "/Projects/Paged"]]
        ]
        records += (0..<120).map { index in
            ["type": "response_item", "payload": ["type": "message", "role": "user",
                "content": [["type": "input_text", "text": "Message \(index) in order"]]]]
        }
        records.append(["type": "response_item", "payload": ["type": "message",
            "role": "assistant", "content": [["type": "output_text", "text": "Final answer target"]]]])
        var transcript = Data()
        for record in records {
            transcript.append(try JSONSerialization.data(withJSONObject: record))
            transcript.append(10)
        }
        try transcript.write(to: sessions.appending(path: "paged.jsonl"))

        let model = SwitchWorkspaceModel(paths: paths)
        await model.loadHistory()
        let id = try XCTUnwrap(model.history.threads.first?.id)
        await model.selectThread(id, query: "", filter: .all)
        XCTAssertEqual(model.selectedThread?.messages.count, 100)
        XCTAssertEqual(model.selectedThread?.messages.first?.text, "Message 0 in order")
        XCTAssertEqual(model.selectedThread?.nextOffset, 100)
        await model.loadMoreMessages()
        XCTAssertEqual(model.selectedThread?.messages.count, 121)
        XCTAssertEqual(model.selectedThread?.messages.last?.text, "Final answer target")
        XCTAssertNil(model.selectedThread?.nextOffset)

        await model.searchMessages(for: id, query: "Final target", filter: .responses)
        XCTAssertEqual(model.selectedThread?.matchingMessageCount, 1)
        XCTAssertEqual(model.selectedThread?.messages.map(\.text), ["Final answer target"])
        XCTAssertTrue(ChatTranscriptExport.text(for: model.selectedThread?.messages ?? [])
            .contains("Final answer target"))
        await model.searchMessages(for: id, query: "Final target", filter: .prompts)
        XCTAssertEqual(model.selectedThread?.matchingMessageCount, 0)
        XCTAssertTrue(model.selectedThread?.messages.isEmpty ?? false)
    }
}
