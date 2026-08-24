import AppKit
import Foundation
import SwiftUI

enum ToolActionID: String, CaseIterable, Codable, Sendable {
    case rulerOpen = "ruler.open"
    case rulerSettings = "ruler.settings"
    case awakeOpen = "awake.open"
    case awakeToggle = "awake.toggle"
    case awakeIndefinite = "awake.indefinite"
    case awakeTimed = "awake.timed"
    case awakeUntil = "awake.until"
    case colorPickerPick = "color-picker.pick"
    case colorPickerHistory = "color-picker.history"
    case colorPickerCopyLast = "color-picker.copy-last"
    case textExtractorCapture = "text-extractor.capture"
    case textExtractorOpen = "text-extractor.open"

    var toolID: String {
        rawValue.split(separator: ".").first.map(String.init) ?? rawValue
    }

    var opensWindow: Bool {
        switch self {
        case .awakeOpen, .colorPickerHistory, .textExtractorOpen:
            true
        default:
            false
        }
    }
}

struct ToolActionRequest: Equatable, Sendable {
    let action: ToolActionID
    var parameters: [String: String] = [:]
}

extension Notification.Name {
    static let toolActionRequested = Notification.Name("toolActionRequested")
}

@Observable
@MainActor
final class ToolActionRouter {
    static let shared = ToolActionRouter()

    private var openWindowAction: OpenWindowAction?
    private var pending: [ToolActionRequest] = []
    private var pendingToolOpens: [String] = []

    private init() {}

    func configure(openWindow: OpenWindowAction) {
        openWindowAction = openWindow
        let requests = pending
        pending.removeAll()
        requests.forEach(execute)
        let toolOpens = pendingToolOpens
        pendingToolOpens.removeAll()
        toolOpens.forEach { open(toolID: $0) }
    }

    private static let windowAliases: [String: String] = [
        "cchistory": "cc-history",
        "cloud-sync": "rclone",
        "cloudsync": "rclone",
        "rsync": "rclone",
        "settings": "main",
        "home": "main"
    ]

    func open(toolID: String) {
        let resolved = Self.windowAliases[toolID] ?? toolID
        guard resolved == "main" || SettingsManager.shared.isToolEnabled(resolved) else {
            LogManager.shared.info("Ignored disabled tool: \(resolved)", source: "ToolActionRouter")
            return
        }
        if resolved == "ruler" {
            execute(ToolActionRequest(action: .rulerOpen))
            dismissMainWindow()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if resolved == "main" || ToolRegistry.builtInTools.contains(where: { $0.id == resolved }) {
            guard let openWindowAction else {
                if pendingToolOpens.last != resolved { pendingToolOpens.append(resolved) }
                return
            }
            presentSingleWindow(id: resolved, using: openWindowAction)
            if resolved != "main" { dismissMainWindow() }
            NSApp.activate(ignoringOtherApps: true)
        } else if MarketplaceManager.shared.receipts.contains(where: { $0.toolID == resolved }) {
            Task {
                do {
                    try await MarketplaceManager.shared.launchInstalledTool(toolID: resolved)
                } catch {
                    LogManager.shared.error(
                        "Failed to launch marketplace tool \(resolved): \(error)",
                        source: "ToolActionRouter"
                    )
                }
            }
        } else {
            LogManager.shared.warning("Unknown tool ID: \(resolved)", source: "ToolActionRouter")
        }
    }

    func execute(_ request: ToolActionRequest) {
        guard SettingsManager.shared.isToolEnabled(request.action.toolID) else {
            LogManager.shared.info(
                "Ignored action for disabled tool: \(request.action.rawValue)",
                source: "ToolActionRouter"
            )
            return
        }
        guard openWindowAction != nil else {
            if pending.last != request { pending.append(request) }
            return
        }

        if request.action.opensWindow {
            if let openWindowAction {
                presentSingleWindow(id: request.action.toolID, using: openWindowAction)
            }
            NSApp.activate(ignoringOtherApps: true)
        }

        NotificationCenter.default.post(
            name: .toolActionRequested,
            object: request.action,
            userInfo: request.parameters
        )
    }

    private func presentSingleWindow(id: String, using openWindow: OpenWindowAction) {
        if let window = NSApp.windows.first(where: {
            Self.windowIdentifier($0.identifier?.rawValue, matches: id)
        }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(id: id)
    }

    private func dismissMainWindow() {
        NSApp.windows.first(where: {
            Self.windowIdentifier($0.identifier?.rawValue, matches: "main")
        })?.close()
    }

    nonisolated static func windowIdentifier(_ identifier: String?, matches toolID: String) -> Bool {
        guard toolID != "ruler", let identifier else { return false }
        return identifier == toolID || identifier.hasPrefix("\(toolID)-")
    }

    func execute(url: URL) -> Bool {
        guard let request = Self.request(from: url) else { return false }
        execute(request)
        return true
    }

    nonisolated static func request(from url: URL) -> ToolActionRequest? {
        guard DeepLinkHandler.isSupportedScheme(url.scheme), url.host == "run" else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let value = components.first,
              let action = ToolActionID(rawValue: value.replacingOccurrences(of: "/", with: "."))
        else { return nil }

        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { result, item in
                if let value = item.value { result[item.name] = value }
            } ?? [:]
        return ToolActionRequest(action: action, parameters: parameters)
    }
}
