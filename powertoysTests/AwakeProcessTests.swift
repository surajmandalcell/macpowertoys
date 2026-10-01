import Darwin
import XCTest
@testable import powertoys

@MainActor
final class AwakeProcessTests: XCTestCase {
    func testDurationInputRejectsValuesThatCannotReachTheClockOrDisplay() {
        for invalid in [TimeInterval.nan, .infinity, -.infinity, 1e300, -1] {
            XCTAssertFalse(AwakeService.isValidDuration(invalid))
            XCTAssertEqual(AwakeService.duration(invalid), "00:00")
            XCTAssertEqual(AwakeService.presetLabel(invalid), "00:00")
        }
        XCTAssertTrue(AwakeService.isValidDuration(0))
        XCTAssertTrue(AwakeService.isValidDuration(168 * 3600 + 59 * 60))
        XCTAssertTrue(AwakeService.isValidDuration(TimeInterval(Int32.max)))
    }

    func testProcessAttachmentChecksExistenceWithoutSendingSignals() throws {
        XCTAssertTrue(AwakeService.processIsRunning(getpid()))
        XCTAssertTrue(AwakeService.processIsRunning(1))
        XCTAssertFalse(AwakeService.processIsRunning(0))
        XCTAssertFalse(AwakeService.processIsRunning(-1))
        XCTAssertFalse(AwakeService.processIsRunning(Int32.max))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        XCTAssertFalse(AwakeService.processIsRunning(process.processIdentifier))
    }
}
