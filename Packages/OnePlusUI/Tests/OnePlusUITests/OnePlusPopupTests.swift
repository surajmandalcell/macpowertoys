import CoreGraphics
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusPopupTests: XCTestCase {
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
