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
    private static let taskManagerSidebarBackdropLayerName = "task-manager.sidebar-backdrop"
    private static let compactAppletWindowIdentifiers = Set([
        "awake", "color-picker", "text-extractor"
    ])
    private static let workspaceWindowIdentifiers = Set([
        "main", "rclone", "logs", "input-devices",
        "system-care", "disk-explorer", "system-monitor", "nettoys", "switch", "mac-tweaks"
    ])

    let windowIdentifier: String
    private weak var restoredWindow: NSWindow?
    private var trafficLightBaselineY: CGFloat?

    override var acceptsFirstResponder: Bool {
        Self.compactAppletWindowIdentifiers.contains(windowIdentifier)
            || Self.workspaceWindowIdentifiers.contains(windowIdentifier)
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
        if let minimumSize = UtilityLayout.minimumContentSize(for: windowIdentifier) {
            window.contentMinSize = minimumSize
        }
        let isCompactApplet = Self.compactAppletWindowIdentifiers.contains(windowIdentifier)
        if restoredWindow !== window {
            WindowStateManager.shared.restoreState(for: window)
            restoredWindow = window
            trafficLightBaselineY = nil
            if trafficLightVerticalOffset != nil {
                scheduleTrafficLightAlignment(in: window)
            }
            if isCompactApplet || Self.workspaceWindowIdentifiers.contains(windowIdentifier) {
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
        if windowIdentifier == "switch" {
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        applyFixedWindowPolicy(to: window)
        scheduleFixedWindowPolicy(in: window)
        if isCompactApplet || windowIdentifier == "mac-tweaks" {
            window.styleMask.remove(.resizable)
            if windowIdentifier == "mac-tweaks" {
                window.contentMinSize = MacTweaksLayout.contentSize
                window.contentMaxSize = MacTweaksLayout.contentSize
                if abs(window.contentLayoutRect.width - MacTweaksLayout.contentSize.width) > 0.5
                    || abs(window.contentLayoutRect.height - MacTweaksLayout.contentSize.height) > 0.5 {
                    window.setContentSize(MacTweaksLayout.contentSize)
                }
                window.collectionBehavior.insert(.fullScreenNone)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.hasShadow = true
            } else {
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
    }

    private var trafficLightVerticalOffset: CGFloat? {
        if windowIdentifier == "mac-tweaks" {
            return MacTweaksLayout.trafficLightVerticalOffset
        }
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
              notifiedWindow === window else { return }
        applyFixedWindowPolicy(to: notifiedWindow)
        scheduleFixedWindowPolicy(in: notifiedWindow)
        guard trafficLightVerticalOffset != nil else { return }
        alignTrafficLights(in: notifiedWindow)
        scheduleTrafficLightAlignment(in: notifiedWindow)
    }

    private func scheduleFixedWindowPolicy(in window: NSWindow) {
        guard windowIdentifier == "system-monitor" else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            applyFixedWindowPolicy(to: window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
            guard let self, let window else { return }
            applyFixedWindowPolicy(to: window)
        }
    }

    private func applyFixedWindowPolicy(to window: NSWindow) {
        guard windowIdentifier == "system-monitor" else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        window.contentMinSize = TaskManagerTheme.windowContentSize
        window.contentMaxSize = TaskManagerTheme.windowContentSize
        let currentSize = window.contentView?.bounds.size ?? .zero
        if abs(currentSize.width - TaskManagerTheme.windowContentSize.width) > 0.5
            || abs(currentSize.height - TaskManagerTheme.windowContentSize.height) > 0.5 {
            window.setContentSize(TaskManagerTheme.windowContentSize)
        }
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        applyTaskManagerBackdrop(to: window)
    }

    private func applyTaskManagerBackdrop(to window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = TaskManagerTheme.windowNSColor
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        guard let rootLayer = contentView.layer else { return }
        rootLayer.backgroundColor = TaskManagerTheme.windowNSColor.cgColor

        let sidebarLayer: CALayer
        if let existingLayer = rootLayer.sublayers?.first(where: {
            $0.name == Self.taskManagerSidebarBackdropLayerName
        }) {
            sidebarLayer = existingLayer
        } else {
            sidebarLayer = CALayer()
            sidebarLayer.name = Self.taskManagerSidebarBackdropLayerName
            rootLayer.insertSublayer(sidebarLayer, at: 0)
        }
        sidebarLayer.backgroundColor = TaskManagerTheme.sidebarNSColor.cgColor
        sidebarLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: TaskManagerTheme.sidebarWidth,
            height: contentView.bounds.height
        )
        sidebarLayer.autoresizingMask = [.layerHeightSizable]
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
        if Self.workspaceWindowIdentifiers.contains(windowIdentifier), windowIdentifier != "system-monitor" {
            buttonTypes.append(.zoomButton)
        }
        for buttonType in buttonTypes {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: targetY))
        }
    }
}
