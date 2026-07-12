//
//  PowerToysIntents.swift
//  powertoys
//

import AppIntents
import Foundation

enum PowerToolTarget: String, AppEnum {
    case home
    case rsync
    case claudeHistory
    case logs

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "PowerToys Tool"

    static let caseDisplayRepresentations: [PowerToolTarget: DisplayRepresentation] = [
        .home: "PowerToys",
        .rsync: "RSync",
        .claudeHistory: "Claude History",
        .logs: "Logs"
    ]

    var deepLinkId: String {
        switch self {
        case .home: return "main"
        case .rsync: return "rclone"
        case .claudeHistory: return "cc-history"
        case .logs: return "logs"
        }
    }
}

struct OpenToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Open PowerToys Tool"
    static let description = IntentDescription("Opens a PowerToys tool window.")
    static let openAppWhenRun = true

    @Parameter(title: "Tool", default: .home)
    var tool: PowerToolTarget

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "powertoys://open/\(tool.deepLinkId)") {
            DeepLinkHandler.shared.handle(url: url)
        }
        return .result()
    }
}

struct OpenRSyncIntent: AppIntent {
    static let title: LocalizedStringResource = "Open RSync"
    static let description = IntentDescription("Opens the RSync file transfer tool.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "powertoys://open/rclone") {
            DeepLinkHandler.shared.handle(url: url)
        }
        return .result()
    }
}

struct OpenClaudeHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Claude History"
    static let description = IntentDescription("Opens the Claude History conversation browser.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "powertoys://open/cc-history") {
            DeepLinkHandler.shared.handle(url: url)
        }
        return .result()
    }
}

struct PowerToysShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenToolIntent(),
            phrases: ["Open \(\.$tool) in \(.applicationName)"],
            shortTitle: "Open Tool",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: OpenRSyncIntent(),
            phrases: ["Open RSync in \(.applicationName)", "Start a transfer in \(.applicationName)"],
            shortTitle: "Open RSync",
            systemImageName: "arrow.up.arrow.down.circle"
        )
        AppShortcut(
            intent: OpenClaudeHistoryIntent(),
            phrases: ["Open Claude History in \(.applicationName)", "Browse conversations in \(.applicationName)"],
            shortTitle: "Claude History",
            systemImageName: "text.bubble"
        )
    }
}
