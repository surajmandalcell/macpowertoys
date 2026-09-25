import AIManagerCore
import AppKit
import SwiftUI

enum SwitchPage: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case recovery = "Recovery"

    var id: String { rawValue }
}

struct SwitchWindowView: View {
    @State private var model: SwitchWorkspaceModel
    @State private var page: SwitchPage
    @State private var showingDelete = false
    @State private var showingAbout = false
    @State private var showingAccountDetails = false
    @State private var showingSharedData = false
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
        VStack(spacing: 0) {
            header
            Group {
                switch page {
                case .accounts: accountsPage
                case .recovery: recoveryPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .utilityContentTransition(value: page)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var header: some View {
        HStack(spacing: 10) {
            Image("SwitchLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .toolIconTile(size: 24)
                .accessibilityHidden(true)
            Text("Switch")
                .font(.system(size: 14, weight: .semibold))
                .padding(.trailing, 22)
            ForEach(SwitchPage.allCases) { destination in
                Button(destination.rawValue) { page = destination }
                    .font(.system(size: 12, weight: page == destination ? .semibold : .medium))
                    .foregroundStyle(page == destination ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(page == destination ? Color.primary.opacity(0.09) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .accessibilityIdentifier("switch.page.\(destination.id)")
                    .accessibilityAddTraits(page == destination ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Button { Task { await model.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isWorking)
            Button {
                showingAbout = true
            } label: {
                Label("About", systemImage: "info.circle")
            }
            .accessibilityIdentifier("switch.about")
        }
        .controlSize(.small)
        .padding(.leading, UtilityLayout.workspaceTitleLeadingInset)
        .padding(.trailing, 18)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { QuietDivider() }
    }

    private var accountsPage: some View {
        Group {
            if model.snapshot != nil && model.accounts.isEmpty && model.importableDiscoveries.isEmpty {
                accountContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    accountList
                        .frame(width: 268)
                        .background(Color(nsColor: .underPageBackgroundColor))
                    QuietDivider()
                    accountContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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
            VStack(alignment: .center, spacing: 12) {
                Image("SwitchLogo")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .toolIconTile(size: 72)
                    .accessibilityHidden(true)
                    .padding(.bottom, 8)
                Text("Your CLI accounts, together")
                    .font(.system(size: 22, weight: .semibold))
                Text("Add a Codex or Grok Build account to switch identities and check usage from one place.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                addAccountMenu
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    .padding(.top, 10)
                Button("Import from Folder…") { chooseImportFolder() }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .foregroundStyle(.tint)
                    .disabled(model.isWorking)
            }
            .frame(maxWidth: 390)
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
                    .foregroundStyle(.tint)
                    .background(Color.accentColor.opacity(0.11),
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
            } else if let snapshot = model.usage[account.id] {
                HStack(spacing: 8) {
                    Text(snapshot.account?.plan?.capitalized ?? "Codex usage")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if snapshot.rateLimits?.ordinaryUsageAllowed == false {
                    Label("Ordinary usage is restricted", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                let buckets = usageBuckets(snapshot)
                if buckets.isEmpty {
                    Text("Rate limits unavailable")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                ForEach(buckets.indices, id: \.self) { index in
                    let bucket = buckets[index]
                    VStack(alignment: .leading, spacing: 9) {
                        Text(bucket.name ?? bucket.model ?? bucket.id ?? "Rate limits")
                            .font(.system(size: 12, weight: .medium))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                            if let primary = bucket.primary, primary.usedPercent != nil {
                                usageRow("Current window", window: primary)
                            }
                            if let secondary = bucket.secondary, secondary.usedPercent != nil {
                                usageRow("Longer window", window: secondary)
                            }
                        }
                        if let credits = bucket.credits {
                            Text("Credits: \(credits.unlimited == true ? "Unlimited" : credits.balance ?? (credits.hasCredits == true ? "Available" : "None"))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if bucket.spendControlReached == true {
                            Text("Spend control reached")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if let summary = snapshot.usage {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        if let value = summary.lifetimeTokens {
                            usageFact("Lifetime", value: value.formatted(.number.notation(.compactName)))
                        }
                        if let value = summary.peakDailyTokens {
                            usageFact("Peak day", value: value.formatted(.number.notation(.compactName)))
                        }
                        if let value = summary.currentStreakDays {
                            usageFact("Current streak", value: "\(value) days")
                        }
                        if let value = summary.longestStreakDays {
                            usageFact("Longest streak", value: "\(value) days")
                        }
                        if let value = summary.longestRunningTurnSeconds {
                            usageFact("Longest turn", value: "\(value) seconds")
                        }
                    }
                }
                if !snapshot.dailyUsage.isEmpty {
                    Text("Activity")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach([CodexTokenPeriod.today, .weekly, .monthly, .yearly], id: \.rawValue) { period in
                            usageFact(period.label,
                                      value: period.tokens(in: snapshot.dailyUsage, endingAt: .now)
                                        .formatted(.number.notation(.compactName)))
                        }
                    }
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
                ProgressView(value: Double(min(max(percent, 0), 100)), total: 100)
                    .accessibilityLabel("\(title), \(percent)% used")
            }
            if let reset = window.resetsAt {
                Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func usageBuckets(_ snapshot: CodexAccountUsageSnapshot) -> [CodexRateLimitBucketSnapshot] {
        guard let limits = snapshot.rateLimits else { return [] }
        var buckets: [CodexRateLimitBucketSnapshot] = []
        if let bucket = limits.defaultBucket {
            buckets.append(bucket)
        }
        for (key, bucket) in limits.buckets.sorted(by: { $0.key < $1.key }) {
            if !buckets.contains(where: { $0.id == (bucket.id ?? key) || $0 == bucket }) {
                buckets.append(bucket)
            }
        }
        return buckets.filter {
            $0.primary?.usedPercent != nil || $0.secondary?.usedPercent != nil
                || $0.credits != nil || $0.spendControlReached != nil
        }
    }

    private func usageFact(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountMetadata(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            QuietDivider()
            DisclosureGroup("Account details", isExpanded: $showingAccountDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    metadataRow("Home", value: account.home.path)
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
        let sources = model.importableDiscoveries
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Account recovery")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Review interrupted changes and linked settings.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)

                if model.pendingRecovery.isEmpty && model.linkedSettingsIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.green)
                            .padding(.bottom, 4)
                        Text("Everything is in sync")
                            .font(.system(size: 17, weight: .semibold))
                        Text("No account changes or linked settings need repair.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Button("Back to Accounts") { page = .accounts }
                            .padding(.top, 7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 14))
                }

                if !model.pendingRecovery.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Interrupted operations")
                            .font(.system(size: 16, weight: .semibold))
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

                if !model.linkedSettingsIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Linked settings")
                            .font(.system(size: 16, weight: .semibold))
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
                DisclosureGroup("Shared data location", isExpanded: $showingSharedData) {
                    Text(model.snapshot?.status.sharedRoot.path ?? "Loading…")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }
            }
            .font(.system(size: 12))
            .controlSize(.small)
            .frame(maxWidth: 620, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .thinScrollIndicators()
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
