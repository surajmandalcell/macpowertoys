import SwiftUI
import OnePlusUI

struct MainModifiedView: View {
    let changed: () -> Void
    @State private var differences: [SettingsRegistry.Difference] = []
    @State private var confirmResetAll = false
    @State private var resetRequest: String?
    @State private var visible = false
    @State private var groupLayout: [[String]] = []
    @State private var groupedDifferences: [String: [SettingsRegistry.Difference]] = [:]
    @State private var groupTitles: [String: String] = [:]

    var body: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Modified", subtitle: "Review your changes. Restore only what you need.") {
                Button("Reset all") { confirmResetAll = true }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                    .disabled(differences.isEmpty || resetRequest != nil)
            }
        } content: {
            if differences.isEmpty {
                OnePlusEmptyState("No modified settings", systemImage: "checkmark.circle",
                                  caption: "Your settings match their defaults.")
            } else {
                ForEach(groupLayout, id: \.first) { ids in
                    HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                        ForEach(ids, id: \.self) { id in
                            group(id, compact: ids.count == 2).frame(maxWidth: .infinity)
                        }
                    }
                }
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

    static func groupRows(_ groups: [(id: String, count: Int)]) -> [[String]] {
        var rows: [[String]] = []
        var index = 0
        while index < groups.count {
            if groups[index].count <= 3, index + 1 < groups.count, groups[index + 1].count <= 3 {
                rows.append([groups[index].id, groups[index + 1].id])
                index += 2
            } else {
                rows.append([groups[index].id])
                index += 1
            }
        }
        return rows
    }

    private func group(_ toolID: String, compact: Bool) -> some View {
        OnePlusCard {
            OnePlusCardHeader(groupTitles[toolID] ?? toolID)
            if !compact {
                HStack(spacing: OnePlusMetrics.cardGap) {
                    Text("Setting").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Current").frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
                    Text("Default").frame(width: OnePlusMetrics.wideControlColumn, alignment: .leading)
                    Color.clear.frame(width: OnePlusCatalogMetrics.openWidth)
                }.onePlusTableHeader()
            }
            LazyVStack(spacing: 0) {
                ForEach(groupedDifferences[toolID] ?? []) { difference in row(difference, compact: compact) }
            }
        }
    }

    private func row(_ difference: SettingsRegistry.Difference, compact: Bool) -> some View {
        HStack(spacing: OnePlusMetrics.cardGap) {
            VStack(alignment: .leading, spacing: OnePlusCatalogMetrics.titleGap) {
                Text(difference.label).onePlusText(.row).lineLimit(1).help(difference.label)
                if compact {
                    Text("Current: \(difference.currentDisplay) · Default: \(difference.defaultDisplay)")
                        .onePlusText(.caption).lineLimit(1).textSelection(.enabled)
                        .help("Current: \(difference.currentDisplay)\nDefault: \(difference.defaultDisplay)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                value(difference.currentDisplay)
                value(difference.defaultDisplay)
            }
            Button("Reset") { resetRequest = difference.id }
                .buttonStyle(OnePlusButtonStyle(.neutral, minWidth: OnePlusCatalogMetrics.openWidth))
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
        let updated = SettingsRegistry.modified()
        let grouped = Dictionary(grouping: updated) { $0.toolID ?? "app" }
        let tools = ToolRegistry.allTools
        let order = ["app"] + tools.map(\.id)
        let present = Set(grouped.keys)
        let groupIDs = order.filter { present.contains($0) } + present.subtracting(order).sorted()

        differences = updated
        groupedDifferences = grouped
        groupLayout = Self.groupRows(groupIDs.map { ($0, grouped[$0]?.count ?? 0) })
        groupTitles = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0.name) })
        groupTitles["app"] = "App settings"
        changed()
    }
}
