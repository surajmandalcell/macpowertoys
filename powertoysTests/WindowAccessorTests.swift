import AppKit
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class WindowAccessorTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []

    func testCompactAppletWindowsUseFixedAlignedChrome() throws {
        for identifier in ["awake", "color-picker", "text-extractor"] {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
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
            let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
            let closeButtonSuperview = try XCTUnwrap(closeButton.superview)
            let closeButtonCenter = closeButtonSuperview.convert(
                NSPoint(x: closeButton.frame.midX, y: closeButton.frame.midY),
                to: window.contentView
            )
            let expectedCenterline = (
                UtilityLayout.compactTitlebarHeight + UtilityLayout.compactTitlebarTopInset
            ) / 2
            let contentView = try XCTUnwrap(window.contentView)
            let closeButtonTopGap = contentView.isFlipped
                ? closeButtonCenter.y
                : contentView.bounds.maxY - closeButtonCenter.y
            XCTAssertEqual(
                closeButtonTopGap,
                expectedCenterline,
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

            for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton] {
                guard let button = window.standardWindowButton(buttonType) else { continue }
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: initialCloseButtonY))
            }
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            XCTAssertEqual(
                try XCTUnwrap(window.standardWindowButton(.closeButton)?.frame.origin.y),
                initialCloseButtonY - UtilityLayout.compactTitlebarTrafficLightVerticalOffset,
                accuracy: 0.5,
                "Late native titlebar layout must be corrected when \(identifier) becomes key"
            )
            let firstResponder = try XCTUnwrap(window.firstResponder as? NSView)
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

    func testWorkspaceTrafficLightsUseBalancedSharedChrome() throws {
        for identifier in [
            "main", "cc-history", "rclone", "logs", "input-devices",
            "system-care", "power-stats"
        ] {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            Self.retainedWindows.append(window)
            let initialY = try XCTUnwrap(window.standardWindowButton(.closeButton)?.frame.origin.y)
            window.contentView = NSHostingView(rootView: WindowAccessor(identifier: identifier))
            window.contentView?.layoutSubtreeIfNeeded()
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
            let buttonSuperview = try XCTUnwrap(closeButton.superview)
            let center = buttonSuperview.convert(
                NSPoint(x: closeButton.frame.midX, y: closeButton.frame.midY),
                to: window.contentView
            )
            let contentView = try XCTUnwrap(window.contentView)
            let topGap = contentView.isFlipped ? center.y : contentView.bounds.maxY - center.y
            XCTAssertEqual(topGap, UtilityLayout.workspaceTitlebarHeight / 2, accuracy: 0.5, identifier)

            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                XCTAssertEqual(
                    try XCTUnwrap(window.standardWindowButton(type)?.frame.origin.y),
                    initialY - UtilityLayout.workspaceTrafficLightVerticalOffset,
                    accuracy: 0.5,
                    identifier
                )
            }
            let zoomButton = try XCTUnwrap(window.standardWindowButton(.zoomButton))
            XCTAssertGreaterThanOrEqual(
                UtilityLayout.workspaceTitleLeadingInset - zoomButton.frame.maxX,
                12,
                identifier
            )
        }
    }

    func testWorkspaceDensityUsesCompactSharedMetrics() {
        XCTAssertEqual(UtilityLayout.compactSidebarWidth, 220)
        XCTAssertEqual(UtilityLayout.dataSidebarWidth, 240)
        XCTAssertEqual(UtilityLayout.conversationSidebarWidth, 260)
        XCTAssertEqual(UtilityLayout.sidebarRowHeight, 28)
        XCTAssertEqual(UtilityLayout.workspaceTitlebarHeight, 40)
        XCTAssertEqual(UtilityLayout.workspaceContentTopInset, 44)
        XCTAssertEqual(UtilityLayout.workspaceTitleLeadingInset, 84)
        XCTAssertEqual(UtilityLayout.workspaceActionHeight, 24)
        XCTAssertEqual(UtilityLayout.separatorOpacity, 0.22)
        XCTAssertEqual(UtilityLayout.increasedContrastSeparatorOpacity, 0.44)
        XCTAssertGreaterThan(
            UtilityLayout.increasedContrastSeparatorOpacity,
            UtilityLayout.separatorOpacity
        )
    }

    func testFloatingButtonOffsetsThroughHiddenTitlebarSurplus() {
        XCTAssertEqual(UtilityLayout.hiddenTitlebarBottomSurplus, 32, accuracy: 0.5)
    }

    func testUtilityMotionStopsWhenReduceMotionIsEnabled() {
        XCTAssertNotNil(UtilityMotion.animation(reduceMotion: false))
        XCTAssertNil(UtilityMotion.animation(reduceMotion: true))
    }
}
