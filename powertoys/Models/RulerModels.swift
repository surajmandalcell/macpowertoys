import AppKit
import CoreGraphics
import Foundation

enum RulerOrientation: String, CaseIterable, Codable, Identifiable, Sendable {
    case horizontal
    case vertical
    case joined

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum RulerUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case points = "pt"
    case pixels = "px"
    case millimeters = "mm"
    case inches = "in"

    var id: String { rawValue }
}

enum RulerZeroCorner: String, CaseIterable, Codable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }
    var title: String {
        rawValue.reduce(into: "") { result, character in
            if character.isUppercase { result.append(" ") }
            result.append(character)
        }.capitalized
    }

    var reversesHorizontal: Bool { self == .topRight || self == .bottomRight }
    var reversesVertical: Bool { self == .bottomLeft || self == .bottomRight }
}

struct RulerStyle: Codable, Equatable, Sendable {
    var unit: RulerUnit = .pixels
    var zeroCorner: RulerZeroCorner = .topLeft
    var opacity = 0.94
    var red = 0.96
    var green = 0.72
    var blue = 0.22
    var floats = true
    var hasShadow = true
    var calibration = 1.0

    var color: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

struct RulerState: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var orientation: RulerOrientation
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var screenID: UInt32?
    var groupID: UUID?
    var isVisible = true

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.width
            height = newValue.height
        }
    }

    init(orientation: RulerOrientation, frame: CGRect, screenID: UInt32?) {
        self.orientation = orientation
        x = frame.origin.x
        y = frame.origin.y
        width = frame.width
        height = frame.height
        self.screenID = screenID
    }
}

struct RulerTick: Equatable, Sendable {
    let position: CGFloat
    let value: Double
    let level: Int
}

struct RulerMeasurement: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var createdAt = Date()
    var isPinned = false

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(frame: CGRect) {
        x = frame.origin.x
        y = frame.origin.y
        width = frame.width
        height = frame.height
    }
}

enum RulerGeometry {
    static func ticks(length: CGFloat, pointsPerUnit: CGFloat, reversed: Bool) -> [RulerTick] {
        guard length > 0, pointsPerUnit > 0 else { return [] }
        let minimumSpacing: CGFloat = 5
        let candidates: [CGFloat] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100]
        let step = candidates.first { $0 * pointsPerUnit >= minimumSpacing } ?? 100
        let count = Int(floor(length / (step * pointsPerUnit)))
        return (0...count).map { index in
            let logical = CGFloat(index) * step
            let position = reversed ? length - logical * pointsPerUnit : logical * pointsPerUnit
            let decimalIndex = Int(round(logical / step))
            let level = decimalIndex % 10 == 0 ? 2 : (decimalIndex % 5 == 0 ? 1 : 0)
            return RulerTick(position: position, value: Double(logical), level: level)
        }
    }

    static func pointsPerUnit(_ unit: RulerUnit, screen: NSScreen?, calibration: Double) -> CGFloat {
        let scale = screen?.backingScaleFactor ?? 1
        switch unit {
        case .points: return 1
        case .pixels: return 1 / scale
        case .millimeters, .inches:
            guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return unit == .inches ? 72 : 72 / 25.4
            }
            let id = CGDirectDisplayID(number.uint32Value)
            let size = CGDisplayScreenSize(id)
            guard size.width > 0 else { return unit == .inches ? 72 : 72 / 25.4 }
            let pointsPerMM = CGFloat(CGDisplayPixelsWide(id)) / scale / size.width * calibration
            return unit == .inches ? pointsPerMM * 25.4 : pointsPerMM
        }
    }
}

enum RulerCopyFormat: String, CaseIterable, Identifiable {
    case plain, css, swiftUI, cgRect, json
    var id: String { rawValue }
    var title: String { self == .swiftUI ? "SwiftUI" : rawValue.capitalized }

    func render(frame: CGRect) -> String {
        let x = Double(frame.origin.x).formatted(.number.precision(.fractionLength(0...2)))
        let y = Double(frame.origin.y).formatted(.number.precision(.fractionLength(0...2)))
        let width = Double(frame.width).formatted(.number.precision(.fractionLength(0...2)))
        let height = Double(frame.height).formatted(.number.precision(.fractionLength(0...2)))
        switch self {
        case .plain: return "\(width) × \(height) at (\(x), \(y))"
        case .css: return "width: \(width)px; height: \(height)px;"
        case .swiftUI: return ".frame(width: \(width), height: \(height))"
        case .cgRect: return "CGRect(x: \(x), y: \(y), width: \(width), height: \(height))"
        case .json: return "{\"x\":\(x),\"y\":\(y),\"width\":\(width),\"height\":\(height)}"
        }
    }
}
