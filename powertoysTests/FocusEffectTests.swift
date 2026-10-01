import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

final class FocusEffectTests: XCTestCase {
    @MainActor
    func testKeyNotificationKeepsAnActiveTextEditor() throws {
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let window = OffscreenFocusWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 280, height: 28))
        window.contentView?.addSubview(field)
        OnePlusFocusPolicy.shared.configure(window)
        defer { window.close(); window.contentView = nil }
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        XCTAssertTrue(window.firstResponder === editor)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertTrue(window.firstResponder === editor, "A key notification must not interrupt typing")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, foreground)
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

private final class OffscreenFocusWindow: NSWindow {
    override var isVisible: Bool { true }
}

private struct FocusEffectProbe: View {
    @Environment(\.isFocusEffectEnabled) private var isFocusEffectEnabled
    let onAppear: (Bool) -> Void

    var body: some View {
        Button("Probe") {}
            .onAppear { onAppear(isFocusEffectEnabled) }
    }
}
