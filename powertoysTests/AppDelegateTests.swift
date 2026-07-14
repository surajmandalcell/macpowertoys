import XCTest
@testable import powertoys

final class AppDelegateTests: XCTestCase {
    func testOnlyStatusItemDoubleClickOpensMainWindow() {
        XCTAssertTrue(AppDelegate.shouldOpenMainWindowForStatusClick(
            clickCount: 2,
            isStatusItem: true
        ))
        XCTAssertFalse(AppDelegate.shouldOpenMainWindowForStatusClick(
            clickCount: 1,
            isStatusItem: true
        ))
        XCTAssertFalse(AppDelegate.shouldOpenMainWindowForStatusClick(
            clickCount: 2,
            isStatusItem: false
        ))
    }
}
