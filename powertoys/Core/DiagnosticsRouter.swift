import AppKit
import SwiftUI

nonisolated enum DiagnosticsRoute: Equatable, Sendable {
    case openPanel(DiagnosticsPanel)
    case appearance(AppAppearance)
    case closePanels

    static func parse(_ url: URL) -> Self? {
        guard DeepLinkHandler.isSupportedScheme(url.scheme), url.host == "diagnostics",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        if parts == ["", "close-panels"] { return .closePanels }
        guard parts.count == 3, parts[0].isEmpty else { return nil }
        switch parts[1] {
        case "appearance": return AppAppearance(rawValue: String(parts[2])).map(Self.appearance)
        case "open-panel": return DiagnosticsPanel(rawValue: String(parts[2])).map(Self.openPanel)
        default: return nil
        }
    }
}

@MainActor
final class DiagnosticsMenuPanels: NSObject {
    static let shared = DiagnosticsMenuPanels()
    weak var mainWindow: NSWindow?
    private let popovers = NSHashTable<NSPopover>.weakObjects()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didShow(_:)),
                                               name: NSPopover.didShowNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func didShow(_ notification: Notification) {
        if let popover = notification.object as? NSPopover { popovers.add(popover) }
    }

    func close() {
        // The native menu controllers own their popovers. Keep only weak references.
        for popover in popovers.allObjects where popover.isShown && !popover.isDetached {
            popover.performClose(nil)
        }
        if let mainWindow, mainWindow.isVisible { mainWindow.close() }
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
