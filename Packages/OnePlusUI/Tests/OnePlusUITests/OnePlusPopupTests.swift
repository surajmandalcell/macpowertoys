import AppKit
import CoreGraphics
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusPopupTests: XCTestCase {
    func testAccessibilityItemsKeepIdentityAndUseClippedScrolledRows() throws {
        let first = OnePlusPopupMenuItem("First") {}
        let last = OnePlusPopupMenuItem("Last", isEnabled: false) {}
        let session = OnePlusPopupSession(entries: [.item(first), .item(last)], density: .regular, initialID: first.id)
        let host = OnePlusPopupAccessibilityHost(frame: CGRect(x: 0, y: 0, width: 200, height: 60))
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: host.frame)
        window.contentView = root
        let scroll = NSScrollView(frame: root.bounds)
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let row = NSView(frame: CGRect(x: 0, y: 90, width: 200, height: 28))
        document.addSubview(row)
        scroll.documentView = document
        root.addSubview(scroll)
        root.addSubview(host)
        let anchor = OnePlusPopupRowAnchor()
        anchor.view = row
        session.rowAnchors[first.id] = anchor
        host.update(session: session)
        let initial = try XCTUnwrap(host.accessibilityChildren() as? [OnePlusPopupAccessibilityItem])
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        host.updateFrames()
        let expected = window.convertToScreen(row.convert(row.visibleRect.intersection(row.bounds), to: nil))
        XCTAssertEqual(initial[0].accessibilityFrame(), expected)
        XCTAssertLessThanOrEqual(expected.height, 28)
        XCTAssertLessThanOrEqual(expected.height, scroll.contentView.bounds.height)
        session.hover(first.id)
        host.update(session: session)
        let updated = try XCTUnwrap(host.accessibilityChildren() as? [OnePlusPopupAccessibilityItem])
        XCTAssertTrue(initial[0] === updated[0])
        XCTAssertTrue(initial[1] === updated[1])
        XCTAssertTrue(updated[0].isAccessibilityFocused())
        XCTAssertFalse(updated[1].accessibilityPerformPress())
        var chosen: UUID?
        session.select = { chosen = $0 }
        XCTAssertTrue(updated[0].accessibilityPerformPress())
        XCTAssertEqual(chosen, first.id)
        XCTAssertFalse(window.isVisible)
    }

    func testHighlightMovesAcrossEnabledItemsAndWraps() {
        let alpha = OnePlusPopupMenuItem("Alpha") {}
        let beta = OnePlusPopupMenuItem("Beta", isEnabled: false) {}
        let gamma = OnePlusPopupMenuItem("Gamma") {}
        let entries: [OnePlusPopupMenuEntry] = [
            .section("Section"), .item(alpha), .item(beta), .separator(), .item(gamma),
        ]
        var state = OnePlusPopupNavigationState()

        state.open(entries: entries, initialID: alpha.id)
        XCTAssertEqual(state.handle(.down, entries: entries), .highlight(gamma.id))
        XCTAssertEqual(state.handle(.down, entries: entries), .highlight(alpha.id))
        XCTAssertEqual(state.handle(.up, entries: entries), .highlight(gamma.id))
    }

    func testTypeSelectHighlightsTheFirstEnabledMatch() {
        let automatic = OnePlusPopupMenuItem("Automatic") {}
        let archived = OnePlusPopupMenuItem("Archived", isEnabled: false) {}
        let daily = OnePlusPopupMenuItem("Daily") {}
        let entries: [OnePlusPopupMenuEntry] = [.item(automatic), .item(archived), .item(daily)]
        var state = OnePlusPopupNavigationState()

        state.open(entries: entries, initialID: nil)
        XCTAssertEqual(state.handle(.type("d"), entries: entries, time: 1), .highlight(daily.id))
        XCTAssertEqual(state.handle(.type("a"), entries: entries, time: 2), .highlight(automatic.id))
    }

    func testPlacementUsesBelowThenAboveThenScreenClamp() {
        let screen = CGRect(x: 0, y: 0, width: 500, height: 500)
        let popup = CGSize(width: 100, height: 120)

        XCTAssertEqual(
            OnePlusPopupPlacement.frame(trigger: CGRect(x: 50, y: 300, width: 160, height: 28),
                                        popupSize: popup, screen: screen),
            CGRect(x: 50, y: 176, width: 100, height: 120)
        )
        XCTAssertEqual(
            OnePlusPopupPlacement.frame(trigger: CGRect(x: 50, y: 20, width: 160, height: 28),
                                        popupSize: popup, screen: screen),
            CGRect(x: 50, y: 52, width: 100, height: 120)
        )
        XCTAssertEqual(
            OnePlusPopupPlacement.frame(trigger: CGRect(x: 480, y: 200, width: 20, height: 28),
                                        popupSize: CGSize(width: 100, height: 490), screen: screen),
            CGRect(x: 400, y: 0, width: 100, height: 490)
        )
    }

    func testEscapeClosesAndRequestsTriggerFocus() {
        let item = OnePlusPopupMenuItem("Automatic") {}
        let entries: [OnePlusPopupMenuEntry] = [.item(item)]
        var state = OnePlusPopupNavigationState()

        state.open(entries: entries, initialID: item.id)
        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.handle(.escape, entries: entries), .closeAndRestoreFocus)
        XCTAssertFalse(state.isOpen)
    }
}
