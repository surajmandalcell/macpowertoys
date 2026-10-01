import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusButtonAlignmentTests: XCTestCase {
    func testButtonContentCentersPaintedCapsAndSymbols() throws {
        for density in OnePlusDensity.allCases {
            for size in [nil, OnePlusButtonStyle.Size.regular, .small] {
                for variant in OnePlusButtonStyle.Variant.allCases {
                    for symbol in ["circle.fill", "eyedropper", "text.viewfinder", "ruler"] {
                        let height: CGFloat = size.map { $0 == .small ? 24 : 28 } ?? density.controlHeight
                        let view = Button {} label: {
                            Label {
                                Text("HILT").foregroundStyle(.green)
                            } icon: {
                                Image(systemName: symbol).foregroundStyle(Color(red: 0, green: 0, blue: 1))
                            }
                        }.buttonStyle(OnePlusButtonStyle(variant, size: size))
                        try assertCenters(view.onePlusDensity(density), height: height,
                                          context: "\(density) \(String(describing: size)) \(variant) \(symbol)",
                                          components: variant == .icon || variant == .borderedIcon ? ["glyph"] : ["label", "glyph"])
                    }
                }
            }
        }
    }

    func testMenuTilesCenterHomeActionLabels() throws {
        for (title, symbol) in [("Pick Color", "eyedropper"), ("Extract Text", "text.viewfinder"), ("Ruler", "ruler")] {
            let tile = OnePlusMenuTile(height: 32, textured: false, action: {}) {
                Label {
                    Text(title).foregroundStyle(.green)
                } icon: {
                    Image(systemName: symbol).rotationEffect(.degrees(symbol == "ruler" ? -45 : 0)).foregroundStyle(Color(red: 0, green: 0, blue: 1))
                }
            }
            try assertCenters(tile.onePlusDensity(.compact), height: 32, context: title)
        }
    }

    func testTextAndIconOnlyButtonsCenterTheirContent() throws {
        for density in OnePlusDensity.allCases {
            for variant in OnePlusButtonStyle.Variant.allCases {
                if variant != .icon && variant != .borderedIcon {
                    try assertCenters(Button {} label: { Text("HILT").foregroundStyle(.green) }
                        .buttonStyle(OnePlusButtonStyle(variant)).onePlusDensity(density),
                                      height: density.controlHeight, context: "text \(variant)", components: ["label"])
                }
                guard variant == .icon || variant == .borderedIcon else { continue }
                try assertCenters(Button {} label: { Image(systemName: "circle.fill").foregroundStyle(Color(red: 0, green: 0, blue: 1)) }
                    .buttonStyle(OnePlusButtonStyle(variant)).onePlusDensity(density),
                                  height: density.controlHeight, context: "icon \(variant)", components: ["glyph"])
            }
        }
    }

    func testMenuTriggersAndSegmentsCenterTheirPaintedContent() throws {
        for density in OnePlusDensity.allCases {
            for variant in [OnePlusMenuButton.Variant.neutral, .ghost, .borderedIcon] {
                try assertCenters(OnePlusMenuButton("HILT", systemImage: "circle.fill", variant: variant, items: [])
                    .onePlusDensity(density), height: density.controlHeight,
                                  context: "menu \(density) \(variant)",
                                  components: variant == .borderedIcon ? ["glyph"] : ["label", "glyph"],
                                  monochrome: true, trailingGlyph: variant != .borderedIcon)
            }
            try assertCenters(OnePlusSegmented(choices: [(0, "HILT")], selection: .constant(0), width: 160)
                .onePlusDensity(density), height: density.controlHeight, context: "segment \(density)",
                              components: ["label"], monochrome: true)
            try assertCenters(OnePlusSegmented(iconChoices: [(0, "Circle", "circle.fill")],
                                               selection: .constant(0), accessibilityLabel: "Shape")
                .onePlusDensity(density), height: density.controlHeight, context: "icon segment \(density)",
                              components: ["glyph"], monochrome: true)
            try assertCenters(OnePlusMenuLabel(title: "HILT", width: 160).onePlusDensity(density),
                              height: density.controlHeight, context: "select \(density)",
                              monochrome: true, trailingGlyph: true)
        }
    }

    func testPopupRowsCenterLabelsAndGlyphs() throws {
        for density in OnePlusDensity.allCases {
            let choices: [(String?, Bool)] = [(nil, false), (nil, true), ("circle.fill", false),
                                              ("eyedropper", false), ("text.viewfinder", false), ("ruler", false)]
            for (symbol, selected) in choices {
                let item = OnePlusPopupMenuItem("HILT", systemImage: symbol, isSelected: selected) {}
                let session = OnePlusPopupSession(entries: [.item(item)], density: density, initialID: nil)
                try assertCenters(OnePlusPopupItemView(item: item, session: session).onePlusDensity(density),
                                  height: OnePlusPopupMetrics.itemHeight(for: density),
                                  context: "popup \(density) \(symbol ?? "text")",
                                  components: symbol == nil && !selected ? ["label"] : ["label", "glyph"],
                                  monochrome: true, leadingGlyph: symbol != nil || selected)
            }
        }
    }

    func testAccentPrimaryInkMeetsContrastInEachAppearanceAndState() throws {
        func luminance(_ color: NSColor) -> CGFloat {
            let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        for name in [NSAppearance.Name.darkAqua, .aqua] {
            try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                let ink = luminance(NSColor(OnePlusColor.accentPrimaryInk).usingColorSpace(.sRGB)!)
                for fill in [OnePlusColor.accent, OnePlusColor.accentPrimaryHover, OnePlusColor.accentPrimaryPressed] {
                    let ground = luminance(NSColor(fill).usingColorSpace(.sRGB)!)
                    XCTAssertGreaterThanOrEqual((max(ink, ground) + 0.05) / (min(ink, ground) + 0.05), 4.5)
                }
            }
        }
    }

    private func assertCenters<V: View>(_ view: V, height: CGFloat, context: String,
                                       components: [String] = ["label", "glyph"],
                                       monochrome: Bool = false, trailingGlyph: Bool = false, leadingGlyph: Bool = false,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let host = NSHostingView(rootView: view.background(OnePlusColor.panel))
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 160, height: height),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            defer { window.close() }
            for scale in [CGFloat(1), 2] {
                let bitmap = try XCTUnwrap(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(160 * scale), pixelsHigh: Int(height * scale),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                bitmap.size = host.bounds.size
                host.cacheDisplay(in: host.bounds, to: bitmap)
                var painted: [(x: Int, y: Int, label: Bool)] = []
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        if monochrome {
                            if appearance == .darkAqua
                                ? min(color.redComponent, color.greenComponent, color.blueComponent) > 0.35
                                : max(color.redComponent, color.greenComponent, color.blueComponent) < 0.7 {
                                painted.append((x, y, true))
                            }
                        } else if color.greenComponent > 0.5 && color.greenComponent - color.redComponent > 0.3 {
                            painted.append((x, y, true))
                        } else if color.blueComponent > 0.5 && color.blueComponent - color.greenComponent > 0.3 {
                            painted.append((x, y, false))
                        }
                    }
                }
                var split = bitmap.pixelsWide
                if trailingGlyph || leadingGlyph {
                    let columns = Set(painted.map(\.x)).sorted()
                    let gap = try XCTUnwrap(zip(columns, columns.dropFirst()).max { $0.1 - $0.0 < $1.1 - $1.0 })
                    split = (gap.0 + gap.1) / 2
                }

                for component in components {
                    let pixels = painted.filter { pixel in
                        if monochrome {
                            guard trailingGlyph || leadingGlyph else { return true }
                            return (component == "label") == trailingGlyph ? pixel.x < split : pixel.x > split
                        }
                        return pixel.label == (component == "label")
                    }
                    let top = try XCTUnwrap(pixels.map(\.y).min(), "\(context) \(component)")
                    let bottom = try XCTUnwrap(pixels.map(\.y).max())
                    let center = CGFloat(top + bottom + 1) / (2 * scale)
                    XCTAssertEqual(center, height / 2, accuracy: 0.5,
                                   "\(context) \(component) \(appearance) at \(scale)x", file: file, line: line)
                }
            }
        }
    }
}
