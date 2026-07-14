import XCTest
@testable import powertoys

final class AppDelegateTests: XCTestCase {
    func testStatusItemInterceptsLeftAndRightClicks() {
        XCTAssertTrue(AppDelegate.statusItemEventMask.contains(.leftMouseDown))
        XCTAssertTrue(AppDelegate.statusItemEventMask.contains(.rightMouseDown))
    }

    @MainActor
    func testStatusItemContextMenuContainsOnlyOpenAndQuit() {
        let menu = AppDelegate().statusItemContextMenu()

        XCTAssertEqual(menu.items.map(\.title), ["Open MacPowerToys", "Quit"])
        XCTAssertTrue(menu.items.allSatisfy { $0.image != nil })
        XCTAssertEqual(
            menu.items.map(\.action),
            [
                #selector(AppDelegate.openMainWindowFromStatusItem),
                #selector(AppDelegate.quitFromStatusItem)
            ]
        )
    }

    @MainActor
    func testDoubleClickCancelsDelayedSingleClick() async throws {
        let coordinator = StatusItemClickCoordinator(delay: 0.01)
        var singleClicks = 0
        var doubleClicks = 0

        coordinator.handle(
            clickCount: 1,
            singleClick: { singleClicks += 1 },
            doubleClick: { doubleClicks += 1 }
        )
        coordinator.handle(
            clickCount: 2,
            singleClick: { singleClicks += 1 },
            doubleClick: { doubleClicks += 1 }
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(singleClicks, 0)
        XCTAssertEqual(doubleClicks, 1)
    }

    @MainActor
    func testSingleClickRunsAfterDelay() async throws {
        let coordinator = StatusItemClickCoordinator(delay: 0.01)
        var singleClicks = 0

        coordinator.handle(
            clickCount: 1,
            singleClick: { singleClicks += 1 },
            doubleClick: {}
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(singleClicks, 1)
    }
}
