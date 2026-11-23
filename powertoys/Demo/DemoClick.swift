//
//  DemoClick.swift
//  powertoys
//
//  Demo stills only: clicks a control by its accessibility label. The events go straight to the
//  app's own window with `sendEvent`, so the pointer never moves and no app is activated.
//

#if MPT_DEMO
import AppKit

@MainActor
enum DemoClick {
    static func element(labeled label: String, right: Bool = false) {
        for window in NSApp.windows where window.isVisible {
            guard let frame = find(label, in: window) else { continue }
            let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
            send(right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp], at: point, in: window)
            return
        }
        NSLog("MacPowerToys Demo: no control labeled %@", label)
    }

    /// SwiftUI's accessibility nodes answer these selectors without adopting `NSAccessibilityProtocol`, so look them up dynamically.
    private static func find(_ label: String, in element: Any) -> NSRect? {
        let node = element as AnyObject
        if node.accessibilityLabel?() == label, let frame = node.accessibilityFrame?() {
            return frame
        }
        for child in node.accessibilityChildren?() ?? [] {
            if let frame = find(label, in: child) { return frame }
        }
        return nil
    }

    private static func send(_ types: [NSEvent.EventType], at point: NSPoint, in window: NSWindow) {
        for type in types {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: 1) else { continue }
            window.sendEvent(event)
        }
    }
}
#endif
