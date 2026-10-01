import AIManagerCore
import AppKit
import OnePlusUI
import SwiftUI
import UniformTypeIdentifiers

enum SwitchPage: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case backup = "Backup"
    case settings = "Settings"
    case about = "About"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .accounts: "person.crop.circle"
        case .backup: "archivebox"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .accounts: "Import, verify, and switch accounts"
        case .backup: "Snapshots and interrupted operations"
        case .settings: "App behavior and data locations"
        case .about: "Saved accounts for your command-line tools"
        }
    }
}

nonisolated enum SwitchPageRoute: Equatable {
    case accounts, account(UUID), add, backup, settings, about

    init?(pageID: String) {
        switch pageID {
        case "accounts": self = .accounts
        case "add": self = .add
        case "backup": self = .backup
        case "settings": self = .settings
        case "about": self = .about
        default:
            guard pageID.hasPrefix("account/"), let id = UUID(uuidString: String(pageID.dropFirst(8))) else { return nil }
            self = .account(id)
        }
    }
}

struct SwitchWindowView: View {
    @State private var model: SwitchWorkspaceModel
    @State private var page: SwitchPage
    @AppStorage("switchUsageShowsUsed") private var showUsageAsUsed = true
    @AppStorage(SwitchTrayUsagePreferences.defaultKey) private var defaultShowTrayUsage = true
    @State private var showingDelete = false
    @State private var showingAddAccount = false
    @State private var showingImportOptions = false
    @State private var choosingImportSource = false
    @State private var pendingImportSource: URL?
    @State private var importMode: ImportMode = .authOnly
    @State private var selectedProviderID = ProviderID.codex
    @State private var copiedAuthPath = false
    @State private var trayUsageOverrides: [UUID: Bool] = [:]
    @State private var importDecisions: [String: ConflictChoice] = [:]
    @State private var grokCode = ""
    @State private var conflictToResolve: RecoveryOperation?
    @State private var linkedIssueToRepair: LinkedSettingsDivergence?
    @State private var pendingAccountRoute: SwitchPageRoute?

    init() {
        _model = State(initialValue: SwitchWorkspaceModel.shared)
        _page = State(initialValue: .accounts)
    }

    init(model: SwitchWorkspaceModel, initialPage: SwitchPage) {
        _model = State(initialValue: model)
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        OnePlusWindowRoot(canvas: .switchAccounts) { sidebar } content: {
            OnePlusPage {
                header
            } content: {
                switch page {
                case .accounts: accountContent
                case .backup: backupContent
                case .settings: SwitchSettingsContent(paths: model.paths)
                case .about: aboutContent
                }
            }
        }
        .buttonStyle(OnePlusButtonStyle())
        .background(WindowAccessor(identifier: "switch"))
        .task {
            if model.snapshot == nil { await model.load() }
            selectPendingAccount()
        }
        .onOpenToolPage("switch", perform: openPage)
        .task(id: usageRequest) {
            if page == .accounts, !model.isWorking, let id = model.selectedAccountID {
                await model.loadUsage(id, onlyIfNeeded: true)
                await model.loadAPIPricing()
            }
        }
        .onChange(of: model.selectedAccountID) { copiedAuthPath = false }
        .onChange(of: model.importPlan?.id) {
            importDecisions = Dictionary(uniqueKeysWithValues:
                (model.importPlan?.conflicts ?? []).map { ($0.relativePath, .keepShared) })
        }
        .sheet(isPresented: $showingAddAccount, onDismiss: {
            showingImportOptions = false
            if let source = pendingImportSource {
                pendingImportSource = nil
                Task { await model.reviewImport(source: source, mode: importMode) }
            }
        }) { addAccountSheet }
        .sheet(isPresented: Binding(get: { model.importPlan != nil },
                                   set: { if !$0 { model.dismissImport() } })) { importSheet }
        .alert("Switch needs attention", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            if !model.pendingRecovery.isEmpty {
                Button("View Backup") { model.errorMessage = nil; page = .backup }
            }
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Remove this account?", isPresented: $showingDelete, titleVisibility: .visible) {
            if let account = model.selectedAccount {
                if model.snapshot?.status.isDefault(account) == true {
                    ForEach(deletionReplacements(for: account)) { replacement in
                        Button("Use \(accountTitle(replacement)) as default and remove", role: .destructive) {
                            Task { await model.removeAccount(account.id, replacement: replacement.id) }
                        }
                    }
                } else {
                    Button("Remove Account", role: .destructive) {
                        Task { await model.removeAccount(account.id, replacement: nil) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved account and its managed credentials will be removed. Switch keeps a backup for interrupted operations.")
        }
        .confirmationDialog("Resolve recovery conflict?", isPresented: Binding(
            get: { conflictToResolve != nil }, set: { if !$0 { conflictToResolve = nil } }
        ), titleVisibility: .visible) {
            if let operation = conflictToResolve {
                Button("Preserve Current Data") {
                    Task { await model.resolveRecoveryConflict(operation.id, choice: .preserveCurrent) }
                    conflictToResolve = nil
                }
                Button("Restore Backup", role: .destructive) {
                    Task { await model.resolveRecoveryConflict(operation.id, choice: .restoreBackup) }
                    conflictToResolve = nil
                }
            }
        } message: { Text("Choose which data Switch should keep for this interrupted operation.") }
        .confirmationDialog("Repair linked setting?", isPresented: Binding(
            get: { linkedIssueToRepair != nil }, set: { if !$0 { linkedIssueToRepair = nil } }
        ), titleVisibility: .visible) {
            if let issue = linkedIssueToRepair {
                Button("Back Up Local File and Repair Link") {
                    Task { await model.repairLinkedSetting(issue) }
                    linkedIssueToRepair = nil
                }
            }
        } message: { Text("Switch will back up the local edit before restoring the shared settings link.") }
    }

    private var usageRequest: String { "\(page.rawValue)/\(model.selectedAccountID?.uuidString ?? "")/\(model.isWorking)" }

    private func openPage(_ pageID: String) {
        guard let destination = SwitchPageRoute(pageID: pageID) else { return }
        switch destination {
        case .accounts, .account:
            page = .accounts
            pendingAccountRoute = destination
            if model.snapshot != nil { selectPendingAccount() }
        case .add:
            page = .accounts
            showingAddAccount = true
        case .backup: page = .backup
        case .settings: page = .settings
        case .about: page = .about
        }
    }

    private func selectPendingAccount() {
        guard let destination = pendingAccountRoute else { return }
        pendingAccountRoute = nil
        switch destination {
        case .accounts: model.selectedAccountID = model.accounts.first?.id
        case .account(let id):
            if model.accounts.contains(where: { $0.id == id }) { model.selectedAccountID = id }
            else { model.errorMessage = "This saved account is no longer available." }
        default: break
        }
    }

    private var sidebar: some View {
        OnePlusSidebar(title: "Switch") {
            OnePlusNavCaption("Accounts")
            ForEach(model.accounts) { account in
                OnePlusAccountNavRow(accountTitle(account), subtitle: account.identity.providerID.displayName,
                                     selected: page == .accounts && model.selectedAccountID == account.id,
                                     isDefault: model.snapshot?.status.isDefault(account) == true) {
                    SwitchProviderIcon(providerID: account.identity.providerID, size: OnePlusMetrics.navIcon)
                } action: {
                    page = .accounts
                    model.selectedAccountID = account.id
                }
                .contextMenu { accountMenu(account, includesOrdering: true) }
            }
            OnePlusNavRow("Add account", systemImage: "plus") { showingAddAccount = true }
                .accessibilityIdentifier("switch.add").disabled(model.isWorking)
            OnePlusNavCaption("App")
            OnePlusNavRow("Backup", systemImage: "archivebox", selected: page == .backup,
                          count: model.pendingRecovery.isEmpty ? nil : model.pendingRecovery.count) { page = .backup }
                .accessibilityIdentifier("switch.page.Backup")
        } bottom: {
            OnePlusNavRow("Settings", systemImage: "gearshape", selected: page == .settings) { page = .settings }
                .keyboardShortcut(",").accessibilityIdentifier("switch.page.Settings")
            OnePlusNavRow("About", systemImage: "info.circle", selected: page == .about) { page = .about }
                .accessibilityIdentifier("switch.about")
        }
        .background {
            ForEach(1...9, id: \.self) { number in
                Button("Select destination \(number)") { selectDestination(number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number)))).hidden()
            }
        }
    }

    private func selectDestination(_ index: Int) {
        if model.accounts.indices.contains(index) {
            page = .accounts; model.selectedAccountID = model.accounts[index].id
        } else {
            switch index - model.accounts.count {
            case 0: showingAddAccount = true
            case 1: page = .backup
            case 2: page = .settings
            case 3: page = .about
            default: break
            }
        }
    }

    @ViewBuilder private var header: some View {
        if page == .accounts, let account = model.selectedAccount {
            OnePlusPageHeader(title: accountTitle(account), subtitle: account.identity.workspaceID
                              ?? model.usage[account.id]?.account?.plan?.capitalized ?? "Personal workspace") {
                accountActions(account)
            }
        } else {
            OnePlusPageHeader(title: page.rawValue, subtitle: page.subtitle) {
                if page == .backup {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                        .disabled(model.isWorking)
                }
            }
        }
    }

    @ViewBuilder private var accountContent: some View {
        if let notice = model.noticeMessage { OnePlusBanner(notice) }
        if model.login != nil {
            OnePlusBanner("A sign-in is still pending.", tone: .warning) {
                Button("Resume sign-in") { showingAddAccount = true }
            }
        }
        if !model.pendingRecovery.isEmpty {
            OnePlusBanner("An account operation needs recovery.", tone: .warning) {
                Button("View Backup") { page = .backup }
            }
        }
        if model.snapshot == nil && model.isWorking {
            OnePlusCard { OnePlusEmptyState("Loading accounts", systemImage: "person.crop.circle",
                                            caption: "Reading the saved account list.") { ProgressView().controlSize(.small) } }
        } else if model.snapshot == nil {
            OnePlusCard {
                OnePlusEmptyState("Accounts unavailable", systemImage: "exclamationmark.circle",
                                  caption: "The saved account list could not be opened.") {
                    Button("Retry") { Task { await model.load() } }
                }
            }
        } else if let account = model.selectedAccount {
            identityCard(account)
            if account.identity.providerID == .codex {
                accountUsage(account)
                if let error = model.usageCacheError { OnePlusBanner(error, tone: .warning) }
                SwitchActivityGrid(rows: model.dailyUsage[account.id] ?? model.usage[account.id]?.dailyUsage,
                                   updatedAt: model.usage[account.id]?.fetchedAt,
                                   error: model.usageErrors[account.id], apiPrice: model.apiPrice)
                    .id(account.id)
            }
        } else {
            OnePlusCard {
                OnePlusEmptyState("Add your first account", systemImage: "person.crop.circle.badge.plus",
                                  caption: "Sign in to a supported tool, or import an existing Codex folder.") {
                    Button("Add account") { showingAddAccount = true }
                    Button("Advanced Import") { beginAdvancedImport() }
                }
            }
        }
        discoveredSources
    }

    private func identityCard(_ account: AccountRecord) -> some View {
        OnePlusCard {
            OnePlusCardHeader("Identity", systemImage: "person.crop.circle") {
                OnePlusStatus(verificationTitle(account.verification.state),
                              state: account.verification.state == .needsSignIn ? .warning : .online)
                    .help(account.verification.detail)
            }
            VStack(spacing: 0) {
                OnePlusKeyValueRow("Account", value: accountTitle(account))
                OnePlusKeyValueRow("Tool", value: account.identity.providerID.displayName)
                if let workspace = account.identity.workspaceID { OnePlusKeyValueRow("Workspace", value: workspace) }
                OnePlusKeyValueRow(account.identity.providerID == .claudeCode ? "Profile config" : "Saved auth",
                                   value: account.credentialFile.path, monospaced: true)
                OnePlusKeyValueRow("Source", value: account.source.path, monospaced: true)
                OnePlusKeyValueRow("Home", value: account.home.path, monospaced: true)
                OnePlusKeyValueRow("Imported", value: account.importedAt.formatted(date: .abbreviated, time: .shortened))
                OnePlusKeyValueRow("Last used", value: account.lastUsedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not launched yet")
            }.padding(OnePlusMetrics.cardPadding)
        }
    }

    @ViewBuilder private func accountActions(_ account: AccountRecord) -> some View {
        let isDefault = model.snapshot?.status.isDefault(account) == true
        Button("Use as default") {
            Task { await model.makeDefault(account.id) }
        }.buttonStyle(OnePlusButtonStyle(isDefault ? .neutral : .primary)).disabled(model.isWorking)
        if account.identity.providerID == .codex {
            Toggle("Show in menu bar", isOn: Binding(get: { showsTrayUsage(account.id) }, set: { value in
                trayUsageOverrides[account.id] = value
                SwitchTrayUsagePreferences.setOverride(value, for: account.id)
            })).toggleStyle(OnePlusSwitchStyle()).fixedSize().disabled(model.isWorking)
                .contextMenu {
                    Button("Use Menu Bar Default") {
                        trayUsageOverrides.removeValue(forKey: account.id)
                        SwitchTrayUsagePreferences.useDefault(for: account.id)
                    }.disabled(SwitchTrayUsagePreferences.explicitValue(for: account.id) == nil)
                }
        }
        Button("Open \(account.identity.providerID.displayName)", systemImage: "play") {
            Task { await model.openAccount(account.id) }
        }.disabled(model.isWorking)
        OnePlusActionMenu("More", width: OnePlusMetrics.controlColumn / 2) { accountMenu(account) }
    }

    @ViewBuilder private func accountMenu(_ account: AccountRecord, includesOrdering: Bool = false) -> some View {
        Button("Verify access") { Task { await model.verify(account.id) } }
            .disabled(model.isWorking || model.usageLoading.contains(account.id))
        Button("Refresh accounts") { Task { await model.refresh() } }.disabled(model.isWorking)
        Button(copiedAuthPath ? "Copied path" : "Copy saved path") { copyAuthPath(account) }
        if includesOrdering {
            Button("Use as default") { Task { await model.makeDefault(account.id) } }
                .disabled(model.isWorking)
            Button("Open \(account.identity.providerID.displayName)") { Task { await model.openAccount(account.id) } }
                .disabled(model.isWorking)
            Divider()
            Button("Move Up") { Task { await model.moveAccount(account.id, by: -1) } }
                .disabled(model.isWorking || model.accounts.first?.id == account.id)
            Button("Move Down") { Task { await model.moveAccount(account.id, by: 1) } }
                .disabled(model.isWorking || model.accounts.last?.id == account.id)
        }
        Divider()
        Button("Remove account", role: .destructive) {
            model.selectedAccountID = account.id; showingDelete = true
        }.disabled(model.isWorking || (model.snapshot?.status.isDefault(account) == true && deletionReplacements(for: account).isEmpty))
    }

    private func accountTitle(_ account: AccountRecord) -> String {
        account.identity.email ?? account.identity.accountID ?? "Saved account"
    }

    private func copyAuthPath(_ account: AccountRecord) {
        NSPasteboard.general.clearContents()
        copiedAuthPath = NSPasteboard.general.setString(account.credentialFile.path, forType: .string)
    }

    private func showsTrayUsage(_ id: UUID) -> Bool {
        trayUsageOverrides[id] ?? SwitchTrayUsagePreferences.explicitValue(for: id) ?? defaultShowTrayUsage
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

    private func accountUsage(_ account: AccountRecord) -> some View {
        OnePlusCard {
            OnePlusCardHeader("Usage", systemImage: "chart.bar") {
                Text(model.usage[account.id]?.account?.plan?.capitalized ?? "").onePlusText(.caption)
                if let fetchedAt = model.usage[account.id]?.fetchedAt {
                    Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))").onePlusText(.caption)
                }
                Button { Task { await model.loadUsage(account.id) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(OnePlusButtonStyle(.icon)).help("Refresh usage").accessibilityLabel("Refresh usage")
                    .disabled(model.isWorking || model.usageLoading.contains(account.id) || account.verification.state == .needsSignIn)
            }
            VStack(alignment: .leading, spacing: 0) {
                if account.verification.state == .needsSignIn {
                    OnePlusBanner("Sign in again to view usage for this account.", tone: .warning) {
                        Button("Sign in") { selectedProviderID = account.identity.providerID; showingAddAccount = true }
                    }.padding(OnePlusMetrics.cardPadding)
                } else if let snapshot = model.usage[account.id] {
                    let buckets = usageBuckets(snapshot)
                    if let error = model.usageErrors[account.id] {
                        OnePlusBanner("\(error) Showing the last saved usage.", tone: .warning)
                    }
                    usageFacts(snapshot)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(buckets.indices, id: \.self) { index in
                                usageBucket(buckets[index])
                            }
                            if buckets.isEmpty {
                                Text("Rate limits unavailable").onePlusText(.caption).padding(OnePlusMetrics.cardPadding)
                            }
                        }
                    }
                    .onePlusScrollIndicators()
                } else {
                    OnePlusEmptyState(
                        model.usageLoading.contains(account.id) ? "Checking account usage" : "Usage has not been checked",
                        systemImage: "chart.bar",
                        caption: usageEmptyCaption(account.id)
                    ) {
                        if model.usageLoading.contains(account.id) { ProgressView().controlSize(.small) }
                        else { Button("Refresh usage") { Task { await model.loadUsage(account.id) } } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: OnePlusMetrics.captionedSettingRow * 4,
                   alignment: model.usage[account.id] == nil ? .center : .topLeading)
        }
    }

    private func usageEmptyCaption(_ accountID: UUID) -> String {
        guard let error = model.usageErrors[accountID] else {
            return "Refresh usage without changing the default account."
        }
        return "\(error) Select Refresh usage to try again."
    }

    private func usageFacts(_ snapshot: CodexAccountUsageSnapshot) -> some View {
        HStack(alignment: .top, spacing: 0) {
            OnePlusStatCell("Ordinary usage", value: snapshot.rateLimits?.ordinaryUsageAllowed.map { $0 ? "Available" : "Restricted" } ?? "Unavailable")
            OnePlusRule(vertical: true)
            OnePlusStatCell("Authentication", value: snapshot.account == nil ? "Verified locally" : "Signed in")
            OnePlusRule(vertical: true)
            OnePlusStatCell("Lifetime", value: snapshot.usage?.lifetimeTokens?.formatted(.number.notation(.compactName)) ?? "Unavailable")
            OnePlusRule(vertical: true)
            OnePlusStatCell("Peak day", value: snapshot.usage?.peakDailyTokens?.formatted(.number.notation(.compactName)) ?? "Unavailable")
            OnePlusRule(vertical: true)
            OnePlusStatCell("Current streak", value: snapshot.usage?.currentStreakDays.map { "\($0) days" } ?? "Unavailable")
            OnePlusRule(vertical: true)
            OnePlusStatCell("Longest streak", value: snapshot.usage?.longestStreakDays.map { "\($0) days" } ?? "Unavailable")
            OnePlusRule(vertical: true)
            OnePlusStatCell("Longest turn", value: snapshot.usage?.longestRunningTurnSeconds.map {
                Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
            } ?? "Unavailable")
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func usageBucket(_ bucket: CodexRateLimitBucketSnapshot) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            OnePlusRule()
            HStack {
                Text(bucket.name ?? bucket.model ?? bucket.id ?? "Rate limits").onePlusText(.cardTitle)
                if let model = bucket.model { Text(model).onePlusText(.caption) }
                Spacer()
                if let plan = bucket.plan { Text(plan).onePlusText(.caption) }
            }
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                if let window = bucket.primary, window.usedPercent != nil { usageRow(window, fallback: "Current window") }
                if let window = bucket.secondary, window.usedPercent != nil { usageRow(window, fallback: "Secondary window") }
            }
            HStack(spacing: OnePlusMetrics.cardGap) {
                if let credits = bucket.credits {
                    OnePlusKeyValueRow("Credits", value: credits.unlimited == true ? "Unlimited"
                                       : credits.balance ?? (credits.hasCredits == true ? "Available" : "None"))
                }
                if let reached = bucket.spendControlReached {
                    OnePlusKeyValueRow("Spend control", value: reached ? "Reached" : "Not reached")
                }
            }
        }.padding(OnePlusMetrics.cardPadding)
    }

    private func usageRow(_ window: CodexRateLimitWindowSnapshot, fallback: String) -> some View {
        let title = windowTitle(window, fallback: fallback)
        let percentage = window.usedPercent.map {
            SwitchTrayUsagePreferences.percentageLabel(used: $0, showUsed: showUsageAsUsed)
        } ?? "Unavailable"
        return VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack { Text(title).onePlusText(.row); Spacer(); Text(percentage).onePlusText(.mono) }
            if let percent = window.usedPercent {
                OnePlusUsageBar(value: Double(showUsageAsUsed ? min(max(percent, 0), 100) : 100 - min(max(percent, 0), 100)) / 100)
                    .accessibilityLabel("\(title), \(percentage)")
            }
            if let reset = window.resetsAt {
                Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))").onePlusText(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func windowTitle(_ window: CodexRateLimitWindowSnapshot, fallback: String) -> String {
        guard let minutes = window.windowDurationMinutes else { return fallback }
        if minutes >= 10_080 { return "Weekly window" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }

    private func usageBuckets(_ snapshot: CodexAccountUsageSnapshot) -> [CodexRateLimitBucketSnapshot] {
        guard let limits = snapshot.rateLimits else { return [] }
        var buckets: [CodexRateLimitBucketSnapshot] = []
        if let bucket = limits.defaultBucket { buckets.append(bucket) }
        for (key, bucket) in limits.buckets.sorted(by: { $0.key < $1.key }) {
            if !buckets.contains(where: { $0.id == (bucket.id ?? key) || $0 == bucket }) { buckets.append(bucket) }
        }
        return buckets.filter {
            $0.primary?.usedPercent != nil || $0.secondary?.usedPercent != nil || $0.credits != nil || $0.spendControlReached != nil
        }
    }

    @ViewBuilder private var discoveredSources: some View {
        if !model.importableDiscoveries.isEmpty {
            OnePlusCard {
                OnePlusCardHeader("Available to import", systemImage: "square.and.arrow.down")
                ForEach(model.importableDiscoveries) { source in
                    OnePlusPathSettingRow(source.identity?.email ?? source.path.lastPathComponent, path: source.path.path) {
                        Button("Review Import") { Task { await model.reviewImport(source: source.path, mode: .authOnly) } }
                            .disabled(model.isWorking)
                    }
                }
            }
        }
    }

    private var backupContent: some View {
        Group {
            if let notice = model.noticeMessage { OnePlusBanner(notice) }
            OnePlusCard {
                OnePlusCardHeader("Pending operations")
                if model.pendingRecovery.isEmpty {
                    OnePlusEmptyState("No interrupted operations", systemImage: "checkmark.circle",
                                      caption: "Recovery actions appear here when an account change needs attention.") {
                        Button("View accounts") { page = .accounts }
                    }
                } else {
                    ForEach(model.pendingRecovery) { operation in
                        OnePlusPathSettingRow(operation.kind.capitalized, path: operation.destination.path) {
                            if operation.phase == .conflicted { Button("Resolve") { conflictToResolve = operation }.disabled(model.isWorking) }
                            else { OnePlusStatus(operation.phase.rawValue, state: .warning) }
                        }
                        OnePlusPathSettingRow("Protected backup", path: operation.backup.path) {
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([operation.backup]) }
                        }
                    }
                }
            }
            if !model.linkedSettingsIssues.isEmpty {
                OnePlusCard {
                    OnePlusCardHeader("Linked settings")
                    ForEach(model.linkedSettingsIssues) { issue in
                        OnePlusPathSettingRow("Linked setting", path: issue.localPath.path) {
                            Button("Review repair") { linkedIssueToRepair = issue }.disabled(model.isWorking)
                        }
                    }
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Backup policy")
                VStack(spacing: 0) {
                    OnePlusKeyValueRow("Before import", value: "Review destination and conflicts")
                    OnePlusKeyValueRow("During import", value: "Back up, stage, verify, then publish")
                    OnePlusKeyValueRow("On failure", value: "Keep prior credentials and the backup journal")
                }.padding(OnePlusMetrics.cardPadding)
                OnePlusSettingRow("Recovery backups", caption: "Created automatically when account data changes.", separator: false) {
                    Button("Show backups", systemImage: "folder") {
                        let folder = model.paths.applicationSupport.appending(path: "backups", directoryHint: .isDirectory)
                        NSWorkspace.shared.activateFileViewerSelecting([
                            FileManager.default.fileExists(atPath: folder.path) ? folder : model.paths.applicationSupport
                        ])
                    }
                }
                OnePlusPathSettingRow("Claude profile backups", path: model.paths.applicationSupport.appending(path: "claude-code-profiles/backups").path) {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.paths.applicationSupport.appending(path: "claude-code-profiles")])
                    }
                }
                if let backup = model.lastBackupURL {
                    OnePlusPathSettingRow("Latest operation backup", path: backup.path) {
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                    }
                }
            }
            if model.pendingRecovery.contains(where: { $0.phase != .conflicted }) {
                OnePlusBanner("An interrupted operation is ready for recovery.", tone: .warning) {
                    Button("Finish pending work") { Task { await model.recover() } }.disabled(model.isWorking)
                }
            }
        }
    }

    private var aboutContent: some View {
        Group {
        OnePlusCard {
            OnePlusCardHeader("Switch")
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Image("SwitchLogo").resizable().scaledToFit().frame(width: OnePlusMetrics.titleRow, height: OnePlusMetrics.titleRow)
                Text("Keep CLI accounts together and switch identities.").onePlusText(.sectionTitle)
                Text("Switch manages sign-in, imports, defaults, usage, and recovery through the shared Switch Core package. The standalone Switch app is optional.")
                    .onePlusText(.row).textSelection(.enabled)
                OnePlusKeyValueRow("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                Text("Conversation browsing and cleanup are available in standalone Switch.").onePlusText(.caption)
            }.padding(OnePlusMetrics.cardPadding)
        }
            ForEach(SwitchTool.shared.manual) { section in
                OnePlusCard {
                    OnePlusCardHeader(section.title)
                    VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                        ForEach(section.points, id: \.self) { Text($0).onePlusText(.row).textSelection(.enabled) }
                    }.padding(OnePlusMetrics.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var addAccountSheet: some View {
        OnePlusSheet(showingImportOptions ? "Import account" : "Add account", close: { showingAddAccount = false }) {
            if showingImportOptions { importOptions }
            else if model.login != nil { loginContent }
            else {
                OnePlusCard {
                    ForEach(AccountManager.providerCatalog) { provider in
                        let available = provider.availability == .enabled
                        Button { selectedProviderID = provider.id } label: {
                            HStack(spacing: OnePlusMetrics.actionSpacing) {
                                SwitchProviderIcon(providerID: provider.id)
                                VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                                    Text(provider.displayName).onePlusText(.row)
                                    Text(available ? "Account switching is supported." : provider.unavailableReason ?? "Not available yet.")
                                        .onePlusText(.caption).lineLimit(1)
                                }
                                Spacer()
                                if selectedProviderID == provider.id { Image(systemName: "checkmark").onePlusText(.row) }
                            }.padding(.horizontal, OnePlusMetrics.cardPadding).frame(height: OnePlusMetrics.captionedSettingRow)
                        }.buttonStyle(OnePlusInteractionStyle(selected: selectedProviderID == provider.id))
                            .disabled(!available || model.isWorking)
                            .accessibilityIdentifier("switch.provider.\(provider.id.rawValue)")
                            .accessibilityValue(selectedProviderID == provider.id ? "Selected" : "")
                    }
                }
            }
        } footer: {
            if showingImportOptions {
                Button("Back") { showingImportOptions = false }.buttonStyle(OnePlusButtonStyle(.ghost))
                Button("Choose file or folder") { choosingImportSource = true }
                    .buttonStyle(OnePlusButtonStyle(.primary)).disabled(model.isWorking)
            } else if model.login != nil {
                Button("Cancel Sign-in") {
                    Task { await model.cancelLogin(); if model.login == nil { showingAddAccount = false } }
                }
                    .buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                if model.loginState == .credentialChoiceRequired {
                    Button("Keep Saved Access") { Task { await checkAccountLogin(choice: .keepShared) } }
                        .disabled(model.isWorking)
                    Button("Use New Access") { Task { await checkAccountLogin(choice: .useImported) } }
                        .disabled(model.isWorking)
                } else {
                    Button("Check Sign-in") { Task { await checkAccountLogin() } }
                        .buttonStyle(OnePlusButtonStyle(.primary)).disabled(model.isWorking)
                }
            } else {
                Button("Advanced Import") { showingImportOptions = true }
                Button("Continue") { Task { await model.beginLogin(providerID: selectedProviderID) } }
                    .buttonStyle(OnePlusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking || AccountManager.providerCatalog.first { $0.id == selectedProviderID }?.availability != .enabled)
            }
        }
        .fileImporter(isPresented: $choosingImportSource, allowedContentTypes: [.folder, .json]) { result in
            switch result {
            case .success(let source): pendingImportSource = source; showingAddAccount = false
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .buttonStyle(OnePlusButtonStyle())
    }

    private var importOptions: some View {
        OnePlusCard {
            OnePlusCardHeader("Import contents")
            OnePlusSettingRow("Include", caption: "Settings and history are available for Codex folders.", separator: false) {
                OnePlusSelect(choices: [(ImportMode.authOnly, "Account access only"), (.full, "Access, settings, history")],
                              selection: $importMode, accessibilityLabel: "Import contents")
            }
        }
    }

    private var loginContent: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            OnePlusBanner(model.loginMessage ?? "Complete sign-in, then check its result.")
            if model.login?.providerID == .grokBuild {
                OnePlusTextField("Authorization code or callback URL", text: $grokCode)
                Button("Submit Code") { Task { await model.submitLoginCode(grokCode) } }
                    .disabled(grokCode.isEmpty || model.isWorking)
            }
            if model.isWorking { ProgressView().controlSize(.small) }
        }
    }

    private func checkAccountLogin(choice: ConflictChoice? = nil) async {
        await model.checkLogin(choice: choice)
        if model.login == nil { showingAddAccount = false; page = .accounts }
    }

    @ViewBuilder private var importSheet: some View {
        if let plan = model.importPlan {
            OnePlusSheet("Review import", width: .large, close: model.dismissImport) {
                VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                    OnePlusKeyValueRow("Account", value: plan.identity.email ?? plan.source.path,
                                       monospaced: plan.identity.email == nil)
                    OnePlusKeyValueRow("Provider", value: plan.identity.providerID.displayName)
                    OnePlusKeyValueRow("Include", value: plan.mode == .authOnly ? "Account access only" : "Account access, settings, and history")
                    OnePlusKeyValueRow("Saved destination", value: plan.credentialDestination.path, monospaced: true)
                    OnePlusKeyValueRow("Backup", value: plan.backup.path, monospaced: true)
                    OnePlusKeyValueRow("Import size", value: "\(plan.manifest.count) items · \(ByteCountFormatter.string(fromByteCount: plan.requiredBytes, countStyle: .file))")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                            ForEach(plan.warnings, id: \.self) { OnePlusBanner($0, tone: .warning) }
                            ForEach(plan.conflicts) { conflict in
                                OnePlusCard {
                                    OnePlusPathSettingRow("Conflicting setting", path: conflict.relativePath) {
                                        OnePlusSelect(choices: [(.keepShared, "Keep saved"), (.useImported, "Use imported")],
                                                      selection: Binding(get: { importDecisions[conflict.relativePath] ?? .keepShared },
                                                                         set: { importDecisions[conflict.relativePath] = $0 }),
                                                      accessibilityLabel: conflict.relativePath)
                                    }
                                    if let target = conflict.externalTarget {
                                        OnePlusPathSettingRow("External setting", path: target.path) {
                                            Button("Review") { Task { await model.reviewExternalSetting(conflict.relativePath) } }
                                        }
                                    }
                                }
                            }
                        }
                    }.onePlusScrollIndicators().frame(maxHeight: OnePlusMetrics.settingRow * 6)
                }
            } footer: {
                Button("Cancel") { model.dismissImport() }.buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
                Button("Import Account") { Task { await model.commitImport(decisions: importDecisions); page = .accounts } }
                    .buttonStyle(OnePlusButtonStyle(.primary)).disabled(model.isWorking)
            }.buttonStyle(OnePlusButtonStyle())
        }
    }

    private func beginAdvancedImport() {
        showingImportOptions = true
        showingAddAccount = true
    }
}

struct SwitchProviderIcon: View {
    let providerID: ProviderID
    var size: CGFloat = OnePlusMetrics.compactControlHeight
    private var assetName: String? {
        switch providerID {
        case .codex: "SwitchCodexProvider"
        case .grokBuild: "SwitchGrokProvider"
        case .claudeCode: "SwitchClaudeProvider"
        case .geminiCLI: "SwitchGeminiProvider"
        case .antigravityCLI: "SwitchAntigravityProvider"
        default: nil
        }
    }
    var body: some View {
        OnePlusProviderTile(size: size) {
            if let assetName { Image(assetName).resizable().scaledToFit() }
            else { Image(systemName: "terminal").resizable().scaledToFit() }
        }.accessibilityHidden(true)
    }
}

struct SwitchActivityGrid: View {
    let rows: [CodexDailyUsageSnapshot]?
    let updatedAt: Date?
    var error: String? = nil
    var apiPrice: CodexAPIPrice? = nil
    @State private var selectedDate: Date?
    @AppStorage("switchActivityPeriod") private var savedPeriod = CodexTokenPeriod.yearly.rawValue
    @State private var presentation: Presentation?
    private var period: CodexTokenPeriod { CodexTokenPeriod(rawValue: savedPeriod) ?? .yearly }

    nonisolated struct Day: Sendable {
        let date: Date
        let tokens: Int64
        let level: Int
        let shortLabel: String
        let accessibilityLabel: String
        let tokenLabel: String
    }

    nonisolated struct Presentation: Sendable {
        let weeks: [[Day?]]
        let totals: [String: Int64]
        let hasData: Bool
    }

    nonisolated private struct Request: Equatable {
        let period: String
        let updatedAt: Date?
        let rows: [CodexDailyUsageSnapshot]?
    }

    nonisolated private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    nonisolated static func makePresentation(
        rows: [CodexDailyUsageSnapshot],
        period: CodexTokenPeriod,
        now: Date
    ) -> Presentation {
        let calendar = Self.calendar
        guard let range = period.dateRange(endingAt: now) else {
            return Presentation(weeks: [], totals: [:], hasData: false)
        }
        let today = range.upperBound
        let first = range.lowerBound
        let start = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: first), to: first) ?? first
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        var tokens: [String: Int64] = [:]
        var hasData = false
        for row in rows {
            guard let key = row.startDate, let date = formatter.date(from: key),
                  formatter.string(from: date) == key,
                  let count = row.tokens, count >= 0 else { continue }
            hasData = true
            guard range.contains(date) else { continue }
            let (sum, overflow) = tokens[key, default: 0].addingReportingOverflow(count)
            tokens[key] = overflow ? Int64.max : sum
        }
        let maximum = max(Int64(1), tokens.values.max() ?? 1)
        let dayCount = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        var weeks: [[Day?]] = []
        for weekOffset in stride(from: 0, to: dayCount, by: 7) {
            var week: [Day?] = []
            for weekday in 0..<7 {
                guard let date = calendar.date(
                    byAdding: .day,
                    value: weekOffset + weekday,
                    to: start
                ), date <= today, date >= first else {
                    week.append(nil)
                    continue
                }
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                let count = tokens[key, default: 0]
                week.append(Day(
                    date: date,
                    tokens: count,
                    level: 3 - min(3, Int(sqrt(Double(count) / Double(maximum)) * 3)),
                    shortLabel: date.formatted(date: .abbreviated, time: .omitted),
                    accessibilityLabel: date.formatted(date: .complete, time: .omitted),
                    tokenLabel: "\(count.formatted()) tokens"
                ))
            }
            weeks.append(week)
        }
        let totals = Dictionary(uniqueKeysWithValues: CodexTokenPeriod.allCases.map { period in
            (period.rawValue, period.tokens(in: rows, endingAt: now))
        })
        return Presentation(weeks: weeks, totals: totals, hasData: hasData)
    }

    private var showsEmptyState: Bool {
        presentation?.hasData == false || (error != nil && presentation?.hasData != true)
    }
    private var chartHeight: CGFloat { 7 * OnePlusMetrics.navPadding + 6 * OnePlusMetrics.navRowGap }

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader("Daily activity", systemImage: "calendar") {
                OnePlusSegmented(choices: CodexTokenPeriod.allCases.map { ($0.rawValue, $0.label) },
                                 selection: $savedPeriod, accessibilityLabel: "Activity period").fixedSize()
            }
            VStack(spacing: 0) {
                activityChart
                HStack(spacing: 0) {
                    ForEach(CodexTokenPeriod.allCases, id: \.rawValue) { period in
                        OnePlusStatCell(period.label, value: presentation?.totals[period.rawValue]
                            .map { $0.formatted(.number.notation(.compactName)) } ?? "-")
                            .help(presentation?.totals[period.rawValue].map(tokenDetail) ?? "Loading token totals")
                        if period != .yearly { OnePlusRule(vertical: true) }
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
            .opacity(showsEmptyState ? 0 : 1)
            .accessibilityHidden(showsEmptyState)
            .allowsHitTesting(!showsEmptyState)
            .overlay {
                if error != nil && presentation?.hasData != true {
                    OnePlusEmptyState("Daily activity unavailable", systemImage: "exclamationmark.circle",
                                      caption: "Refresh usage to try again.")
                } else if presentation?.hasData == false {
                    OnePlusEmptyState("No daily activity", systemImage: "calendar",
                                      caption: "This account has no recorded daily token usage.")
                }
            }
        }
        .task(id: Request(period: period.rawValue, updatedAt: updatedAt, rows: rows)) {
            selectedDate = nil
            guard let rows else { return }
            let period = period
            let result = await Task.detached(priority: .utility) {
                Self.makePresentation(rows: rows, period: period, now: .now)
            }.value
            guard !Task.isCancelled else { return }
            presentation = result
        }
    }

    private func tokenDetail(_ tokens: Int64) -> String {
        var detail = "\(tokens.formatted()) tokens"
        if let price = apiPrice {
            detail += ". \(price.model) API rate equivalents: input \(price.inputEquivalent(for: tokens).formatted(.currency(code: "USD"))), output \(price.outputEquivalent(for: tokens).formatted(.currency(code: "USD")))."
            if let cached = price.cachedInputEquivalent(for: tokens) {
                detail += " Cached input \(cached.formatted(.currency(code: "USD")))."
            }
            detail += " This compares rates, not billed spend."
        }
        return detail
    }

    private var activityChart: some View {
        ZStack {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: OnePlusMetrics.navRowGap) {
                    if let presentation {
                        ForEach(presentation.weeks.indices, id: \.self) { column in
                            VStack(spacing: OnePlusMetrics.navRowGap) {
                                ForEach(0..<7) { row in
                                    if let day = presentation.weeks[column][row] {
                                        Button { selectedDate = day.date } label: {
                                            RoundedRectangle(cornerRadius: OnePlusMetrics.segmentRadius)
                                                .fill(day.tokens == 0 ? OnePlusColor.track : OnePlusColor.chartSeries[day.level])
                                                .frame(width: OnePlusMetrics.navPadding, height: OnePlusMetrics.navPadding)
                                        }.buttonStyle(OnePlusInteractionStyle(selected: selectedDate == day.date))
                                            .accessibilityLabel(day.accessibilityLabel)
                                            .accessibilityValue(day.tokenLabel)
                                    } else {
                                        Color.clear.frame(width: OnePlusMetrics.navPadding, height: OnePlusMetrics.navPadding)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                }
            }.onePlusScrollIndicators().frame(height: chartHeight)
            if presentation == nil {
                ProgressView("Loading daily activity").controlSize(.small).onePlusText(.row)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(OnePlusMetrics.cardPadding)
        .overlay(alignment: .bottomLeading) {
            if let selectedDate,
               let day = presentation?.weeks.flatMap({ $0 }).compactMap({ $0 }).first(where: { $0.date == selectedDate }) {
                Text("\(day.shortLabel): \(day.tokenLabel)")
                    .onePlusText(.caption).padding(.horizontal, OnePlusMetrics.cardPadding)
            }
        }
    }
}
