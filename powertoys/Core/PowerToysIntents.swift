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
    case ruler
    case awake
    case colorPicker
    case textExtractor

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "PowerToys Tool"

    static let caseDisplayRepresentations: [PowerToolTarget: DisplayRepresentation] = [
        .home: "PowerToys",
        .rsync: "Cloud Sync",
        .claudeHistory: "Claude History",
        .logs: "Logs",
        .ruler: "Ruler",
        .awake: "Awake",
        .colorPicker: "Color Picker",
        .textExtractor: "Text Extractor"
    ]

    var deepLinkId: String {
        switch self {
        case .home: return "main"
        case .rsync: return "rclone"
        case .claudeHistory: return "cc-history"
        case .logs: return "logs"
        case .ruler: return "ruler"
        case .awake: return "awake"
        case .colorPicker: return "color-picker"
        case .textExtractor: return "text-extractor"
        }
    }
}

struct OpenRulerIntent: AppIntent {
    static let title: LocalizedStringResource = "Ruler"
    static let description = IntentDescription("Opens the PowerToys Ruler controls.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerOpen))
        return .result()
    }
}

struct OpenAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Awake"
    static let description = IntentDescription("Opens PowerToys Awake controls.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        ToolActionRouter.shared.execute(ToolActionRequest(action: .awakeOpen))
        return .result()
    }
}

struct PickColorIntent: AppIntent {
    static let title: LocalizedStringResource = "Color Picker"
    static let description = IntentDescription("Picks and copies an onscreen color.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        ToolActionRouter.shared.execute(ToolActionRequest(action: .colorPickerPick))
        return .result()
    }
}

struct ExtractTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Text Extractor"
    static let description = IntentDescription("Selects onscreen text and copies it using local recognition.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorCapture))
        return .result()
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
    static let title: LocalizedStringResource = "Open Cloud Sync"
    static let description = IntentDescription("Opens the Cloud Sync file transfer tool.")
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
            phrases: ["Open Cloud Sync in \(.applicationName)", "Start a transfer in \(.applicationName)"],
            shortTitle: "Open Cloud Sync",
            systemImageName: "arrow.up.arrow.down.circle"
        )
        AppShortcut(
            intent: OpenClaudeHistoryIntent(),
            phrases: ["Open Claude History in \(.applicationName)", "Browse conversations in \(.applicationName)"],
            shortTitle: "Claude History",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: OpenRulerIntent(),
            phrases: ["Open Ruler in \(.applicationName)", "Measure with \(.applicationName)"],
            shortTitle: "Ruler",
            systemImageName: "ruler"
        )
        AppShortcut(
            intent: OpenAwakeIntent(),
            phrases: ["Open Awake in \(.applicationName)"],
            shortTitle: "Awake",
            systemImageName: "cup.and.saucer"
        )
        AppShortcut(
            intent: PickColorIntent(),
            phrases: ["Pick a color with \(.applicationName)"],
            shortTitle: "Color Picker",
            systemImageName: "eyedropper"
        )
        AppShortcut(
            intent: ExtractTextIntent(),
            phrases: ["Extract text with \(.applicationName)"],
            shortTitle: "Text Extractor",
            systemImageName: "text.viewfinder"
        )
    }
}
