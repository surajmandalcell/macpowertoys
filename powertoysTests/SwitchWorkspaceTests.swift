import AIManagerCore
import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class SwitchWorkspaceTests: XCTestCase {
    func testUsageFactsFitShortLabelsAndValuesWithinTwoRows() {
        let snapshot = sampleUsage()
        let host = NSHostingView(rootView: SwitchWindowView.usageFacts(snapshot).frame(width: 992))
        host.layoutSubtreeIfNeeded()
        let cell = NSHostingView(rootView: OnePlusStatCell("Authentication", value: "Verified locally").fixedSize())
        cell.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(cell.fittingSize.width, 992 / 7)
        XCTAssertLessThan(cell.fittingSize.width, (992 - 3) / 4)
        XCTAssertEqual(host.fittingSize.height, cell.fittingSize.height * 2 + 1, accuracy: 1)
    }

    func testActivityDateLabelsStayUTCAndWeeksFollowTheLocale() throws {
        let previousZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        defer { NSTimeZone.default = previousZone }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let now = try XCTUnwrap(formatter.date(from: "2026-01-01"))
        let rows = [CodexDailyUsageSnapshot(startDate: "2026-01-01", tokens: 1_234),
                    CodexDailyUsageSnapshot(startDate: "2025-12-26", tokens: 42),
                    CodexDailyUsageSnapshot(startDate: "2025-12-32", tokens: 999)]
        for firstWeekday in [1, 2] {
            let result = SwitchActivityGrid.makePresentation(rows: rows, period: .weekly, now: now,
                                                            locale: Locale(identifier: "en_US"), firstWeekday: firstWeekday)
            let day = try XCTUnwrap(result.weeks.last?.compactMap { $0 }.last)
            XCTAssertEqual(day.shortLabel, "Jan 1, 2026")
            XCTAssertEqual(day.accessibilityLabel, "Thursday, January 1, 2026")
            XCTAssertEqual(day.tokenLabel, "1,234 tokens")
            XCTAssertEqual(result.weeks[0].firstIndex { $0 != nil }, firstWeekday == 1 ? 5 : 4)
            XCTAssertEqual(result.weeks[1].lastIndex { $0 != nil }, firstWeekday == 1 ? 4 : 3)
            XCTAssertEqual(result.totals["weekly"], 1_276)
        }
        let german = SwitchActivityGrid.makePresentation(rows: rows, period: .today, now: now,
                                                        locale: Locale(identifier: "de_DE"), firstWeekday: 2)
        let day = try XCTUnwrap(german.weeks.flatMap { $0 }.compactMap { $0 }.first)
        XCTAssertEqual(day.shortLabel, "1. Jan. 2026")
        XCTAssertEqual(day.tokenLabel, "1.234 tokens")
    }

    func testDailyActivityKeepsItsHeightWhileLoadingRefreshingAndEmpty() async throws {
        let snapshot = sampleUsage()
        let host = NSHostingView(rootView: SwitchActivityGrid(rows: nil, updatedAt: nil)
            .frame(width: 992))
        host.layoutSubtreeIfNeeded()
        let pendingHeight = host.fittingSize.height
        let totals = NSHostingView(rootView: OnePlusStatCell("Today", value: "-"))
        totals.layoutSubtreeIfNeeded()
        // Reserve all chart rows and insets; totals use the current shared type.
        XCTAssertEqual(pendingHeight, 40 + 7 * 10 + 6 * 2 + 2 * 16 + totals.fittingSize.height,
                       accuracy: 1)

        host.rootView = SwitchActivityGrid(rows: snapshot.dailyUsage, updatedAt: snapshot.fetchedAt)
            .frame(width: 992)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, pendingHeight, accuracy: 1)

        host.rootView = SwitchActivityGrid(rows: nil, updatedAt: nil).frame(width: 992)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, pendingHeight, accuracy: 1)

        host.rootView = SwitchActivityGrid(rows: [], updatedAt: snapshot.fetchedAt.addingTimeInterval(1))
            .frame(width: 992)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, pendingHeight, accuracy: 1)

        host.rootView = SwitchActivityGrid(rows: nil, updatedAt: nil, error: "Synthetic usage failure")
            .frame(width: 992)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, pendingHeight, accuracy: 1)
    }

    func testAppletRendersSharedCardsAtFixedCanvasInBothAppearances() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let model = SwitchWorkspaceModel(paths: ManagerPaths.environment(["AI_MANAGER_ROOT": root.path]))
        await model.load()

        for size in [NSSize(width: 1_240, height: 840)] {
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

        for size in [NSSize(width: 1_240, height: 840)] {
            for scheme in [ColorScheme.light, .dark] {
                for page in SwitchPage.allCases {
                    try await attachRender(of: page, model: model, size: size,
                                           scheme: scheme, state: "Populated")
                }
            }
        }
        XCTAssertEqual(model.selectedAccount?.verification.state.rawValue,
                       VerificationState.verifiedWithCodex.rawValue)
        for scheme in [ColorScheme.light, .dark] {
            try await attachTrayRender(model: model, scheme: scheme)
        }
    }

    func testSwitchPageRoutesAcceptSavedAccountIDsAndRejectMalformedIDs() {
        let id = UUID(uuidString: "52E4321A-F67C-4874-BA55-8D6E70719EC7")!
        XCTAssertEqual(SwitchPageRoute(pageID: "account/\(id.uuidString)"), .account(id))
        XCTAssertEqual(SwitchPageRoute(pageID: "account/\(id.uuidString.lowercased())"), .account(id))
        XCTAssertEqual(SwitchPageRoute(pageID: "accounts"), .accounts)
        XCTAssertEqual(SwitchPageRoute(pageID: "add"), .add)
        XCTAssertEqual(SwitchPageRoute(pageID: "backup"), .backup)
        XCTAssertEqual(SwitchPageRoute(pageID: "settings"), .settings)
        XCTAssertEqual(SwitchPageRoute(pageID: "about"), .about)
        for invalid in ["account/", "account/not-an-id", "account/\(id.uuidString)/extra", "unknown"] {
            XCTAssertNil(SwitchPageRoute(pageID: invalid))
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

    private func sampleUsage(now: Date = .now) -> CodexAccountUsageSnapshot {
        let main = CodexRateLimitBucketSnapshot(
            id: "codex", name: "Codex", plan: "Plus", model: "gpt-5.6-sol",
            primary: .init(usedPercent: 42, windowDurationMinutes: 300,
                           resetsAt: now.addingTimeInterval(84 * 60)),
            secondary: .init(usedPercent: 53, windowDurationMinutes: 10_080,
                             resetsAt: now.addingTimeInterval(172_740)),
            credits: .init(hasCredits: true, unlimited: false, balance: "12.50"),
            spendControlReached: false)
        let fast = CodexRateLimitBucketSnapshot(
            id: "fast", name: "Fast models", plan: "Plus", model: "gpt-5.6-luna",
            primary: .init(usedPercent: 50, windowDurationMinutes: 1_440,
                           resetsAt: now.addingTimeInterval(7_140)),
            secondary: nil, credits: nil, spendControlReached: false)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let daily = (0..<90).map { offset in
            CodexDailyUsageSnapshot(startDate: formatter.string(from: now.addingTimeInterval(-Double(offset) * 86_400)),
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
            dailyUsage: daily, fetchedAt: now)
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
        XCTAssertEqual(OnePlusWindowCanvas.tool("switch")?.size,
                       NSSize(width: 1240, height: 840))
    }

    func testTrayUsageChoicesRespectDefaultsAndOverrides() throws {
        let name = "mpt-switch-prefs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let accountID = UUID()
        XCTAssertTrue(SwitchTrayUsagePreferences.showsUsage(for: accountID, defaults: defaults))
        defaults.set(false, forKey: SwitchTrayUsagePreferences.defaultKey)
        XCTAssertFalse(SwitchTrayUsagePreferences.showsUsage(for: accountID, defaults: defaults))
        SwitchTrayUsagePreferences.setOverride(true, for: accountID, defaults: defaults)
        XCTAssertTrue(SwitchTrayUsagePreferences.showsUsage(for: accountID, defaults: defaults))
        SwitchTrayUsagePreferences.setOverride(false, for: accountID, defaults: defaults)
        XCTAssertFalse(SwitchTrayUsagePreferences.showsUsage(for: accountID, defaults: defaults))
        SwitchTrayUsagePreferences.useDefault(for: accountID, defaults: defaults)
        XCTAssertNil(SwitchTrayUsagePreferences.explicitValue(for: accountID, defaults: defaults))
        XCTAssertEqual(SwitchTrayUsagePreferences.percentageLabel(used: 120, showUsed: false), "0% left")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = sampleUsage(now: now)
        let sinceReset = SwitchTrayTokenPeriod.sinceReset.tokens(in: snapshot, now: now)
        XCTAssertGreaterThan(sinceReset, 0)
        XCTAssertLessThan(sinceReset, SwitchTrayTokenPeriod.weekly.tokens(in: snapshot, now: now))
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

    func testRetainedUsageSurvivesFailureAndClearsQuotasWhenSignInIsRequired() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "mpt-switch-cache-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path,
                                               "AI_MANAGER_CODEX_EXECUTABLE": root.appending(path: "missing-codex").path])
        let model = SwitchWorkspaceModel(paths: paths)
        await model.load()
        try await importAccount(named: "cached", into: model, root: root)
        let account = try XCTUnwrap(model.accounts.first)
        let cached = sampleUsage()
        let cache = try CodexUsageStatisticsCache(
            databaseURL: paths.applicationSupport.appending(path: "cache/account-usage.sqlite"),
            activityDatabaseURL: paths.applicationSupport.appending(path: "activity/daily.sqlite"))
        try await cache.upsertSuccess(accountID: account.id, snapshot: cached)
        try await cache.upsertSuccess(accountID: account.id, snapshot: .init(
            account: cached.account, requiresOpenAIAuthentication: cached.requiresOpenAIAuthentication,
            rateLimits: cached.rateLimits, usage: cached.usage, dailyUsage: [],
            fetchedAt: cached.fetchedAt.addingTimeInterval(1)))
        try "model = \"gpt-test\"\n".write(to: paths.defaultHome.appending(path: "config.toml"),
                                         atomically: true, encoding: .utf8)
        try Data("{\"gpt-test\":{\"input_cost_per_token\":0.000002,\"output_cost_per_token\":0.00001}}".utf8)
            .write(to: paths.applicationSupport.appending(path: "cache/model-pricing.json"))
        await model.loadAPIPricing()
        XCTAssertEqual(model.apiPrice?.inputEquivalent(for: 1_000_000), 2)
        XCTAssertEqual(model.apiPrice?.outputEquivalent(for: 1_000_000), 10)

        await model.refresh()
        XCTAssertEqual(model.dailyUsage[account.id]?.count, cached.dailyUsage.count)
        let defaultBefore = model.snapshot?.status.firstDefaultAccountID
        await model.loadUsage(account.id)
        XCTAssertNotNil(model.usage[account.id])
        XCTAssertNotNil(model.usageErrors[account.id])
        XCTAssertEqual(model.snapshot?.status.firstDefaultAccountID, defaultBefore)

        let originalAuth = try Data(contentsOf: account.credentialFile)
        try Data("{}".utf8).write(to: account.credentialFile, options: .atomic)
        await model.verify(account.id)
        XCTAssertEqual(model.selectedAccount?.verification.state, .needsSignIn)
        XCTAssertNil(model.usage[account.id])
        XCTAssertEqual(model.dailyUsage[account.id]?.count, cached.dailyUsage.count)
        try originalAuth.write(to: account.credentialFile, options: .atomic)
        let reopened = SwitchWorkspaceModel(paths: paths)
        await reopened.load()
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.accounts.count, 1)
        XCTAssertNil(reopened.usage[account.id])
        XCTAssertEqual(reopened.dailyUsage[account.id]?.count, cached.dailyUsage.count)
    }

    func testDailyActivityUsesYesterdayAndKeepsTotalsOutsideTheSelectedPeriod() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let now = try XCTUnwrap(formatter.date(from: "2026-10-01"))
        let rows: [CodexDailyUsageSnapshot] = [
            .init(startDate: "2026-10-01", tokens: 10),
            .init(startDate: "2026-09-30", tokens: 30),
            .init(startDate: "2026-09-31", tokens: 999),
            .init(startDate: "2026-09-30", tokens: -10),
            .init(startDate: "2025-12-31", tokens: 1_000_000)]
        let yesterday = SwitchActivityGrid.makePresentation(rows: rows, period: .yesterday, now: now)
        let days = yesterday.weeks.flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(days.map(\.date), [try XCTUnwrap(formatter.date(from: "2026-09-30"))])
        XCTAssertEqual(days.map(\.tokens), [30])
        XCTAssertEqual(days.first?.level, 0)
        XCTAssertEqual(yesterday.totals["today"], 10)
        XCTAssertEqual(yesterday.totals["yesterday"], 30)
        let emptyToday = SwitchActivityGrid.makePresentation(rows: Array(rows.suffix(1)), period: .today, now: now)
        XCTAssertTrue(emptyToday.hasData)
        XCTAssertEqual(emptyToday.totals["today"], 0)
        let overflow = SwitchActivityGrid.makePresentation(rows: [
            .init(startDate: "2026-10-01", tokens: Int64.max),
            .init(startDate: "2026-10-01", tokens: 1)], period: .today, now: now)
        XCTAssertEqual(overflow.weeks.flatMap { $0 }.compactMap { $0 }.first?.tokens, Int64.max)
    }

    func testFailedSwitchReconcilesCoreStatusAndPreservesTheDefault() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "mpt-switch-fault-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path])
        let model = SwitchWorkspaceModel(paths: paths)
        await model.load()
        try await importAccount(named: "first", into: model, root: root)
        try await importAccount(named: "second", into: model, root: root)
        let first = try XCTUnwrap(model.accounts.first { $0.identity.email == "first@example.test" })
        let second = try XCTUnwrap(model.accounts.first { $0.identity.email == "second@example.test" })
        await model.makeDefault(first.id)
        let manager = try AccountManager(paths: paths, writerCheck: { _ in .inactive }, faultInjector: { point in
            if point == .afterDefaultCredentialPublication { throw AIManagerError.operationFailed("Synthetic switch interruption") }
        })
        let interrupted = SwitchWorkspaceModel(paths: paths, manager: manager)
        await interrupted.load()
        await interrupted.makeDefault(second.id)
        let current = try await manager.status()
        XCTAssertNotNil(interrupted.errorMessage)
        XCTAssertFalse(interrupted.isWorking)
        XCTAssertEqual(interrupted.snapshot?.status, current)
        XCTAssertEqual(current.firstDefaultAccountID, first.id)
    }

    func testClaudeProfilesResumeVerifyAndLaunchWithoutChangingCodex() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "mpt-switch-claude-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "claude")
        try "#!/bin/sh\nprintf '%s\\n' '{\"loggedIn\":true,\"email\":\"claude@example.test\"}'\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path,
                                               "AI_MANAGER_CLAUDE_EXECUTABLE": executable.path])
        let runner = AccountLoginRunner(launch: { _, _ in })
        let manager = try AccountManager(paths: paths, writerCheck: { _ in .inactive }, loginRunner: runner)
        let model = SwitchWorkspaceModel(paths: paths, manager: manager)
        await model.load()
        try await importAccount(named: "codex", into: model, root: root)
        let codex = try XCTUnwrap(model.accounts.first)
        await model.makeDefault(codex.id)
        await model.beginLogin(providerID: .claudeCode)

        let reopened = SwitchWorkspaceModel(paths: paths, manager: manager)
        await reopened.load()
        XCTAssertNotNil(reopened.login)
        await reopened.checkLogin()
        let claude = try XCTUnwrap(reopened.accounts.first { $0.identity.providerID == .claudeCode })
        await reopened.verify(claude.id)
        await reopened.openAccount(claude.id)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.snapshot?.status.defaultAccountID(for: .codex), codex.id)
        XCTAssertEqual(reopened.snapshot?.status.defaultAccountID(for: .claudeCode), claude.id)
        let script = paths.applicationSupport.appending(path: "Launch/Open MacPowerToys Switch.command")
        let contents = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(contents.contains("export CLAUDE_CONFIG_DIR='\(claude.home.path)'"))
        XCTAssertTrue(contents.contains("unset OPENAI_API_KEY CODEX_ACCESS_TOKEN XAI_API_KEY ANTHROPIC_API_KEY"))
        XCTAssertNil(reopened.usage[claude.id])
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
