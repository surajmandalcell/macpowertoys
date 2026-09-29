import AppKit
import SwiftUI

nonisolated enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark, light, automatic
    static let storageKey = "app.appearance"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    @MainActor
    func apply() {
        let appearance: NSAppearance? = switch self {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .automatic: nil
        }
        if NSApp.appearance != appearance { NSApp.appearance = appearance }
    }
}
