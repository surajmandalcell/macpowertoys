import AIManagerCore
import AppKit
import Foundation
import Observation

enum SwitchTrayUsagePreferences {
    static let defaultKey = "switchTrayShowsUsage"
    static let periodKey = "switchTrayTokenPeriod"
    private static let overridePrefix = "switchTrayShowsUsage.account."

    static func explicitValue(for id: UUID, defaults: UserDefaults = .standard) -> Bool? {
        let key = overridePrefix + id.uuidString
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    static func showsUsage(for id: UUID, defaults: UserDefaults = .standard) -> Bool {
        explicitValue(for: id, defaults: defaults)
            ?? (defaults.object(forKey: defaultKey) == nil || defaults.bool(forKey: defaultKey))
    }

    static func setOverride(_ value: Bool, for id: UUID, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: overridePrefix + id.uuidString)
    }

    static func useDefault(for id: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: overridePrefix + id.uuidString)
    }

    static func percentageLabel(used: Int, showUsed: Bool) -> String {
        let clamped = min(max(used, 0), 100)
        return "\(showUsed ? clamped : 100 - clamped)% \(showUsed ? "used" : "left")"
    }
}

enum SwitchTrayTokenPeriod: String, CaseIterable, Identifiable {
    case sinceReset, today, yesterday, weekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sinceReset: "Since reset"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    func tokens(in snapshot: CodexAccountUsageSnapshot, dailyUsage: [CodexDailyUsageSnapshot]? = nil,
                now: Date = .now) -> Int64 {
        let rows = dailyUsage ?? snapshot.dailyUsage
        if let period = CodexTokenPeriod(rawValue: rawValue) {
            return period.tokens(in: rows, endingAt: now)
        }
        let windows = [snapshot.rateLimits?.defaultBucket?.primary,
                       snapshot.rateLimits?.defaultBucket?.secondary].compactMap { $0 }
        guard let weekly = windows.filter({ ($0.windowDurationMinutes ?? 0) >= 10_080 })
            .max(by: { ($0.windowDurationMinutes ?? 0) < ($1.windowDurationMinutes ?? 0) }),
              let reset = weekly.resetsAt, let minutes = weekly.windowDurationMinutes,
              minutes > 0 else {
            return CodexTokenPeriod.weekly.tokens(in: rows, endingAt: now)
        }
        return CodexTokenPeriod.tokens(in: rows,
                                       from: reset.addingTimeInterval(-Double(minutes) * 60),
                                       through: now)
    }
}

@Observable
@MainActor
final class SwitchWorkspaceModel {
    static let shared = SwitchWorkspaceModel()

    private(set) var snapshot: AccountSnapshot?
    private(set) var usage: [UUID: CodexAccountUsageSnapshot] = [:]
    private(set) var usageLoading: Set<UUID> = []
    private(set) var usageErrors: [UUID: String] = [:]
    private var usageAttempts: Set<UUID> = []
    private(set) var dailyUsage: [UUID: [CodexDailyUsageSnapshot]] = [:]
    private(set) var apiPrice: CodexAPIPrice?
    private(set) var usageCacheError: String?
    private(set) var noticeMessage: String?
    private(set) var lastBackupURL: URL?
    private(set) var login: AccountLoginSession?
    private(set) var loginState: AccountLoginState?
    private(set) var loginMessage: String?
    private(set) var importPlan: ImportPlan?
    private(set) var isWorking = false
    var errorMessage: String?
    var selectedAccountID: UUID?

    @ObservationIgnored private var manager: AccountManager?
    @ObservationIgnored private var usageCache: CodexUsageStatisticsCache?
    @ObservationIgnored private var pricingResolver: CodexAPIPricingResolver?
    let paths: ManagerPaths

    init(paths: ManagerPaths = .environment(), manager: AccountManager? = nil) {
        self.paths = paths
        self.manager = manager
    }

    var accounts: [AccountRecord] { snapshot?.status.accounts ?? [] }
    var discoveries: [DiscoveredSource] { snapshot?.discoveries ?? [] }
    var importableDiscoveries: [DiscoveredSource] {
        discoveries.filter { source in
            guard source.support == .supportedChatGPT || source.support == .supportedOAuth else {
                return false
            }
            return !accounts.contains { account in
                if account.source.standardizedFileURL == source.path.standardizedFileURL { return true }
                guard let identity = source.identity else { return false }
                return account.identity.providerID == identity.providerID
                    && account.identity.authMode == identity.authMode
                    && identity.userID != nil && account.identity.userID == identity.userID
                    && identity.accountID != nil && account.identity.accountID == identity.accountID
                    && (identity.providerID != .grokBuild
                        || account.identity.workspaceID == identity.workspaceID)
            }
        }
    }
    var selectedAccount: AccountRecord? {
        accounts.first { $0.id == selectedAccountID }
    }
    var pendingRecovery: [RecoveryOperation] { snapshot?.status.pendingRecovery ?? [] }
    var linkedSettingsIssues: [LinkedSettingsDivergence] {
        snapshot?.status.linkedSettingsDivergences ?? []
    }

    func load() async {
        guard let manager = await prepareManager() else { return }
        await perform {
            let refreshed = try await manager.refreshAccounts()
            self.apply(refreshed)
            await self.loadCachedUsage()
        }
    }

    func refresh() async { await load() }

    func makeDefault(_ id: UUID) async {
        guard let manager else { return }
        await perform {
            let result = try await manager.switchDefault(to: id)
            self.lastBackupURL = result.backup
            self.noticeMessage = "New \(self.accounts.first { $0.id == id }?.identity.providerID.displayName ?? "provider") sessions will use this account."
            self.apply(try await manager.refreshAccounts(includeDiscoveries: false))
        }
    }

    func openAccount(_ id: UUID) async {
        guard let manager, let account = accounts.first(where: { $0.id == id }) else { return }
        await perform {
            if self.snapshot?.status.isDefault(account) != true {
                self.lastBackupURL = try await manager.switchDefault(to: id).backup
                self.apply(try await manager.refreshAccounts(includeDiscoveries: false))
            }
            let spec = try await manager.launchSpec(accountID: id)
            let paths = self.paths
            let script = try await Task.detached(priority: .userInitiated) {
                try Self.makeLaunchArtifact(spec, paths: paths)
            }.value
            if self.paths.isolationRoot == nil && !NSWorkspace.shared.open(script) {
                throw AIManagerError.operationFailed("Terminal could not open this account.")
            }
            self.noticeMessage = self.paths.isolationRoot == nil
                ? "Terminal accepted the \(account.identity.providerID.displayName) launch request."
                : "The launch file is ready. Terminal was not opened."
        }
    }

    func moveAccount(_ id: UUID, by offset: Int) async {
        guard let manager, let source = accounts.firstIndex(where: { $0.id == id }),
              accounts.indices.contains(source + offset) else { return }
        var ids = accounts.map(\.id)
        ids.insert(ids.remove(at: source), at: source + offset)
        await perform { self.snapshot?.status = try await manager.reorderAccounts(ids) }
    }

    func verify(_ id: UUID) async {
        guard let manager, !isWorking, !usageLoading.contains(id) else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let result = await manager.checkAccount(accountID: id)
        await recordUsage(result, accountID: id)
        do {
            applyStatus(try await manager.status())
            if result.verification.state == .needsSignIn || result.verification.state == .unsupported {
                errorMessage = result.verification.detail
            } else {
                noticeMessage = result.verification.detail
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadUsage(_ id: UUID, onlyIfNeeded: Bool = false) async {
        guard let manager, !isWorking, !usageLoading.contains(id),
              !onlyIfNeeded || !usageAttempts.contains(id),
              accounts.contains(where: { $0.id == id && $0.identity.providerID == .codex })
        else { return }
        usageAttempts.insert(id)
        usageLoading.insert(id)
        usageErrors.removeValue(forKey: id)
        defer { usageLoading.remove(id) }
        let result = await manager.checkAccount(accountID: id)
        await recordUsage(result, accountID: id)
        do { applyStatus(try await manager.status()) }
        catch { usageErrors[id] = "The account list could not be refreshed. \(error.localizedDescription)" }
    }

    func refreshUsage() async {
        for account in accounts where account.identity.providerID == .codex
            && SwitchTrayUsagePreferences.showsUsage(for: account.id) {
            guard !Task.isCancelled else { return }
            await loadUsage(account.id)
        }
    }

    private func recordUsage(_ result: AccountCheckResult, accountID: UUID) async {
        guard let index = accounts.firstIndex(where: { $0.id == accountID && $0.identity.providerID == .codex }) else { return }
        snapshot?.status.accounts[index].verification = result.verification
        await prepareUsageCache()
        do {
            if let refreshed = result.usage {
                usage[accountID] = refreshed
                dailyUsage[accountID] = refreshed.dailyUsage
                usageErrors.removeValue(forKey: accountID)
                try await usageCache?.upsertSuccess(accountID: accountID, snapshot: refreshed)
            } else {
                if result.verification.state == .needsSignIn { usage.removeValue(forKey: accountID) }
                usageErrors[accountID] = result.verification.detail
                try await usageCache?.recordFailure(accountID: accountID, failure:
                    result.verification.state == .needsSignIn ? .authenticationRequired : .unavailable)
            }
            await loadCachedUsage()
        } catch {
            usageCacheError = "Usage could not be saved. \(error.localizedDescription)"
        }
    }

    private func prepareUsageCache() async {
        guard usageCache == nil else { return }
        let support = paths.applicationSupport
        do {
            usageCache = try await Task.detached(priority: .utility) {
                try CodexUsageStatisticsCache(
                    databaseURL: support.appending(path: "cache/account-usage.sqlite"),
                    activityDatabaseURL: support.appending(path: "activity/daily.sqlite"))
            }.value
            usageCacheError = nil
        } catch {
            usageCacheError = "Usage history is unavailable. \(error.localizedDescription)"
        }
    }

    private func loadCachedUsage() async {
        await prepareUsageCache()
        guard let usageCache else { return }
        do {
            let accountIDs = accounts.filter { $0.identity.providerID == .codex }.map(\.id)
            let cached = try await usageCache.latest(for: accountIDs)
            for entry in cached {
                guard accounts.contains(where: { $0.id == entry.accountID }) else { continue }
                if entry.failure == .authenticationRequired
                    || accounts.first(where: { $0.id == entry.accountID })?.verification.state == .needsSignIn {
                    usage.removeValue(forKey: entry.accountID)
                } else if let saved = entry.snapshot {
                    usage[entry.accountID] = saved
                }
                if let failure = entry.failure {
                    usageErrors[entry.accountID] = usageErrors[entry.accountID] ?? entry.failureMessage ?? failure.message
                } else {
                    usageErrors.removeValue(forKey: entry.accountID)
                }
            }
            var retained: [UUID: [CodexDailyUsageSnapshot]] = [:]
            for id in accountIDs { retained[id] = try await usageCache.dailyUsage(for: id) }
            dailyUsage = retained
            usageCacheError = nil
        } catch {
            usageCacheError = "Usage history could not be read. \(error.localizedDescription)"
        }
    }

    func loadAPIPricing() async {
        let config = paths.defaultHome.appending(path: "config.toml")
        let model = await Task.detached(priority: .utility) {
            (try? Data(contentsOf: config, options: [.mappedIfSafe]))
                .flatMap(CodexAPIPricingResolver.configuredModel)
        }.value
        guard let model else { apiPrice = nil; return }
        if pricingResolver == nil {
            pricingResolver = CodexAPIPricingResolver(
                cacheURL: paths.applicationSupport.appending(path: "cache/model-pricing.json"))
        }
        let price = try? await pricingResolver?.price(for: model)
        guard !Task.isCancelled else { return }
        apiPrice = price
    }

    #if DEBUG
    func setUsageForRender(_ snapshot: CodexAccountUsageSnapshot, accountID: UUID) {
        usage[accountID] = snapshot
        dailyUsage[accountID] = snapshot.dailyUsage
        usageAttempts.insert(accountID)
        if let index = self.snapshot?.status.accounts.firstIndex(where: { $0.id == accountID }) {
            self.snapshot?.status.accounts[index].verification = .init(
                state: .verifiedWithCodex, checkedAt: snapshot.fetchedAt,
                detail: "Synthetic account and usage data for visual verification.")
        }
    }
    #endif

    func beginLogin(providerID: ProviderID) async {
        guard let manager, login == nil else { return }
        await perform {
            let started = try await manager.startAccountLogin(providerID: providerID)
            self.login = started.session
            self.loginState = .waitingForLogin
            self.loginMessage = "Complete sign-in in the opened browser, then check its result here."
        }
    }

    func checkLogin(choice: ConflictChoice? = nil) async {
        guard let manager, let login else { return }
        await perform {
            let check = try await manager.checkAccountLogin(id: login.id, credentialChoice: choice)
            self.loginState = check.state
            self.loginMessage = check.message
            if check.state == .completed {
                self.login = nil
                self.loginState = nil
                self.apply(try await manager.refreshAccounts())
                self.selectedAccountID = check.account?.id
            }
        }
    }

    func submitLoginCode(_ code: String) async {
        guard let manager, let login else { return }
        await perform { try await manager.submitAccountLoginCode(id: login.id, input: code) }
    }

    func cancelLogin() async {
        guard let manager, let login else { return }
        await perform {
            try await manager.cancelAccountLogin(id: login.id)
            self.login = nil
            self.loginState = nil
            self.loginMessage = nil
            self.snapshot?.pendingLoginSessions.removeAll { $0.id == login.id }
        }
    }

    func reviewImport(source: URL, mode: ImportMode) async {
        guard let manager else { return }
        await perform { self.importPlan = try await manager.planImport(source: source, mode: mode) }
    }

    func commitImport(decisions: [String: ConflictChoice]) async {
        guard let manager, let importPlan else { return }
        await perform {
            let result = try await manager.importAccount(plan: importPlan, decisions: decisions)
            self.lastBackupURL = result.backup
            self.noticeMessage = result.unresolved.isEmpty ? "Account imported."
                : "Account imported. \(result.unresolved.joined(separator: " "))"
            self.importPlan = nil
            self.apply(try await manager.refreshAccounts())
            self.selectedAccountID = result.account.id
        }
    }

    func reviewExternalSetting(_ relativePath: String) async {
        guard let manager, let importPlan else { return }
        await perform {
            self.importPlan = try await manager.reviewExternalSetting(
                plan: importPlan,
                relativePath: relativePath
            )
        }
    }

    func dismissImport() { importPlan = nil }

    func removeAccount(_ id: UUID, replacement: UUID?) async {
        guard let manager else { return }
        await perform {
            _ = try await manager.deleteAccount(
                accountID: id,
                replacementDefaultAccountID: replacement
            )
            self.apply(try await manager.refreshAccounts())
        }
    }

    func recover() async {
        guard let manager else { return }
        await perform {
            let results = try await manager.recover()
            self.applyStatus(try await manager.status())
            self.noticeMessage = results.isEmpty ? "No interrupted operations need recovery."
                : results.map(\.message).joined(separator: " ")
        }
    }

    func resolveRecoveryConflict(_ id: UUID, choice: RecoveryConflictChoice) async {
        guard let manager else { return }
        await perform {
            let result = try await manager.resolveRecoveryConflict(operationID: id, choice: choice)
            self.applyStatus(try await manager.status())
            self.noticeMessage = result.message
        }
    }

    func repairLinkedSetting(_ issue: LinkedSettingsDivergence) async {
        guard let manager else { return }
        await perform {
            _ = try await manager.repairLinkedSetting(
                accountID: issue.accountID,
                relativePath: issue.relativePath,
                reviewedFingerprint: issue.localFingerprint
            )
            self.snapshot?.status = try await manager.status()
        }
    }

    private func apply(_ refreshed: AccountSnapshot) {
        snapshot = refreshed
        if selectedAccountID == nil || !refreshed.status.accounts.contains(where: { $0.id == selectedAccountID }) {
            selectedAccountID = refreshed.status.firstDefaultAccountID ?? refreshed.status.accounts.first?.id
        }
        let ids = Set(refreshed.status.accounts.map(\.id))
        usage = usage.filter { ids.contains($0.key) }
        dailyUsage = dailyUsage.filter { ids.contains($0.key) }
        usageErrors = usageErrors.filter { ids.contains($0.key) }
        usageAttempts.formIntersection(ids)
        for account in refreshed.status.accounts where account.verification.state == .needsSignIn {
            usage.removeValue(forKey: account.id)
        }
        if login == nil, let pending = refreshed.pendingLoginSessions.first {
            login = pending
            loginState = .waitingForLogin
            loginMessage = "A sign-in is still pending. Complete it, then check its result."
        }
    }

    private func applyStatus(_ status: ManagerStatus) {
        if var refreshed = snapshot {
            refreshed.status = status
            apply(refreshed)
        } else {
            apply(AccountSnapshot(status: status, providers: AccountManager.providerCatalog,
                                  discoveries: [], pendingLoginSessions: []))
        }
    }

    nonisolated private static func makeLaunchArtifact(_ spec: LaunchSpec, paths: ManagerPaths) throws -> URL {
        let directory = paths.applicationSupport.appending(path: "Launch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let url = directory.appending(path: "Open MacPowerToys Switch.command")
        var exports = ["CODEX_HOME", "GROK_HOME", "CLAUDE_CONFIG_DIR"].compactMap { key in
            spec.environment[key].map { "export \(key)=\(shellQuote($0))" }
        }
        if paths.isolationRoot != nil, let home = spec.environment["HOME"] {
            exports.append("export HOME=\(shellQuote(home))")
        }
        let command = ([spec.executable.path] + spec.arguments).map(shellQuote).joined(separator: " ")
        let workingDirectory = spec.workingDirectory.map { "cd \(shellQuote($0.path))\n" } ?? ""
        let contents = (
            ["#!/bin/zsh", "set -e", "unset OPENAI_API_KEY CODEX_ACCESS_TOKEN XAI_API_KEY ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_AWS_API_KEY ANTHROPIC_BASE_URL CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY CLAUDE_CODE_USE_ANTHROPIC_AWS"]
                + exports + [workingDirectory + "exec \(command)"]
        ).joined(separator: "\n") + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func prepareManager() async -> AccountManager? {
        if let manager { return manager }
        guard !isWorking else { return nil }
        isWorking = true
        errorMessage = nil
        noticeMessage = nil
        defer { isWorking = false }
        do {
            let paths = paths
            let manager = try await Task.detached(priority: .userInitiated) {
                try AccountManager(paths: paths)
            }.value
            self.manager = manager
            return manager
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        noticeMessage = nil
        defer { isWorking = false }
        do {
            try await action()
        } catch {
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
            if let manager, let status = try? await manager.status() {
                applyStatus(status)
                await loadCachedUsage()
            }
        }
    }
}
