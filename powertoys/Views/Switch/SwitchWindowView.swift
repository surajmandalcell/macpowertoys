import AIManagerCore
import AppKit
import SwiftUI

enum SwitchPage: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case recovery = "Recovery"

    var id: String { rawValue }
    var icon: String { self == .accounts ? "person.2.fill" : "cross.case" }
}

struct SwitchWindowView: View {
    @State private var model: SwitchWorkspaceModel
    @State private var page: SwitchPage
    @State private var showingDelete = false
    @State private var showingAbout = false
    @State private var showingAccountDetails = false
    @State private var copiedAuthPath = false
    @State private var importDecisions: [String: ConflictChoice] = [:]
    @State private var grokCode = ""
    @State private var conflictToResolve: RecoveryOperation?
    @State private var linkedIssueToRepair: LinkedSettingsDivergence?

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
            navigationRail
            Group {
                switch page {
                case .accounts: accountsPage
                case .recovery: recoveryPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .utilityContentTransition(value: page)
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "switch"))
        .task { await model.load() }
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
        .alert("Switch needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var navigationRail: some View {
        VStack(spacing: 12) {
            Image("SwitchLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .toolIconTile(size: 32)
                .accessibilityHidden(true)
                .padding(.bottom, 12)

            ForEach(SwitchPage.allCases) { destination in
                railButton(destination.icon, label: destination.rawValue,
                           selected: page == destination) { page = destination }
                    .accessibilityIdentifier("switch.page.\(destination.id)")
            }
            Spacer(minLength: 0)
            railButton("info.circle", label: "About Switch", selected: false) {
                showingAbout = true
            }
        }
        .padding(.top, 60)
        .padding(.bottom, 18)
        .frame(width: 68)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.09, green: 0.12, blue: 0.18))
    }

    private func railButton(_ symbol: String, label: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.68))
                .frame(width: 42, height: 40)
                .background(selected ? Color.white.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(label)
    }

    private var accountsPage: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(title: "Accounts", subtitle: "Switch between CLI identities") {
                Button { Task { await model.refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isWorking)
            }
            HStack(spacing: 0) {
                accountList
                    .frame(width: 256)
                    .background(Color(nsColor: .controlBackgroundColor))
                QuietDivider()
                accountContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Saved accounts")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(model.accounts.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                addAccountMenu
                    .labelStyle(.iconOnly)
                    .help("Add account")
                    .disabled(model.isWorking)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            QuietDivider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.accounts) { account in
                        accountRow(account)
                    }
                    if model.accounts.isEmpty && model.snapshot != nil {
                        Text("No saved accounts")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    discoveredSources
                }
                .padding(8)
            }
            .thinScrollIndicators()
        }
    }

    private func accountRow(_ account: AccountRecord) -> some View {
        let selected = model.selectedAccountID == account.id
        return Button {
            model.selectedAccountID = account.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: providerIcon(account))
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(account.identity.providerID == .codex ? "Codex CLI" : "Grok Build")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.snapshot?.status.isDefault(account) == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tint)
                        .help("Default account")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 9))
        .accessibilityValue(selected ? "Selected" : "")
        .help(account.identity.email ?? account.identity.accountID ?? account.home.path)
        .contextMenu {
            Button(model.snapshot?.status.isDefault(account) == true ? "Open \(providerName(account))" : "Use & Open \(providerName(account))") {
                Task { await model.openAccount(account.id) }
            }
            Button("Make Default") { Task { await model.makeDefault(account.id) } }
                .disabled(model.snapshot?.status.isDefault(account) == true)
            Button("Copy Auth Path") { copyAuthPath(account) }
            Divider()
            Button("Move Up") { Task { await model.moveAccount(account.id, by: -1) } }
                .disabled(model.accounts.first?.id == account.id)
            Button("Move Down") { Task { await model.moveAccount(account.id, by: 1) } }
                .disabled(model.accounts.last?.id == account.id)
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        if model.snapshot == nil && model.isWorking {
            ProgressView("Loading accounts…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let account = model.selectedAccount {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    accountDetails(account)
                    if account.identity.providerID == .codex { accountUsage(account) }
                    accountMetadata(account)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .thinScrollIndicators()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                Text("Bring your accounts together")
                    .font(.system(size: 19, weight: .medium))
                Text("Add a Codex or Grok Build account to change the active CLI identity from here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                addAccountMenu
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 330, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    private func providerIcon(_ account: AccountRecord) -> String {
        account.identity.providerID == .codex
            ? "chevron.left.forwardslash.chevron.right" : "bolt.fill"
    }

    private func providerName(_ account: AccountRecord) -> String {
        account.identity.providerID == .codex ? "Codex" : "Grok Build"
    }

    private func copyAuthPath(_ account: AccountRecord) {
        NSPasteboard.general.clearContents()
        copiedAuthPath = NSPasteboard.general.setString(account.credentialFile.path, forType: .string)
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedAuthPath = false
        }
    }

    private func accountDetails(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: providerIcon(account))
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 50, height: 50)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.13, green: 0.21, blue: 0.32),
                                in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                        .font(.system(size: 19, weight: .medium))
                        .lineLimit(1)
                        .help(account.identity.email ?? account.identity.accountID ?? account.home.path)
                    HStack(spacing: 8) {
                        Text(account.identity.providerID == .codex ? "Codex CLI" : "Grok Build")
                        if model.snapshot?.status.isDefault(account) == true {
                            Text("·")
                            Text("Default identity")
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
                if model.snapshot?.status.isDefault(account) == true {
                    Button("Open \(providerName(account))") {
                        Task { await model.openAccount(account.id) }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Use & Open \(providerName(account))") {
                        Task { await model.openAccount(account.id) }
                    }
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
            VStack(alignment: .leading, spacing: 13) {
                accountFact("Access", value: verificationTitle(account.verification.state),
                            symbol: verificationSymbol(account.verification.state))
                    .help(account.verification.detail)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Home")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 64, alignment: .leading)
                    Text(account.home.path)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(account.home.path)
                        .textSelection(.enabled)
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

    private func accountFact(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 64, alignment: .leading)
            Label(value, systemImage: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
            QuietDivider()
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
                    Text(plan).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    if let primary = limits.primary { usageRow("Current window", window: primary) }
                    if let secondary = limits.secondary { usageRow("Longer window", window: secondary) }
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
    }

    private func usageRow(_ title: String, window: CodexRateLimitWindowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(window.usedPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .contentTransition(.numericText())
            }
            if let percent = window.usedPercent {
                ProgressView(value: Double(percent), total: 100)
                    .accessibilityLabel("\(title), \(percent)% used")
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func accountMetadata(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            QuietDivider()
            DisclosureGroup("Account details", isExpanded: $showingAccountDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    if let workspace = account.identity.workspaceID {
                        metadataRow("Workspace", value: workspace)
                    }
                    metadataRow("Saved auth", value: account.credentialFile.path)
                    metadataRow("Source", value: account.source.path)
                    metadataRow("Imported", value: account.importedAt.formatted(date: .abbreviated, time: .shortened))
                    metadataRow("Last used", value: account.lastUsedAt?.formatted(date: .abbreviated, time: .shortened)
                                ?? "Not launched yet")
                    Button(copiedAuthPath ? "Copied" : "Copy Auth Path") { copyAuthPath(account) }
                        .controlSize(.small)
                }
                .padding(.top, 8)
            }
            .font(.system(size: 13, weight: .medium))
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
    }

    @ViewBuilder
    private var discoveredSources: some View {
        let sources = model.discoveries.filter {
            $0.support == .supportedChatGPT || $0.support == .supportedOAuth
        }
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("AVAILABLE TO IMPORT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(source.identity?.email ?? source.path.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Button("Review Import") {
                            Task { await model.reviewImport(source: source.path, mode: .authOnly) }
                        }
                        .controlSize(.small)
                        .disabled(model.isWorking)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
            }
        }
    }

    private var recoveryPage: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(title: "Recovery", subtitle: "Account store and linked settings") {
                Button("Refresh") { Task { await model.refresh() } }
                    .disabled(model.isWorking)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Interrupted operations")
                            .font(.system(size: 14, weight: .medium))
                        if model.pendingRecovery.isEmpty {
                            Label("No operations need recovery", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Finish these operations before changing accounts.")
                                .foregroundStyle(.secondary)
                            Button("Recover Operations") { Task { await model.recover() } }
                                .disabled(model.isWorking)
                            ForEach(model.pendingRecovery) { operation in
                                HStack {
                                    Text("\(operation.kind) · \(operation.phase.rawValue)")
                                    Spacer()
                                    if operation.phase == .conflicted {
                                        Button("Resolve…") { conflictToResolve = operation }
                                    }
                                }
                            }
                        }
                    }
                    QuietDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Linked settings")
                            .font(.system(size: 14, weight: .medium))
                        if model.linkedSettingsIssues.isEmpty {
                            Label("No settings need repair", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.linkedSettingsIssues) { issue in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(issue.relativePath).fontWeight(.medium)
                                        Text(issue.localPath.path)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                    Button("Review Repair…") { linkedIssueToRepair = issue }
                                }
                            }
                        }
                    }
                    QuietDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shared data")
                            .font(.system(size: 14, weight: .medium))
                        Text(model.snapshot?.status.sharedRoot.path ?? "Loading…")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 12))
                .controlSize(.small)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .thinScrollIndicators()
        }
        .confirmationDialog("Resolve recovery conflict?", isPresented: Binding(
            get: { conflictToResolve != nil },
            set: { if !$0 { conflictToResolve = nil } }
        ), titleVisibility: .visible) {
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
        .confirmationDialog("Repair linked setting?", isPresented: Binding(
            get: { linkedIssueToRepair != nil },
            set: { if !$0 { linkedIssueToRepair = nil } }
        ), titleVisibility: .visible) {
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

    private var loginSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Account").font(.system(size: 17, weight: .semibold))
            Text(model.loginMessage ?? "Complete sign-in, then check its result.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if model.login?.providerID == .grokBuild {
                TextField("Authorization code or callback URL", text: $grokCode)
                    .textFieldStyle(.roundedBorder)
                Button("Submit Code") { Task { await model.submitLoginCode(grokCode) } }
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
