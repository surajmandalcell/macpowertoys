import AppKit
import SwiftUI

/// DESIGN.md v14. All appearance decisions stay in this namespace.
public enum OnePlusColor {
    public static func dynamic(_ name: String, dark: UInt32, light: UInt32,
                               highContrastDark: UInt32? = nil, highContrastLight: UInt32? = nil) -> NSColor {
        NSColor(name: NSColor.Name("OnePlus.\(name)")) { appearance in
            resolve(appearance: appearance, increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                    dark: dark, light: light, highContrastDark: highContrastDark, highContrastLight: highContrastLight)
        }
    }

    static func resolve(appearance: NSAppearance, increasedContrast: Bool, dark: UInt32, light: UInt32,
                        highContrastDark: UInt32? = nil, highContrastLight: UInt32? = nil) -> NSColor {
        let highContrast = increasedContrast || appearance.name == .accessibilityHighContrastAqua || appearance.name == .accessibilityHighContrastDarkAqua
        let darkAppearance = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = highContrast ? (darkAppearance ? highContrastDark ?? dark : highContrastLight ?? light) : (darkAppearance ? dark : light)
        return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                   green: CGFloat((hex >> 8) & 255) / 255,
                   blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    public static let window = Color(nsColor: dynamic("window", dark: 0x161616, light: 0xF5F5F5))
    public static let sidebar = Color(nsColor: dynamic("sidebar", dark: 0x1D1D1D, light: 0xE7E7E7))
    public static let panel = Color(nsColor: dynamic("panel", dark: 0x202020, light: 0xFAFAFA))
    public static let tableAlternate = Color(nsColor: dynamic("tableAlternate", dark: 0x242424, light: 0xF2F2F2))
    public static let panelHover = Color(nsColor: dynamic("panelHover", dark: 0x262626, light: 0xFFFFFF))
    public static let raised = Color(nsColor: dynamic("raised", dark: 0x292929, light: 0xFFFFFF))
    public static let raisedHover = Color(nsColor: dynamic("raisedHover", dark: 0x303030, light: 0xF0F0F0))
    public static let pressed = Color(nsColor: dynamic("pressed", dark: 0x252525, light: 0xE4E4E4))
    public static let field = Color(nsColor: dynamic("field", dark: 0x252525, light: 0xF2F2F2))
    public static let fieldFocus = Color(nsColor: dynamic("fieldFocus", dark: 0x2B2B2B, light: 0xEAEAEA))
    public static let track = Color(nsColor: dynamic("track", dark: 0x181818, light: 0xE4E4E4))
    public static let selection = Color(nsColor: dynamic("selection", dark: 0x343434, light: 0xD4D4D4, highContrastDark: 0x3D3D3D, highContrastLight: 0xC8C8C8))
    public static let selectionInactive = Color(nsColor: dynamic("selectionInactive", dark: 0x292929, light: 0xE0E0E0, highContrastDark: 0x2B2B2B, highContrastLight: 0xDDDDDD))
    public static let selectedControl = Color(nsColor: dynamic("selectedControl", dark: 0x424242, light: 0xFFFFFF))
    public static let line = Color(nsColor: dynamic("line", dark: 0x343434, light: 0xD1D1D1, highContrastDark: 0xA0A0A0, highContrastLight: 0x707070))
    public static let lineSoft = Color(nsColor: dynamic("lineSoft", dark: 0x2B2B2B, light: 0xE1E1E1, highContrastDark: 0x919191, highContrastLight: 0x777777))
    public static let ink = Color(nsColor: dynamic("ink", dark: 0xEDEDED, light: 0x242424, highContrastDark: 0xFFFFFF, highContrastLight: 0x000000))
    public static let secondary = Color(nsColor: dynamic("secondary", dark: 0xC8C8C8, light: 0x4B4B4B, highContrastDark: 0xDADADA, highContrastLight: 0x444444))
    public static let muted = Color(nsColor: dynamic("muted", dark: 0xBCBCBC, light: 0x565656, highContrastDark: 0xDADADA, highContrastLight: 0x444444))
    public static let metricCaption = Color(nsColor: dynamic("metricCaption", dark: 0xA0A0A0, light: 0x5B5B5B, highContrastDark: 0xDADADA, highContrastLight: 0x444444))
    public static let controlInk = Color(nsColor: dynamic("controlInk", dark: 0xDEDEDE, light: 0x343434, highContrastDark: 0xFFFFFF, highContrastLight: 0x000000))
    public static let accent = Color(nsColor: dynamic("accent", dark: 0xEE5B50, light: 0xD94F45))
    public static let accentPrimaryInk = Color(nsColor: dynamic("accentPrimaryInk", dark: 0x161616, light: 0x000000))
    public static let accentPrimaryHover = Color(nsColor: dynamic("accentPrimaryHover", dark: 0xE65A4F, light: 0xD34E44))
    public static let accentPrimaryPressed = Color(nsColor: dynamic("accentPrimaryPressed", dark: 0xDE584E, light: 0xCD4D43))
    public static let dataBlue = Color(nsColor: dynamic("dataBlue", dark: 0x8AAEEA, light: 0x3564A4))
    public static let primaryFill = Color(nsColor: dynamic("primaryFill", dark: 0xDDDDDD, light: 0x383838))
    public static let primaryHover = Color(nsColor: dynamic("primaryHover", dark: 0xCCCCCC, light: 0x303030))
    public static let primaryPressed = Color(nsColor: dynamic("primaryPressed", dark: 0xBCBCBC, light: 0x292929))
    public static let primaryInk = Color(nsColor: dynamic("primaryInk", dark: 0x252525, light: 0xFFFFFF))
    public static let ok = Color(nsColor: dynamic("ok", dark: 0x7FA889, light: 0x3F7A4E))
    public static let warn = Color(nsColor: dynamic("warn", dark: 0xFFC09A, light: 0x74390F, highContrastDark: 0xFFE0C0, highContrastLight: 0x6B3208))
    public static let danger = Color(nsColor: dynamic("danger", dark: 0xFFB6AC, light: 0x872E25, highContrastDark: 0xFFCCC6, highContrastLight: 0x792820))
    public static let dangerFill = Color(nsColor: dynamic("dangerFill", dark: 0x382624, light: 0xFBE9E7))
    public static let dangerLine = Color(nsColor: dynamic("dangerLine", dark: 0x6D4541, light: 0xE3B3AD, highContrastDark: 0xE99B91, highContrastLight: 0x872E25))
    public static let focus = Color(nsColor: dynamic("focus", dark: 0x8B8B8B, light: 0x747474, highContrastDark: 0xC0C0C0, highContrastLight: 0x505050))
    public static let desktop = Color(nsColor: dynamic("desktop", dark: 0x0B0B0B, light: 0xD7D7D7))
    public static let chartLine = Color(nsColor: dynamic("chartLine", dark: 0xBEBEBE, light: 0x656565))
    public static let chartGrid = line
    public static let chartSeries: [Color] = zip(
        [UInt32(0xBCBCBC), 0x8A8A8A, 0x626262, 0x454545],
        [UInt32(0x626262), 0x8A8A8A, 0xABABAB, 0xCBCBCB]
    ).enumerated().map { Color(nsColor: dynamic("chart\($0.offset)", dark: $0.element.0, light: $0.element.1)) }
    public static let storageSeries: [Color] = [
        UInt32(0x66504A), 0x4C6272, 0x6C5A43, 0x48645E, 0x68546C, 0x745047,
        0x455D70, 0x706048, 0x435E60, 0x5B4E67, 0x536149
    ].enumerated().map { Color(nsColor: dynamic("storage\($0.offset)", dark: $0.element, light: $0.element)) }
}

public enum OnePlusTheme {
    public static let desktop = OnePlusColor.desktop
    public static let window = OnePlusColor.window
    public static let sidebar = OnePlusColor.sidebar
    public static let card = OnePlusColor.panel
    public static let cardHover = OnePlusColor.panelHover
    public static let line = OnePlusColor.line
    public static let lineSoft = OnePlusColor.lineSoft
    public static let ink = OnePlusColor.ink
    public static let secondary = OnePlusColor.secondary
    public static let muted = OnePlusColor.muted
    public static let accent = OnePlusColor.accent
}
