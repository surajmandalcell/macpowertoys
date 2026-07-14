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

    override var acceptsFirstResponder: Bool {
        windowIdentifier == "awake"
    }

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
        let isCompactApplet = Self.compactAppletWindowIdentifiers.contains(windowIdentifier)
        if restoredWindow !== window {
            WindowStateManager.shared.restoreState(for: window)
            restoredWindow = window
            if isCompactApplet {
                DispatchQueue.main.async { [weak window] in
                    guard let window else { return }
                    for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton] {
                        guard let button = window.standardWindowButton(buttonType) else { continue }
                        button.setFrameOrigin(NSPoint(
                            x: button.frame.origin.x,
                            y: button.frame.origin.y - UtilityLayout.compactTitlebarTrafficLightVerticalOffset
                        ))
                    }
                }
            }
        }
        if windowIdentifier == "awake" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
            }
        }
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
        if isCompactApplet {
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
}
