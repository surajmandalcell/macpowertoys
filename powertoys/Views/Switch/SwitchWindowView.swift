import AIManagerCore
import AppKit
import SwiftUI

enum SwitchPage: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case backup = "Backup"
    case settings = "Settings"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .accounts: "person.crop.circle"
        case .backup: "archivebox"
        case .settings: "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .accounts: "Import, verify, and switch accounts"
        case .backup: "Snapshots and interrupted operations"
        case .settings: "App behavior and data locations"
        }
    }
}

struct SwitchWindowView: View {
    @State private var model: SwitchWorkspaceModel
    @State private var page: SwitchPage
    @AppStorage("switchAppearanceMode") private var appearanceMode = "system"
    @AppStorage("switchUsageShowsUsed") private var showUsageAsUsed = true
    @AppStorage(SwitchTrayUsagePreferences.defaultKey) private var defaultShowTrayUsage = true
    @AppStorage(SwitchTrayUsagePreferences.periodKey) private var trayTokenPeriod = SwitchTrayTokenPeriod.sinceReset.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @State private var showingDelete = false
    @State private var showingAbout = false
    @State private var copiedAuthPath = false
    @State private var hoveredAccountID: UUID?
    @State private var trayUsageOverrides: [UUID: Bool] = [:]
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

    private var schemeOverride: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
    private var palette: SwitchPalette {
        SwitchPalette(dark: (schemeOverride ?? systemScheme) == .dark)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            VStack(spacing: 0) {
                header
                Group {
                    switch page {
                    case .accounts: accountsPage
                    case .backup: backupPage
                    case .settings: settingsPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .utilityContentTransition(value: page)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(palette.ink)
        .background(palette.canvas)
        .ignoresSafeArea()
        .preferredColorScheme(schemeOverride)
        .background(WindowAccessor(identifier: "switch"))
        .task { await model.load() }
        .task(id: model.selectedAccountID) {
            if let id = model.selectedAccountID {
                await model.loadUsage(id, onlyIfNeeded: true)
            }
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
        .alert("Switch needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 48).accessibilityHidden(true)
            ForEach(SwitchPage.allCases) { destination in
                railButton(destination.symbol, label: destination.rawValue,
                           selected: page == destination) { page = destination }
            }
            Spacer(minLength: 0)
            railButton(palette.dark ? "sun.max" : "moon", label: palette.dark ? "Light mode" : "Dark mode") {
                appearanceMode = palette.dark ? "light" : "dark"
            }
            .accessibilityIdentifier("switch.appearance")
            Menu {
                ForEach(AccountManager.providerCatalog.filter { $0.availability == .enabled }) { provider in
                    Button(provider.displayName) { Task { await model.beginLogin(providerID: provider.id) } }
                }
                Divider()
                Button("Import from Folder…") { chooseImportFolder() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Add account")
            .accessibilityLabel("Add account")
            .accessibilityIdentifier("switch.add")
            .disabled(model.isWorking)
            railButton("info.circle", label: "About Switch") { showingAbout = true }
                .accessibilityIdentifier("switch.about")
        }
        .frame(width: 48)
        .background(palette.rail)
        .overlay(alignment: .trailing) { palette.railLine.frame(width: 1) }
    }

    private func railButton(_ symbol: String, label: String, selected: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 48, height: 48)
                .foregroundStyle(selected ? palette.activeInk : palette.railIdle)
                .background(selected ? palette.active : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("switch.page.\(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var header: some View {
        ZStack {
            SwitchTitleDragRegion()
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(page.rawValue)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.35)
                    .allowsHitTesting(false)
                Text(page.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                Spacer(minLength: 12)
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(model.isWorking)
                .help("Refresh accounts")
                .accessibilityLabel("Refresh accounts")
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 48)
        .background(palette.canvas)
        .overlay(alignment: .bottom) { palette.railLine.frame(height: 1) }
    }

    private var accountsPage: some View {
        HStack(spacing: 8) {
            accountList.frame(width: 200)
            accountContent.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var accountList: some View {
        SwitchPanel(title: "Accounts", palette: palette) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.accounts) { account in accountRow(account) }
                        if model.snapshot == nil {
                            ProgressView("Loading accounts…")
                                .controlSize(.small)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if model.accounts.isEmpty {
                            Text("No accounts yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.muted)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        discoveredSources
                    }
                }
                .thinScrollIndicators()
                addAccountMenu
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.panel2)
                    .disabled(model.isWorking)
            }
        }
    }

    private func accountRow(_ account: AccountRecord) -> some View {
        let selected = model.selectedAccountID == account.id
        return Button {
            model.selectedAccountID = account.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if model.snapshot?.status.isDefault(account) == true {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .help("Default account")
                    }
                }
                Text(account.identity.providerID.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? palette.activeInk.opacity(0.75) : palette.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(selected ? palette.activeInk : palette.ink)
            .background(selected ? palette.active :
                        (hoveredAccountID == account.id ? palette.listHover : Color.clear))
            .overlay(alignment: .bottom) { palette.lineSoft.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hoveredAccountID = $0 ? account.id : nil }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(model.snapshot?.status.isDefault(account) == true ? "Default account" : "")
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
                VStack(spacing: 8) {
                    SwitchPanel(title: "Identity", palette: palette, highlighted: true,
                                badge: model.snapshot?.status.isDefault(account) == true ? "Default" : nil) {
                        accountDetails(account)
                    }
                    if account.identity.providerID == .codex {
                        SwitchPanel(title: "Usage", palette: palette) { accountUsage(account) }
                    }
                    SwitchPanel(title: "Account details", palette: palette) { accountMetadata(account) }
                }
                .frame(maxWidth: .infinity)
            }
            .thinScrollIndicators()
        } else {
            SwitchPanel(title: "Account", palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add your first account")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Sign in to Codex or Grok Build, or import an existing account folder.")
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: 520, alignment: .leading)
                    HStack(spacing: 6) {
                        addAccountMenu.disabled(model.isWorking)
                        SwitchActionButton(title: "Advanced Import…", symbol: "folder",
                                           palette: palette) { chooseImportFolder() }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            Label("Add account", systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 40)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(account.identity.workspaceID ?? "Personal workspace")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                    .textSelection(.enabled)
            }
            if account.verification.state == .imported
                || account.verification.state == .needsSignIn
                || account.verification.state == .unsupported {
                Text(verificationTitle(account.verification.state))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                    .help(account.verification.detail)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { accountActions(account) }
                VStack(alignment: .leading, spacing: 4) { accountActions(account) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func accountActions(_ account: AccountRecord) -> some View {
        let isDefault = model.snapshot?.status.isDefault(account) == true
        SwitchActionButton(title: isDefault ? "Using as default" : "Use",
                           symbol: isDefault ? "checkmark.seal" : "checkmark",
                           palette: palette, prominent: true, disabled: model.isWorking) {
            Task { await model.makeDefault(account.id) }
        }
        if account.identity.providerID == .codex {
            SwitchActionButton(title: "Show in Menubar",
                               symbol: showsTrayUsage(account.id) ? "checkmark.seal" : "checkmark",
                               palette: palette, disabled: model.isWorking) {
                let value = !showsTrayUsage(account.id)
                trayUsageOverrides[account.id] = value
                SwitchTrayUsagePreferences.setOverride(value, for: account.id)
            }
            .accessibilityValue(showsTrayUsage(account.id) ? "On" : "Off")
            .contextMenu {
                Button("Use Menubar Default") {
                    trayUsageOverrides.removeValue(forKey: account.id)
                    SwitchTrayUsagePreferences.useDefault(for: account.id)
                }
                .disabled(SwitchTrayUsagePreferences.explicitValue(for: account.id) == nil)
            }
        }
        SwitchActionButton(title: isDefault ? "Open \(providerName(account))" : "Use & Open \(providerName(account))",
                           symbol: "play", palette: palette, disabled: model.isWorking) {
            Task { await model.openAccount(account.id) }
        }
        SwitchActionButton(title: "Verify access", symbol: "magnifyingglass",
                           palette: palette, iconOnly: true, disabled: model.isWorking) {
            Task { await model.verify(account.id) }
        }
        SwitchActionButton(title: copiedAuthPath ? "Copied auth path" : "Copy auth path",
                           symbol: copiedAuthPath ? "checkmark" : "doc.on.doc",
                           palette: palette, iconOnly: true) { copyAuthPath(account) }
        SwitchActionButton(title: "Remove account", symbol: "trash", palette: palette,
                           iconOnly: true, danger: true,
                           disabled: model.isWorking ||
                             (isDefault && deletionReplacements(for: account).isEmpty)) {
            showingDelete = true
        }
    }

    private func showsTrayUsage(_ id: UUID) -> Bool {
        trayUsageOverrides[id] ?? SwitchTrayUsagePreferences.explicitValue(for: id)
            ?? defaultShowTrayUsage
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(model.usage[account.id]?.account?.plan?.capitalized ?? "Usage")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                if let fetchedAt = model.usage[account.id]?.fetchedAt {
                    Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.muted)
                }
                SwitchActionButton(title: model.usageLoading.contains(account.id) ? "Refreshing usage" : "Refresh usage",
                                   symbol: "arrow.clockwise", palette: palette,
                                   iconOnly: model.usage[account.id] != nil,
                                   disabled: model.usageLoading.contains(account.id)
                                     || account.verification.state == .needsSignIn) {
                    Task { await model.loadUsage(account.id) }
                }
            }
            if account.verification.state == .needsSignIn {
                Text("Sign in again to view usage for this account.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
            } else if let snapshot = model.usage[account.id] {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)], spacing: 12) {
                    if let allowed = snapshot.rateLimits?.ordinaryUsageAllowed {
                        usageFact("Ordinary usage", value: allowed ? "Available" : "Restricted")
                    }
                    usageFact("Authentication", value: snapshot.account == nil ? "Verified locally" : "Signed in")
                    if let summary = snapshot.usage {
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
                let buckets = usageBuckets(snapshot)
                if buckets.isEmpty {
                    Text("Rate limits unavailable")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                ForEach(buckets.indices, id: \.self) { index in
                    let bucket = buckets[index]
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Text(bucket.name ?? bucket.model ?? bucket.id ?? "Rate limits")
                                .font(.system(size: 12, weight: .semibold))
                            if let model = bucket.model {
                                Text(model).font(.system(size: 10)).foregroundStyle(palette.muted)
                            }
                            Spacer()
                            if let plan = bucket.plan {
                                Text(plan).font(.system(size: 10)).foregroundStyle(palette.muted)
                            }
                        }
                        HStack(alignment: .top, spacing: 20) {
                            if let primary = bucket.primary, primary.usedPercent != nil {
                                usageRow(windowTitle(primary, fallback: "Current window"), window: primary)
                                    .frame(maxWidth: .infinity)
                            }
                            if let secondary = bucket.secondary, secondary.usedPercent != nil {
                                usageRow(windowTitle(secondary, fallback: "Secondary window"), window: secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        HStack(spacing: 16) {
                            if let credits = bucket.credits {
                                usageFact("Credits", value: credits.unlimited == true ? "Unlimited" :
                                          credits.balance ?? (credits.hasCredits == true ? "Available" : "None"))
                            }
                            if let reached = bucket.spendControlReached {
                                usageFact("Spend control", value: reached ? "Reached" : "Not reached")
                            }
                            Spacer()
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(index.isMultiple(of: 2) ? palette.panel2 : palette.listHover.opacity(0.55))
                }
                if !snapshot.dailyUsage.isEmpty {
                    SwitchActivityGrid(rows: snapshot.dailyUsage, palette: palette)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach([CodexTokenPeriod.today, .weekly, .monthly, .yearly], id: \.rawValue) { period in
                            usageFact(period.label,
                                      value: period.tokens(in: snapshot.dailyUsage, endingAt: .now)
                                        .formatted(.number.notation(.compactName)))
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    if model.usageLoading.contains(account.id) { ProgressView().controlSize(.small) }
                    Text(model.usageLoading.contains(account.id) ? "Checking account usage…" :
                         (model.usageErrors[account.id] == nil ? "Usage has not been checked" : "Usage could not be refreshed"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                if let failure = model.usageErrors[account.id] {
                    Text(failure).font(.system(size: 10)).foregroundStyle(palette.amber)
                } else if !model.usageLoading.contains(account.id) {
                    Text("Refresh this saved account without changing the default account.")
                        .font(.system(size: 10)).foregroundStyle(palette.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageRow(_ title: String, window: CodexRateLimitWindowSnapshot) -> some View {
        let percentage = window.usedPercent.map {
            SwitchTrayUsagePreferences.percentageLabel(used: $0, showUsed: showUsageAsUsed)
        } ?? "—"
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(percentage)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .contentTransition(.numericText())
            }
            if let percent = window.usedPercent {
                ProgressView(value: Double(min(max(percent, 0), 100)), total: 100)
                    .tint(palette.titleArt)
                    .accessibilityLabel("\(title), \(percentage)")
            }
            if let reset = window.resetsAt {
                Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
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
        VStack(spacing: 0) {
            metadataRow("Saved auth", value: account.credentialFile.path)
            metadataRow("Source", value: account.source.path, striped: true)
            metadataRow("Home", value: account.home.path)
            if let workspace = account.identity.workspaceID {
                metadataRow("Workspace", value: workspace, striped: true)
            }
            metadataRow("Imported", value: account.importedAt.formatted(date: .abbreviated, time: .shortened),
                        striped: account.identity.workspaceID == nil)
            metadataRow("Last used", value: account.lastUsedAt?.formatted(date: .abbreviated, time: .shortened)
                        ?? "Not launched yet", striped: account.identity.workspaceID != nil)
        }
    }

    private func metadataRow(_ label: String, value: String, striped: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 38)
        .background(striped ? palette.panel2.opacity(0.55) : Color.clear)
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

    private var backupPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                SwitchPanel(title: "Pending operations", palette: palette) {
                    VStack(spacing: 0) {
                        if model.pendingRecovery.isEmpty {
                            Text("No interrupted backup work needs attention.")
                                .foregroundStyle(palette.muted)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(model.pendingRecovery) { operation in
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(palette.amber)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(operation.kind.capitalized).fontWeight(.semibold)
                                        Text(operation.destination.path)
                                            .font(.system(size: 10))
                                            .foregroundStyle(palette.muted)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 0)
                                    Text(operation.phase.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                    if operation.phase == .conflicted {
                                        SwitchActionButton(title: "Resolve…", palette: palette) {
                                            conflictToResolve = operation
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .overlay(alignment: .bottom) { palette.lineSoft.frame(height: 1) }
                            }
                        }
                    }
                }
                if !model.linkedSettingsIssues.isEmpty {
                    SwitchPanel(title: "Linked settings", palette: palette) {
                        VStack(spacing: 0) {
                        ForEach(model.linkedSettingsIssues) { issue in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.relativePath).fontWeight(.medium)
                                    Text(issue.localPath.path)
                                        .foregroundStyle(palette.muted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                SwitchActionButton(title: "Review repair…", palette: palette) {
                                    linkedIssueToRepair = issue
                                }
                            }
                            .padding(16)
                            .overlay(alignment: .bottom) { palette.lineSoft.frame(height: 1) }
                        }
                        }
                    }
                }
                SwitchPanel(title: "Backup policy", palette: palette) {
                    VStack(spacing: 0) {
                        metadataRow("Before import", value: "Review destination and conflicts")
                        metadataRow("During import", value: "Back up, stage, verify, then publish", striped: true)
                        metadataRow("On failure", value: "Keep prior credentials and the backup journal")
                    }
                }
                HStack {
                    Text("Backups never delete source data.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                    Spacer()
                    SwitchActionButton(title: "Finish pending work", symbol: "archivebox",
                                       palette: palette, prominent: true,
                                       disabled: model.pendingRecovery.allSatisfy { $0.phase == .conflicted } || model.isWorking) {
                        Task { await model.recover() }
                    }
                }
                .padding(12)
                .background(palette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
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

    private var settingsPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                SwitchPanel(title: "App behavior", palette: palette) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Switch window")
                            Spacer()
                            Picker("Appearance", selection: $appearanceMode) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 230)
                        }
                        .padding(16)
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Show percentage used")
                                Text("Turn off to show the percentage left in usage views.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.muted)
                            }
                            Spacer()
                            Toggle("Show percentage used", isOn: $showUsageAsUsed)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        .padding(16)
                        .background(palette.panel2.opacity(0.55))
                    }
                }
                SwitchPanel(title: "Menubar defaults", palette: palette) {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Show account usage")
                                Text("Accounts without their own choice show usage in Menubar.")
                                    .font(.system(size: 10)).foregroundStyle(palette.muted)
                            }
                            Spacer()
                            Toggle("Show account usage", isOn: $defaultShowTrayUsage)
                                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                        .padding(16)
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Token summary")
                                Text("Choose the period shown beside each account's usage.")
                                    .font(.system(size: 10)).foregroundStyle(palette.muted)
                            }
                            Spacer()
                            Picker("Token summary", selection: $trayTokenPeriod) {
                                ForEach(SwitchTrayTokenPeriod.allCases) { period in
                                    Text(period.label).tag(period.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190)
                        }
                        .padding(16)
                        .background(palette.panel2.opacity(0.55))
                    }
                }
                SwitchPanel(title: "Data locations", palette: palette) {
                    VStack(spacing: 0) {
                        dataLocationRow("Codex home", detail: "Settings, plugins, and conversations stay here when accounts change.",
                                        url: model.paths.defaultHome)
                        dataLocationRow("Codex account vault", detail: "Private Codex auth.json snapshots.",
                                        url: model.paths.credentialStore, striped: true)
                        dataLocationRow("Grok Build home", detail: "Grok configuration, rules, and active login.",
                                        url: model.paths.grokHome)
                        dataLocationRow("Grok Build account vault", detail: "Private Grok subscription OAuth snapshots.",
                                        url: model.paths.grokCredentialStore, striped: true)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .thinScrollIndicators()
    }

    private func dataLocationRow(_ title: String, detail: String, url: URL,
                                 striped: Bool = false) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(palette.muted)
                Text(url.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(url.path)
            }
            Spacer(minLength: 20)
            SwitchActionButton(title: "Reveal", symbol: "folder", palette: palette) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 68)
        .background(striped ? palette.panel2.opacity(0.55) : Color.clear)
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

private final class SwitchTitleDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 { window?.performDrag(with: event) }
    }
}

private struct SwitchTitleDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SwitchTitleDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct SwitchPalette {
    let dark: Bool

    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        let value = self.dark ? dark : light
        return Color(.sRGB, red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255, opacity: 1)
    }

    var canvas: Color { color(0xECEBE7, 0x18191B) }
    var rail: Color { color(0xF4F3EF, 0x141517) }
    var panel: Color { color(0xFAF9F6, 0x202124) }
    var panel2: Color { color(0xF0EFEB, 0x27282B) }
    var control: Color { color(0xD1CEC4, 0x3B3E44) }
    var listHover: Color { color(0xE5E4DF, 0x303238) }
    var railLine: Color { color(0xDAD9D5, 0x292B2F) }
    var lineSoft: Color { color(0xE2E1DC, 0x35373C) }
    var ink: Color { color(0x1A1B1D, 0xF2F2F3) }
    var muted: Color { color(0x666970, 0xB9BBC0) }
    var railIdle: Color { color(0x5D6670, 0xB0B7C2) }
    var active: Color { color(0x3C4A61, 0x445878) }
    var activeInk: Color { color(0xF2F1ED, 0xF2F1ED) }
    var green: Color { color(0x557D68, 0x8EB9A2) }
    var amber: Color { color(0x856F43, 0xD0B47A) }
    var red: Color { color(0x8D5A60, 0xD9959C) }
    var titleArt: Color { color(0x657B98, 0x7F95B5) }
}

private struct SwitchPanel<Content: View>: View {
    let title: String
    let palette: SwitchPalette
    var highlighted = false
    var badge: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(highlighted ? palette.ink : palette.muted)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(palette.green.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background {
                ZStack(alignment: .trailing) {
                    LinearGradient(colors: [palette.green.opacity(0.16), .clear,
                                            palette.titleArt.opacity(0.24)],
                                   startPoint: .leading, endPoint: .trailing)
                    Canvas { context, size in
                        let anchor = size.width - 13
                        for radius in stride(from: CGFloat(24), through: 60, by: 9) {
                            context.stroke(Path(ellipseIn: CGRect(x: anchor - radius, y: 47 - radius,
                                                                  width: radius * 2, height: radius * 2)),
                                           with: .color(palette.titleArt.opacity(0.24)), lineWidth: 0.65)
                        }
                    }
                }
                .opacity(highlighted ? 0.70 : 0.28)
                .allowsHitTesting(false)
            }
            .background(palette.panel2)
            content
        }
        .background(palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct SwitchActionButton: View {
    let title: String
    var symbol: String? = nil
    let palette: SwitchPalette
    var prominent = false
    var iconOnly = false
    var danger = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11)) }
                if !iconOnly { Text(title).lineLimit(1) }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(prominent ? palette.canvas : (danger ? palette.red : palette.ink))
            .padding(.horizontal, iconOnly ? 8 : 10)
            .frame(height: 28)
            .background(iconOnly ? Color.clear : (prominent ? palette.ink : palette.control))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct SwitchActivityGrid: View {
    let rows: [CodexDailyUsageSnapshot]
    let palette: SwitchPalette
    @State private var selectedDate: Date?
    @State private var period: CodexTokenPeriod = .yearly

    private struct Day {
        let date: Date
        let tokens: Int64
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var weeks: [[Day?]] {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: 1 - period.dayCount, to: today) ?? today
        let start = calendar.date(byAdding: .day,
                                  value: 1 - calendar.component(.weekday, from: first),
                                  to: first) ?? first
        var tokens: [String: Int64] = [:]
        for row in rows {
            guard let date = row.startDate, let count = row.tokens else { continue }
            let key = String(date.prefix(10))
            let (sum, overflow) = tokens[key, default: 0].addingReportingOverflow(max(0, count))
            tokens[key] = overflow ? Int64.max : sum
        }
        let count = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        return stride(from: 0, to: count, by: 7).map { week in
            (0..<7).map { weekday in
                guard let date = calendar.date(byAdding: .day, value: week + weekday, to: start),
                      date <= today, date >= first else { return nil }
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                let key = String(format: "%04d-%02d-%02d", parts.year ?? 0,
                                 parts.month ?? 0, parts.day ?? 0)
                return Day(date: date, tokens: tokens[key, default: 0])
            }
        }
    }

    var body: some View {
        let weeks = weeks
        let maximum = max(1, weeks.flatMap { $0 }.compactMap { $0?.tokens }.max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily activity").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("Activity period", selection: $period) {
                    Text("7 days").tag(CodexTokenPeriod.weekly)
                    Text("1 month").tag(CodexTokenPeriod.monthly)
                    Text("1 year").tag(CodexTokenPeriod.yearly)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.top, 8)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 3) {
                    VStack(spacing: 3) {
                        ForEach(0..<7) { day in
                            Text(day == 1 ? "M" : day == 3 ? "W" : day == 5 ? "F" : "")
                                .font(.system(size: 7))
                                .foregroundStyle(palette.muted)
                                .frame(width: 12, height: 9)
                        }
                    }
                    ForEach(weeks.indices, id: \.self) { column in
                        VStack(spacing: 3) {
                            ForEach(0..<7) { row in
                                if let day = weeks[column][row] {
                                    Button { selectedDate = day.date } label: {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(day.tokens == 0 ? palette.control.opacity(0.58) :
                                                  palette.green.opacity(0.24 + 0.70 *
                                                    sqrt(Double(day.tokens) / Double(maximum))))
                                            .frame(width: 9, height: 9)
                                    }
                                    .buttonStyle(.plain)
                                    .focusEffectDisabled()
                                    .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.tokens.formatted()) tokens")
                                    .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                                    .accessibilityValue("\(day.tokens.formatted()) tokens")
                                } else {
                                    Color.clear.frame(width: 9, height: 9).accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
            }
            .thinScrollIndicators()
            if let selectedDate,
               let day = weeks.flatMap({ $0 }).compactMap({ $0 }).first(where: { $0.date == selectedDate }) {
                Text("\(selectedDate.formatted(date: .abbreviated, time: .omitted)): \(day.tokens.formatted()) tokens")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.muted)
            }
        }
        .onChange(of: period) { selectedDate = nil }
    }
}
