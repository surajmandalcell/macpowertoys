import XCTest
@testable import powertoys

final class MenuBarAttentionBudgetTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testWindowLengthFollowsEta() {
        XCTAssertEqual(MenuBarAttentionBudget.windowLength(eta: nil), 45)
        XCTAssertEqual(MenuBarAttentionBudget.windowLength(eta: 10), .infinity)
        XCTAssertEqual(MenuBarAttentionBudget.windowLength(eta: 100), 20)
        XCTAssertEqual(MenuBarAttentionBudget.windowLength(eta: 1000), 80)
        XCTAssertEqual(MenuBarAttentionBudget.windowLength(eta: 10_000), 240)
    }

    func testPlaysOneWindowThenHoldsStill() {
        var budget = MenuBarAttentionBudget()
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(0), motionAllowed: true), .animating)
        XCTAssertEqual(budget.update(.running(eta: 5000), now: at(44), motionAllowed: true), .animating)
        XCTAssertEqual(budget.update(.running(eta: 5000), now: at(45), motionAllowed: true), .working)
        XCTAssertEqual(budget.update(.running(eta: 5000), now: at(600), motionAllowed: true), .working)
    }

    func testShortJobPlaysUntilItEndsThenOneFinishCycle() {
        var budget = MenuBarAttentionBudget()
        XCTAssertEqual(budget.update(.running(eta: 8), now: at(0), motionAllowed: true), .animating)
        XCTAssertEqual(budget.update(.running(eta: 1), now: at(300), motionAllowed: true), .animating)
        XCTAssertEqual(budget.update(.idle, now: at(301), motionAllowed: true), .finishing)
        XCTAssertEqual(budget.update(.idle, now: at(302), motionAllowed: true), .idle)
    }

    func testBurstOfJobsDoesNotFlicker() {
        var budget = MenuBarAttentionBudget()
        XCTAssertEqual(budget.update(.running(eta: 5), now: at(0), motionAllowed: true), .animating)
        XCTAssertEqual(budget.update(.idle, now: at(5), motionAllowed: true), .finishing)
        XCTAssertEqual(budget.update(.running(eta: 5), now: at(60), motionAllowed: true), .working)
        XCTAssertEqual(budget.update(.idle, now: at(65), motionAllowed: true), .idle)
        XCTAssertEqual(budget.update(.running(eta: 5), now: at(15 * 60), motionAllowed: true), .animating)
    }

    func testPauseStopsMotionAndResumeIsATrigger() {
        var budget = MenuBarAttentionBudget()
        _ = budget.update(.running(eta: nil), now: at(0), motionAllowed: true)
        XCTAssertEqual(budget.update(.paused, now: at(10), motionAllowed: true), .idle)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(20), motionAllowed: true), .working)
        XCTAssertEqual(budget.update(.paused, now: at(30), motionAllowed: true), .idle)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(16 * 60), motionAllowed: true), .animating)
    }

    func testErrorIsStaticAndMotionOffShowsWorkingGlyph() {
        var budget = MenuBarAttentionBudget()
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(0), motionAllowed: false), .working)
        XCTAssertEqual(budget.update(.failed, now: at(5), motionAllowed: true), .error)
        XCTAssertEqual(budget.update(.idle, now: at(6), motionAllowed: false), .idle)
    }
}
