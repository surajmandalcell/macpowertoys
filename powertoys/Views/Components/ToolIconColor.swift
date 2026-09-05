import AppKit
import SwiftUI

/// The dominant saturated color of a tool's icon, for tinted tool actions.
enum ToolIconColor {
    private static var cache: [String: NSColor] = [:]

    static func major(for toolID: String) -> Color {
        guard let tool = ToolRegistry.tool(for: toolID),
              let color = major(asset: tool.logoAsset) else { return .accentColor }
        return Color(nsColor: color)
    }

    static func major(asset: String) -> NSColor? {
        if let cached = cache[asset] { return cached }
        guard !asset.isEmpty, let image = NSImage(named: asset) else { return nil }
        let size = 32
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        var buckets: [Int: (weight: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [:]
        var ground: (weight: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0, 0)
        for y in 0..<size {
            for x in 0..<size {
                guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.5 else { continue }
                let color = pixel.usingColorSpace(.deviceRGB) ?? pixel
                let saturation = color.saturationComponent
                let brightness = color.brightnessComponent
                if saturation > 0.25, brightness > 0.2 {
                    let bucket = Int(color.hueComponent * 12) % 12
                    var entry = buckets[bucket] ?? (0, 0, 0, 0)
                    let weight = saturation * brightness
                    entry.weight += weight
                    entry.r += color.redComponent * weight
                    entry.g += color.greenComponent * weight
                    entry.b += color.blueComponent * weight
                    buckets[bucket] = entry
                } else {
                    ground.weight += 1
                    ground.r += color.redComponent
                    ground.g += color.greenComponent
                    ground.b += color.blueComponent
                }
            }
        }
        let picked: NSColor?
        if let best = buckets.values.max(by: { $0.weight < $1.weight }), best.weight > 8 {
            picked = NSColor(red: best.r / best.weight, green: best.g / best.weight, blue: best.b / best.weight, alpha: 1)
        } else if ground.weight > 0 {
            let average = NSColor(red: ground.r / ground.weight, green: ground.g / ground.weight, blue: ground.b / ground.weight, alpha: 1)
            picked = average.brightnessComponent < 0.35 || average.saturationComponent < 0.12 ? nil : average
        } else {
            picked = nil
        }
        if let picked { cache[asset] = picked }
        return picked
    }

    /// Black or white, whichever reads on the tint.
    static func label(on tint: NSColor) -> Color {
        let color = tint.usingColorSpace(.deviceRGB) ?? tint
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance > 0.6 ? .black : .white
    }
}
