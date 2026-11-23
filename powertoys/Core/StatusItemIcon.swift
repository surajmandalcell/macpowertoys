import AppKit
import OnePlusUI

@MainActor
enum StatusItemIcon {
    private static var symbols: [String: NSImage] = [:]
    // Matches SF Symbols at 14 pt regular, medium scale (Control Center, Wi-Fi); DESIGN.md "Shared behavior".
    private static let mainCanvas: CGFloat = 16
    private static let mainInk: CGFloat = 13.6
    static let main = normalized(NSImage(named: "MenuBarIcon") ?? NSImage(), side: mainCanvas, inkSize: mainInk)

    static func symbol(_ name: String) -> NSImage? {
        if let image = symbols[name] { return image }
        if ToolGlyph.allCases.contains(where: { $0.isAsset && $0.symbol == name }) {
            guard let image = NSImage(named: name)?.copy() as? NSImage else { return nil }
            image.size = NSSize(width: OnePlusMenuMetrics.statusIconSize, height: OnePlusMenuMetrics.statusIconSize)
            image.isTemplate = true
            symbols[name] = image
            return image
        }
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: OnePlusMenuMetrics.statusIconSize, weight: .regular))
        else { return nil }
        let image = normalized(source)
        symbols[name] = image
        return image
    }

    /// A traced menu bar glyph asset (`MenuBarGlyph*`), drawn at its own optical size; see spec/icons.md.
    static func glyph(_ name: String) -> NSImage? {
        if let image = symbols[name] { return image }
        guard let image = NSImage(named: name) else { return nil }
        image.isTemplate = true
        symbols[name] = image
        return image
    }

    /// The base glyph with an accent layer (such as Awake's rays) at one opacity step of a pulse.
    static func glyph(_ base: String, accent: String, opacity: CGFloat) -> NSImage? {
        let key = "\(base)+\(accent)@\(opacity)"
        if let image = symbols[key] { return image }
        guard let baseImage = glyph(base), let accentImage = glyph(accent) else { return nil }
        let image = NSImage(size: baseImage.size, flipped: false) { bounds in
            baseImage.draw(in: bounds)
            accentImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: opacity)
            return true
        }
        image.isTemplate = true
        symbols[key] = image
        return image
    }

    static func attachmentSymbol(_ name: String) -> NSImage? {
        let key = "attachment." + name
        if let image = symbols[key] { return image }
        guard let source = symbol(name)?.copy() as? NSImage else { return nil }
        source.isTemplate = false
        let image = NSImage(size: source.size, flipped: false) { bounds in
            source.draw(in: bounds)
            NSColor.labelColor.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        // Text attachments do not apply native template tint. Resolve it on each draw.
        image.cacheMode = .never
        symbols[key] = image
        return image
    }

    private static func normalized(
        _ source: NSImage,
        side: CGFloat = OnePlusMenuMetrics.statusIconSize,
        inkSize: CGFloat = OnePlusMenuMetrics.statusIconInkSize
    ) -> NSImage {
        let size = NSSize(width: side, height: side)
        let (source, ink) = rasterized(source)
        let scale = inkSize / max(ink.width, ink.height, 1)
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

    static func rasterized(_ image: NSImage) -> (NSImage, NSRect) {
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
