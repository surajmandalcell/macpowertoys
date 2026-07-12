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
    var capabilities: ToolCapabilities { get }
    var manual: [ToolManualSection] { get }
    var hasTrayTab: Bool { get }
    var isEnabled: Bool { get set }
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
    let capabilities: ToolCapabilities = [.hasWindow]
    var isEnabled: Bool = true

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

// MARK: - RSync Tool

struct RcloneTool: Tool {
    let id = "rclone"
    let name = "RSync"
    let description = "Move files between your Mac and cloud storage with live progress, automatic retries, and ignore rules."
    let icon = "arrow.up.arrow.down.circle"
    let logoAsset = "CloudSyncLogo"
    let category = ToolCategory.files
    let capabilities: ToolCapabilities = [.hasWindow]
    let hasTrayTab = true
    var isEnabled: Bool = true

    let manual: [ToolManualSection] = [
        ToolManualSection(title: "Connect Google Drive", points: [
            "Click + next to Remotes in the RSync sidebar.",
            "Pick a name and press Connect — your browser opens to sign in with Google.",
            "Approve access and the remote appears immediately. Tokens refresh automatically from then on."
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
    let capabilities: ToolCapabilities = [.hasWindow]
    var isEnabled: Bool = true

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

// MARK: - Available Tools

struct ToolRegistry {
    static let allTools: [any Tool] = [
        CCHistoryTool.shared,
        RcloneTool.shared
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
