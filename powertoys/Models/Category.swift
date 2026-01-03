import Foundation

enum Category: String, CaseIterable, Identifiable {
    case all = "All Tools"
    case text = "Text"
    case files = "Files"
    case system = "System"
    case dev = "Dev"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .text:
            return "textformat"
        case .files:
            return "folder"
        case .system:
            return "gearshape.2"
        case .dev:
            return "hammer"
        case .settings:
            return "slider.horizontal.3"
        }
    }

    var isMainCategory: Bool {
        self != .settings
    }
}
