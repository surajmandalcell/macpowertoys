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
                            group(id).frame(maxWidth: .infinity)
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
            let group = groups[index]
            if group.count <= 3, index + 1 < groups.count,
               groups[index + 1].count == group.count {
                rows.append([group.id, groups[index + 1].id])
                index += 2
            } else {
                rows.append([group.id])
                index += 1
            }
        }
        return rows
    }

    private func group(_ toolID: String) -> some View {
        let lastID = groupedDifferences[toolID]?.last?.id
        return VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            OnePlusSectionTitle(groupTitles[toolID] ?? toolID)
            LazyVStack(spacing: 0) {
                ForEach(groupedDifferences[toolID] ?? []) { difference in
                    row(difference, separator: difference.id != lastID)
                }
            }
        }
        .environment(\.onePlusCardPadding, 0)
    }

    private func row(_ difference: SettingsRegistry.Difference, separator: Bool) -> some View {
        OnePlusSettingRow(
            difference.label,
            controlWidth: OnePlusCatalogMetrics.placementWidth,
            separator: separator
        ) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Text("\(difference.currentDisplay) → \(difference.defaultDisplay)")
                    .onePlusText(.caption).lineLimit(1).truncationMode(.middle)
                    .help("Current: \(difference.currentDisplay) · Default: \(difference.defaultDisplay)")
                    .accessibilityLabel("Current: \(difference.currentDisplay) · Default: \(difference.defaultDisplay)")
                Button("Reset") { resetRequest = difference.id }
                    .buttonStyle(OnePlusButtonStyle(.neutral, minWidth: OnePlusCatalogMetrics.openWidth))
                    .disabled(resetRequest != nil)
                    .help("Reset \(difference.label)")
                    .accessibilityLabel("Reset \(difference.label)")
            }
        }
        .accessibilityValue("Current: \(difference.currentDisplay) · Default: \(difference.defaultDisplay)")
        .onePlusRowHover()
        .contextMenu {
            Button("Reset \(difference.label)") { resetRequest = difference.id }.disabled(resetRequest != nil)
        }
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
