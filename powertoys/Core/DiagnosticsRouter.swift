import AppKit
import SwiftUI
import OnePlusUI

nonisolated enum DiagnosticsRoute: Equatable, Sendable {
    case openPanel(DiagnosticsPanel, tab: String? = nil)
    case appearance(AppAppearance)
    case closePanels
    case closeWindow(String)
    case nativeClose(String)
    case timings
    case openIndividualPanel(String)

    static func parse(_ url: URL) -> Self? {
        guard DeepLinkHandler.isSupportedScheme(url.scheme), url.host == "diagnostics",
              url.user == nil, url.password == nil, url.port == nil,
              url.fragment == nil else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = components.queryItems ?? []
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        if parts == ["", "close-panels"], url.query == nil { return .closePanels }
        if parts == ["", "timings"], url.query == nil { return .timings }
        guard parts.count == 3, parts[0].isEmpty else { return nil }
        switch parts[1] {
        case "close-window", "native-close":
            let id = String(parts[2])
            guard url.query == nil, !id.isEmpty, id.utf8.count <= 80,
                  id.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else { return nil }
            return parts[1] == "native-close" ? .nativeClose(id) : .closeWindow(id)
        case "open-tool-panel":
            guard url.query == nil, IndividualMenuBarTool(rawValue: String(parts[2])) != nil else { return nil }
            return .openIndividualPanel(String(parts[2]))
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
    private let popovers = NSHashTable<OnePlusMenuPresenter>.weakObjects()
    private(set) var captureWindow: NSPanel?
    private var cachedWindows: [DiagnosticsPanel: NSPanel] = [:]
    private var cachedTabs: [DiagnosticsPanel: String] = [:]
    private var cachedProfiles: [SystemMonitorRemoteProfile]?
    private var presentationTask: Task<Void, Never>?
    var makeCaptureContent: ((DiagnosticsPanel, [SystemMonitorRemoteProfile]?, @escaping (CGFloat) -> Void) -> AnyView?)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didShow(_:)),
                                               name: OnePlusMenuPresenter.didShowNotification, object: nil)
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func didShow(_ notification: Notification) {
        if let popover = notification.object as? OnePlusMenuPresenter { popovers.add(popover) }
    }

    func close(clearCache: Bool = false) {
        presentationTask?.cancel()
        presentationTask = nil
        for panel in DiagnosticsPanel.allCases { OnePlusPanelTimings.shared.cancel(panel: panel.rawValue) }
        for tool in IndividualMenuBarTool.allCases { OnePlusPanelTimings.shared.cancel(panel: tool.id) }
        captureWindow?.orderOut(nil)
        captureWindow = nil
        if clearCache {
            cachedWindows.removeAll()
            cachedTabs.removeAll()
            cachedProfiles = nil
        }
        // The native menu controllers own their popovers. Keep only weak references.
        for popover in popovers.allObjects where popover.isShown {
            popover.performClose(nil)
        }
        if let mainWindow, mainWindow.isVisible { mainWindow.close() }
    }

    func open(_ panel: DiagnosticsPanel, tab: String?) {
        let switching = (captureWindow?.identifier?.rawValue == "diagnostics-panel.\(panel.rawValue)"
            && captureWindow?.isVisible == true) || (panel == .portman && PortmanMenuController.shared.isShown)
        if !switching { close() }
        presentationTask?.cancel()
        presentationTask = nil
        OnePlusPanelTimings.shared.begin(panel: panel.rawValue, operation: switching ? .tabSwitch : .open,
                                         tab: tab ?? "", input: "diagnostics")
        if panel == .systemMonitor {
            let defaults = defaults
            presentationTask = Task { [weak self] in
                if tab == SystemMonitorTrayPage.processes.rawValue {
                    await TaskManagerMenuProcessModel.shared.prepareForPresentation()
                }
                let profiles = await Task.detached(priority: .userInitiated) {
                    SystemMonitorRemoteProfiles.load(defaults: defaults)
                }.value
                guard !Task.isCancelled else { return }
                self?.presentationTask = nil
                self?.present(panel, tab: tab, profiles: profiles)
            }
        } else {
            present(panel, tab: tab)
        }
    }

    private func present(_ panel: DiagnosticsPanel, tab: String?, profiles: [SystemMonitorRemoteProfile]? = nil) {
        if captureWindow?.identifier?.rawValue == "diagnostics-panel.\(panel.rawValue)",
           captureWindow?.isVisible == true {
            if let tab {
                ToolPageRouter.shared.post(tool: "menu.\(panel.rawValue)", page: tab, recordTiming: false)
                cachedTabs[panel] = tab
            }
            return
        }
        if panel == .portman {
            PortmanMenuController.shared.show(initialPage: tab.flatMap(PortmanPanelView.Page.init(panelID:)),
                                              activateApp: false)
            return
        }
        panel.selectTab(tab, defaults: defaults)
        presentCapturePanel(panel, tab: tab, profiles: profiles)
    }

    private func presentCapturePanel(_ panel: DiagnosticsPanel, tab: String?, profiles: [SystemMonitorRemoteProfile]?) {
        // MenuBarExtra has no public presentation binding. Capture the same content
        // in a nonactivating panel; native menu-bar clicks keep their existing host.
        let screen = panel.statusButton?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = panel.statusButton?.window?.frame
        if let window = cachedWindows[panel], cachedTabs[panel] == (tab ?? ""),
           panel != .systemMonitor || cachedProfiles == profiles {
            captureWindow = window
            window.contentView?.layoutSubtreeIfNeeded()
            window.orderFrontInBackground()
            return
        }
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
        let resize: (CGFloat) -> Void = { [weak window] height in
            guard let window, height.isFinite, height > 0, abs(window.frame.height - height) > 0.5 else { return }
            window.setContentSize(CGSize(width: OnePlusMenuMetrics.width, height: height))
            window.setFrameTopLeftPoint(CGPoint(x: x, y: top))
        }
        guard let content = makeCaptureContent?(panel, profiles, resize) else {
            LogManager.shared.warning("Panel content is not ready: \(panel.rawValue)", source: "DeepLinkHandler")
            return
        }
        let hosting = NSHostingController(rootView: content
            .environment(\.onePlusMenuMaximumHeight, visible.height * OnePlusMenuMetrics.heightFraction)
            .fixedSize(horizontal: false, vertical: true).frame(width: OnePlusMenuMetrics.width)
            .onePlusFocusPolicy().onOnePlusMenuHeightChange(resize))
        window.contentViewController = hosting
        let size = hosting.sizeThatFits(in: NSSize(width: OnePlusMenuMetrics.width,
                                                   height: visible.height * OnePlusMenuMetrics.heightFraction))
        hosting.view.setFrameSize(size)
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(size)
        window.setFrameTopLeftPoint(CGPoint(x: x, y: top))
        OnePlusFocusPolicy.shared.configure(window)
        captureWindow = window
        cachedWindows[panel] = window
        cachedTabs[panel] = tab ?? ""
        if panel == .systemMonitor { cachedProfiles = profiles }
        window.orderFrontInBackground()
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
