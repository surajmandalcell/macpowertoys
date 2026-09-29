import AppKit
import XCTest
@testable import OnePlusUI

final class OnePlusLiveUpdatesTests: XCTestCase {
    func testVisibilityRequiresAVisibleUnminimizedUnoccludedWindow() {
        let visible: NSWindow.OcclusionState = [.visible]
        XCTAssertTrue(OnePlusWindowVisibility.isActive(
            isVisible: true, isMiniaturized: false, occlusionState: visible))
        XCTAssertFalse(OnePlusWindowVisibility.isActive(
            isVisible: false, isMiniaturized: false, occlusionState: visible))
        XCTAssertFalse(OnePlusWindowVisibility.isActive(
            isVisible: true, isMiniaturized: true, occlusionState: visible))
        XCTAssertFalse(OnePlusWindowVisibility.isActive(
            isVisible: true, isMiniaturized: false, occlusionState: []))
    }
}
