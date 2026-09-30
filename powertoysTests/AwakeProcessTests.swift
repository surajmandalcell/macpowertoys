import Darwin
import XCTest
@testable import powertoys

@MainActor
final class AwakeProcessTests: XCTestCase {
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
