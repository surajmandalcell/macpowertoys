//
//  WindowAccessor.swift
//  powertoys
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let windowIdentifier: String

    init(identifier: String) {
        windowIdentifier = identifier
    }

    func makeNSView(context: Context) -> NSView {
        WindowAccessorView(windowIdentifier: windowIdentifier)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class WindowAccessorView: NSView {
    private static let compactAppletWindowIdentifiers = Set([
        "ruler", "awake", "color-picker", "text-extractor"
    ])

    let windowIdentifier: String
    private weak var restoredWindow: NSWindow?

    init(windowIdentifier: String) {
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
        window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
        if restoredWindow !== window {
            WindowStateManager.shared.restoreState(for: window)
            restoredWindow = window
        }
        if windowIdentifier == "awake" {
            DispatchQueue.main.async { [weak window] in
                window?.makeFirstResponder(nil)
            }
        }
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
        window.standardWindowButton(.zoomButton)?.isHidden = Self.compactAppletWindowIdentifiers.contains(windowIdentifier)
    }
}
