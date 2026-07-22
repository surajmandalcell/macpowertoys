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
            XCTAssertFalse(window.styleMask.contains(.resizable), identifier)
            XCTAssertEqual(
                adjustedCloseButtonY,
                initialCloseButtonY - UtilityLayout.compactTitlebarTrafficLightVerticalOffset,
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
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

            let reappliedCloseButtonY = try XCTUnwrap(
                window.standardWindowButton(.closeButton)?.frame.origin.y
            )
            let reappliedMinimizeButtonY = try XCTUnwrap(
                window.standardWindowButton(.miniaturizeButton)?.frame.origin.y
            )
            XCTAssertEqual(
                reappliedCloseButtonY,
                initialCloseButtonY - UtilityLayout.compactTitlebarTrafficLightVerticalOffset,
                accuracy: 0.5,
                identifier
            )
            XCTAssertEqual(
                reappliedMinimizeButtonY,
                initialCloseButtonY - UtilityLayout.compactTitlebarTrafficLightVerticalOffset,
                accuracy: 0.5,
                identifier
            )
            let firstResponder = try XCTUnwrap(window.firstResponder as? NSView)
            let contentView = try XCTUnwrap(window.contentView)
            XCTAssertTrue(
                firstResponder === contentView || firstResponder.isDescendant(of: contentView),
                identifier
            )
            XCTAssertFalse(firstResponder is NSControl, identifier)
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

    func testCompactAppletClampsDelayedWindowResizeToContentHeight() {
        let contentHeight: CGFloat = 300
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: contentHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        Self.retainedWindows.append(window)
        window.contentView = NSHostingView(
            rootView: Color.clear
                .frame(width: 400, height: contentHeight)
                .background(WindowAccessor(identifier: "text-extractor"))
        )
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(waitUntil {
            window.identifier?.rawValue == "text-extractor"
        })

        var oversizedFrame = window.frame
        oversizedFrame.origin.y -= 32
        oversizedFrame.size.height += 32
        let topEdge = oversizedFrame.maxY
        window.setFrame(oversizedFrame, display: false)
        XCTAssertTrue(waitUntil {
            abs(window.frame.height - contentHeight) <= 0.5
        })

        XCTAssertEqual(window.frame.height, contentHeight, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, topEdge, accuracy: 0.5)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date(timeIntervalSinceNow: 0.01)))
        }
        return condition()
    }
}
