import AIManagerCore
import Foundation
import Observation

@Observable
@MainActor
final class SwitchWorkspaceModel {
    private(set) var snapshot: AccountSnapshot?
    private(set) var usage: [UUID: CodexAccountUsageSnapshot] = [:]
    private(set) var history = ChatHistorySnapshot()
    private(set) var selectedThread: ChatThreadDetail?
    private(set) var cleanupItems: [CleanupConversation] = []
    private(set) var cleanupPlan: ConversationCleanupPlan?
    private(set) var cleanupTrash: [ConversationCleanupBatch] = []
    private(set) var login: AccountLoginSession?
    private(set) var loginState: AccountLoginState?
    private(set) var loginMessage: String?
    private(set) var importPlan: ImportPlan?
    private(set) var isWorking = false
    private(set) var isLoadingHistory = false
    private(set) var isLoadingMessages = false
    private(set) var isLoadingMoreMessages = false
    var errorMessage: String?
    var selectedAccountID: UUID?
    var selectedThreadID: String?
    var historyQuery = ""

    private let manager: AccountManager?
    private let historyIndex: ChatHistoryIndex
    private let applicationSupport: URL
    private var activityCache: CodexUsageStatisticsCache?
    private var messageGeneration = 0
    private var activeMessageQuery = ""
    private var activeMessageFilter: ChatMessageFilter = .all
    private let startupError: String?

    init(paths: ManagerPaths = .environment()) {
        do {
            manager = try AccountManager(paths: paths)
            startupError = nil
        } catch {
            manager = nil
            startupError = error.localizedDescription
        }
        historyIndex = ChatHistoryIndex(
            home: paths.sharedRoot,
            cacheFile: paths.applicationSupport.appending(path: "conversation-index.json")
        )
        applicationSupport = paths.applicationSupport
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
        usage[id] = nil
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

    func loadHistory() async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            history = try await historyIndex.refresh(query: historyQuery)
            if let selectedThreadID, !history.threads.contains(where: { $0.id == selectedThreadID }) {
                self.selectedThreadID = nil
                selectedThread = nil
                messageGeneration &+= 1
                isLoadingMessages = false
                isLoadingMoreMessages = false
            } else if let selectedThreadID {
                await searchMessages(
                    for: selectedThreadID, query: activeMessageQuery, filter: activeMessageFilter
                )
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchHistory() async {
        history = await historyIndex.search(query: historyQuery)
        selectedThreadID = nil
        selectedThread = nil
        messageGeneration &+= 1
        isLoadingMessages = false
        isLoadingMoreMessages = false
    }

    func selectThread(_ id: String, query: String, filter: ChatMessageFilter) async {
        selectedThreadID = id
        await searchMessages(for: id, query: query, filter: filter)
    }

    func searchMessages(for id: String, query: String, filter: ChatMessageFilter) async {
        guard !Task.isCancelled, selectedThreadID == id else { return }
        messageGeneration &+= 1
        let generation = messageGeneration
        activeMessageQuery = query
        activeMessageFilter = filter
        selectedThread = nil
        isLoadingMessages = true
        isLoadingMoreMessages = false
        defer { if messageGeneration == generation { isLoadingMessages = false } }
        do {
            let detail = try await historyIndex.detail(for: id, query: query, filter: filter)
            guard !Task.isCancelled, messageGeneration == generation,
                  selectedThreadID == id else { return }
            selectedThread = detail
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled && messageGeneration == generation {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreMessages() async {
        guard !isLoadingMessages, !isLoadingMoreMessages,
              let selectedThread, let offset = selectedThread.nextOffset else { return }
        let generation = messageGeneration
        isLoadingMoreMessages = true
        defer { if messageGeneration == generation { isLoadingMoreMessages = false } }
        do {
            guard let page = try await historyIndex.detail(
                for: selectedThread.thread.id, offset: offset,
                query: activeMessageQuery, filter: activeMessageFilter
            ), !Task.isCancelled, messageGeneration == generation,
                  selectedThreadID == selectedThread.thread.id else { return }
            self.selectedThread = ChatThreadDetail(
                thread: selectedThread.thread,
                messages: selectedThread.messages + page.messages,
                omittedMessageCount: page.omittedMessageCount,
                matchingMessageCount: page.matchingMessageCount,
                nextOffset: page.nextOffset
            )
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled && messageGeneration == generation {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadCleanup() async {
        guard let manager else { return }
        await perform { try await self.refreshCleanup(manager) }
    }

    func reviewCleanup(ids: Set<String>) async {
        guard let manager else { return }
        await perform {
            let selected = self.cleanupItems.filter { ids.contains($0.id) }
            try await self.prepareActivityCache()
            self.cleanupPlan = try await manager.reviewCleanup(selected)
        }
    }

    func moveReviewedConversationsToTrash() async {
        guard let manager, let cleanupPlan else { return }
        await perform {
            _ = try await manager.moveConversationsToTrash(cleanupPlan) { sources in
                try await self.historyIndex.preserveActivity(for: sources)
            }
            self.cleanupPlan = nil
            self.cleanupItems = try await manager.cleanupInventory(
                summaries: await self.historyIndex.cleanupSummaries()
            )
            self.cleanupTrash = try await manager.cleanupTrash()
        }
    }

    func dismissCleanupReview() { cleanupPlan = nil }

    func restoreTrash(_ id: UUID) async {
        guard let manager else { return }
        await perform {
            try await manager.restoreCleanupTrash(id)
            self.cleanupItems = try await manager.cleanupInventory(
                summaries: await self.historyIndex.cleanupSummaries()
            )
            self.cleanupTrash = try await manager.cleanupTrash()
        }
    }

    func emptyTrash(_ id: UUID) async {
        guard let manager else { return }
        await perform {
            try await manager.permanentlyRemoveCleanupTrash(id)
            self.cleanupTrash = try await manager.cleanupTrash()
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

    private func prepareActivityCache() async throws {
        guard activityCache == nil else { return }
        let support = applicationSupport
        let cache = try await Task.detached(priority: .utility) {
            try CodexUsageStatisticsCache(
                databaseURL: support.appending(path: "cache/account-usage.sqlite"),
                activityDatabaseURL: support.appending(path: "activity/daily.sqlite")
            )
        }.value
        activityCache = cache
        await historyIndex.attachActivityCache(cache)
    }

    private func refreshCleanup(_ manager: AccountManager) async throws {
        _ = try await historyIndex.refresh()
        cleanupItems = try await manager.cleanupInventory(summaries: await historyIndex.cleanupSummaries())
        cleanupTrash = try await manager.cleanupTrash()
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
