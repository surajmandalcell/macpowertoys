import Foundation

enum MainCatalogFilter: String { case all, enabled, favorites }
enum MainCatalogSort: String, CaseIterable {
    case defaultOrder, name, category
    static let choices = allCases.map { ($0, $0.title) }
    var title: String {
        switch self {
        case .defaultOrder: "Default order"
        case .name: "Name"
        case .category: "Category"
        }
    }
}
enum MainCatalogViewMode: String { case grid, list }
enum MainSettingsTab: String, CaseIterable {
    case general, marketplace, about
    var title: String { rawValue.capitalized }
}

enum MainPageRoute: Equatable {
    case catalog(MainCatalogFilter), settings(MainSettingsTab), tool(String), manual(String)

    static func resolve(_ page: String, toolIDs: [String], savedSettingsTab: String = MainSettingsTab.general.rawValue) -> Self? {
        switch page {
        case "all-tools": return .catalog(.all)
        case "favorites": return .catalog(.favorites)
        case "settings": return .settings(MainSettingsTab(rawValue: savedSettingsTab) ?? .general)
        case "settings-general": return .settings(.general)
        case "settings-marketplace": return .settings(.marketplace)
        case "settings-about": return .settings(.about)
        default:
            if page.hasPrefix("manual/") {
                let id = String(page.dropFirst(7))
                return toolIDs.contains(id) ? .manual(id) : nil
            }
            let id = page.hasPrefix("tool/") ? String(page.dropFirst(5)) : page
            return toolIDs.contains(id) ? .tool(id) : nil
        }
    }
}

enum MainCatalog {
    static func matches(_ tool: any Tool, query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let text = ([tool.name, tool.category.rawValue, tool.description] + tool.searchKeywords).joined(separator: " ")
        return terms.allSatisfy { text.localizedStandardContains($0) }
    }

    static func favorites(from stored: String) -> Set<String> {
        guard let data = stored.data(using: .utf8), let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    static func storing(favorites: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(favorites.sorted()) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func sorted(_ tools: [any Tool], by sort: MainCatalogSort) -> [any Tool] {
        guard sort != .defaultOrder else { return tools }
        return tools.sorted { left, right in
            if sort == .category, left.category != right.category {
                return left.category.rawValue.localizedStandardCompare(right.category.rawValue) == .orderedAscending
            }
            let order = left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
    }
}
