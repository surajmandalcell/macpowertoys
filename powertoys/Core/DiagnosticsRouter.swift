import AppKit
import SwiftUI
import OnePlusUI

nonisolated enum DiagnosticsRoute: Equatable, Sendable {
    case openPanel(DiagnosticsPanel, tab: String? = nil)
    case appearance(AppAppearance)
    case closePanels

    static func parse(_ url: URL) -> Self? {
        guard DeepLinkHandler.isSupportedScheme(url.scheme), url.host == "diagnostics",
              url.user == nil, url.password == nil, url.port == nil,
              url.fragment == nil else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        if parts == ["", "close-panels"], url.query == nil { return .closePanels }
        guard parts.count == 3, parts[0].isEmpty else { return nil }
        switch parts[1] {
        case "appearance":
            guard url.query == nil else { return nil }
            return AppAppearance(rawValue: String(parts[2])).map(Self.appearance)
        case "open-panel":
            guard let panel = DiagnosticsPanel(rawValue: String(parts[2])),
                  url.query == nil || (query.count == 1 && query[0].name == "tab"
                    && query[0].value.map { $0.utf8.count <= 80 } == true) else { return nil }
            return .openPanel(panel, tab: query.first?.value)
        default: return nil
        }
    }
}

@MainActor
final class DiagnosticsMenuPanels: NSObject {
    static let shared = DiagnosticsMenuPanels()
    weak var mainWindow: NSWindow?
    private let popovers = NSHashTable<NSPopover>.weakObjects()
    private(set) var captureWindow: NSPanel?
    var makeCaptureContent: ((DiagnosticsPanel) -> AnyView?)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didShow(_:)),
                                               name: NSPopover.didShowNotification, object: nil)
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func didShow(_ notification: Notification) {
        if let popover = notification.object as? NSPopover { popovers.add(popover) }
    }

    func close() {
        captureWindow?.orderOut(nil)
        captureWindow?.contentViewController = nil
        captureWindow = nil
        // The native menu controllers own their popovers. Keep only weak references.
        for popover in popovers.allObjects where popover.isShown && !popover.isDetached {
            popover.performClose(nil)
        }
        if let mainWindow, mainWindow.isVisible { mainWindow.close() }
    }

    func open(_ panel: DiagnosticsPanel, tab: String?) {
        panel.selectTab(tab, defaults: defaults)
        if captureWindow?.identifier?.rawValue == "diagnostics-panel.\(panel.rawValue)",
           captureWindow?.isVisible == true { return }
        if panel == .portman {
            PortmanMenuController.shared.show(initialPage: tab.flatMap(PortmanPanelView.Page.init(panelID:)),
                                              activateApp: false)
            return
        }
        close()
        guard let content = makeCaptureContent?(panel) else {
            LogManager.shared.warning("Panel content is not ready: \(panel.rawValue)", source: "DeepLinkHandler")
            return
        }
        presentCapturePanel(content, panel: panel)
    }

    private func presentCapturePanel(_ content: AnyView, panel: DiagnosticsPanel) {
        // MenuBarExtra has no public presentation binding. Capture the same content
        // in a nonactivating panel; native menu-bar clicks keep their existing host.
        let screen = panel.statusButton?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = panel.statusButton?.window?.frame
        let window = DiagnosticsCapturePanel(contentRect: CGRect(x: 0, y: 0, width: OnePlusMenuMetrics.width, height: 80),
                                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = panel == .main ? "MacPowerToys Menu" : "Task Manager Menu"
        window.identifier = .init("diagnostics-panel.\(panel.rawValue)")
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.level = .popUpMenu
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.animationBehavior = .none
        let top = anchor?.minY ?? visible.maxY
        let x = min(max(visible.minX, (anchor?.midX ?? visible.maxX) - OnePlusMenuMetrics.width / 2),
                    visible.maxX - OnePlusMenuMetrics.width)
        window.setFrameTopLeftPoint(CGPoint(x: x, y: top))
        let hosting = NSHostingController(rootView: content
            .fixedSize(horizontal: false, vertical: true).frame(width: OnePlusMenuMetrics.width)
            .onePlusFocusPolicy().onOnePlusMenuHeightChange { [weak window] height in
            guard let window, height.isFinite, height > 0, abs(window.frame.height - height) > 0.5 else { return }
            window.setContentSize(CGSize(width: OnePlusMenuMetrics.width, height: height))
            window.setFrameTopLeftPoint(CGPoint(x: x, y: top))
        })
        window.contentViewController = hosting
        let size = hosting.sizeThatFits(in: NSSize(width: OnePlusMenuMetrics.width,
                                                   height: visible.height * OnePlusMenuMetrics.heightFraction))
        hosting.view.setFrameSize(size)
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(size)
        window.setFrameTopLeftPoint(CGPoint(x: x, y: top))
        OnePlusFocusPolicy.shared.configure(window)
        captureWindow = window
        window.orderFrontRegardless()
    }
}

private final class DiagnosticsCapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct DiagnosticsMainMenuWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DiagnosticsMenuPanels.shared.mainWindow = window }
        }
    }
}
