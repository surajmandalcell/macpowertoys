import AppKit
import SwiftUI

/// One-color 16 pt sidebar glyphs with 1.5 pt strokes, drawn from each tool's own icon.
/// Template SVG assets `SidebarGlyph<Name>`; the sidebar tints them `secondary`, `ink` when selected.
enum SidebarGlyph {
    static let allTools = "SidebarGlyphAllTools"

    /// The template glyph for a built-in tool; marketplace tools have none and keep their artwork.
    static func glyph(for toolID: String) -> Image? { assetName(for: toolID).map { Image($0) } }

    static func assetName(for toolID: String) -> String? {
        switch toolID {
        case "rclone": "SidebarGlyphRSync"
        case "logs": "SidebarGlyphEventViewer"
        case "ruler": "SidebarGlyphRuler"
        case "awake": "SidebarGlyphKwake"
        case "color-picker": "SidebarGlyphColorPicker"
        case "text-extractor": "SidebarGlyphTextExtractor"
        case "input-devices": "SidebarGlyphInputDevices"
        case "portman": "SidebarGlyphPortman"
        case "mac-tweaks": "SidebarGlyphMacTweaks"
        default: nil
        }
    }

    /// The glyph in `color`, or white on a rounded `tile` (System Settings style). Vector until drawn.
    static func image(_ source: NSImage, color: NSColor, tile: NSColor? = nil, size: CGFloat = 16) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            var glyphRect = rect
            if let tile {
                tile.setFill()
                NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
                glyphRect = rect.insetBy(dx: size * 0.13, dy: size * 0.13)
            }
            let glyph = tinted(source, color: tile == nil ? color : .white, size: glyphRect.size)
            // A tile shrinks the glyph and its strokes; four small offsets restore the line weight.
            let offsets: [CGFloat] = tile == nil ? [0] : [-size * 0.012, size * 0.012]
            for dx in offsets { for dy in offsets { glyph.draw(in: glyphRect.offsetBy(dx: dx, dy: dy)) } }
            return true
        }
    }

    private static func tinted(_ source: NSImage, color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
