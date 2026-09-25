import AIManagerCore
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class SwitchWorkspaceModel {
    private(set) var snapshot: AccountSnapshot?
    private(set) var usage: [UUID: CodexAccountUsageSnapshot] = [:]
    private(set) var login: AccountLoginSession?
    private(set) var loginState: AccountLoginState?
    private(set) var loginMessage: String?
    private(set) var importPlan: ImportPlan?
    private(set) var isWorking = false
    var errorMessage: String?
    var selectedAccountID: UUID?

    private let manager: AccountManager?
    private let paths: ManagerPaths
    private let startupError: String?

    init(paths: ManagerPaths = .environment()) {
        self.paths = paths
        do {
            manager = try AccountManager(paths: paths)
            startupError = nil
        } catch {
            manager = nil
            startupError = error.localizedDescription
        }
    }

    var accounts: [AccountRecord] { snapshot?.status.accounts ?? [] }
    var discoveries: [DiscoveredSource] { snapshot?.discoveries ?? [] }
    var selectedAccount: AccountRecord? {
        accounts.first { $0.id == selectedAccountID }
    }
    var pendingRecovery: [RecoveryOperation] { snapshot?.status.pendingRecovery ?? [] }
    var linkedSettingsIssues: [LinkedSettingsDivergence] {
        snapshot?.status.linkedSettingsDivergences ?? []
    }

    func load() async {
        guard let manager else {
            errorMessage = startupError ?? "Switch could not open its account store."
            return
        }
        await perform {
            let refreshed = try await manager.refreshAccounts()
            self.apply(refreshed)
        }
    }

    func refresh() async { await load() }

    func makeDefault(_ id: UUID) async {
        guard let manager else { return }
        await perform {
            _ = try await manager.switchDefault(to: id)
            self.apply(try await manager.refreshAccounts(includeDiscoveries: false))
        }
    }

    func openAccount(_ id: UUID) async {
        guard let manager, let account = accounts.first(where: { $0.id == id }) else { return }
        await perform {
            if self.snapshot?.status.isDefault(account) != true {
                _ = try await manager.switchDefault(to: id)
                self.apply(try await manager.refreshAccounts(includeDiscoveries: false))
            }
            let spec = try await manager.launchSpec(accountID: id)
            let script = try self.makeLaunchArtifact(spec)
            if self.paths.isolationRoot == nil && !NSWorkspace.shared.open(script) {
                throw AIManagerError.operationFailed("Terminal could not open this account.")
            }
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
        guard let manager, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        let result = await manager.checkAccount(accountID: id)
        usage[id] = result.usage
        do {
            snapshot?.status = try await manager.status()
            if result.verification.state == .needsSignIn {
                errorMessage = result.verification.detail
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    func loadUsage(_ id: UUID) async {
        guard let manager, !isWorking else { return }
        await perform {
            self.usage[id] = try await manager.readCodexAccountUsage(accountID: id)
        }
    }

    func beginLogin(providerID: ProviderID) async {
        guard let manager else { return }
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
            _ = try await manager.recover()
            self.apply(try await manager.refreshAccounts())
        }
    }

    func resolveRecoveryConflict(_ id: UUID, choice: RecoveryConflictChoice) async {
        guard let manager else { return }
        await perform {
            _ = try await manager.resolveRecoveryConflict(operationID: id, choice: choice)
            self.apply(try await manager.refreshAccounts())
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
        if login == nil { login = refreshed.pendingLoginSessions.first }
    }

    private func makeLaunchArtifact(_ spec: LaunchSpec) throws -> URL {
        let directory = paths.applicationSupport.appending(path: "Launch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let url = directory.appending(path: "Open MacPowerToys Switch.command")
        var exports = ["CODEX_HOME", "GROK_HOME"].compactMap { key in
            spec.environment[key].map { "export \(key)=\(shellQuote($0))" }
        }
        if paths.isolationRoot != nil, let home = spec.environment["HOME"] {
            exports.append("export HOME=\(shellQuote(home))")
        }
        let command = ([spec.executable.path] + spec.arguments).map(shellQuote).joined(separator: " ")
        let workingDirectory = spec.workingDirectory.map { "cd \(shellQuote($0.path))\n" } ?? ""
        let contents = (
            ["#!/bin/zsh", "set -e", "unset OPENAI_API_KEY CODEX_ACCESS_TOKEN XAI_API_KEY"]
                + exports + [workingDirectory + "exec \(command)"]
        ).joined(separator: "\n") + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await action()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
