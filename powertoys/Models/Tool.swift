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
    var category: ToolCategory { get }
    var capabilities: ToolCapabilities { get }
    var isEnabled: Bool { get set }
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

// MARK: - CC History Tool

struct CCHistoryTool: Tool {
    let id = "cc-history"
    let name = "CC History"
    let description = "View Claude Code conversation history."
    let icon = "text.bubble"
    let category = ToolCategory.dev
    let capabilities: ToolCapabilities = [.hasWindow]
    var isEnabled: Bool = true

    static let shared = CCHistoryTool()
}

// MARK: - Logs Tool

struct LogsTool: Tool {
    let id = "logs"
    let name = "Logs"
    let description = "View application logs and diagnostics."
    let icon = "doc.text.magnifyingglass"
    let category = ToolCategory.system
    let capabilities: ToolCapabilities = [.hasWindow]
    var isEnabled: Bool = true

    static let shared = LogsTool()
}

// MARK: - Available Tools

struct ToolRegistry {
    static let allTools: [any Tool] = [
        CCHistoryTool.shared,
        LogsTool.shared
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
