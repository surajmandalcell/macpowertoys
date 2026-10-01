import AppKit

/// Arrow-free status panels use the shell's alpha outline for the native shadow.
@MainActor
public final class OnePlusMenuPresenter: NSObject {
    public static let didShowNotification = Notification.Name("OnePlusMenuPresenter.didShow")
    public var onClose: (() -> Void)?
    let window: NSPanel = MenuWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
    private weak var anchor: NSView?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    public override init() {
        super.init()
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.level = .popUpMenu
        window.collectionBehavior = [.transient, .fullScreenAuxiliary]
        window.animationBehavior = .none
    }

    isolated deinit { removeMonitors(); window.orderOut(nil) }

    public var isShown: Bool { window.isVisible }
    public var appearance: NSAppearance? {
        get { window.appearance }
        set { window.appearance = newValue }
    }
    public var contentViewController: NSViewController? {
        get { window.contentViewController }
        set { if window.contentViewController !== newValue { window.contentViewController = newValue } }
    }
    public var contentSize: NSSize {
        get { window.frame.size }
        set {
            guard newValue.width.isFinite, newValue.height.isFinite,
                  newValue.width > 0, newValue.height > 0, newValue != contentSize else { return }
            let top = window.frame.maxY
            window.setContentSize(newValue)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
            window.invalidateShadow()
        }
    }

    public func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge, takesFocus: Bool = true) {
        guard let owner = view.window, let screen = owner.screen else { return }
        anchor = view
        appearance = NSApp.appearance
        let trigger = owner.convertToScreen(view.convert(rect, to: nil))
        window.setFrame(Self.frame(anchor: trigger, size: contentSize, screen: screen.visibleFrame), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        window.invalidateShadow()
        removeMonitors()
        installMonitors()
        window.orderFrontRegardless()
        if takesFocus { window.makeKey() }
        NotificationCenter.default.post(name: Self.didShowNotification, object: self)
    }

    public func performClose(_ sender: Any?) { close() }
    public func close() {
        let wasShown = isShown
        removeMonitors()
        window.orderOut(nil)
        anchor = nil
        if wasShown { onClose?() }
    }

    static func frame(anchor: NSRect, size: NSSize, screen: NSRect) -> NSRect {
        NSRect(x: min(max(screen.minX, anchor.midX - size.width / 2), screen.maxX - size.width),
               y: max(screen.minY, min(anchor.minY, screen.maxY) - size.height),
               width: size.width, height: size.height)
    }

    private func owns(_ candidate: NSWindow?) -> Bool {
        var candidate = candidate
        while let current = candidate {
            if current === window { return true }
            candidate = current.sheetParent ?? current.parent
        }
        return false
    }

    private func installMonitors() {
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouse.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.window === self.window, event.keyCode == 53,
                   event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                   self.window.attachedSheet == nil, self.window.childWindows?.isEmpty != false {
                    self.close()
                    return nil
                }
            } else if !self.owns(event.window) {
                if let anchor = self.anchor, event.window === anchor.window,
                   anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) { return event }
                self.close()
            }
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            guard let self else { return }
            // Status-bar events can arrive through the global monitor before the action.
            // Let the anchor's action toggle its panel instead of closing then reopening it.
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            if let anchor = self.anchor, let owner = anchor.window,
               owner.convertToScreen(anchor.convert(anchor.bounds, to: nil)).contains(point) { return }
            self.close()
        }) { monitors.append(monitor) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: NSApp, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        if let owner = anchor?.window {
            for name in [NSWindow.didMoveNotification, NSWindow.willCloseNotification] {
                observers.append(center.addObserver(forName: name, object: owner, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.close() }
                })
            }
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}

private final class MenuWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
