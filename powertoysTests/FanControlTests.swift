import Darwin
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

    @MainActor
    func testFirstFanReadMarksUnavailableDataAsResolved() async {
        let service = FanControlService.shared
        service.start(owner: "fan-test-read")
        await service.refresh()
        XCTAssertTrue(service.hasCompletedRead)
        service.stop(owner: "fan-test-read")
        XCTAssertEqual(service.pollOwnerCount, 0)
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

    func testNativeSMCFanDecodingAndKernelLayout() {
        XCTAssertTrue(NativeFanReader.hasExpectedLayout)
        XCTAssertEqual(NativeFanReader.decodeNumber([2], type: "ui8 "), 2)
        XCTAssertEqual(NativeFanReader.decodeNumber([0x00, 0x60, 0x58, 0x45], type: "flt "), 3_462)
        XCTAssertEqual(NativeFanReader.decodeNumber([0x36, 0x18], type: "fpe2"), 3_462)
        XCTAssertEqual(NativeFanReader.decodeNumber([0x12, 0x34], type: "ui16", littleEndianIntegers: true), 0x3412)
        XCTAssertEqual(NativeFanReader.decodeNumber([0x12, 0x34], type: "ui16", littleEndianIntegers: false), 0x1234)
        XCTAssertNil(NativeFanReader.decodeNumber([0x12], type: "ui16"))
        XCTAssertEqual(NativeFanReader.encodeNumber(3_462, type: "fpe2"), [0x36, 0x18])
        XCTAssertEqual(NativeFanReader.encodeNumber(3_462, type: "flt "), [0x00, 0x60, 0x58, 0x45])
        XCTAssertNil(NativeFanReader.encodeNumber(100_000, type: "fpe2"))
    }

    func testFanWritesRejectAnUnprivilegedProcess() {
        guard geteuid() != 0 else { return }
        XCTAssertThrowsError(try NativeFanReader.apply(.max))
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

    func testFanCommandBoundsProcessOutputWithoutHardwareAccess() {
        XCTAssertThrowsError(try FanCommand.run("/usr/bin/printf", ["%262145s", "x"])) { error in
            XCTAssertEqual(error.localizedDescription, "The fan helper returned too much data.")
        }
    }

    func testFanCommandStopsProcessThatIgnoresTermination() {
        let started = Date()
        XCTAssertThrowsError(try FanCommand.run("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 30"]))
        XCTAssertLessThan(Date().timeIntervalSince(started), 9)
    }
}
