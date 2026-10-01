import AppKit
import SwiftUI

final class OnePlusTableUsageBar: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor(OnePlusColor.line).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let fraction = value.isFinite ? min(max(value, 0), 1) : 0
        guard fraction > 0 else { return }
        NSColor(OnePlusColor.chartLine).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.minX, y: bounds.minY,
            width: bounds.width * fraction, height: bounds.height), xRadius: radius, yRadius: radius).fill()
    }
}
