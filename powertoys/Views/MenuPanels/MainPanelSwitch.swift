import AIManagerCore
import OnePlusUI
import SwiftUI

struct SwitchTrayView: View {
    @State private var model: SwitchWorkspaceModel
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
            TrayToolHeader(tab: .switchAccounts)
            OnePlusMenuSectionHeader("CLI accounts", actionTitle: "Refresh", compactAction: true) {
                Task { await model.refresh() }
            }
            .disabled(model.isWorking)
            if model.snapshot == nil && model.isWorking {
                OnePlusMenuCard { ProgressView("Loading accounts…").controlSize(.small) }
            } else if model.accounts.isEmpty {
                OnePlusMenuCard { Text("No saved accounts").onePlusText(.caption) }
            } else {
                VStack(spacing: OnePlusMenuMetrics.tileGap) {
                    ForEach(model.accounts) { account in accountCard(account) }
                }
                if model.accounts.contains(where: { $0.identity.providerID == .codex }) {
                    Button("Refresh Usage") {
                        Task {
                            for account in model.accounts where account.identity.providerID == .codex {
                                guard !Task.isCancelled else { return }
                                await model.loadUsage(account.id)
                            }
                        }
                    }
                    .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    .disabled(model.isWorking || !model.usageLoading.isEmpty)
                }
            }
        }
        .task { if model.snapshot == nil { await model.load() } }
        .alert("Switch needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func accountCard(_ account: AccountRecord) -> some View {
        let isDefault = model.snapshot?.status.isDefault(account) == true
        let showsUsage = SwitchTrayUsagePreferences.explicitValue(for: account.id) ?? defaultShowUsage
        return Button {
            guard !isDefault else { return }
            Task { await model.makeDefault(account.id) }
        } label: {
            OnePlusMenuCard {
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
                    }
                    if showsUsage, let snapshot = model.usage[account.id] {
                        if let primary = snapshot.rateLimits?.defaultBucket?.primary?.usedPercent {
                            usageBar(primary, title: "Current window")
                        }
                        if let secondary = snapshot.rateLimits?.defaultBucket?.secondary?.usedPercent {
                            usageBar(secondary, title: "Secondary window")
                        }
                        if let period = SwitchTrayTokenPeriod(rawValue: tokenPeriod) {
                            Text("\(period.tokens(in: snapshot).formatted(.number.notation(.compactName))) tokens")
                                .onePlusText(.caption).help(period.label)
                        }
                    } else if showsUsage, account.identity.providerID == .codex {
                        Text(model.usageLoading.contains(account.id) ? "Loading usage…" : "Refresh Usage to load limits")
                            .onePlusText(.caption)
                    }
                    if let error = model.usageErrors[account.id] {
                        Text(error).onePlusText(.caption, color: OnePlusColor.danger).lineLimit(2).help(error)
                    }
                }
            }
        }
        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.menuTileRadius))
        .disabled(model.isWorking)
        .accessibilityIdentifier("switch.tray.account.\(account.id)")
        .accessibilityValue(isDefault ? "Default" : "Make default")
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
