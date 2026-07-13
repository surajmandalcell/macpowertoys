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
    var category: ToolCategory { get }
    var manual: [ToolManualSection] { get }
    var hasTrayTab: Bool { get }
}

extension Tool {
    var hasTrayTab: Bool { false }
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
    let description = "View application logs and diagnostics."
    let icon = "doc.text.magnifyingglass"
    let logoAsset = "LogsLogo"
    let category = ToolCategory.system

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Reading Logs", points: [
            "Every tool reports here — errors, warnings, info, and debug messages.",
            "Filter by level in the sidebar, or search across messages and sources.",
            "Log text is fully selectable for copying into bug reports."
        ]),
        ToolManualSection(title: "Housekeeping", points: [
            "Logs are kept for two days, then pruned automatically.",
            "Clear Logs empties the in-memory view.",
            "Press ⌘, inside the window to change the log font size."
        ])
    ]

    static let shared = LogsTool()
}

// MARK: - Ruler Tool

struct RulerTool: Tool {
    let id = "ruler"
    let name = "Ruler"
    let description = "Measure layouts across displays with floating rulers, guides, calibrated units, and developer-friendly copy formats."
    let icon = "ruler"
    let logoAsset = "RulerLogo"
    let category = ToolCategory.dev

    let manual = [
        ToolManualSection(title: "Rulers", points: [
            "Create horizontal, vertical, or joined rulers and keep as many visible as you need.",
            "Drag the body to move a ruler. Drag its highlighted end or corner to resize it.",
            "Choose points, backing pixels, millimeters, or inches without confusing Retina points with pixels."
        ]),
        ToolManualSection(title: "Developer Copy", points: [
            "Copy dimensions as plain text, CSS, SwiftUI, CGRect, or JSON.",
            "Use the cursor marker, zero-corner controls, aspect presets, and measurement pins for repeatable checks."
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

// MARK: - Available Tools

struct ToolRegistry {
    static let allTools: [any Tool] = [
        CCHistoryTool.shared,
        RcloneTool.shared,
        LogsTool.shared,
        RulerTool.shared,
        AwakeTool.shared,
        ColorPickerTool.shared,
        TextExtractorTool.shared
    ]

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
