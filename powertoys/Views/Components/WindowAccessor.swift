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
        "awake", "color-picker", "text-extractor"
    ])
    private static let workspaceWindowIdentifiers = Set([
        "main", "cc-history", "rclone", "logs", "input-devices",
        "system-care", "power-stats"
    ])

    let windowIdentifier: String
    private weak var restoredWindow: NSWindow?
    private var trafficLightBaselineY: CGFloat?

    override var acceptsFirstResponder: Bool {
        Self.compactAppletWindowIdentifiers.contains(windowIdentifier)
    }

    init(windowIdentifier: String) {
        self.windowIdentifier = windowIdentifier
        super.init(frame: .zero)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window else { return }
        window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
        let isCompactApplet = Self.compactAppletWindowIdentifiers.contains(windowIdentifier)
        if restoredWindow !== window {
            WindowStateManager.shared.restoreState(for: window)
            restoredWindow = window
            trafficLightBaselineY = nil
            if trafficLightVerticalOffset != nil {
                scheduleTrafficLightAlignment(in: window)
            }
            if isCompactApplet {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                    guard let self, let window else { return }
                    window.makeFirstResponder(self)
                }
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

    private var trafficLightVerticalOffset: CGFloat? {
        if Self.compactAppletWindowIdentifiers.contains(windowIdentifier) {
            return UtilityLayout.compactTitlebarTrafficLightVerticalOffset
        }
        if Self.workspaceWindowIdentifiers.contains(windowIdentifier) {
            return UtilityLayout.workspaceTrafficLightVerticalOffset
        }
        return nil
    }

    private func scheduleTrafficLightAlignment(in window: NSWindow) {
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            alignTrafficLights(in: window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
            guard let self, let window else { return }
            alignTrafficLights(in: window)
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let notifiedWindow = notification.object as? NSWindow,
              notifiedWindow === window,
              trafficLightVerticalOffset != nil
        else { return }
        alignTrafficLights(in: notifiedWindow)
        scheduleTrafficLightAlignment(in: notifiedWindow)
    }

    private func alignTrafficLights(in window: NSWindow) {
        guard let verticalOffset = trafficLightVerticalOffset,
              let closeButton = window.standardWindowButton(.closeButton) else { return }
        if trafficLightBaselineY == nil {
            trafficLightBaselineY = closeButton.frame.origin.y
        }
        guard let baselineY = trafficLightBaselineY else { return }
        let targetY = baselineY - verticalOffset
        var buttonTypes = [NSWindow.ButtonType.closeButton, .miniaturizeButton]
        if Self.workspaceWindowIdentifiers.contains(windowIdentifier) {
            buttonTypes.append(.zoomButton)
        }
        for buttonType in buttonTypes {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: targetY))
        }
    }
}
