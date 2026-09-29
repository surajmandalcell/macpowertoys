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
        var remaining = groups
        var rows: [[String]] = []
        while !remaining.isEmpty {
            let group = remaining.removeFirst()
            guard group.count <= 3,
                  let match = remaining.firstIndex(where: { $0.count == group.count && $0.count <= 3 })
            else { rows.append([group.id]); continue }
            rows.append([group.id, remaining.remove(at: match).id])
        }
        return rows
    }

    private func group(_ toolID: String) -> some View {
        let lastID = groupedDifferences[toolID]?.last?.id
        OnePlusCard {
            OnePlusCardHeader(groupTitles[toolID] ?? toolID)
            LazyVStack(spacing: 0) {
                ForEach(groupedDifferences[toolID] ?? []) { difference in
                    row(difference, separator: difference.id != lastID)
                }
            }
        }
    }

    private func row(_ difference: SettingsRegistry.Difference, separator: Bool) -> some View {
        OnePlusSettingRow(
            difference.label,
            caption: "Current: \(difference.currentDisplay) · Default: \(difference.defaultDisplay)",
            separator: separator
        ) {
            Button("Reset") { resetRequest = difference.id }
                .buttonStyle(OnePlusButtonStyle(.neutral, minWidth: OnePlusCatalogMetrics.openWidth))
                .disabled(resetRequest != nil)
                .help("Reset \(difference.label)")
                .accessibilityLabel("Reset \(difference.label)")
        }
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
