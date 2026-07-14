import AppKit
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class WindowAccessorTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []

    func testWindowMovementStaysInTitlebar() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        Self.retainedWindows.append(window)

        window.contentView = NSHostingView(
            rootView: WindowAccessor(identifier: "main")
        )
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.identifier?.rawValue, "main")
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.isMovable)
    }
}
