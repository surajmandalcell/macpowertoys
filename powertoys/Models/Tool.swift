//
//  Tool.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation
import OnePlusUI

// MARK: - Tool Protocol

protocol Tool: Identifiable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var summary: String { get }
    var icon: String { get }
    var logoAsset: String { get }
    var iconFileURL: URL? { get }
    var category: ToolCategory { get }
    var manual: [ToolManualSection] { get }
    var hasTrayTab: Bool { get }
    var searchKeywords: [String] { get }
}

extension Tool {
    var summary: String { description }
    var hasTrayTab: Bool { false }
    var iconFileURL: URL? { nil }
    var searchKeywords: [String] { [] }
}

// MARK: - Manual

/// One How to use checklist: steps, then shortcuts, then notes. The title shows only when a tool has more than one.
struct ToolManualSection: Identifiable {
    let title: String
    var steps: [OnePlusLinearChecklistStep] = []
    var keys: [OnePlusLinearChecklistKey] = []
    var notes: [String] = []

    var id: String { title }
}

private typealias Step = OnePlusLinearChecklistStep
private typealias Key = OnePlusLinearChecklistKey

// MARK: - Tool Category

enum ToolCategory: String, CaseIterable, Identifiable {
    // Case order is the sidebar and overview order.
    case all = "All Tools"
    case system = "System"
    case dev = "Developer"
    case text = "Text"
    case files = "Files"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .dev: return "hammer"
        case .text: return "textformat"
        case .files: return "folder"
        case .system: return "gearshape.2"
        }
    }
}

// MARK: - Cloud Sync Tool

struct RcloneTool: Tool {
    let id = "rclone"
    let name = "RSync UI"
    let summary = "Sync folders to cloud and remote storage"
    let description = "Move files between your Mac and cloud storage with live progress, automatic retries, and ignore rules."
    let icon = ToolGlyph.cloudSync.symbol
    let logoAsset = "CloudSyncLogo"
    let category = ToolCategory.files
    let hasTrayTab = true

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Connect storage", steps: [
            Step("plus.circle", "Click + next to Remotes in the sidebar."),
            Step("server.rack", "Pick a storage type, fill in its settings, and click Connect."),
            Step("person.badge.key", "For Google Drive, Dropbox, and similar, sign in when the browser opens."),
        ]),
        ToolManualSection(title: "Move files", steps: [
            Step("arrow.left.arrow.right", "Click New Transfer and pick the source and the target."),
            Step("doc.on.doc", "Copy adds new files. Sync makes the target match the source and deletes extras. Move deletes the source files."),
            Step("chart.bar", "Watch the progress live. A failed transfer tries again by itself."),
            Step("folder", "Click a remote to browse it. Drag files in to upload them, or out to download them."),
        ], keys: [
            Key(["⌘", "N"], "New transfer"), Key(["Space"], "Quick Look the selected file"),
            Key(["⌘", ","], "Ignore rules, speed limits, and retries"),
        ]),
        ToolManualSection(title: "Dev Sync", steps: [
            Step("externaldrive", "Open Dev Sync and click Set Up Dev Sync. Pick your dev folder and a folder on an external drive."),
            Step("arrow.right", "One-Way copies your projects to the drive. Two-Way syncs changes both ways."),
            Step("eye", "Check the preview. Nothing changes until you confirm it."),
        ], notes: [
            "Files that Git ignores are not copied, but .env files are still backed up unless you turn that off.",
            "Every overwritten or deleted file is kept for a while, so you can get it back.",
        ])
    ]

    static let shared = RcloneTool()
}

// MARK: - Logs Tool

struct LogsTool: Tool {
    let id = "logs"
    let name = "Event Viewer"
    let summary = "Read app and system logs in one place"
    let description = "Inspect MacPowerToys activity and recent macOS errors and faults in clearly separated views."
    let icon = ToolGlyph.logs.symbol
    let logoAsset = "LogsLogo"
    let category = ToolCategory.system

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Read logs", steps: [
            Step("sidebar.left", "Pick Internal Logs for MacPowerToys, or System Issues for recent macOS errors."),
            Step("line.3.horizontal.decrease", "Filter by level, or search the messages."),
            Step("text.cursor", "Select any text to copy it into a bug report."),
        ], keys: [
            Key(["⌘", "F"], "Search"), Key(["⌘", ","], "Change the font size"),
        ], notes: [
            "Internal logs are deleted after two days. System Issues are read fresh each time and never saved.",
        ])
    ]

    static let shared = LogsTool()
}

// MARK: - Ruler Tool

struct RulerTool: Tool {
    let id = "ruler"
    let name = "Ruler"
    let summary = "Measure on-screen distances in px, mm, or in"
    let description = "Measure the screen with movable, resizable rulers in pixels, millimeters, or inches."
    let icon = ToolGlyph.ruler.symbol
    let logoAsset = "RulerLogo"
    let category = ToolCategory.dev

    let manual = [
        ToolManualSection(title: "Rulers", steps: [
            Step("hand.draw", "Drag the ruler to move it."),
            Step("arrow.up.left.and.arrow.down.right", "Drag an end or a corner to make it longer or shorter."),
            Step("arrow.left.and.right", "Press the arrow keys to move 1 pixel. Hold Shift to move 10."),
        ], keys: [
            Key(["⌘", "N"], "New ruler"), Key(["⌘", "`"], "Next ruler"),
            Key(["H"], "Hide or show the top wing"), Key(["V"], "Hide or show the side wing"),
            Key(["U"], "Change the unit"), Key(["F"], "Float above apps"),
            Key(["S"], "Shadow on or off"), Key(["G"], "Move both wings together"),
            Key(["O"], "Line up at the pointer"), Key(["⌘", ","], "Settings for this ruler"),
            Key(["⌥", "⌘", ","], "Defaults for new rulers"),
        ])
    ]

    static let shared = RulerTool()
}

// MARK: - Awake Tool

struct AwakeTool: Tool {
    let id = "awake"
    let name = "Awake"
    let summary = "Keep your Mac awake for a set time"
    let description = "Keep your Mac awake indefinitely, for a duration, or until a chosen time without changing Energy settings."
    let icon = ToolGlyph.awake.symbol
    let logoAsset = "AwakeLogo"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Keep awake", steps: [
            Step("power", "Turn on Keep awake."),
            Step("timer", "Pick how long: a set time, until a set hour, or until you turn it off."),
            Step("display", "Turn on Keep display on to keep the screen lit too."),
        ], keys: [
            Key(["⌃", "⌥", "⌘", "A"], "Turn Awake on or off"),
        ], notes: [
            "The Mac still sleeps when you close the lid, the battery is low, or it gets too hot.",
            "Awake never changes your Energy settings.",
        ])
    ]

    static let shared = AwakeTool()
}

// MARK: - Color Picker Tool

struct ColorPickerTool: Tool {
    let id = "color-picker"
    let name = "Color Picker"
    let summary = "Pick and save colors from anywhere on screen"
    let description = "Pick any onscreen color, copy it instantly, and keep a compact searchable history of useful values."
    let icon = ToolGlyph.colorPicker.symbol
    let logoAsset = "ColorPickerLogo"
    let category = ToolCategory.dev
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Pick a color", steps: [
            Step("command", "Press ⇧⌘3, or click Pick Color."),
            Step("eyedropper", "Click any pixel on the screen."),
            Step("doc.on.clipboard", "The color is copied. It is HEX unless you change Copy format."),
            Step("clock.arrow.circlepath", "Open History to copy it again as RGB, HSL, CSS, SwiftUI, or NSColor."),
        ], keys: [
            Key(["⇧", "⌘", "3"], "Pick a color from anywhere"), Key(["esc"], "Stop picking"),
        ])
    ]

    static let shared = ColorPickerTool()
}

// MARK: - Text Extractor Tool

struct TextExtractorTool: Tool {
    let id = "text-extractor"
    let name = "Text Extractor"
    let summary = "Copy text from any part of the screen"
    let description = "Select text anywhere on screen and copy it using private, fully on-device Apple Vision recognition."
    let icon = ToolGlyph.textExtractor.symbol
    let logoAsset = "TextExtractorLogo"
    let category = ToolCategory.text
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Copy text", steps: [
            Step("command", "Press ⇧⌘2, or click Extract Text."),
            Step("rectangle.dashed", "Drag a box around the text on the screen."),
            Step("doc.on.clipboard", "Let go. The text is copied."),
            Step("lock.shield", "Allow Screen Recording the first time macOS asks."),
        ], keys: [
            Key(["⇧", "⌘", "2"], "Copy text from anywhere"), Key(["esc"], "Stop"),
        ], notes: [
            "The text is read on this Mac. The screen image is deleted right after.",
        ])
    ]

    static let shared = TextExtractorTool()
}

// MARK: - Input Devices Tool

struct InputDevicesTool: Tool {
    let id = "input-devices"
    let name = "Input Devices"
    let summary = "Separate mouse and trackpad scrolling"
    let description = "Tune mouse and trackpad scrolling independently, including direction, speed, horizontal movement, and wheel smoothing."
    let icon = ToolGlyph.inputDevices.symbol
    let logoAsset = "InputDevicesLogoA"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Scrolling", steps: [
            Step("switch.2", "Turn on Use custom scrolling."),
            Step("lock.shield", "Allow Accessibility when macOS asks."),
            Step("computermouse", "Set the mouse and the trackpad on their own: direction, speed, and sideways scrolling."),
            Step("wand.and.stars", "Turn on Smoothing to make a mouse wheel scroll smoothly."),
        ], notes: [
            "Input Devices changes only scrolling. It never records keys, clicks, or where the pointer goes.",
        ])
    ]

    static let shared = InputDevicesTool()
}

struct PortmanTool: Tool {
    let id = "portman"
    let name = "Portman"
    let summary = "See and stop processes that hold ports"
    let description = "See local development servers and forward private SSH ports to this Mac."
    let icon = ToolGlyph.portman.symbol
    let logoAsset = "PortmanLogo"
    let category = ToolCategory.dev
    let hasTrayTab = false

    let manual = [
        ToolManualSection(title: "Local servers", steps: [
            Step("menubar.rectangle", "Click Portman in the menu bar to see the dev servers that hold a port."),
            Step("cursorarrow.click", "Click a server to see its memory, CPU, and project."),
            Step("stop.circle", "Click Clean up to stop the servers you pick. It first shows how much memory you get back."),
        ], keys: [
            Key(["⌥", "⌘", "P"], "Open Portman"),
        ]),
        ToolManualSection(title: "SSH ports", steps: [
            Step("network", "Type an SSH host, or pick one from your SSH config, and scan it."),
            Step("checkmark.circle", "Pick the ports and the local port numbers."),
            Step("arrow.left.arrow.right", "Each port now opens on this Mac at 127.0.0.1."),
        ], notes: [
            "SSH uses your own keys. A tunnel ends when you stop it or quit MacPowerToys.",
        ])
    ]

    static let shared = PortmanTool()
}

struct MacTweaksTool: Tool {
    let id = "mac-tweaks"
    let name = "Mac Tweaks"
    let summary = "Hidden macOS settings with one switch each"
    let description = "Find and control small Mac settings, starting with Mic Lock for Bluetooth headphone sound."
    let icon = ToolGlyph.macTweaks.symbol
    let logoAsset = "MacTweaksLogo"
    let category = ToolCategory.system
    let searchKeywords = ["mic lock", "microphone", "bluetooth", "airpods", "audio input"]

    let manual = [
        ToolManualSection(title: "Change a setting", steps: [
            Step("sidebar.left", "Click Open Mac Tweaks, then pick a page such as Dock, Finder, or Input."),
            Step("slider.horizontal.3", "Change a control. It saves at once."),
            Step("arrow.clockwise", "For Dock and Finder changes, click Restart Dock or Restart Finder, or Later."),
            Step("arrow.uturn.backward", "Click the reset arrow next to a control to get the old value back."),
        ], keys: [
            Key(["⌘", "K"], "Search all settings"), Key(["esc"], "Clear the search"),
        ], notes: [
            "Mac Tweaks saves the old value before your first change, so every change can be undone.",
            "Some settings work only on some macOS versions. Those controls are read-only on other versions.",
        ]),
        ToolManualSection(title: "Mic Lock", steps: [
            Step("mic", "Open Input and turn on Mic Lock."),
            Step("list.number", "Pick your main microphone and up to three backups."),
            Step("headphones", "Now Bluetooth headphones no longer take over the microphone and lower the sound."),
            Step("waveform", "Click Test to check the level. Allow the microphone when macOS asks."),
        ], notes: [
            "If the sound breaks, click Revive Audio. macOS asks for your password, and sound in other apps can stop for a moment.",
        ])
    ]

    static let shared = MacTweaksTool()
}

// MARK: - Marketplace Tool

struct MarketplaceTool: Tool {
    let receipt: MarketplaceReceipt
    let iconFileURL: URL?

    var id: String { receipt.toolID }
    var name: String { receipt.name }
    var description: String { receipt.summary }
    var icon: String { "shippingbox" }
    var logoAsset: String { "" }
    var category: ToolCategory { receipt.category.toolCategory }
    var manual: [ToolManualSection] {
        receipt.manual.map { ToolManualSection(title: $0.title, steps: $0.points.map { OnePlusLinearChecklistStep("checkmark.circle", $0) }) }
    }
}

// MARK: - Available Tools

struct ToolRegistry {
    static let builtInTools: [any Tool] = [
        RcloneTool.shared,
        LogsTool.shared,
        RulerTool.shared,
        AwakeTool.shared,
        ColorPickerTool.shared,
        TextExtractorTool.shared,
        InputDevicesTool.shared,
        PortmanTool.shared,
        MacTweaksTool.shared
    ]

    static var allTools: [any Tool] {
        builtInTools + MarketplaceManager.shared.installedTools
    }

    static func tools(for category: ToolCategory) -> [any Tool] {
        if category == .all {
            return allTools
        }
        return allTools.filter { $0.category == category }
    }

    static func tool(for id: String) -> (any Tool)? {
        allTools.first { $0.id == id }
    }
}
