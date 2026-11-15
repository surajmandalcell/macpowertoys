import SwiftUI
import OnePlusUI

/// The v15 overview: one captioned section per category, one row per tool. The filter tabs sit in the pane toolbar.
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
    }

    var body: some View {
        OnePlusLinearPaneBody {
            if groups.isEmpty { emptyState }
            ForEach(groups) { group in
                OnePlusLinearSection(group.category.rawValue, count: group.tools.count) {
                    ForEach(group.tools, id: \.id) { tool in
                        MainToolRow(tool: tool, favorite: favoriteBinding(tool.id), focus: $focusedRow,
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
            favoriteIDs = MainCatalog.setting(favorite: value, for: id, in: favoriteIDs)
            storedFavorites = MainCatalog.storing(favorites: favoriteIDs)
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
        groups = rows.groups
        visibleTools = rows.visible
    }
}

/// All, Enabled, and Favorites with live counts, for the pane toolbar. Counts refresh on change, never in `body`.
struct MainCatalogTabs: View {
    @Binding var filter: MainCatalogFilter
    @AppStorage("main.favorites") private var storedFavorites = "[]"
    @State private var settings = SettingsManager.shared
    @State private var tabs: [OnePlusTab<MainCatalogFilter>] = []

    init(filter: Binding<MainCatalogFilter>) {
        _filter = filter
        _tabs = State(initialValue: Self.currentTabs(favorites: MainCatalog.favorites(from: storedFavorites)))
    }

    var body: some View {
        OnePlusLinearTextTabs(tabs: tabs, selection: $filter)
            .accessibilityLabel("Show tools")
            .accessibilityIdentifier("main.catalog.filter")
            .onChange(of: storedFavorites) { _, _ in refresh() }
            .onChange(of: settings.disabledToolIDs) { _, _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)) { _ in refresh() }
    }

    private func refresh() {
        tabs = Self.currentTabs(favorites: MainCatalog.favorites(from: storedFavorites))
    }

    private static func currentTabs(favorites: Set<String>) -> [OnePlusTab<MainCatalogFilter>] {
        let rows = MainCatalog.preparedRows(ToolRegistry.allTools, query: "", filter: .all, favorites: favorites,
                                            disabled: SettingsManager.shared.disabledToolIDs)
        return MainCatalog.tabs(total: rows.total, enabled: rows.enabled, favorites: rows.favorites)
    }
}
