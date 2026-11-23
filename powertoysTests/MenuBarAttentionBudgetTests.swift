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

    func testErrorGlyphShowsOnlyAnUnseenNewestFailure() {
        func job(_ state: TransferState, finished seconds: TimeInterval) -> TransferJob {
            let job = TransferJob(operation: .copy, kind: .directory, sourceFs: "/source", destinationFs: "remote:backup",
                                  sourceDisplay: "source", destinationDisplay: "backup", excludePatterns: [], maxRetries: 3)
            job.state = state
            job.finishedAt = at(seconds)
            return job
        }
        let failed = job(.failed, finished: 10)
        let jobs = [job(.completed, finished: 5), failed]
        XCTAssertEqual(RcloneJobManager.unseenFailure(in: jobs, acknowledged: nil), failed.id)
        XCTAssertNil(RcloneJobManager.unseenFailure(in: jobs, acknowledged: failed.id.uuidString))
        XCTAssertNil(RcloneJobManager.unseenFailure(in: jobs + [job(.completed, finished: 20)], acknowledged: nil))
    }

    func testAwakePulsesBrieflyOnTurnOnThenHoldsStill() {
        var budget = MenuBarAttentionBudget(policy: .awake)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(0), motionAllowed: true), .animating)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(5), motionAllowed: true), .animating)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(6), motionAllowed: true), .working)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(3600), motionAllowed: true), .working)
        XCTAssertEqual(budget.update(.idle, now: at(3601), motionAllowed: true), .idle)
    }

    func testAwakeRetriggerPlaysAtMostOncePer15MinutesAndMotionOffStaysStill() {
        var budget = MenuBarAttentionBudget(policy: .awake)
        _ = budget.update(.running(eta: nil), now: at(0), motionAllowed: true)
        _ = budget.update(.idle, now: at(60), motionAllowed: true)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(120), motionAllowed: true), .working)
        _ = budget.update(.idle, now: at(130), motionAllowed: true)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(15 * 60), motionAllowed: false), .working)
        _ = budget.update(.idle, now: at(16 * 60), motionAllowed: true)
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(31 * 60), motionAllowed: true), .animating)
    }

    func testErrorIsStaticAndMotionOffShowsWorkingGlyph() {
        var budget = MenuBarAttentionBudget()
        XCTAssertEqual(budget.update(.running(eta: nil), now: at(0), motionAllowed: false), .working)
        XCTAssertEqual(budget.update(.failed, now: at(5), motionAllowed: true), .error)
        XCTAssertEqual(budget.update(.idle, now: at(6), motionAllowed: false), .idle)
    }
}
