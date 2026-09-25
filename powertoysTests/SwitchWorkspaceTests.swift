import AIManagerCore
import AppKit
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class SwitchWorkspaceTests: XCTestCase {
    func testAppletRendersOriginalAccountsBackupAndSettingsLayout() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let model = SwitchWorkspaceModel(paths: ManagerPaths.environment(["AI_MANAGER_ROOT": root.path]))
        await model.load()

        for size in [NSSize(width: 1_120, height: 740), NSSize(width: 880, height: 600)] {
            for scheme in [ColorScheme.light, .dark] {
                try await attachRender(of: .accounts, model: model, size: size,
                                       scheme: scheme, state: "Empty")
            }
        }

        try await importAccount(named: "first", into: model, root: root)
        try await importAccount(named: "second", into: model, root: root)
        XCTAssertEqual(model.accounts.count, 2)
        let first = try XCTUnwrap(model.accounts.first { $0.identity.email == "first@example.test" })
        let second = try XCTUnwrap(model.accounts.first { $0.identity.email == "second@example.test" })
        await model.makeDefault(first.id)
        await model.refresh()
        XCTAssertTrue(model.discoveries.contains { $0.identity?.accountID == "account-first" })
        XCTAssertFalse(model.importableDiscoveries.contains {
            $0.identity?.accountID == "account-first"
        })
        model.selectedAccountID = second.id
        model.setUsageForRender(sampleUsage(), accountID: second.id)

        for size in [NSSize(width: 1_120, height: 740), NSSize(width: 880, height: 600)] {
            for scheme in [ColorScheme.light, .dark] {
                for page in SwitchPage.allCases {
                    try await attachRender(of: page, model: model, size: size,
                                           scheme: scheme, state: "Populated")
                }
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            try await attachTrayRender(model: model, scheme: scheme)
        }
    }

    private func attachRender(of page: SwitchPage, model: SwitchWorkspaceModel,
                              size: NSSize, scheme: ColorScheme, state: String) async throws {
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
        attachment.name = "Switch — \(state) — \(page.rawValue) — \(scheme == .dark ? "Dark" : "Light") — \(Int(size.width))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func sampleUsage() -> CodexAccountUsageSnapshot {
        let main = CodexRateLimitBucketSnapshot(
            id: "codex", name: "Codex", plan: "Plus", model: "gpt-5.6-sol",
            primary: .init(usedPercent: 42, windowDurationMinutes: 300,
                           resetsAt: .now.addingTimeInterval(84 * 60)),
            secondary: .init(usedPercent: 53, windowDurationMinutes: 10_080,
                             resetsAt: .now.addingTimeInterval(172_740)),
            credits: .init(hasCredits: true, unlimited: false, balance: "12.50"),
            spendControlReached: false)
        let fast = CodexRateLimitBucketSnapshot(
            id: "fast", name: "Fast models", plan: "Plus", model: "gpt-5.6-luna",
            primary: .init(usedPercent: 50, windowDurationMinutes: 1_440,
                           resetsAt: .now.addingTimeInterval(7_140)),
            secondary: nil, credits: nil, spendControlReached: false)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let daily = (0..<90).map { offset in
            CodexDailyUsageSnapshot(startDate: formatter.string(from: Date.now.addingTimeInterval(-Double(offset) * 86_400)),
                                    tokens: offset.isMultiple(of: 5) ? 0 : Int64(10_000 + offset * 900))
        }
        return CodexAccountUsageSnapshot(
            account: .init(kind: "chatgpt", email: "second@example.test", plan: "plus"),
            requiresOpenAIAuthentication: true,
            rateLimits: .init(accountID: "account-second", ordinaryUsageAllowed: true,
                              defaultBucket: main, buckets: ["fast": fast]),
            usage: .init(lifetimeTokens: 2_800_000, peakDailyTokens: 184_000,
                         currentStreakDays: 4, longestStreakDays: 12,
                         longestRunningTurnSeconds: 214),
            dailyUsage: daily, fetchedAt: .now)
    }

    private func attachTrayRender(model: SwitchWorkspaceModel, scheme: ColorScheme) async throws {
        let size = NSSize(width: 360, height: 240)
        let host = NSHostingView(rootView: SwitchTrayView(model: model)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
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
        attachment.name = "Switch — Quick Menu — \(scheme == .dark ? "Dark" : "Light")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAppletLoadsCoreStoreWithoutStandaloneApp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpt-switch-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = SwitchWorkspaceModel(paths: ManagerPaths.environment(["AI_MANAGER_ROOT": root.path]))
        await model.load()

        XCTAssertNotNil(model.snapshot)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.snapshot?.status.sharedRoot,
                       root.appending(path: "default-home", directoryHint: .isDirectory))
        XCTAssertEqual(ToolRegistry.tool(for: "switch")?.logoAsset, "SwitchLogo")
        XCTAssertEqual(UtilityLayout.minimumContentSize(for: "switch"),
                       NSSize(width: 880, height: 600))
    }

    func testAccountImportSwitchAndRemovalUseIsolatedCoreStore() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-accounts-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let model = SwitchWorkspaceModel(paths: ManagerPaths.environment(["AI_MANAGER_ROOT": root.path]))
        await model.load()

        try await importAccount(named: "first", into: model, root: root)
        try await importAccount(named: "second", into: model, root: root)
        XCTAssertEqual(model.accounts.count, 2)
        let first = try XCTUnwrap(model.accounts.first { $0.identity.email == "first@example.test" })
        let second = try XCTUnwrap(model.accounts.first { $0.identity.email == "second@example.test" })
        await model.moveAccount(second.id, by: -1)
        XCTAssertEqual(model.accounts.map(\.id), [second.id, first.id])

        await model.makeDefault(second.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.snapshot?.status.firstDefaultAccountID, second.id)
        await model.removeAccount(second.id, replacement: first.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.accounts.map(\.id), [first.id])
        XCTAssertEqual(model.snapshot?.status.firstDefaultAccountID, first.id)
    }

    func testOpeningAnIsolatedAccountPreparesLaunchWithoutStartingTerminal() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-open-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "codex")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let paths = ManagerPaths.environment([
            "AI_MANAGER_ROOT": root.path,
            "AI_MANAGER_CODEX_EXECUTABLE": executable.path
        ])
        let model = SwitchWorkspaceModel(paths: paths)
        await model.load()
        try await importAccount(named: "first", into: model, root: root)
        try await importAccount(named: "second", into: model, root: root)
        let first = try XCTUnwrap(model.accounts.first { $0.identity.email == "first@example.test" })
        let second = try XCTUnwrap(model.accounts.first { $0.identity.email == "second@example.test" })
        await model.makeDefault(first.id)

        await model.openAccount(second.id)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.snapshot?.status.firstDefaultAccountID, second.id)
        let script = paths.applicationSupport.appending(path: "Launch/Open MacPowerToys Switch.command")
        let contents = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(contents.contains("unset OPENAI_API_KEY CODEX_ACCESS_TOKEN XAI_API_KEY"))
        XCTAssertTrue(contents.contains("exec '\(executable.path)'"))
        XCTAssertEqual(try files.attributesOfItem(atPath: script.path)[.posixPermissions] as? Int,
                       0o700)
    }

    private func importAccount(named name: String, into model: SwitchWorkspaceModel,
                               root: URL) async throws {
        let files = FileManager.default
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
}
