import SwiftUI
import OnePlusUI

/// The Settings-style overview: an identity block, a filter, and one grouped section per category.
struct AllToolsGridView: View {
    @Binding var selectedTool: String?
    var query: String
    @Binding var filter: MainCatalogFilter
    @Binding var focusedToolID: String?
    @AppStorage("main.favorites") private var storedFavorites = "[]"
    @State private var settings = SettingsManager.shared
    @FocusState private var focusedRow: String?
    @State private var typedPrefix = ""
    @State private var lastTypedAt = Date.distantPast
    @State private var favoriteIDs: Set<String> = []
    @State private var groups: [MainToolGroup] = []
    @State private(set) var visibleTools: [any Tool] = []
    @State private var toolCount = 0
    @State private var enabledCount = 0
    @State private var favoriteCount = 0

    init(selectedTool: Binding<String?>, query: String = "",
         filter: Binding<MainCatalogFilter> = .constant(.all),
         focusedToolID: Binding<String?> = .constant(nil)) {
        _selectedTool = selectedTool; self.query = query; _filter = filter; _focusedToolID = focusedToolID
        let favorites = MainCatalog.favorites(from: storedFavorites)
        let rows = MainCatalog.preparedRows(ToolRegistry.allTools, query: query, filter: filter.wrappedValue,
                                            favorites: favorites, disabled: SettingsManager.shared.disabledToolIDs)
        _favoriteIDs = State(initialValue: favorites)
        _groups = State(initialValue: rows.groups)
        _visibleTools = State(initialValue: rows.visible)
        _toolCount = State(initialValue: rows.total)
        _enabledCount = State(initialValue: rows.enabled)
        _favoriteCount = State(initialValue: rows.favorites)
    }

    var body: some View {
        MainPaneScroll {
            MainHero(title: "MacPowerToys", subtitle: "Your Mac, a little more capable.") {
                MainAppIconTile(size: MainPaneMetrics.heroIcon)
            } controls: {
                OnePlusSegmented(choices: [(MainCatalogFilter.all, "All \(toolCount)"),
                                           (.enabled, "Enabled \(enabledCount)"),
                                           (.favorites, "Favorites \(favoriteCount)")],
                                 selection: $filter, accessibilityLabel: "Show tools",
                                 width: MainPaneMetrics.segmentedWidth)
            }
            if groups.isEmpty { emptyState }
            ForEach(groups) { group in
                MainSection(title: group.category.rawValue) {
                    ForEach(group.tools, id: \.id) { tool in
                        MainToolRow(tool: tool, favorite: favoriteBinding(tool.id), focusedToolID: $focusedToolID,
                                    bodyFocus: $focusedRow, separator: tool.id != group.tools.last?.id,
                                    move: { moveFocus(from: tool.id, direction: $0) }, typeSelect: typeSelect) {
                            selectSettings(tool.id)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("main.all-tools")
        .onChange(of: focusedRow) { _, id in if let id { focusedToolID = id } }
        .onChange(of: query) { _, _ in refreshCatalog() }
        .onChange(of: filter) { _, _ in refreshCatalog() }
        .onChange(of: settings.disabledToolIDs) { _, _ in refreshCatalog() }
        .onChange(of: storedFavorites) { _, value in
            let updated = MainCatalog.favorites(from: value)
            if updated != favoriteIDs { favoriteIDs = updated; refreshCatalog() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)) { _ in refreshCatalog() }
    }

    private var emptyState: some View {
        OnePlusEmptyState(query.isEmpty ? filter == .favorites ? "No favorites yet" : "No enabled tools" : "No matching tools",
                          systemImage: query.isEmpty ? "star" : "magnifyingglass",
                          caption: query.isEmpty
                            ? filter == .favorites ? "Use the star on a tool to add a favorite." : "Enable a tool to show it here."
                            : "Try another name, category, or keyword.")
            .frame(maxWidth: .infinity)
    }

    private func favoriteBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { favoriteIDs.contains(id) }, set: { value in
            var updated = favoriteIDs
            if value { updated.insert(id) } else { updated.remove(id) }
            favoriteIDs = updated
            storedFavorites = MainCatalog.storing(favorites: updated)
            refreshCatalog()
        })
    }

    private func selectSettings(_ toolID: String) {
        MainToolTab.select(.settings, for: toolID)
        selectedTool = toolID
    }

    private func moveFocus(from id: String, direction: MoveCommandDirection) {
        let ids = visibleTools.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let offset: Int
        switch direction {
        case .up, .left: offset = -1
        case .down, .right: offset = 1
        @unknown default: return
        }
        focusedRow = ids[min(max(index + offset, 0), ids.count - 1)]
    }

    private func typeSelect(_ characters: String) {
        let now = Date()
        typedPrefix = now.timeIntervalSince(lastTypedAt) > 1 ? characters : typedPrefix + characters
        lastTypedAt = now
        focusedRow = visibleTools.first {
            $0.name.range(of: typedPrefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
        }?.id ?? focusedRow
    }

    private func refreshCatalog() {
        let rows = MainCatalog.preparedRows(ToolRegistry.allTools, query: query, filter: filter,
                                            favorites: favoriteIDs, disabled: settings.disabledToolIDs)
        toolCount = rows.total
        enabledCount = rows.enabled
        favoriteCount = rows.favorites
        groups = rows.groups
        visibleTools = rows.visible
    }
}
