import AppKit
import ObjectiveC
import Observation
import SwiftUI

@MainActor @Observable
public final class OnePlusFocusPolicy {
    public static let shared = OnePlusFocusPolicy()
    public private(set) var showsFocus = false
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var voiceOver: NSKeyValueObservation?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var keyboardObserver: NSObjectProtocol?
    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private let windows = NSHashTable<NSWindow>.weakObjects()

    public var eventMonitorOwnerCount: Int { eventMonitor == nil ? 0 : 1 }
    public var observerOwnerCount: Int { observers.count + (voiceOver == nil ? 0 : 1) + (keyboardObserver == nil ? 0 : 1) }

    public static func visualsEnabled(fullKeyboardAccess: Bool, voiceOver: Bool) -> Bool {
        fullKeyboardAccess || voiceOver
    }

    public static func acceptsFocus(isVisible: Bool, pointer: Bool, textInput: Bool,
                                    selectionInput: Bool = false) -> Bool {
        isVisible && (!pointer || textInput || selectionInput)
    }

    public func install() {
        guard !installed else { return }
        installed = true
        Self.installResponderHook()
        refresh()
        voiceOver = NSWorkspace.shared.observe(\.isVoiceOverEnabled) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, UserDefaults.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        keyboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.KeyboardUIModeChanged"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if let window { self?.configure(window) }
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if let window { self?.configure(window) }
            }
        })
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.refresh()
            if Self.isPointerEvent(event.type), let window = event.window {
                Self.dismissPointerFocus(in: window, at: event.locationInWindow)
            }
            return event
        }
    }

    public func refresh() {
        update(fullKeyboardAccess: NSApp.isFullKeyboardAccessEnabled, voiceOver: NSWorkspace.shared.isVoiceOverEnabled)
    }

    public func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        voiceOver = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let keyboardObserver { DistributedNotificationCenter.default().removeObserver(keyboardObserver) }
        keyboardObserver = nil
        windows.removeAllObjects()
        installed = false
    }

    func update(fullKeyboardAccess: Bool, voiceOver: Bool) {
        let value = Self.visualsEnabled(fullKeyboardAccess: fullKeyboardAccess, voiceOver: voiceOver)
        guard showsFocus != value else { return }
        showsFocus = value
        for window in NSApp.windows {
            configureRings(window.contentView)
            window.contentView?.needsDisplay = true
        }
    }

    public func configure(_ window: NSWindow) {
        install()
        guard windows.member(window) == nil else {
            Self.clearInvalidFocus(in: window)
            return
        }
        windows.add(window)
        window.initialFirstResponder = nil
        if !showsFocus, !Self.isTextInput(window.firstResponder), !Self.isSelectionInput(window.firstResponder) {
            window.makeFirstResponder(window)
        }
        Self.clearInvalidFocus(in: window)
        configureRings(window.contentView)
    }

    private static func clearInvalidFocus(in window: NSWindow) {
        guard let view = window.firstResponder as? NSView else { return }
        if view.window !== window || view.isHiddenOrHasHiddenAncestor || view.visibleRect.intersection(view.bounds).isEmpty ||
            !view.acceptsFirstResponder || (view as? NSControl)?.isEnabled == false {
            window.makeFirstResponder(window)
        }
    }

    private func configureRings(_ view: NSView?) {
        guard let view else { return }
        view.focusRingType = showsFocus ? .default : .none
        view.needsDisplay = true
        view.subviews.forEach { configureRings($0) }
    }

    public static func dismissPointerFocus(in window: NSWindow, at point: NSPoint) {
        var hit = window.contentView?.hitTest(point)
        while let view = hit {
            if isTextInput(view) || isSelectionInput(view) { return }
            hit = view.superview
        }
        window.makeFirstResponder(window)
    }

    private static func isTextInput(_ responder: NSResponder?) -> Bool {
        if let field = responder as? NSTextField { return field.isEditable || field.isSelectable }
        if let editor = responder as? NSTextView { return editor.isEditable || editor.isSelectable }
        return false
    }

    private static func isSelectionInput(_ responder: NSResponder?) -> Bool {
        responder is NSTableView || responder is NSCollectionView || responder is NSBrowser
    }

    static func isPointerEvent(_ type: NSEvent.EventType?) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp: true
        default: false
        }
    }

    static func allows(_ responder: NSResponder?, in window: NSWindow, pointer: Bool) -> Bool {
        if !shared.installed { return true }
        if responder == nil || responder === window { return true }
        if shared.windows.member(window) == nil { return true }
        return acceptsFocus(isVisible: window.isVisible, pointer: pointer && !shared.showsFocus,
                            textInput: isTextInput(responder), selectionInput: isSelectionInput(responder))
    }

    private static var hookInstalled = false
    private static func installResponderHook() {
        guard !hookInstalled,
              let original = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.makeFirstResponder(_:))),
              let replacement = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.onePlusMakeFirstResponder(_:))) else { return }
        method_exchangeImplementations(original, replacement)
        hookInstalled = true
    }
}

extension NSWindow {
    @objc fileprivate func onePlusMakeFirstResponder(_ responder: NSResponder?) -> Bool {
        let pointer = OnePlusFocusPolicy.isPointerEvent(NSApp.currentEvent?.type)
        guard OnePlusFocusPolicy.allows(responder, in: self, pointer: pointer) else { return false }
        if let view = responder as? NSView {
            view.focusRingType = OnePlusFocusPolicy.shared.showsFocus ? .default : .none
        }
        return onePlusMakeFirstResponder(responder)
    }
}

public extension View {
    func onePlusFocusPolicy() -> some View {
        focusEffectDisabled(!OnePlusFocusPolicy.shared.showsFocus)
            .background(OnePlusFocusReader())
    }
}

private struct OnePlusFocusReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FocusView() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class FocusView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { OnePlusFocusPolicy.shared.configure(window) }
        }
    }
}
