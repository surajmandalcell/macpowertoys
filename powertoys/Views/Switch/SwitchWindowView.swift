import AIManagerCore
import AppKit
import SwiftUI

private enum SwitchPage: String, CaseIterable, Identifiable {
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
    @State private var model = SwitchWorkspaceModel()
    @State private var page = SwitchPage.accounts
    @State private var showingDelete = false
    @State private var importDecisions: [String: ConflictChoice] = [:]
    @State private var grokCode = ""
    @State private var showingAbout = false
    @State private var selectedCleanupIDs: Set<String> = []
    @State private var trashBatchToEmpty: ConversationCleanupBatch?
    @State private var conflictToResolve: RecoveryOperation?
    @State private var linkedIssueToRepair: LinkedSettingsDivergence?
    @State private var pageTask: Task<Void, Never>?

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
            pageTask = Task {
                if page == .conversations { await model.loadHistory() }
                if page == .maintenance { await model.loadCleanup() }
            }
        }
        .onDisappear { pageTask?.cancel() }
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
                            isSelected: page == destination
                        ) { page = destination }
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
                .disabled(model.isWorking)
            }

            if model.snapshot == nil && model.isWorking {
                ProgressView("Loading accounts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let account = model.selectedAccount {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        accountDetails(account)
                        if account.identity.providerID == .codex { accountUsage(account) }
                        discoveredSources
                    }
                    .padding(UtilityLayout.horizontalInset)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ContentUnavailableView(
                            "No saved accounts",
                            systemImage: "person.crop.circle.badge.plus",
                            description: Text("Sign in or import an existing CLI account to begin.")
                        )
                        .frame(maxWidth: .infinity)
                        discoveredSources
                    }
                    .padding(UtilityLayout.horizontalInset)
                }
            }
        }
    }

    private func accountDetails(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    if model.snapshot?.status.isDefault(account) == true {
                        Text("Default")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Text(account.identity.providerID == .codex ? "Codex CLI" : "Grok Build")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("ACCESS").utilitySectionHeader()
                Text(account.verification.detail)
                    .font(.system(size: 12))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("HOME").utilitySectionHeader()
                Text(account.home.path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
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
        }
        .utilitySectionCard()
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

    private func accountUsage(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Usage").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Refresh Usage") { Task { await model.loadUsage(account.id) } }
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
                if let primary = limits.primary {
                    usageRow(title: "Current window", window: primary)
                }
                if let secondary = limits.secondary {
                    usageRow(title: "Longer window", window: secondary)
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
        .utilitySectionCard()
    }

    private func usageRow(title: String, window: CodexRateLimitWindowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(window.usedPercent.map { "\($0)% used" } ?? "Unavailable")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            if let percent = window.usedPercent {
                ProgressView(value: Double(percent), total: 100)
                    .accessibilityLabel(title)
            }
        }
    }

    @ViewBuilder
    private var discoveredSources: some View {
        let sources = model.discoveries.filter { source in
            source.support == .supportedChatGPT || source.support == .supportedOAuth
        }
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Available to import").font(.system(size: 13, weight: .semibold))
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
            .utilitySectionCard()
        }
    }

    private var conversationsPage: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(title: "Conversations", subtitle: "Shared Codex history") {
                TextField("Search conversations", text: $model.historyQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { Task { await model.searchHistory() } }
                    .accessibilityLabel("Search conversations")
                    .disabled(model.isLoadingHistory)
                Button("Refresh") { Task { await model.loadHistory() } }
                    .disabled(model.isLoadingHistory)
            }
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.history.threads) { thread in
                            Button {
                                Task { await model.selectThread(thread.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(thread.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                    Text(thread.updatedAt, style: .date)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(model.selectedThreadID == thread.id
                                    ? Color.accentColor.opacity(0.15) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(UtilityInteractionButtonStyle())
                        }
                    }
                    .padding(12)
                }
                .frame(width: 280)
                .background(Color(nsColor: .controlBackgroundColor))
                QuietDivider()
                if let detail = model.selectedThread {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            Text(detail.thread.title)
                                .font(.system(size: 17, weight: .semibold))
                            ForEach(detail.messages) { message in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(message.role.rawValue.capitalized)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(message.text)
                                        .font(.system(size: 12))
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if detail.nextOffset != nil {
                                Button("Load More Messages") {
                                    Task { await model.loadMoreMessages() }
                                }
                                .controlSize(.small)
                                .disabled(model.isLoadingMessages)
                            }
                        }
                        .padding(UtilityLayout.horizontalInset)
                    }
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
                        Text("Recovery").font(.system(size: 13, weight: .semibold))
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
                    .utilitySectionCard()
                    if !model.linkedSettingsIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Linked settings need review")
                                .font(.system(size: 13, weight: .semibold))
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
                        .utilitySectionCard()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Conversation cleanup")
                                .font(.system(size: 13, weight: .semibold))
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
                    .utilitySectionCard()
                    if !model.cleanupTrash.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Switch Trash").font(.system(size: 13, weight: .semibold))
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
                        .utilitySectionCard()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shared data").font(.system(size: 13, weight: .semibold))
                        Text(model.snapshot?.status.sharedRoot.path ?? "Loading…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Switch.app and MacPowerToys use the same account store. Switch.app is optional.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .utilitySectionCard()
                }
                .padding(UtilityLayout.horizontalInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
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
