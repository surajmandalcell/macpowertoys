import Foundation

enum MainCatalogFilter: String { case all, enabled, favorites }
enum MainSettingsTab: String, CaseIterable {
    case general, marketplace, about
    var title: String { rawValue.capitalized }
}

struct MainToolGroup: Identifiable {
    let category: ToolCategory
    let tools: [any Tool]
    var id: ToolCategory { category }
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

    /// Sidebar and overview groups: one per category, in category order, registry order inside.
    static func groups(_ tools: [any Tool]) -> [MainToolGroup] {
        ToolCategory.allCases.compactMap { category in
            let members = tools.filter { $0.category == category }
            return members.isEmpty ? nil : MainToolGroup(category: category, tools: members)
        }
    }

    /// Command-2 to Command-9 follow the sidebar order after All tools.
    static func shortcutTools(_ tools: [any Tool]) -> [any Tool] {
        Array(groups(tools).flatMap(\.tools).prefix(8))
    }
}
