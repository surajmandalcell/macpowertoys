import Foundation

extension MainCatalog {
    static func preparedRows(
        _ tools: [any Tool], query: String, filter: MainCatalogFilter, sort: MainCatalogSort,
        favorites: Set<String>, disabled: Set<String>
    ) -> (visible: [any Tool], total: Int, enabled: Int, favorites: Int) {
        let hasQuery = !query.allSatisfy(\.isWhitespace)
        let visible = tools.filter { tool in
            (filter == .all || filter == .enabled && !disabled.contains(tool.id)
                || filter == .favorites && favorites.contains(tool.id))
                && (!hasQuery || matches(tool, query: query))
        }
        return (sorted(visible, by: sort), tools.count,
                tools.lazy.filter { !disabled.contains($0.id) }.count,
                tools.lazy.filter { favorites.contains($0.id) }.count)
    }
}
