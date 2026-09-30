import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

final class FocusEffectTests: XCTestCase {
    @MainActor
    func testKeyNotificationKeepsAnActiveTextEditor() throws {
        let window = NSWindow(contentRect: NSRect(x: 32, y: 32, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 280, height: 28))
        window.contentView?.addSubview(field)
        OnePlusFocusPolicy.shared.configure(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close(); window.contentView = nil }
        XCTAssertTrue(NSApp.keyWindow === window)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertTrue(window.firstResponder === editor, "A key notification must not interrupt typing")
    }

    @MainActor
    func testSharedRootSuppressesDescendantFocusEffects() {
        var focusEffectEnabled = true
        let host = NSHostingView(rootView: FocusEffectProbe { focusEffectEnabled = $0 }
            .utilityMotionPolicy())
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(focusEffectEnabled)
    }
}

private struct FocusEffectProbe: View {
    @Environment(\.isFocusEffectEnabled) private var isFocusEffectEnabled
    let onAppear: (Bool) -> Void

    var body: some View {
        Button("Probe") {}
            .onAppear { onAppear(isFocusEffectEnabled) }
    }
}
