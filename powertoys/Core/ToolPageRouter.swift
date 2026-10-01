import AppKit
import SwiftUI
import OnePlusUI

nonisolated struct OpenToolRoute: Equatable, Sendable {
    let tool: String
    let page: String?

    static func parse(_ url: URL) -> Self? {
        guard DeepLinkHandler.isSupportedScheme(url.scheme), url.host == "open",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else { return nil }
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              path.hasPrefix("/"), path.utf8.count <= 8_192 else { return nil }
        var values: [String] = []
        for part in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            guard let value = String(part).removingPercentEncoding,
                  !value.isEmpty, value != ".", value != "..", value.utf8.count <= 255,
                  !value.contains("/"), !value.contains("\\"),
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            values.append(value)
        }
        guard let tool = values.first, tool.utf8.count <= 80, tool.utf8.allSatisfy({
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45
        }) else { return nil }
        // Bound the decoded page, while allowing any number of path segments.
        let page = values.dropFirst().joined(separator: "/")
        guard page.utf8.count <= 2_048 else { return nil }
        return Self(tool: tool, page: values.count > 1 ? page : nil)
    }
}

nonisolated struct ToolPageRequest: Equatable, Sendable {
    let tool: String
    let page: String

    var opensSheet: Bool {
        switch (tool, page) {
        case ("rclone", "new-transfer"), ("switch", "add"), ("disk-explorer", "choose-folder"): true
        default: false
        }
    }
}

extension Notification.Name {
    static let openToolPage = Notification.Name("openToolPage")
}

@MainActor
final class ToolPageRouter {
    static let shared = ToolPageRouter()
    private var pending: [String: ToolPageRequest] = [:]

    func post(tool: String, page: String, recordTiming: Bool = true) {
        if recordTiming {
            OnePlusPanelTimings.shared.begin(panel: "page.\(tool)", operation: .pageSwitch,
                                            tab: page, input: "page-router")
        }
        let request = ToolPageRequest(tool: tool, page: page)
        pending[tool] = request
        NotificationCenter.default.post(name: .openToolPage, object: request,
                                        userInfo: ["tool": tool, "page": page])
    }

    func take(tool: String, matching page: String? = nil, allowSheet: Bool = true) -> ToolPageRequest? {
        guard let request = pending[tool], page == nil || page == request.page,
              allowSheet || !request.opensSheet else { return nil }
        pending[tool] = nil
        return request
    }
}

private struct OpenToolPageModifier: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive
    let tool: String?
    let page: String?
    let action: (String) -> Void

    private func deliver() {
        guard let tool else { return }
        if let request = ToolPageRouter.shared.take(tool: tool, matching: page,
                                                    allowSheet: appearsActive && NSApp.isActive) {
            action(request.page)
        }
    }

    func body(content: Content) -> some View {
        content.onAppear(perform: deliver)
            .onChange(of: appearsActive) { _, active in if active { deliver() } }
            .onReceive(NotificationCenter.default.publisher(for: .openToolPage)) { notification in
                guard (notification.object as? ToolPageRequest)?.tool == tool else { return }
                deliver()
            }
    }
}

extension View {
    func onToolWindowURL(_ tool: String) -> some View {
        onePlusWindowTimings(tool)
            .handlesExternalEvents(preferring: [], allowing: [])
            .onOpenURL { DeepLinkHandler.shared.handle(url: $0) }
    }

    func onOpenToolPage(_ tool: String?, matching page: String? = nil,
                        perform action: @escaping (String) -> Void) -> some View {
        modifier(OpenToolPageModifier(tool: tool, page: page, action: action))
    }
}

private struct ToolWindowIDKey: EnvironmentKey { static let defaultValue = "" }
extension EnvironmentValues {
    var toolWindowID: String {
        get { self[ToolWindowIDKey.self] }
        set { self[ToolWindowIDKey.self] = newValue }
    }
}

nonisolated enum DiagnosticsPanel: String, CaseIterable, Sendable {
    case main, systemMonitor = "system-monitor", portman

    nonisolated static func parse(_ url: URL) -> Self? {
        guard case .openPanel(let panel, _) = DiagnosticsRoute.parse(url) else { return nil }
        return panel
    }

    @MainActor
    func selectTab(_ id: String?, defaults: UserDefaults = .standard) {
        guard let id else { return }
        switch self {
        case .main:
            guard let tab = TrayTab(panelID: id), tab.panelID == id,
                  tab == .home || TrayPopoverLayout.defaultComplexTabs.contains(tab) else { return }
            if defaults.string(forKey: "tray.selectedTab.v2") != tab.rawValue {
                defaults.set(tab.rawValue, forKey: "tray.selectedTab.v2")
            }
        case .systemMonitor:
            guard let page = SystemMonitorTrayPage(rawValue: id) else { return }
            if defaults.string(forKey: "systemMonitor.trayPage") != page.rawValue {
                defaults.set(page.rawValue, forKey: "systemMonitor.trayPage")
            }
        case .portman:
            let pages: [String: PortmanPanelView.Page] = ["servers": .local, "forward": .forward, "settings": .settings]
            guard let page = pages[id] else { return }
            if defaults.string(forKey: "portman.selectedPage") != page.rawValue {
                defaults.set(page.rawValue, forKey: "portman.selectedPage")
            }
        }
    }

    @MainActor
    var statusButton: NSStatusBarButton? {
        func buttons(in view: NSView) -> [NSStatusBarButton] {
            if let button = view as? NSStatusBarButton { return [button] }
            return view.subviews.flatMap { buttons(in: $0) }
        }
        let candidates = NSApp.windows.flatMap { $0.contentView.map(buttons(in:)) ?? [] }
        return matchingButton(in: candidates)
    }

    @MainActor
    func matchingButton(in candidates: [NSStatusBarButton]) -> NSStatusBarButton? {
        let button = candidates.first { button in
            switch self {
            case .systemMonitor: button.accessibilityIdentifier() == "SystemMonitorMenuBarItem"
                || button.identifier?.rawValue == "SystemMonitorMenuBarItem"
            case .portman: button.accessibilityIdentifier() == "portman.statusItem"
            case .main:
                // The main item is owned by SwiftUI, so its label is an accessibility child.
                Self.isMainLabel(button) || (button.accessibilityChildren()?.contains(where: Self.isMainLabel) ?? false)
            }
        }
        if let button { return button }
        guard self == .main else { return nil }
        // SwiftUI can flatten its label into an image without copying its AX name.
        // All other status items have identifiers owned by the native controllers.
        let remaining = candidates.filter {
            $0.identifier?.rawValue.hasPrefix("individual-menu.") != true
                && DiagnosticsPanel.systemMonitor.matchingButton(in: [$0]) == nil
                && DiagnosticsPanel.portman.matchingButton(in: [$0]) == nil
        }
        return remaining.count == 1 ? remaining[0] : nil
    }

    @MainActor private static func isMainLabel(_ value: Any) -> Bool {
        guard let element = value as? any NSAccessibilityProtocol else { return false }
        return element.accessibilityIdentifier() == "MenuBarIcon"
            || element.accessibilityLabel() == "MacPowerToys"
            || (element.accessibilityChildren()?.contains(where: isMainLabel) ?? false)
    }
}
