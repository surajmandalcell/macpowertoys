import SwiftUI
import OnePlusUI

struct AllToolsGridView: View {
    @Binding var selectedTool: String?
    var query: String
    @Binding var filter: MainCatalogFilter
    @Binding var focusedToolID: String?
    @AppStorage("main.favorites") private var storedFavorites = "[]"
    @AppStorage("main.sort") private var sort = MainCatalogSort.defaultOrder
    @AppStorage("main.viewMode") private var viewMode = MainCatalogViewMode.grid
    @State private var settings = SettingsManager.shared
    @FocusState private var focusedCard: String?
    @State private var typedPrefix = ""
    @State private var lastTypedAt = Date.distantPast
    @State private var favoriteIDs: Set<String> = []
    @State private var visibleTools: [any Tool] = []
    @State private var toolCount = 0
    @State private var enabledCount = 0
    @State private var favoriteCount = 0

    init(selectedTool: Binding<String?>, query: String = "",
         filter: Binding<MainCatalogFilter> = .constant(.all),
         focusedToolID: Binding<String?> = .constant(nil)) {
        _selectedTool = selectedTool; self.query = query; _filter = filter; _focusedToolID = focusedToolID
        let favorites = MainCatalog.favorites(from: storedFavorites)
        let rows = MainCatalog.preparedRows(ToolRegistry.allTools, query: query, filter: filter.wrappedValue,
                                            sort: sort, favorites: favorites, disabled: settings.disabledToolIDs)
        _favoriteIDs = State(initialValue: favorites)
        _visibleTools = State(initialValue: rows.visible)
        _toolCount = State(initialValue: rows.total)
        _enabledCount = State(initialValue: rows.enabled)
        _favoriteCount = State(initialValue: rows.favorites)
    }

    var body: some View {
        OnePlusPage(scrolls: !visibleTools.isEmpty) {
            OnePlusPageHeader(title: "All tools", subtitle: "Your Mac, a little more capable.")
        } tabs: {
            OnePlusTabStrip(tabs: [
                OnePlusTab(.all, "All tools", count: toolCount),
                OnePlusTab(.enabled, "Enabled", count: enabledCount),
                OnePlusTab(.favorites, "Favorites", count: favoriteCount)
            ], selection: $filter) { tabTools }
        } content: {
            if visibleTools.isEmpty { emptyState }
            else if viewMode == .grid { grid }
            else { list }
        }
        .accessibilityIdentifier("main.all-tools")
        .onChange(of: focusedCard) { _, id in if let id { focusedToolID = id } }
        .onChange(of: query) { _, _ in refreshCatalog() }
        .onChange(of: filter) { _, _ in refreshCatalog() }
        .onChange(of: settings.disabledToolIDs) { _, _ in refreshCatalog() }
        .onChange(of: storedFavorites) { _, value in
            let updated = MainCatalog.favorites(from: value)
            if updated != favoriteIDs { favoriteIDs = updated; refreshCatalog() }
        }
        .onChange(of: sort) { refreshCatalog() }
        .onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)) { _ in refreshCatalog() }
    }

    private var tabTools: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            OnePlusSelect(choices: MainCatalogSort.choices,
                          selection: $sort, accessibilityLabel: "Sort tools")
            OnePlusSegmented(iconChoices: [(.grid, "Grid", "square.grid.2x2"), (.list, "List", "list.bullet")],
                             selection: $viewMode, accessibilityLabel: "Tool view")
                .frame(width: OnePlusCatalogMetrics.viewControlWidth)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OnePlusCatalogMetrics.gap),
                                 count: OnePlusCatalogMetrics.columns), spacing: OnePlusCatalogMetrics.gap) {
            ForEach(visibleTools, id: \.id) { tool in
                MainToolCard(tool: tool, favorite: favoriteBinding(tool.id), focusedToolID: $focusedToolID,
                             bodyFocus: $focusedCard, move: { moveFocus(from: tool.id, direction: $0) }, typeSelect: typeSelect) {
                    selectSettings(tool.id)
                }
            }
        }
    }

    private var list: some View {
        OnePlusCard {
            LazyVStack(spacing: 0) {
                ForEach(visibleTools, id: \.id) { tool in
                    MainToolListRow(tool: tool, favorite: favoriteBinding(tool.id), focusedToolID: $focusedToolID,
                                    bodyFocus: $focusedCard, move: { moveFocus(from: tool.id, direction: $0) }, typeSelect: typeSelect) {
                        selectSettings(tool.id)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        OnePlusEmptyState(query.isEmpty ? filter == .favorites ? "No favorites yet" : "No enabled tools" : "No matching tools",
                          systemImage: query.isEmpty ? "star" : "magnifyingglass",
                          caption: query.isEmpty
                            ? filter == .favorites ? "Use the star on a tool to add a favorite." : "Enable a tool to show it here."
                            : "Try another name, category, or keyword.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let stride = viewMode == .grid ? OnePlusCatalogMetrics.columns : 1
        let offset: Int
        switch direction {
        case .up: offset = -stride
        case .down: offset = stride
        case .left: offset = -1
        case .right: offset = 1
        @unknown default: return
        }
        focusedCard = ids[min(max(index + offset, 0), ids.count - 1)]
    }

    private func typeSelect(_ characters: String) {
        let now = Date()
        typedPrefix = now.timeIntervalSince(lastTypedAt) > 1 ? characters : typedPrefix + characters
        lastTypedAt = now
        focusedCard = visibleTools.first {
            $0.name.range(of: typedPrefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
        }?.id ?? focusedCard
    }

    private func refreshCatalog() {
        let rows = MainCatalog.preparedRows(ToolRegistry.allTools, query: query, filter: filter,
                                            sort: sort, favorites: favoriteIDs, disabled: settings.disabledToolIDs)
        toolCount = rows.total
        enabledCount = rows.enabled
        favoriteCount = rows.favorites
        visibleTools = rows.visible
    }
}
