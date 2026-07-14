//
//  WindowAccessor.swift
//  powertoys
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var windowIdentifier: String?

    init(identifier: String? = nil) {
        windowIdentifier = identifier
    }

    func makeNSView(context: Context) -> NSView {
        WindowAccessorView(windowIdentifier: windowIdentifier)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowAccessorView)?.windowIdentifier = windowIdentifier
    }
}

private class WindowAccessorView: NSView {
    var windowIdentifier: String?
    private weak var restoredWindow: NSWindow?

    init(windowIdentifier: String?) {
        self.windowIdentifier = windowIdentifier
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window else { return }
        if let windowIdentifier {
            window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
        }
        if restoredWindow !== window {
            WindowStateManager.shared.restoreState(for: window)
            restoredWindow = window
        }
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
    }
}
