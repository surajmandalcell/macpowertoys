import AIManagerCore
import AppKit
import SwiftUI

enum SwitchPage: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case conversations = "Conversations"
    case maintenance = "Maintenance"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .accounts: "person.2"
        case .conversations: "text.bubble"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
}

struct SwitchWindowView: View {
    @State private var model: SwitchWorkspaceModel
    @State private var page: SwitchPage
    @State private var showingDelete = false
    @State private var importDecisions: [String: ConflictChoice] = [:]
    @State private var grokCode = ""
    @State private var showingAbout = false
    @State private var selectedCleanupIDs: Set<String> = []
    @State private var trashBatchToEmpty: ConversationCleanupBatch?
    @State private var conflictToResolve: RecoveryOperation?
    @State private var linkedIssueToRepair: LinkedSettingsDivergence?
    @State private var pageTask: Task<Void, Never>?
    @State private var messageSearchTask: Task<Void, Never>?
    @State private var isMessageSearchPending = false
    @State private var messageQuery = ""
    @AppStorage("switch.messageFilterMask") private var messageFilterMask = ChatMessageFilter.all.rawValue

    init() {
        _model = State(initialValue: SwitchWorkspaceModel())
        _page = State(initialValue: .accounts)
    }

    init(model: SwitchWorkspaceModel, initialPage: SwitchPage) {
        _model = State(initialValue: model)
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .utilityContentTransition(value: page)
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "switch"))
        .task {
            await model.load()
            if page == .conversations { await model.loadHistory() }
            if page == .maintenance { await model.loadCleanup() }
        }
        .onChange(of: page) {
            pageTask?.cancel()
            messageSearchTask?.cancel()
            isMessageSearchPending = false
            pageTask = Task {
                if page == .conversations { await model.loadHistory() }
                if page == .maintenance { await model.loadCleanup() }
            }
        }
        .onDisappear {
            pageTask?.cancel()
            messageSearchTask?.cancel()
            isMessageSearchPending = false
        }
        .onChange(of: messageQuery) { scheduleMessageSearch() }
        .onChange(of: messageFilterMask) { scheduleMessageSearch() }
        .onChange(of: model.cleanupItems) {
            selectedCleanupIDs.formIntersection(Set(
                model.cleanupItems.filter { $0.exclusionReason == nil }.map(\.id)
            ))
        }
        .onChange(of: model.importPlan?.id) {
            importDecisions = Dictionary(uniqueKeysWithValues:
                (model.importPlan?.conflicts ?? []).map { ($0.relativePath, .keepShared) }
            )
        }
        .sheet(isPresented: Binding(
            get: { model.login != nil },
            set: { if !$0 { Task { await model.cancelLogin() } } }
        )) { loginSheet }
        .sheet(isPresented: Binding(
            get: { model.importPlan != nil },
            set: { if !$0 { model.dismissImport() } }
        )) { importSheet }
        .sheet(isPresented: $showingAbout) {
            ToolAboutView(toolId: "switch", showsModalCloseButton: true)
                .frame(width: 540, height: 520)
        }
        .sheet(isPresented: Binding(
            get: { model.cleanupPlan != nil },
            set: { if !$0 { model.dismissCleanupReview() } }
        )) { cleanupReviewSheet }
        .alert("Switch needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SwitchPage.allCases) { destination in
                        SidebarRow(
                            icon: destination.icon,
                            title: destination.rawValue,
                            isSelected: page == destination && (
                                destination != .accounts || model.accounts.isEmpty
                            )
                        ) {
                            page = destination
                            if destination == .accounts && !model.accounts.isEmpty {
                                model.selectedAccountID = model.snapshot?.status.firstDefaultAccountID
                                    ?? model.accounts.first?.id
                            }
                        }
                        .accessibilityIdentifier("switch.page.\(destination.id)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, UtilityLayout.workspaceContentTopInset)

                if !model.accounts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SidebarSectionHeader(title: "Saved accounts")
                        ForEach(model.accounts) { account in
                            SidebarRow(
                                icon: account.identity.providerID == .codex ? "chevron.left.forwardslash.chevron.right" : "sparkles",
                                title: account.identity.email ?? account.identity.accountID ?? "Account",
                                isSelected: page == .accounts && model.selectedAccountID == account.id
                            ) {
                                model.selectedAccountID = account.id
                                page = .accounts
                            }
                            .help(account.identity.email ?? account.identity.accountID ?? account.home.path)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer(minLength: 12)
                SidebarRow(icon: "gearshape", title: "About Switch") { showingAbout = true }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            SidebarTitle(text: "Switch")
        }
        .frame(width: UtilityLayout.dataSidebarWidth)
        .background(VisualEffectBackground())
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .accounts: accountsPage
        case .conversations: conversationsPage
        case .maintenance: maintenancePage
        }
    }

    private var accountsPage: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(title: "Accounts", subtitle: "Switch between saved CLI accounts") {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isWorking)
                addAccountMenu
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
            }

            if model.snapshot == nil && model.isWorking {
                ProgressView("Loading accounts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let account = model.selectedAccount {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        accountDetails(account)
                        if account.identity.providerID == .codex { accountUsage(account) }
                        discoveredSources
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .thinScrollIndicators()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "person.crop.square")
                                .font(.system(size: 28, weight: .ultraLight))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, height: 48, alignment: .leading)
                            Text("Your accounts, in one place")
                                .font(.system(size: 21, weight: .medium))
                            Text("Add a CLI account to switch identities, review usage, and keep your conversations together.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            addAccountMenu
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isWorking)
                        }
                        .frame(maxWidth: 400, alignment: .leading)
                        .padding(.top, 60)
                        discoveredSources
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .thinScrollIndicators()
            }
        }
    }

    private var addAccountMenu: some View {
        Menu {
            ForEach(AccountManager.providerCatalog.filter { $0.availability == .enabled }) { provider in
                Button(provider.displayName) {
                    Task { await model.beginLogin(providerID: provider.id) }
                }
            }
            Divider()
            Button("Import from Folder…") { chooseImportFolder() }
        } label: {
            Label("Add Account", systemImage: "plus")
        }
    }

    private func accountDetails(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: account.identity.providerID == .codex
                    ? "chevron.left.forwardslash.chevron.right" : "sparkles")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                        .font(.system(size: 21, weight: .medium))
                        .lineLimit(1)
                        .help(account.identity.email ?? account.identity.accountID ?? account.home.path)
                    HStack(spacing: 8) {
                        Text(account.identity.providerID == .codex ? "Codex CLI" : "Grok Build")
                        if model.snapshot?.status.isDefault(account) == true {
                            Text("·")
                            Label("Default", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if model.snapshot?.status.isDefault(account) != true {
                    Button("Make Default") { Task { await model.makeDefault(account.id) } }
                        .buttonStyle(.borderedProminent)
                }
                Button("Verify Access") { Task { await model.verify(account.id) } }
                Button("Remove…", role: .destructive) { showingDelete = true }
                    .disabled(deletionReplacements(for: account).isEmpty && model.snapshot?.status.isDefault(account) == true)
                    .help(model.snapshot?.status.isDefault(account) == true
                        ? "Add another account for this provider before removing its default."
                        : "Remove this saved account")
            }
            .controlSize(.small)
            .disabled(model.isWorking)

            QuietDivider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Access")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 76, alignment: .leading)
                    Label(verificationTitle(account.verification.state),
                          systemImage: verificationSymbol(account.verification.state))
                        .font(.system(size: 12))
                        .help(account.verification.detail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Home")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 76, alignment: .leading)
                    Text(account.home.path)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(account.home.path)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .confirmationDialog(
            "Remove \(account.identity.email ?? "this account")?",
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            if model.snapshot?.status.isDefault(account) == true {
                ForEach(deletionReplacements(for: account)) { replacement in
                    Button("Use \(replacement.identity.email ?? "another account") as default and remove", role: .destructive) {
                        Task { await model.removeAccount(account.id, replacement: replacement.id) }
                    }
                }
            } else {
                Button("Remove Account", role: .destructive) {
                    Task { await model.removeAccount(account.id, replacement: nil) }
                }
            }
        } message: {
            Text("The saved account and its managed credentials will be removed. Switch keeps a recovery backup for interrupted operations.")
        }
    }

    private func deletionReplacements(for account: AccountRecord) -> [AccountRecord] {
        model.accounts.filter { $0.id != account.id && $0.identity.providerID == account.identity.providerID }
    }

    private func verificationTitle(_ state: VerificationState) -> String {
        switch state {
        case .imported: "Saved, not checked"
        case .needsSignIn: "Sign-in required"
        case .verifiedLocally: "Credentials valid"
        case .verifiedWithCodex: "Access verified"
        case .unsupported: "Unsupported account"
        }
    }

    private func verificationSymbol(_ state: VerificationState) -> String {
        switch state {
        case .imported: "clock"
        case .needsSignIn: "exclamationmark.circle"
        case .verifiedLocally, .verifiedWithCodex: "checkmark.circle"
        case .unsupported: "xmark.circle"
        }
    }

    private func accountUsage(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Usage").font(.system(size: 13, weight: .medium))
                Spacer()
                Button(model.usage[account.id] == nil ? "Load Usage" : "Refresh Usage") {
                    Task { await model.loadUsage(account.id) }
                }
                .controlSize(.small)
                .disabled(model.isWorking || account.verification.state == .needsSignIn)
            }
            if account.verification.state == .needsSignIn {
                Text("Sign in again to view usage for this account.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let limits = model.usage[account.id]?.rateLimits?.defaultBucket {
                if let plan = model.usage[account.id]?.account?.plan {
                    Text(plan)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    if let primary = limits.primary {
                        usageRow(title: "Current window", window: primary)
                    }
                    if let secondary = limits.secondary {
                        usageRow(title: "Longer window", window: secondary)
                    }
                }
                if let total = model.usage[account.id]?.usage?.lifetimeTokens {
                    Text("\(total.formatted()) lifetime tokens")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Load usage to see current rate limits for this account.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func usageRow(title: String, window: CodexRateLimitWindowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(window.usedPercent.map { "\($0)%" } ?? "—")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .contentTransition(.numericText())
            if let percent = window.usedPercent {
                ProgressView(value: Double(percent), total: 100)
                    .accessibilityLabel("\(title), \(percent)% used")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .utilitySectionCard()
    }

    @ViewBuilder
    private var discoveredSources: some View {
        let sources = model.discoveries.filter { source in
            source.support == .supportedChatGPT || source.support == .supportedOAuth
        }
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                QuietDivider()
                Text("Available to import").font(.system(size: 13, weight: .medium))
                ForEach(sources) { source in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.identity?.email ?? source.path.lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                            Text(source.path.path)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Review Import") {
                            Task { await model.reviewImport(source: source.path, mode: .authOnly) }
                        }
                        .controlSize(.small)
                        .disabled(model.isWorking)
                    }
                }
            }
        }
    }

    private var conversationsPage: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(title: "Conversations", subtitle: "Shared Codex history") {
                Button("Refresh") { Task { await model.loadHistory() } }
                    .disabled(model.isLoadingHistory)
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TextField("Search conversations", text: $model.historyQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await model.searchHistory() } }
                        .accessibilityLabel("Search conversations")
                        .disabled(model.isLoadingHistory)
                        .padding(12)
                    HStack {
                        Text("\(model.history.matchingThreadCount.formatted()) conversations")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.isLoadingHistory && model.history.totalThreadCount == 0 {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(model.history.threads) { thread in
                                Button {
                                    messageSearchTask?.cancel()
                                    isMessageSearchPending = false
                                    Task {
                                        await model.selectThread(
                                            thread.id, query: messageQuery, filter: messageFilter
                                        )
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(thread.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        HStack(spacing: 4) {
                                            Text(thread.updatedAt, style: .date)
                                            Text("·")
                                            Text("\(thread.messageCount.formatted()) messages")
                                        }
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(model.selectedThreadID == thread.id
                                        ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(UtilityInteractionButtonStyle())
                                .focusEffectDisabled()
                                .accessibilityValue(model.selectedThreadID == thread.id ? "Selected" : "")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    }
                    .thinScrollIndicators()
                }
                .frame(width: 260)
                .background(Color(nsColor: .controlBackgroundColor))
                QuietDivider()
                if let id = model.selectedThreadID,
                   let thread = model.history.threads.first(where: { $0.id == id }) {
                    conversationDetail(thread)
                } else if model.isLoadingHistory {
                    ProgressView("Loading conversations…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        model.history.threads.isEmpty ? "No conversations" : "Select a conversation",
                        systemImage: "text.bubble"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var messageFilter: ChatMessageFilter {
        ChatMessageFilter(rawValue: messageFilterMask & ChatMessageFilter.all.rawValue)
    }

    private func roleBinding(_ role: ChatMessageFilter) -> Binding<Bool> {
        Binding(
            get: { messageFilter.contains(role) },
            set: { enabled in
                let mask = messageFilter.rawValue
                messageFilterMask = enabled ? mask | role.rawValue : mask & ~role.rawValue
            }
        )
    }

    private func scheduleMessageSearch(immediate: Bool = false) {
        messageSearchTask?.cancel()
        isMessageSearchPending = false
        guard page == .conversations, let id = model.selectedThreadID else { return }
        let query = messageQuery
        let filter = messageFilter
        isMessageSearchPending = true
        messageSearchTask = Task {
            if !immediate {
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            await model.searchMessages(for: id, query: query, filter: filter)
            if !Task.isCancelled { isMessageSearchPending = false }
        }
    }

    private func conversationDetail(_ thread: ChatThreadSummary) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(thread.title)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .help(thread.title)
                HStack(spacing: 6) {
                    Text("\(thread.messageCount.formatted()) messages")
                    if let tokens = thread.totalTokens {
                        Text("· \(tokens.formatted(.number.notation(.compactName))) tokens")
                            .help("\(tokens.formatted()) recorded tokens")
                    }
                    Spacer(minLength: 4)
                    Text(thread.updatedAt, style: .date)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            HStack(spacing: 6) {
                TextField("Search messages", text: $messageQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 90, maxWidth: .infinity)
                    .onSubmit { scheduleMessageSearch(immediate: true) }
                    .accessibilityLabel("Search messages in this conversation")
                Menu("Roles") {
                    Toggle("Prompts", isOn: roleBinding(.prompts))
                    Toggle("Responses", isOn: roleBinding(.responses))
                    Toggle("Tools", isOn: roleBinding(.tools))
                    Toggle("Other", isOn: roleBinding(.other))
                }
                .help("Filter messages by role")
                .fixedSize()
                Button("Copy Shown") {
                    guard let detail = model.selectedThread else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        ChatTranscriptExport.text(for: detail.messages), forType: .string
                    )
                }
                .disabled(isMessageSearchPending || (model.selectedThread?.messages.isEmpty ?? true))
                .fixedSize()
            }
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            QuietDivider()

            if isMessageSearchPending || model.isLoadingMessages {
                ProgressView("Loading messages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = model.selectedThread {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !messageQuery.isEmpty || messageFilter != .all {
                            Text("\(detail.matchingMessageCount.formatted()) matching messages")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if detail.messages.isEmpty {
                            ContentUnavailableView("No matching messages", systemImage: "text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(detail.messages) { message in
                            HStack(alignment: .top, spacing: 14) {
                                Text(message.role.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .leading)
                                Text(message.text)
                                    .font(.system(size: 12))
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 14)
                            QuietDivider()
                        }
                        if detail.nextOffset != nil {
                            Button("Load More Messages") {
                                Task { await model.loadMoreMessages() }
                            }
                            .controlSize(.small)
                            .disabled(model.isLoadingMoreMessages)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .thinScrollIndicators()
            } else {
                ContentUnavailableView("Conversation unavailable", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var maintenancePage: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(title: "Maintenance", subtitle: "Account store and recovery") {
                Button("Refresh") {
                    Task {
                        await model.refresh()
                        await model.loadCleanup()
                    }
                }
                .disabled(model.isWorking)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recovery").font(.system(size: 13, weight: .medium))
                        if model.pendingRecovery.isEmpty {
                            Text("No interrupted operations need recovery.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(model.pendingRecovery.count) interrupted operation(s) need attention before account changes can continue.")
                                .font(.system(size: 12))
                            Button("Recover Operations") { Task { await model.recover() } }
                                .controlSize(.small)
                                .disabled(model.isWorking)
                            ForEach(model.pendingRecovery) { operation in
                                HStack {
                                    Text("\(operation.kind) · \(operation.phase.rawValue)")
                                        .font(.system(size: 12))
                                    Spacer()
                                    if operation.phase == .conflicted {
                                        Button("Resolve…") { conflictToResolve = operation }
                                            .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                    QuietDivider()
                    if !model.linkedSettingsIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Linked settings need review")
                                .font(.system(size: 13, weight: .medium))
                            ForEach(model.linkedSettingsIssues) { issue in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(issue.relativePath)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(issue.localPath.path)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                    Button("Review Repair…") { linkedIssueToRepair = issue }
                                        .controlSize(.small)
                                }
                            }
                        }
                        QuietDivider()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Conversation cleanup")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button("Review Selected…") {
                                Task { await model.reviewCleanup(ids: selectedCleanupIDs) }
                            }
                            .controlSize(.small)
                            .disabled(selectedCleanupIDs.isEmpty || model.isWorking)
                        }
                        Text("Choose conversations to move to Switch Trash. Nothing is removed until you review the selection.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        if model.cleanupItems.isEmpty {
                            Text(model.isWorking ? "Scanning conversations…" : "No conversations available for cleanup.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(model.cleanupItems) { item in
                                    Toggle(isOn: Binding(
                                        get: { selectedCleanupIDs.contains(item.id) },
                                        set: { isSelected in
                                            if isSelected { selectedCleanupIDs.insert(item.id) }
                                            else { selectedCleanupIDs.remove(item.id) }
                                        }
                                    )) {
                                        HStack {
                                            Text(item.title).lineLimit(1)
                                            Spacer()
                                            Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.system(size: 12))
                                    }
                                    .disabled(item.exclusionReason != nil)
                                    .help(item.exclusionReason ?? item.relativePath)
                                }
                            }
                        }
                    }
                    QuietDivider()
                    if !model.cleanupTrash.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Switch Trash").font(.system(size: 13, weight: .medium))
                            ForEach(model.cleanupTrash) { batch in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(batch.conversations.count) conversations")
                                            .font(.system(size: 12, weight: .medium))
                                        Text(batch.createdAt, style: .date)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Restore") { Task { await model.restoreTrash(batch.id) } }
                                    Button("Delete Permanently…", role: .destructive) {
                                        trashBatchToEmpty = batch
                                    }
                                }
                                .controlSize(.small)
                                .disabled(model.isWorking)
                            }
                        }
                        QuietDivider()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shared data").font(.system(size: 13, weight: .medium))
                        Text(model.snapshot?.status.sharedRoot.path ?? "Loading…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.snapshot?.status.sharedRoot.path ?? "")
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .thinScrollIndicators()
        }
        .confirmationDialog(
            "Delete these conversations permanently?",
            isPresented: Binding(
                get: { trashBatchToEmpty != nil },
                set: { if !$0 { trashBatchToEmpty = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let batch = trashBatchToEmpty {
                Button("Delete \(batch.conversations.count) Conversations", role: .destructive) {
                    Task { await model.emptyTrash(batch.id) }
                    trashBatchToEmpty = nil
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog(
            "Resolve recovery conflict?",
            isPresented: Binding(
                get: { conflictToResolve != nil },
                set: { if !$0 { conflictToResolve = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let operation = conflictToResolve {
                Button("Preserve Current Data") {
                    Task { await model.resolveRecoveryConflict(operation.id, choice: .preserveCurrent) }
                    conflictToResolve = nil
                }
                Button("Restore Backup") {
                    Task { await model.resolveRecoveryConflict(operation.id, choice: .restoreBackup) }
                    conflictToResolve = nil
                }
            }
        } message: {
            Text("Choose which data Switch should keep for this interrupted operation.")
        }
        .confirmationDialog(
            "Repair linked setting?",
            isPresented: Binding(
                get: { linkedIssueToRepair != nil },
                set: { if !$0 { linkedIssueToRepair = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let issue = linkedIssueToRepair {
                Button("Back Up Local File and Repair Link") {
                    Task { await model.repairLinkedSetting(issue) }
                    linkedIssueToRepair = nil
                }
            }
        } message: {
            Text("Switch will back up the local edit before restoring the shared settings link.")
        }
    }

    @ViewBuilder
    private var cleanupReviewSheet: some View {
        if let plan = model.cleanupPlan {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Conversation Cleanup")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(plan.conversations.count) conversations · \(ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .file))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(plan.conversations) { item in
                            HStack {
                                Text(item.title).lineLimit(1)
                                Spacer()
                                Text(item.project).foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                .thinScrollIndicators()
                Text("Move to Switch Trash is reversible until you delete that trash batch permanently.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { model.dismissCleanupReview() }
                    Spacer()
                    Button("Move to Switch Trash") {
                        Task {
                            await model.moveReviewedConversationsToTrash()
                            if model.cleanupPlan == nil { selectedCleanupIDs.removeAll() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                }
                .controlSize(.small)
            }
            .padding(20)
            .frame(width: 520, height: 400)
        }
    }

    private var loginSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Account").font(.system(size: 17, weight: .semibold))
            Text(model.loginMessage ?? "Complete sign-in, then check its result.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if model.login?.providerID == .grokBuild {
                TextField("Authorization code or callback URL", text: $grokCode)
                    .textFieldStyle(.roundedBorder)
                Button("Submit Code") {
                    Task { await model.submitLoginCode(grokCode) }
                }
                .disabled(grokCode.isEmpty || model.isWorking)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Cancel Sign-in") { Task { await model.cancelLogin() } }
                Spacer()
                if model.loginState == .credentialChoiceRequired {
                    Button("Keep Saved Access") { Task { await model.checkLogin(choice: .keepShared) } }
                    Button("Use New Access") { Task { await model.checkLogin(choice: .useImported) } }
                } else {
                    Button("Check Sign-in") { Task { await model.checkLogin() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
            .disabled(model.isWorking)
        }
        .padding(20)
        .frame(width: 480, height: 240)
    }

    @ViewBuilder
    private var importSheet: some View {
        if let plan = model.importPlan {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Import").font(.system(size: 17, weight: .semibold))
                Text(plan.identity.email ?? plan.source.path)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                Text("\(plan.manifest.count) item(s) · \(ByteCountFormatter.string(fromByteCount: plan.requiredBytes, countStyle: .file)) required")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plan.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12))
                        }
                        ForEach(plan.conflicts) { conflict in
                            VStack(alignment: .leading, spacing: 6) {
                                Picker(conflict.relativePath, selection: Binding(
                                    get: { importDecisions[conflict.relativePath] ?? .keepShared },
                                    set: { importDecisions[conflict.relativePath] = $0 }
                                )) {
                                    Text("Keep saved").tag(ConflictChoice.keepShared)
                                    Text("Use imported").tag(ConflictChoice.useImported)
                                }
                                if let target = conflict.externalTarget {
                                    HStack {
                                        Text(target.path)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .textSelection(.enabled)
                                        Spacer()
                                        Button("Review External Setting") {
                                            Task { await model.reviewExternalSetting(conflict.relativePath) }
                                        }
                                        .controlSize(.small)
                                    }
                                }
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                .thinScrollIndicators()
                Spacer(minLength: 0)
                HStack {
                    Button("Cancel") { model.dismissImport() }
                    Spacer()
                    Button("Import Account") {
                        Task { await model.commitImport(decisions: importDecisions) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                }
                .controlSize(.small)
            }
            .padding(20)
            .frame(width: 520, height: 360)
        }
    }

    private func chooseImportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Review Import"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in await model.reviewImport(source: url, mode: .full) }
        }
    }
}
