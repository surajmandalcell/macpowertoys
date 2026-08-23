import XCTest
@testable import powertoys

final class PowerStatsTests: XCTestCase {
    func testCounterDeltasRejectResetsAndCalculateRates() throws {
        XCTAssertEqual(
            try XCTUnwrap(PowerStatsDelta.cpuUsage(previous: (100, 60), current: (200, 100))),
            60,
            accuracy: 0.001
        )
        XCTAssertNil(PowerStatsDelta.cpuUsage(previous: (200, 100), current: (100, 50)))
        XCTAssertEqual(try XCTUnwrap(PowerStatsDelta.rate(previous: 1_000, current: 3_000, seconds: 2)), 1_000)
        XCTAssertNil(PowerStatsDelta.rate(previous: 3_000, current: 1_000, seconds: 2))
    }

    func testDetailedHistoryHasABoundedCeiling() {
        XCTAssertEqual(PowerStatsService.maximumHistoryCount, 120)
    }
}
