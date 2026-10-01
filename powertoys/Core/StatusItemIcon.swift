import AppKit
import OnePlusUI

@MainActor
enum StatusItemIcon {
    private static var symbols: [String: NSImage] = [:]
    static let main = normalized(NSImage(named: "MenuBarIcon") ?? NSImage())

    static func symbol(_ name: String) -> NSImage? {
        if let image = symbols[name] { return image }
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: OnePlusMenuMetrics.statusIconSize, weight: .regular))
        else { return nil }
        let image = normalized(source)
        symbols[name] = image
        return image
    }

    private static func normalized(_ source: NSImage) -> NSImage {
        let side = OnePlusMenuMetrics.statusIconSize
        let size = NSSize(width: side, height: side)
        let (source, ink) = rasterized(source)
        let scale = OnePlusMenuMetrics.statusIconInkSize / max(ink.width, ink.height, 1)
        let image = NSImage(size: size, flipped: false) { _ in
            source.draw(in: NSRect(
                x: side / 2 - ink.midX * scale,
                y: side / 2 - ink.midY * scale,
                width: source.size.width * scale,
                height: source.size.height * scale
            ))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func rasterized(_ image: NSImage) -> (NSImage, NSRect) {
        let scale: CGFloat = 4
        guard image.size.width > 0, image.size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(ceil(image.size.width * scale)), pixelsHigh: Int(ceil(image.size.height * scale)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let pixels = bitmap.bitmapData else { return (image, NSRect(origin: .zero, size: image.size)) }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var left = bitmap.pixelsWide, top = bitmap.pixelsHigh, right = -1, bottom = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where pixels[y * bitmap.bytesPerRow + x * 4 + 3] > 25 {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= left else { return (image, NSRect(origin: .zero, size: image.size)) }
        let sx = image.size.width / CGFloat(bitmap.pixelsWide)
        let sy = image.size.height / CGFloat(bitmap.pixelsHigh)
        let source = NSImage(size: image.size)
        source.addRepresentation(bitmap)
        return (source, NSRect(x: CGFloat(left) * sx, y: CGFloat(bitmap.pixelsHigh - bottom - 1) * sy,
                               width: CGFloat(right - left + 1) * sx, height: CGFloat(bottom - top + 1) * sy))
    }
}
