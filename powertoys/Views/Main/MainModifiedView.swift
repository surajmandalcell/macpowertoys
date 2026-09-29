import SwiftUI
import OnePlusUI

struct MainModifiedView: View {
    let changed: () -> Void
    @State private var differences: [SettingsRegistry.Difference] = []
    @State private var confirmResetAll = false
    @State private var resetRequest: String?
    @State private var visible = false

    var body: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Modified", subtitle: "Review your changes. Restore only what you need.") {
                Button("Reset all") { confirmResetAll = true }
                    .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
                    .disabled(differences.isEmpty || resetRequest != nil)
            }
        } content: {
            if differences.isEmpty {
                OnePlusEmptyState("No modified settings", systemImage: "checkmark.circle",
                                  caption: "Your settings match their defaults.")
            } else {
                ForEach(groupIDs, id: \.self) { id in group(id) }
            }
        }
        .background {
            if visible {
                Color.clear.onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in refresh() }
            }
        }
        .onAppear { visible = true; refresh() }
        .onDisappear { visible = false }
        .task(id: resetRequest) {
            guard let resetRequest else { return }
            if resetRequest == "all" { await SettingsRegistry.resetAll() }
            else if let difference = differences.first(where: { $0.id == resetRequest }) {
                await SettingsRegistry.reset(difference)
            }
            self.resetRequest = nil
            refresh()
        }
        .confirmationDialog("Reset all modified settings?", isPresented: $confirmResetAll, titleVisibility: .visible) {
            Button("Reset all", role: .destructive) { resetRequest = "all" }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore the listed preferences to their defaults. This also enables disabled tools.")
        }
        .accessibilityIdentifier("main.modified")
    }

    private var groupIDs: [String] {
        let order = ["app"] + ToolRegistry.allTools.map(\.id)
        let present = Set(differences.map { $0.toolID ?? "app" })
        return order.filter { present.contains($0) } + present.subtracting(order).sorted()
    }

    private func group(_ toolID: String) -> some View {
        OnePlusCard {
            OnePlusCardHeader(toolID == "app" ? "App settings" : ToolRegistry.tool(for: toolID)?.name ?? toolID)
            HStack(spacing: OnePlusMetrics.cardGap) {
                Text("Setting").frame(maxWidth: .infinity, alignment: .leading)
                Text("Current").frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
                Text("Default").frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
                Color.clear.frame(width: OnePlusCatalogMetrics.openWidth)
            }.onePlusTableHeader()
            LazyVStack(spacing: 0) {
                ForEach(differences.filter { ($0.toolID ?? "app") == toolID }) { difference in row(difference) }
            }
        }
    }

    private func row(_ difference: SettingsRegistry.Difference) -> some View {
        HStack(spacing: OnePlusMetrics.cardGap) {
            Text(difference.label).onePlusText(.row).lineLimit(1).help(difference.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            value(difference.currentDisplay)
            value(difference.defaultDisplay)
            Button("Reset") { resetRequest = difference.id }
                .buttonStyle(OnePlusButtonStyle(.neutral, size: .small, minWidth: OnePlusCatalogMetrics.openWidth))
                .disabled(resetRequest != nil)
                .help("Reset \(difference.label)")
                .accessibilityLabel("Reset \(difference.label)")
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(height: OnePlusMetrics.settingRow)
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
        .contextMenu {
            Button("Reset \(difference.label)") { resetRequest = difference.id }.disabled(resetRequest != nil)
        }
    }

    private func value(_ text: String) -> some View {
        Text(text).onePlusText(.mono).lineLimit(1).help(text).textSelection(.enabled)
            .frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
    }

    private func refresh() {
        differences = SettingsRegistry.modified()
        changed()
    }
}
