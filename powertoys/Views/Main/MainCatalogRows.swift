import Foundation
import OnePlusUI

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

    static func tabs(total: Int, enabled: Int, favorites: Int) -> [OnePlusTab<MainCatalogFilter>] {
        [OnePlusTab(.all, "All", count: total), OnePlusTab(.enabled, "Enabled", count: enabled),
         OnePlusTab(.favorites, "Favorites", count: favorites)]
    }

    static func setting(favorite: Bool, for id: String, in favorites: Set<String>) -> Set<String> {
        favorite ? favorites.union([id]) : favorites.subtracting([id])
    }
}
