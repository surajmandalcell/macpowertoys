import XCTest
@testable import powertoys

final class SystemMonitorTests: XCTestCase {
    func testCounterDeltasRejectResetsAndCalculateRates() throws {
        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorDelta.cpuUsage(previous: (100, 60), current: (200, 100))),
            60,
            accuracy: 0.001
        )
        XCTAssertNil(SystemMonitorDelta.cpuUsage(previous: (200, 100), current: (100, 50)))
        XCTAssertEqual(try XCTUnwrap(SystemMonitorDelta.rate(previous: 1_000, current: 3_000, seconds: 2)), 1_000)
        XCTAssertNil(SystemMonitorDelta.rate(previous: 3_000, current: 1_000, seconds: 2))
    }

    func testDetailedHistoryHasABoundedCeiling() {
        XCTAssertEqual(SystemMonitorService.maximumHistoryCount, 120)
    }

    @MainActor
    func testLegacyMenuSettingsLoadWhenCurrentSettingsAreAbsent() throws {
        let suite = "SystemMonitorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = SystemMonitorMenuSettings(
            enabled: true,
            mode: .direct,
            interval: 3,
            metrics: [.network]
        )
        defaults.set(try JSONEncoder().encode(expected), forKey: SystemMonitorService.legacySettingsKey)

        XCTAssertEqual(SystemMonitorService.storedMenuSettings(in: defaults), expected)
    }
}
