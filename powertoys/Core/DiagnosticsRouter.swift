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
    private var openTask: Task<Void, Never>?
    private(set) var captureWindow: NSPanel?
    var makeCaptureContent: ((DiagnosticsPanel) -> AnyView?)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didShow(_:)),
                                               name: NSPopover.didShowNotification, object: nil)
    }

    isolated deinit { openTask?.cancel(); NotificationCenter.default.removeObserver(self) }

    @objc private func didShow(_ notification: Notification) {
        if let popover = notification.object as? NSPopover { popovers.add(popover) }
    }

    func close() {
        openTask?.cancel(); openTask = nil
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
        close()
        if let content = makeCaptureContent?(panel) {
            presentCapturePanel(content, panel: panel)
            openTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled else { return }
                panel.selectTab(tab, defaults: self?.defaults ?? .standard)
                self?.openTask = nil
            }
            return
        }
        openTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.openTask = nil } }
            var clicked = false
            // Status items can still be attaching when a background URL arrives.
            // This request has a two-second deadline and no idle work.
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                if !clicked, let button = panel.statusButton {
                    button.performClick(nil)
                    clicked = true
                }
                let shown = panel == .main ? self.mainWindow?.isVisible == true
                    : self.popovers.allObjects.contains { $0.isShown }
                if clicked && shown {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    panel.selectTab(tab, defaults: self.defaults)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            LogManager.shared.warning("Panel did not open: \(panel.rawValue)", source: "DeepLinkHandler")
        }
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
        window.contentViewController = NSHostingController(rootView: DiagnosticsCaptureContent(content: content) { [weak window] height in
            guard let window, height.isFinite, height > 0, abs(window.frame.height - height) > 0.5 else { return }
            window.setContentSize(CGSize(width: OnePlusMenuMetrics.width, height: height))
            window.setFrameTopLeftPoint(CGPoint(x: x, y: top))
        })
        captureWindow = window
        window.orderFrontRegardless()
    }
}

private final class DiagnosticsCapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct DiagnosticsCaptureHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct DiagnosticsCaptureContent: View {
    let content: AnyView
    let heightChanged: (CGFloat) -> Void
    var body: some View {
        content.fixedSize(horizontal: false, vertical: true)
            .frame(width: OnePlusMenuMetrics.width)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: DiagnosticsCaptureHeight.self, value: proxy.size.height)
            })
            .onPreferenceChange(DiagnosticsCaptureHeight.self, perform: heightChanged)
    }
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
