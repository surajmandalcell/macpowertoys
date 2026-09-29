import AppKit
import SwiftUI

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
}

extension Notification.Name {
    static let openToolPage = Notification.Name("openToolPage")
}

@MainActor
final class ToolPageRouter {
    static let shared = ToolPageRouter()
    private var pending: [String: ToolPageRequest] = [:]

    func handleNativeURL(_ url: URL, tool: String) {
        // SwiftUI opens native scenes itself. Deliver their page without reopening.
        guard !AppDelegate.requiresManualURLRouting(url),
              let route = OpenToolRoute.parse(url), route.tool == tool, let page = route.page else { return }
        post(tool: tool, page: page)
    }

    func post(tool: String, page: String) {
        let request = ToolPageRequest(tool: tool, page: page)
        pending[tool] = request
        NotificationCenter.default.post(name: .openToolPage, object: request,
                                        userInfo: ["tool": tool, "page": page])
    }

    func take(tool: String, matching page: String? = nil) -> ToolPageRequest? {
        guard let request = pending[tool], page == nil || page == request.page else { return nil }
        pending[tool] = nil
        return request
    }
}

private struct OpenToolPageModifier: ViewModifier {
    let tool: String
    let page: String?
    let action: (String) -> Void

    private func deliver() {
        if let request = ToolPageRouter.shared.take(tool: tool, matching: page) { action(request.page) }
    }

    func body(content: Content) -> some View {
        content.onAppear(perform: deliver)
            .onReceive(NotificationCenter.default.publisher(for: .openToolPage)) { notification in
                guard (notification.object as? ToolPageRequest)?.tool == tool else { return }
                deliver()
            }
    }
}

extension View {
    func onNativeToolPageURL(_ tool: String) -> some View {
        onOpenURL { ToolPageRouter.shared.handleNativeURL($0, tool: tool) }
    }

    func onOpenToolPage(_ tool: String, matching page: String? = nil,
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
        guard case .openPanel(let panel) = DiagnosticsRoute.parse(url) else { return nil }
        return panel
    }

    @MainActor
    @discardableResult func open() -> Bool {
        func buttons(in view: NSView) -> [NSStatusBarButton] {
            if let button = view as? NSStatusBarButton { return [button] }
            return view.subviews.flatMap { buttons(in: $0) }
        }
        let candidates = NSApp.windows.flatMap { $0.contentView.map(buttons(in:)) ?? [] }
        let button = candidates.first { button in
            switch self {
            case .systemMonitor: button.accessibilityIdentifier() == "SystemMonitorMenuBarItem"
            case .portman: button.accessibilityIdentifier() == "portman.statusItem"
            case .main:
                // The main item is owned by SwiftUI, so its label is an accessibility child.
                Self.isMainLabel(button) || (button.accessibilityChildren()?.contains(where: Self.isMainLabel) ?? false)
            }
        }
        guard let button else {
            LogManager.shared.warning("Panel status item is unavailable: \(rawValue)", source: "DeepLinkHandler")
            return false
        }
        button.performClick(nil)
        return true
    }

    @MainActor private static func isMainLabel(_ value: Any) -> Bool {
        guard let element = value as? any NSAccessibilityProtocol else { return false }
        return element.accessibilityIdentifier() == "MenuBarIcon"
            || element.accessibilityLabel() == "MacPowerToys"
            || (element.accessibilityChildren()?.contains(where: isMainLabel) ?? false)
    }
}
