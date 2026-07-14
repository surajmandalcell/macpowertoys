import AppKit
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class WindowAccessorTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []

    func testCompactAppletWindowsUseFixedAlignedChrome() throws {
        for identifier in ["ruler", "awake", "color-picker", "text-extractor"] {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            Self.retainedWindows.append(window)

            let initialCloseButtonY = try XCTUnwrap(
                window.standardWindowButton(.closeButton)?.frame.origin.y
            )
            window.contentView = NSHostingView(
                rootView: WindowAccessor(identifier: identifier)
            )
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            let adjustedCloseButtonY = try XCTUnwrap(
                window.standardWindowButton(.closeButton)?.frame.origin.y
            )
            let adjustedMinimizeButtonY = try XCTUnwrap(
                window.standardWindowButton(.miniaturizeButton)?.frame.origin.y
            )
            let resolvedWindowSize = window.frame.size
            XCTAssertFalse(window.styleMask.contains(.resizable), identifier)
            XCTAssertEqual(
                adjustedCloseButtonY,
                initialCloseButtonY - 4,
                accuracy: 0.5,
                identifier
            )
            XCTAssertEqual(
                adjustedMinimizeButtonY,
                adjustedCloseButtonY,
                accuracy: 0.5,
                identifier
            )
            XCTAssertTrue(
                try XCTUnwrap(window.standardWindowButton(.zoomButton)?.isHidden),
                identifier
            )

            for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton] {
                guard let button = window.standardWindowButton(buttonType) else {
                    return XCTFail("Missing traffic light for \(identifier)")
                }
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: initialCloseButtonY))
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

            let reappliedCloseButtonY = try XCTUnwrap(
                window.standardWindowButton(.closeButton)?.frame.origin.y
            )
            let reappliedMinimizeButtonY = try XCTUnwrap(
                window.standardWindowButton(.miniaturizeButton)?.frame.origin.y
            )
            XCTAssertEqual(
                reappliedCloseButtonY,
                initialCloseButtonY - 4,
                accuracy: 0.5,
                identifier
            )
            XCTAssertEqual(
                reappliedMinimizeButtonY,
                initialCloseButtonY - 4,
                accuracy: 0.5,
                identifier
            )
            XCTAssertEqual(window.minSize, resolvedWindowSize, identifier)
            XCTAssertEqual(window.maxSize, resolvedWindowSize, identifier)
        }
    }

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
