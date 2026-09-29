import AppKit
import OnePlusUI
import SwiftUI

/// Restores position only. The scene's OnePlusFixedWindowChrome owns size and chrome.
struct WindowAccessor: NSViewRepresentable {
    let windowIdentifier: String
    init(identifier: String) { windowIdentifier = identifier }
    func makeNSView(context: Context) -> NSView { WindowAccessorView(identifier: windowIdentifier) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowAccessorView: NSView {
    let windowIdentifier: String
    private weak var restoredWindow: NSWindow?

    init(identifier: String) {
        windowIdentifier = identifier
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, restoredWindow !== window else { return }
        restoredWindow = window
        window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
        let canvas = OnePlusWindowCanvas.tool(windowIdentifier)
        let currentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
        let size = canvas.map {
            CGSize(width: $0.size.width, height: $0.heightRange == nil ? $0.size.height : currentSize.height)
        } ?? currentSize
        WindowStateManager.shared.restoreState(for: window)
        let restoredTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(size)
        window.setFrameTopLeftPoint(restoredTopLeft)
        window.isMovableByWindowBackground = false
        window.appearance = nil
    }
}
