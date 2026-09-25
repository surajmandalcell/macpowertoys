import XCTest
@testable import powertoys

final class FanControlTests: XCTestCase {
    @MainActor
    func testVisibleOwnersShareAndReleaseOnePoller() {
        let service = FanControlService.shared
        for _ in 0..<25 {
            service.start(owner: "fan-test-home")
            service.start(owner: "fan-test-window")
            XCTAssertEqual(service.pollOwnerCount, 1)

            service.stop(owner: "fan-test-home")
            XCTAssertEqual(service.pollOwnerCount, 1)
            service.stop(owner: "fan-test-window")
            XCTAssertEqual(service.pollOwnerCount, 0)
        }
    }

    func testRealFanTextReportsRPMAndPercentWithoutClaimingControl() throws {
        let sample = """
        Number of fans: 2.0

        0: Fan #0
        Actual speed: 3462.0
        Minimal speed: 1350.0
        Maximum speed: 5777.0
        Target speed: 3466.0
        Mode: forced

        1: Fan #1
        Actual speed: 3482.0
        Minimal speed: 1350.0
        Maximum speed: 5777.0
        Target speed: 3466.0
        Mode: forced
        """
        let snapshot = try XCTUnwrap(FanCommand.parseStatsFans(sample))

        XCTAssertEqual(snapshot.fans.map(\.index), [0, 1])
        XCTAssertEqual(snapshot.averageRPM, 3_472)
        XCTAssertEqual(snapshot.utilization, 60)
        XCTAssertFalse(snapshot.canControl)
        XCTAssertNil(snapshot.detectedPreset)
        XCTAssertTrue(snapshot.hasExternalManualControl)
    }

    func testCoolAndMaxOnlyRequestGuardedFullProfile() {
        XCTAssertEqual(FanCommand.arguments(for: .cool), ["fan", "profile", "full"])
        XCTAssertEqual(FanCommand.arguments(for: .max), ["fan", "profile", "full"])
        XCTAssertEqual(FanCommand.arguments(for: .auto), ["fan", "profile", "auto"])
    }

    func testSmctlStatusRequiresReadableFanModesForControl() throws {
        let output = """
        {"profile":"auto","fans":[
          {"index":0,"actualRPM":3462,"maximumRPM":5777,"mode":"auto"},
          {"index":1,"actualRPM":3482,"maximumRPM":5777,"mode":"system"}
        ]}
        """
        let snapshot = try XCTUnwrap(FanCommand.parseSmctlStatus(output))
        XCTAssertTrue(snapshot.canControl)
        XCTAssertEqual(snapshot.detectedPreset, .auto)
        XCTAssertEqual(snapshot.utilization, 60)

        let unknown = output.replacingOccurrences(of: "\"mode\":\"system\"", with: "\"mode\":\"unknown\"")
        XCTAssertFalse(try XCTUnwrap(FanCommand.parseSmctlStatus(unknown)).canControl)
    }
}
