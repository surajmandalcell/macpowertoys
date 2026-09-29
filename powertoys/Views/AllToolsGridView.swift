import SwiftUI
import OnePlusUI

struct AllToolsGridView: View {
    @Binding var selectedTool: String?
    var query: String
    @Binding var filter: MainCatalogFilter
    @Binding var focusedToolID: String?
    var changed: () -> Void
    @AppStorage("main.favorites") private var storedFavorites = "[]"
    @AppStorage("main.sort") private var sort = MainCatalogSort.defaultOrder
    @AppStorage("main.viewMode") private var viewMode = MainCatalogViewMode.grid
    @State private var settings = SettingsManager.shared
    @FocusState private var focusedCard: String?
    @State private var typedPrefix = ""
    @State private var lastTypedAt = Date.distantPast

    init(selectedTool: Binding<String?>, query: String = "",
         filter: Binding<MainCatalogFilter> = .constant(.all),
         focusedToolID: Binding<String?> = .constant(nil), changed: @escaping () -> Void = {}) {
        _selectedTool = selectedTool; self.query = query; _filter = filter; _focusedToolID = focusedToolID
        self.changed = changed
    }

    private var favorites: Set<String> { MainCatalog.favorites(from: storedFavorites) }
    private var tools: [any Tool] { ToolRegistry.allTools }
    private var visibleTools: [any Tool] {
        MainCatalog.sorted(tools.filter {
            MainCatalog.matches($0, query: query) && (filter == .all
                || filter == .enabled && settings.isToolEnabled($0.id)
                || filter == .favorites && favorites.contains($0.id))
        }, by: sort)
    }

    var body: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "All tools", subtitle: "Your Mac, a little more capable.")
        } tabs: {
            OnePlusTabStrip(tabs: [
                OnePlusTab(.all, "All tools", count: tools.count),
                OnePlusTab(.enabled, "Enabled", count: tools.filter { settings.isToolEnabled($0.id) }.count),
                OnePlusTab(.favorites, "Favorites", count: tools.filter { favorites.contains($0.id) }.count)
            ], selection: $filter) { tabTools }
        } content: {
            if visibleTools.isEmpty { emptyState }
            else if viewMode == .grid { grid }
            else { list }
        }
        .accessibilityIdentifier("main.all-tools")
        .onChange(of: focusedCard) { _, id in if let id { focusedToolID = id } }
        .onChange(of: storedFavorites) { changed() }
        .onChange(of: sort) { changed() }
        .onChange(of: viewMode) { changed() }
    }

    private var tabTools: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            OnePlusSelect(choices: MainCatalogSort.allCases.map { ($0, $0.title) },
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
                    selectedTool = tool.id
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
                        selectedTool = tool.id
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
    }

    private func favoriteBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { favorites.contains(id) }, set: { value in
            var updated = favorites
            if value { updated.insert(id) } else { updated.remove(id) }
            storedFavorites = MainCatalog.storing(favorites: updated)
        })
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
}
