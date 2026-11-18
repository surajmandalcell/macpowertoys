import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

/// Renders the main-window sidebar with each sidebar icon option, plus a glyph contact sheet, offscreen.
/// Option fixtures only: the shipped sidebar is unchanged. Nothing is ordered on screen.
@MainActor
final class SidebarGlyphRenderTests: XCTestCase {
    private enum Treatment { case monochrome, monoAccentSelection, accent, colored, tiles, current }

    private struct Option {
        let file: String
        let name: String
        let text: String
        let treatment: Treatment
    }

    private static let options = [
        Option(file: "monochrome", name: "Monochrome",
               text: "Every glyph is gray like the row text, and the selected glyph turns black or white like Finder.",
               treatment: .monochrome),
        Option(file: "mono-accent", name: "Monochrome, coral selection",
               text: "Every glyph is gray, and only the selected glyph turns coral, like Settings and Exit today.",
               treatment: .monoAccentSelection),
        Option(file: "accent", name: "Accent",
               text: "Every glyph is coral, like the accent-tinted sidebar in macOS 14 Finder and Mail.",
               treatment: .accent),
        Option(file: "colored", name: "Colored glyphs",
               text: "Each line glyph has its own tool color, so tools are easy to find by color.",
               treatment: .colored),
        Option(file: "tiles", name: "Color tiles",
               text: "Each glyph is white on a small rounded color square, like System Settings.",
               treatment: .tiles),
        Option(file: "current", name: "Keep as is",
               text: "The small full-color app icons stay, with gray Settings and Exit symbols.",
               treatment: .current)
    ]

    /// Distinct hues around the wheel; the icons' own hues repeat (four violets), so these spread them.
    private static let identity: [String: UInt32] = [
        "logs": 0xEE5B50, "ruler": 0xF07A2A, "awake": 0xEFB41C, "input-devices": 0x34B36B,
        "text-extractor": 0x17A6A0, "rclone": 0x2E9BEA, "portman": 0x5A6CF2,
        "color-picker": 0xA45BEE, "mac-tweaks": 0xE0559A, "all-tools": 0xEE5B50
    ]
    private static let selectedID = "mac-tweaks"
    private static let hoveredID = "ruler"

    func testRenderSidebarIconOptionsAndContactSheet() throws {
        let directory = ProcessInfo.processInfo.environment["GLYPH_RENDER_DIR"]
            ?? "/Volumes/External1TB/data/_custom/orca/workspaces/powertoys/v15-glyphs-r1"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let groups = MainCatalog.groups(ToolRegistry.builtInTools)
        XCTAssertEqual(groups.flatMap(\.tools).compactMap { SidebarGlyph.assetName(for: $0.id) }.count, 9)

        var entries: [[String: Any]] = []
        for (index, option) in Self.options.enumerated() {
            var entry: [String: Any] = ["name": option.name, "recommended": index == 0, "text": option.text]
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let file = "sidebar-\(option.file)-\(mode).png"
                try render(sidebar(option.treatment, groups: groups), size: CGSize(width: 215, height: 660),
                           appearance: appearance, scale: 2, to: "\(directory)/\(file)")
                entry[mode] = file
            }
            entries.append(entry)
        }
        var sheet: [String: Any] = ["name": "Glyph set, 16 pt and 32 pt", "recommended": true,
                                    "text": "All ten glyphs in ink at sidebar size and at double size, at 2x."]
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for scale in [1, 2] {
                let file = "glyphs-\(mode)-\(scale)x.png"
                try render(contactSheet(groups: groups), size: CGSize(width: 860, height: 124),
                           appearance: appearance, scale: CGFloat(scale), to: "\(directory)/\(file)")
                if scale == 2 { sheet[mode] = file }
            }
        }
        let manifest: [String: Any] = ["groups": [
            ["group": "Sidebar icons", "options": entries],
            ["group": "Glyph set", "options": [sheet]]
        ]]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: "\(directory)/manifest.json"))
    }

    // MARK: Fixtures

    private func sidebar(_ treatment: Treatment, groups: [MainToolGroup]) -> some View {
        OnePlusLinearSidebar {
            OnePlusLinearSearchField(text: .constant(""))
        } navigation: {
            row("All tools", id: "all-tools", treatment: treatment) {
                treatment == .current ? MainToolIcon.app : glyphImage(SidebarGlyph.allTools, id: "all-tools", treatment: treatment)
            }
            ForEach(groups) { group in
                OnePlusLinearNavCaption(group.category.rawValue)
                ForEach(group.tools, id: \.id) { tool in
                    self.row(tool.name, id: tool.id, treatment: treatment) {
                        treatment == .current ? MainToolIcon.image(for: tool)
                            : self.glyphImage(SidebarGlyph.assetName(for: tool.id) ?? "", id: tool.id, treatment: treatment)
                    }
                }
            }
        } bottom: {
            bottomRow("Settings", symbol: "gearshape", shortcut: "⌘,", treatment: treatment)
            bottomRow("Exit", symbol: "power", shortcut: "⌘Q", treatment: treatment)
        }
        .frame(height: 660)
    }

    private func row(_ title: String, id: String, treatment: Treatment, image: () -> Image) -> some View {
        OnePlusLinearNavRow(title, image: image(), selected: id == Self.selectedID) {}
            .environment(\.onePlusControlState, id == Self.hoveredID ? .hover : .rest)
    }

    @ViewBuilder
    private func bottomRow(_ title: String, symbol: String, shortcut: String, treatment: Treatment) -> some View {
        if treatment == .current {
            OnePlusLinearNavRow(title, systemImage: symbol, shortcut: shortcut) {}
        } else {
            OnePlusLinearNavRow(title, image: symbolImage(symbol, treatment: treatment)) {}
                .overlay(alignment: .trailing) {
                    Text(shortcut).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.muted)
                        .padding(.trailing, OnePlusLinearMetrics.navPadding)
                }
        }
    }

    private func color(id: String, treatment: Treatment) -> NSColor {
        let selected = id == Self.selectedID
        switch treatment {
        case .monochrome: return NSColor(selected ? OnePlusLinearColor.ink : OnePlusLinearColor.secondary)
        case .monoAccentSelection: return NSColor(selected ? OnePlusLinearColor.accent : OnePlusLinearColor.secondary)
        case .accent: return NSColor(OnePlusLinearColor.accent)
        case .colored, .tiles: return Self.hex(Self.identity[id] ?? 0x8E8E93)
        case .current: return .labelColor
        }
    }

    private func glyphImage(_ asset: String, id: String, treatment: Treatment) -> Image {
        let source = NSImage(named: asset) ?? NSImage()
        let tint = color(id: id, treatment: treatment)
        return Image(nsImage: SidebarGlyph.image(source, color: tint, tile: treatment == .tiles ? tint : nil))
    }

    /// Settings and Exit keep their SF Symbols, drawn at the glyph set's optical weight.
    private func symbolImage(_ name: String, treatment: Treatment) -> Image {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        let square = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let size = symbol.size
            symbol.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2,
                                   width: size.width, height: size.height))
            return true
        }
        let tint: NSColor = switch treatment {
        case .colored, .tiles: Self.hex(0x8E8E93)
        default: color(id: name, treatment: treatment)
        }
        return Image(nsImage: SidebarGlyph.image(square, color: tint, tile: treatment == .tiles ? tint : nil))
    }

    private func contactSheet(groups: [MainToolGroup]) -> some View {
        let names = [("All tools", SidebarGlyph.allTools)]
            + groups.flatMap(\.tools).map { ($0.name, SidebarGlyph.assetName(for: $0.id) ?? "") }
        return HStack(alignment: .top, spacing: 0) {
            ForEach(names, id: \.1) { name, asset in
                let source = NSImage(named: asset) ?? NSImage()
                VStack(spacing: 10) {
                    Image(nsImage: SidebarGlyph.image(source, color: NSColor(OnePlusLinearColor.ink), size: 16))
                        .frame(width: 16, height: 16)
                    Image(nsImage: SidebarGlyph.image(source, color: NSColor(OnePlusLinearColor.ink), size: 32))
                        .frame(width: 32, height: 32)
                    Text(name).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.muted).lineLimit(1)
                }
                .frame(width: 84)
            }
        }
        .padding(.top, 24)
        .frame(width: 860, height: 124, alignment: .top)
        .background(OnePlusLinearColor.window)
    }

    // MARK: Rendering

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private func render(_ view: some View, size: CGSize, appearance name: NSAppearance.Name, scale: CGFloat, to path: String) throws {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        appearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
