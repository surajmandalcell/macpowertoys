import AppKit
import Foundation

enum ColorCopyFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case hex, hexa, rgb, rgba, hsl, hsla, cssVariable, swiftUI, nsColor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cssVariable: "CSS Variable"
        case .swiftUI: "SwiftUI"
        case .nsColor: "NSColor"
        default: rawValue.uppercased()
        }
    }
}

struct ColorProject: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let name: String
    var createdAt = Date()
}

struct ColorSample: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    var createdAt = Date()
    var isPinned = false
    var projectID: UUID?

    var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    func matches(_ other: ColorSample, tolerance: Double = 0.0005) -> Bool {
        abs(red - other.red) < tolerance &&
        abs(green - other.green) < tolerance &&
        abs(blue - other.blue) < tolerance &&
        abs(alpha - other.alpha) < tolerance
    }

    func string(_ format: ColorCopyFormat) -> String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        let a = Int((alpha * 255).rounded())
        let hsl = hslComponents
        switch format {
        case .hex: return String(format: "#%02X%02X%02X", r, g, b)
        case .hexa: return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        case .rgb: return "rgb(\(r), \(g), \(b))"
        case .rgba: return "rgba(\(r), \(g), \(b), \(decimal(alpha)))"
        case .hsl: return "hsl(\(Int(hsl.h.rounded())), \(Int((hsl.s * 100).rounded()))%, \(Int((hsl.l * 100).rounded()))%)"
        case .hsla: return "hsla(\(Int(hsl.h.rounded())), \(Int((hsl.s * 100).rounded()))%, \(Int((hsl.l * 100).rounded()))%, \(decimal(alpha)))"
        case .cssVariable: return "--color: \(string(.hexa));"
        case .swiftUI: return "Color(red: \(decimal(red)), green: \(decimal(green)), blue: \(decimal(blue)), opacity: \(decimal(alpha)))"
        case .nsColor: return "NSColor(srgbRed: \(decimal(red)), green: \(decimal(green)), blue: \(decimal(blue)), alpha: \(decimal(alpha)))"
        }
    }

    private var hslComponents: (h: Double, s: Double, l: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        guard maximum != minimum else { return (0, 0, lightness) }
        let delta = maximum - minimum
        let saturation = lightness > 0.5 ? delta / (2 - maximum - minimum) : delta / (maximum + minimum)
        let hue: Double
        if maximum == red { hue = (green - blue) / delta + (green < blue ? 6 : 0) }
        else if maximum == green { hue = (blue - red) / delta + 2 }
        else { hue = (red - green) / delta + 4 }
        return (hue * 60, saturation, lightness)
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)))
    }
}
