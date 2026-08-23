//
//  Tool.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation

// MARK: - Tool Protocol

protocol Tool: Identifiable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var icon: String { get }
    var logoAsset: String { get }
    var iconFileURL: URL? { get }
    var category: ToolCategory { get }
    var manual: [ToolManualSection] { get }
    var hasTrayTab: Bool { get }
}

extension Tool {
    var hasTrayTab: Bool { false }
    var iconFileURL: URL? { nil }
}

// MARK: - Manual

struct ToolManualSection: Identifiable {
    let title: String
    let points: [String]

    var id: String { title }
}

// MARK: - Tool Category

enum ToolCategory: String, CaseIterable, Identifiable {
    case all = "All Tools"
    case dev = "Developer"
    case text = "Text"
    case files = "Files"
    case system = "System"

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

// MARK: - Claude History Tool

struct CCHistoryTool: Tool {
    let id = "cc-history"
    let name = "Claude History"
    let description = "Browse every Claude Code conversation on this Mac — live, searchable, and bookmarkable."
    let icon = "text.bubble"
    let logoAsset = "ClaudeHistoryLogo"
    let category = ToolCategory.dev

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Browsing", points: [
            "Sessions are read from ~/.claude/projects and grouped by project.",
            "Click a session to open it. New messages stream in live while Claude Code is running.",
            "Right-click a session to bookmark it or copy its ID and log path."
        ]),
        ToolManualSection(title: "Search & Filters", points: [
            "The sidebar search matches session titles. Enable deep search to scan message content too.",
            "Use the User, Claude, and Tools toggles above a conversation to choose what is visible.",
            "⌘F searches within the open conversation. ⌘⇧F searches across everything."
        ]),
        ToolManualSection(title: "Copy & Panels", points: [
            "Select messages and press ⌘C to copy them in your preferred format.",
            "Click a tool icon in a message to inspect its input and output in the side panel.",
            "Press ⌘, inside the window for auto-refresh, deep search, and cache options."
        ])
    ]

    static let shared = CCHistoryTool()
}

// MARK: - Cloud Sync Tool

struct RcloneTool: Tool {
    let id = "rclone"
    let name = "Cloud Sync"
    let description = "Move files between your Mac and cloud storage with live progress, automatic retries, and ignore rules."
    let icon = "arrow.up.arrow.down.circle"
    let logoAsset = "CloudSyncLogo"
    let category = ToolCategory.files
    let hasTrayTab = true

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Connect Cloud Storage", points: [
            "Click + next to Remotes in the Cloud Sync sidebar.",
            "Choose any connector offered by your installed rclone version, enter its required settings, and press Connect.",
            "For OAuth connectors, complete the provider's browser sign-in. rclone stores and refreshes the resulting credentials."
        ]),
        ToolManualSection(title: "Transfers", points: [
            "Press ⌘N or click New Transfer.",
            "Copy adds and updates files. Sync mirrors the source exactly, deleting extras. Move removes files from the source.",
            "Watch overall and per-file progress live. Failed transfers retry automatically with backoff."
        ]),
        ToolManualSection(title: "Browse & Preview", points: [
            "Click a remote in the sidebar to browse its files.",
            "Double-click folders to navigate. Press Space or click the eye to Quick Look a file.",
            "Drag files out to your Mac to download them, or drop local files into the folder to upload."
        ]),
        ToolManualSection(title: "Activity & Details", points: [
            "Every finished transfer is recorded in Activity with sizes and timing.",
            "Click ⓘ on any transfer for its full details — paths, ignore rules, speed, attempts, and errors."
        ]),
        ToolManualSection(title: "Ignore Rules & Limits", points: [
            "Open Settings from the sidebar (⌘,) to edit ignore patterns — one glob per line, applied to every transfer.",
            "System junk like .DS_Store, .fseventsd, and System Volume Information is ignored by default.",
            "Parallel transfers, bandwidth limits, and retry counts live on the same page."
        ])
    ]

    static let shared = RcloneTool()
}

// MARK: - Logs Tool

struct LogsTool: Tool {
    let id = "logs"
    let name = "Logs"
    let description = "Inspect MacPowerToys activity and recent macOS errors and faults in clearly separated views."
    let icon = "doc.text.magnifyingglass"
    let logoAsset = "LogsLogo"
    let category = ToolCategory.system

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Reading Logs", points: [
            "Internal Logs contains MacPowerToys errors, warnings, info, and debug messages.",
            "System Issues reads recent macOS errors and faults on demand without saving them in the app.",
            "Choose a source in the sidebar, then filter internal levels or search messages and sources.",
            "Log text is fully selectable for copying into bug reports."
        ]),
        ToolManualSection(title: "Housekeeping", points: [
            "Internal logs are kept for two days, then pruned automatically.",
            "Clear Internal Logs empties the app's in-memory view.",
            "System Issues keeps at most 500 rows in memory and fetches them again when requested.",
            "Press ⌘, inside the window to change the log font size."
        ])
    ]

    static let shared = LogsTool()
}

// MARK: - Ruler Tool

struct RulerTool: Tool {
    let id = "ruler"
    let name = "Ruler"
    let description = "Measure the screen with movable, resizable rulers in pixels, millimeters, or inches."
    let icon = "ruler"
    let logoAsset = "RulerLogo"
    let category = ToolCategory.dev

    let manual = [
        ToolManualSection(title: "Rulers", points: [
            "Drag a ruler to move it and drag an end or corner to resize it.",
            "Press ⌘N for another ruler. Use H or V to show or hide a wing, and ⌘` to cycle rulers.",
            "Use U for units, F for floating, S for shadow, G for grouping, and O to align at the pointer."
        ]),
        ToolManualSection(title: "Settings", points: [
            "Press ⌘, to edit the active ruler. Press ⌥⌘, to edit defaults for new rulers.",
            "Choose color, foreground and background opacity, dimensions, float, and shadow."
        ])
    ]

    static let shared = RulerTool()
}

// MARK: - Awake Tool

struct AwakeTool: Tool {
    let id = "awake"
    let name = "Awake"
    let description = "Keep your Mac awake indefinitely, for a duration, or until a chosen time without changing Energy settings."
    let icon = "cup.and.saucer"
    let logoAsset = "AwakeLogo"
    let category = ToolCategory.system
    let hasTrayTab = true

    let manual = [
        ToolManualSection(title: "Modes", points: [
            "Passive uses normal macOS power settings. Indefinite remains active until disabled.",
            "Timed mode counts down for a duration. Until mode expires at a specific date and time.",
            "Keep Display On is independent and only applies while an active Awake mode is selected."
        ]),
        ToolManualSection(title: "System Behavior", points: [
            "Awake uses macOS power assertions and never edits your Energy settings.",
            "Manual sleep, closing a MacBook lid, low power, and thermal protection still take precedence."
        ])
    ]

    static let shared = AwakeTool()
}

// MARK: - Color Picker Tool

struct ColorPickerTool: Tool {
    let id = "color-picker"
    let name = "Color Picker"
    let description = "Pick any onscreen color, copy it instantly, and keep a compact searchable history of useful values."
    let icon = "eyedropper"
    let logoAsset = "ColorPickerLogo"
    let category = ToolCategory.dev

    let manual = [
        ToolManualSection(title: "Pick and Copy", points: [
            "Press Pick Color to start the native macOS sampler immediately.",
            "The selected color is copied in your default format and saved to history.",
            "Open Color History to copy HEX, RGB, HSL, CSS, SwiftUI, or NSColor representations."
        ])
    ]

    static let shared = ColorPickerTool()
}

// MARK: - Text Extractor Tool

struct TextExtractorTool: Tool {
    let id = "text-extractor"
    let name = "Text Extractor"
    let description = "Select text anywhere on screen and copy it using private, fully on-device Apple Vision recognition."
    let icon = "text.viewfinder"
    let logoAsset = "TextExtractorLogo"
    let category = ToolCategory.text

    let manual = [
        ToolManualSection(title: "Extract Text", points: [
            "Press Extract Text, drag around a screen region, and release to recognize and copy its text.",
            "Vision performs recognition locally. Captured pixels are discarded after processing.",
            "Screen Recording permission is required because macOS protects pixels belonging to other applications."
        ])
    ]

    static let shared = TextExtractorTool()
}

// MARK: - Input Devices Tool

struct InputDevicesTool: Tool {
    let id = "input-devices"
    let name = "Input Devices"
    let description = "Tune mouse and trackpad scrolling independently, including direction, speed, horizontal movement, and wheel smoothing."
    let icon = "computermouse"
    var logoAsset: String {
        guard let data = UserDefaults.standard.data(forKey: "inputDevices.settings"),
              let settings = try? JSONDecoder().decode(InputDevicesSettings.self, from: data) else {
            return "InputDevicesLogoA"
        }
        return settings.iconAsset
    }
    let category = ToolCategory.system

    let manual = [
        ToolManualSection(title: "Profiles", points: [
            "Mouse-like wheel events and precise trackpad events have separate controls.",
            "Reverse either axis, change speed, disable horizontal motion, or smooth coarse mouse-wheel steps.",
            "Automatic classification uses macOS event precision because public scroll events do not expose a physical device identifier."
        ]),
        ToolManualSection(title: "Permission", points: [
            "Enable Input Control and grant Accessibility permission when macOS asks.",
            "Input Devices changes only scroll events. It does not record keys, clicks, or pointer movement."
        ])
    ]

    static let shared = InputDevicesTool()
}

// MARK: - System Care Tool

struct SystemCareTool: Tool {
    let id = "system-care"
    let name = "System Care"
    let description = "Understand storage, preview safe cleanup, remove apps, and access advanced Mole maintenance without hidden privilege prompts."
    let icon = "sparkles"
    let logoAsset = "SystemCareLogo"
    let category = ToolCategory.system

    let manual = [
        ToolManualSection(title: "Storage and Cleanup", points: [
            "Choose a folder in Storage to see its largest contents and drill into any directory.",
            "Quick Cleanup scans supported rebuildable data. Guided Cleanup lets you choose categories. Analysis Only cannot clean.",
            "Review every selected item before moving it to macOS Trash."
        ]),
        ToolManualSection(title: "Mole CLI", points: [
            "Mole CLI is an optional attributed external dependency and is not bundled with MacPowerToys.",
            "Structured analysis and history appear natively. Interactive or privileged operations open in Terminal.",
            "MacPowerToys never collects a sudo password."
        ])
    ]

    static let shared = SystemCareTool()
}

// MARK: - Power Stats Tool

struct PowerStatsTool: Tool {
    let id = "power-stats"
    let name = "Power Stats"
    let description = "Watch CPU, memory, disk, network, battery, and thermal health on demand, with an optional lightweight menu-bar summary."
    let icon = "gauge.with.dots.needle.50percent"
    let logoAsset = "PowerStatsLogo"
    let category = ToolCategory.system

    let manual = [
        ToolManualSection(title: "Detailed Monitoring", points: [
            "Open Power Stats to start the one-second detailed sampler and bounded two-minute history.",
            "Closing the window stops disk, battery, thermal, load, and history collection.",
            "All displayed metrics use documented public macOS APIs."
        ]),
        ToolManualSection(title: "Menu Bar", points: [
            "Enable a grouped summary or individual CPU, memory, and network items.",
            "Choose a 1, 2, 3, or 5 second interval. Disabling the menu item stops its timer completely."
        ])
    ]

    static let shared = PowerStatsTool()
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
        receipt.manual.map { ToolManualSection(title: $0.title, points: $0.points) }
    }
}

// MARK: - Available Tools

struct ToolRegistry {
    static let builtInTools: [any Tool] = [
        CCHistoryTool.shared,
        RcloneTool.shared,
        LogsTool.shared,
        RulerTool.shared,
        AwakeTool.shared,
        ColorPickerTool.shared,
        TextExtractorTool.shared,
        InputDevicesTool.shared,
        SystemCareTool.shared,
        PowerStatsTool.shared
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
