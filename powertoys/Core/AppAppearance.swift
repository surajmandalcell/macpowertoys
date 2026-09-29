import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark, light, automatic
    static let storageKey = "app.appearance"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .automatic: nil
        }
    }
}
