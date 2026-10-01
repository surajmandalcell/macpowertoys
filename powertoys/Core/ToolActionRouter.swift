import AppKit
import Foundation
import SwiftUI
import OnePlusUI
import QuartzCore

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
    case portmanOpen = "portman.open"

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
    var activateApp = true
}

extension Notification.Name {
    static let toolActionRequested = Notification.Name("toolActionRequested")
}

struct ToolLaunchFailure: Identifiable, Equatable, Sendable {
    let id = UUID()
    let toolID: String
    let message: String
}

@Observable
@MainActor
final class ToolActionRouter {
    static let shared = ToolActionRouter()
    private static let maximumPendingCount = 32

    private var openWindowAction: OpenWindowAction?
    private var pending: [ToolActionRequest] = []
    private var pendingToolOpens: [(id: String, activateApp: Bool)] = []
    @ObservationIgnored private var backgroundWindows: [String: NSWindow] = [:]
    var launchFailure: ToolLaunchFailure?

    private init() {}

    func configure(openWindow: OpenWindowAction) {
        openWindowAction = openWindow
        let requests = pending
        pending.removeAll()
        requests.forEach(execute)
        let toolOpens = pendingToolOpens
        pendingToolOpens.removeAll()
        toolOpens.forEach { open(toolID: $0.id, activateApp: $0.activateApp) }
    }

    private static let windowAliases: [String: String] = [
        "cloud-sync": "rclone",
        "cloudsync": "rclone",
        "rsync": "rclone",
        "power-stats": "system-monitor",
        "settings": "main",
        "home": "main"
    ]

    func open(toolID: String, page: String?, activateApp: Bool = true) {
        guard let page else { open(toolID: toolID, activateApp: activateApp); return }
        let resolved = Self.resolvedWindowID(toolID)
        guard resolved == "main" || (SettingsManager.shared.isToolEnabled(resolved)
            && ToolRegistry.builtInTools.contains(where: { $0.id == resolved })) else { return }
        ToolPageRouter.shared.post(tool: resolved, page: page)
        open(toolID: resolved, activateApp: activateApp)
    }

    func open(toolID: String, activateApp: Bool = true) {
        let resolved = Self.resolvedWindowID(toolID)
        guard resolved == "main" || SettingsManager.shared.isToolEnabled(resolved) else {
            LogManager.shared.info("Ignored disabled tool: \(resolved)", source: "ToolActionRouter")
            return
        }
        if resolved == "ruler" {
            execute(ToolActionRequest(action: .rulerOpen, activateApp: activateApp))
            return
        }

        if resolved == "portman" {
            PortmanMenuController.shared.show(activateApp: activateApp)
            dismissMainWindowAfterToolOpen()
            return
        }

        if resolved == "main" || ToolRegistry.builtInTools.contains(where: { $0.id == resolved }) {
            if !OnePlusPanelTimings.shared.hasPending("window.\(resolved)") {
                OnePlusPanelTimings.shared.begin(panel: "window.\(resolved)", operation: .windowOpen, input: "tool-router")
            }
            guard let openWindowAction else {
                if pendingToolOpens.last?.id != resolved || pendingToolOpens.last?.activateApp != activateApp {
                    if pendingToolOpens.count == Self.maximumPendingCount { pendingToolOpens.removeFirst() }
                    pendingToolOpens.append((resolved, activateApp))
                }
                return
            }
            Self.presentSingleWindow(id: resolved, windows: NSApp.windows, activateApp: activateApp,
                createWindow: { id in
                    let window = MacPowerToysApp.makeBackgroundWindow(id: id)
                    self.backgroundWindows[id] = window
                    return window
                }, activate: { NSApp.activate(ignoringOtherApps: true) }) { openWindowAction(id: $0) }
            if resolved != "main" { dismissMainWindowAfterToolOpen() }
        } else {
            Task {
                await MarketplaceManager.shared.restore()
                guard SettingsManager.shared.isToolEnabled(resolved) else { return }
                guard MarketplaceManager.shared.receipts.contains(where: { $0.toolID == resolved }) else {
                    LogManager.shared.warning("Unknown tool ID: \(resolved)", source: "ToolActionRouter")
                    return
                }
                if launchFailure?.toolID == resolved { launchFailure = nil }
                do {
                    try await MarketplaceManager.shared.launchInstalledTool(toolID: resolved, activateApp: activateApp)
                    dismissMainWindowAfterToolOpen()
                } catch {
                    launchFailure = ToolLaunchFailure(toolID: resolved, message: error.localizedDescription)
                    LogManager.shared.error(
                        "Failed to launch marketplace tool \(resolved): \(error)",
                        source: "ToolActionRouter"
                    )
                }
            }
        }
    }

    static func resolvedWindowID(_ toolID: String) -> String {
        windowAliases[toolID] ?? toolID
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
            if pending.last != request {
                if pending.count == Self.maximumPendingCount { pending.removeFirst() }
                pending.append(request)
            }
            return
        }

        if request.action == .portmanOpen {
            open(toolID: "portman", activateApp: request.activateApp)
            return
        }

        // Screen selectors take input. Background URLs can only open their applet.
        if !request.activateApp,
           request.action == .colorPickerPick || request.action == .textExtractorCapture {
            open(toolID: request.action.toolID, activateApp: false)
            return
        }

        if request.action.opensWindow {
            open(toolID: request.action.toolID, activateApp: request.activateApp)
        }

        if request.action == .rulerOpen {
            OnePlusPanelTimings.shared.begin(panel: "window.ruler", operation: .windowOpen, input: "tool-router")
        }
        var userInfo: [String: Any] = request.parameters
        userInfo["activateApp"] = request.activateApp
        NotificationCenter.default.post(
            name: .toolActionRequested,
            object: request.action,
            userInfo: userInfo
        )
        if request.action == .rulerOpen {
            dismissMainWindowAfterToolOpen()
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first(where: {
                    $0.identifier?.rawValue == "ruler-window" && $0.isVisible
                }) else { OnePlusPanelTimings.shared.cancel(panel: "window.ruler"); return }
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                CATransaction.flush()
                OnePlusPanelTimings.shared.finish(panel: "window.ruler", tab: nil,
                                                  size: window.contentView?.frame.size ?? .zero)
            }
        }
    }

    static func presentSingleWindow(id: String, windows: [NSWindow],
                                    activateApp: Bool, createWindow: (String) -> NSWindow?,
                                    activate: () -> Void, openWindow: (String) -> Void) {
        let existing = windows.first(where: {
            Self.windowIdentifier($0.identifier?.rawValue, matches: id)
        })
        if existing == nil, activateApp {
            openWindow(id)
            activate()
            return
        }
        guard let window = existing ?? createWindow(id) else { return }
        window.onePlusPrepareForOpening()
        if activateApp {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            activate()
        } else {
            // Deminiaturizing also makes a window key; leave it to an explicit open.
            window.orderFrontRegardless()
        }
    }

    private func dismissMainWindowAfterToolOpen() {
        Self.finishToolOpen {
            NSApp.windows.first(where: {
                Self.windowIdentifier($0.identifier?.rawValue, matches: "main")
            })?.close()
        }
    }

    static func finishToolOpen(defaults: UserDefaults = .standard, dismissMainWindow: () -> Void) {
        guard defaults.bool(forKey: "app.closeMainWindowAfterOpeningTool") else { return }
        dismissMainWindow()
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
        return ToolActionRequest(action: action, parameters: parameters, activateApp: false)
    }
}
