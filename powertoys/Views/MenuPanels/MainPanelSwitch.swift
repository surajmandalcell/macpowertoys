import AIManagerCore
import OnePlusUI
import SwiftUI

struct SwitchTrayView: View {
    @State private var model: SwitchWorkspaceModel
    @Environment(\.onePlusIsVisible) private var isVisible
    @AppStorage("switchUsageShowsUsed") private var showUsageAsUsed = true
    @AppStorage(SwitchTrayUsagePreferences.defaultKey) private var defaultShowUsage = true
    @AppStorage(SwitchTrayUsagePreferences.periodKey) private var tokenPeriod = SwitchTrayTokenPeriod.sinceReset.rawValue

    init() {
        _model = State(initialValue: SwitchWorkspaceModel())
    }

    init(model: SwitchWorkspaceModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            header
            if model.snapshot == nil && model.isWorking {
                ProgressView("Loading accounts…").controlSize(.small)
            } else if model.accounts.isEmpty {
                Text("No saved accounts").onePlusText(.caption)
            } else {
                VStack(spacing: OnePlusMenuMetrics.tileGap) {
                    ForEach(model.accounts) { account in accountRow(account) }
                }
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            if model.snapshot == nil { await model.load() }
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
        OnePlusMenuControlRow("CLI accounts", systemImage: TrayTab.switchAccounts.symbol) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                if model.accounts.contains(where: { account in
                    account.identity.providerID == .codex
                        && (SwitchTrayUsagePreferences.explicitValue(for: account.id) ?? defaultShowUsage)
                        && !Self.hasUsageLimits(model.usage[account.id])
                }) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .onePlusText(.caption, color: OnePlusColor.warn)
                        .accessibilityLabel("Usage limits are not loaded")
                        .help("Usage limits are not loaded for some accounts. Refresh accounts and usage to load them.")
                }
                Button {
                    Task {
                        await model.refresh()
                        guard !Task.isCancelled else { return }
                        await model.refreshUsage()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                .disabled(model.isWorking || !model.usageLoading.isEmpty)
                .accessibilityLabel("Refresh accounts and usage")
                .accessibilityIdentifier("switch.tray.refresh")
                .help("Refresh accounts and usage")
            }
        }
    }

    nonisolated static func hasUsageLimits(_ snapshot: CodexAccountUsageSnapshot?) -> Bool {
        let bucket = snapshot?.rateLimits?.defaultBucket
        return bucket?.primary?.usedPercent != nil || bucket?.secondary?.usedPercent != nil
    }

    private func accountRow(_ account: AccountRecord) -> some View {
        let isDefault = model.snapshot?.status.isDefault(account) == true
        let showsUsage = SwitchTrayUsagePreferences.explicitValue(for: account.id) ?? defaultShowUsage
        return Button {
            guard !isDefault else { return }
            Task { await model.makeDefault(account.id) }
        } label: {
            accountContent(account, isDefault: isDefault, showsUsage: showsUsage)
                .padding(OnePlusMenuMetrics.bodyInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.menuTileRadius))
        .disabled(model.isWorking)
        .accessibilityIdentifier("switch.tray.account.\(account.id)")
        .accessibilityValue(isDefault ? "Default" : "Make default")
    }

    private func accountContent(_ account: AccountRecord, isDefault: Bool, showsUsage: Bool) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                SwitchProviderIcon(providerID: account.identity.providerID, size: OnePlusMetrics.compactControlHeight)
                VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                    Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                        .onePlusText(.row).lineLimit(1)
                    Text(account.identity.providerID.displayName).onePlusText(.caption)
                }
                Spacer(minLength: OnePlusMetrics.actionSpacing)
                if isDefault {
                    Label("Default", systemImage: "checkmark.circle.fill")
                        .onePlusText(.caption, color: OnePlusColor.ink)
                }
                if showsUsage, let snapshot = model.usage[account.id],
                   let period = SwitchTrayTokenPeriod(rawValue: tokenPeriod) {
                    Text("\(period.tokens(in: snapshot).formatted(.number.notation(.compactName))) tokens")
                        .onePlusText(.caption).help(period.label)
                }
            }
            if showsUsage, let snapshot = model.usage[account.id] {
                if let primary = snapshot.rateLimits?.defaultBucket?.primary?.usedPercent {
                    usageBar(primary, title: "Current window")
                }
                if let secondary = snapshot.rateLimits?.defaultBucket?.secondary?.usedPercent {
                    usageBar(secondary, title: "Secondary window")
                }
            }
            if let error = model.usageErrors[account.id] {
                Text(error).onePlusText(.caption, color: OnePlusColor.danger).lineLimit(2).help(error)
            }
        }
    }

    private func usageBar(_ percent: Int, title: String) -> some View {
        let fraction = Double(min(max(percent, 0), 100)) / 100
        let label = SwitchTrayUsagePreferences.percentageLabel(used: percent, showUsed: showUsageAsUsed)
        return VStack(spacing: OnePlusMetrics.navRowGap) {
            HStack { Text(title); Spacer(); Text(label).monospacedDigit() }.onePlusText(.caption)
            OnePlusUsageBar(value: showUsageAsUsed ? fraction : 1 - fraction, color: OnePlusColor.accent)
                .accessibilityLabel("\(title), \(label)")
        }
    }
}
