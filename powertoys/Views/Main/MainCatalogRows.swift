import Foundation

extension MainCatalog {
    static func preparedRows(
        _ tools: [any Tool], query: String, filter: MainCatalogFilter,
        favorites: Set<String>, disabled: Set<String>
    ) -> (groups: [MainToolGroup], visible: [any Tool], total: Int, enabled: Int, favorites: Int) {
        let hasQuery = !query.allSatisfy(\.isWhitespace)
        let groups = groups(tools.filter { tool in
            (filter == .all || filter == .enabled && !disabled.contains(tool.id)
                || filter == .favorites && favorites.contains(tool.id))
                && (!hasQuery || matches(tool, query: query))
        })
        return (groups, groups.flatMap(\.tools), tools.count,
                tools.lazy.filter { !disabled.contains($0.id) }.count,
                tools.lazy.filter { favorites.contains($0.id) }.count)
    }
}
