import AppKit
import SwiftUI

/// Restores saved placement. SwiftUI owns the canvas size.
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
        WindowStateManager.shared.restoreState(for: window)
        if window.isMovableByWindowBackground { window.isMovableByWindowBackground = false }
        if window.appearance != nil { window.appearance = nil }
    }
}
