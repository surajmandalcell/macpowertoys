import XCTest
@testable import powertoys

final class SystemMonitorRemoteMultiplexTests: XCTestCase {
    func testSSHControlSocketReusesTheConnectionWithoutChangingTheRemoteCommand() throws {
        let path = "/private/tmp/mpt-%C"
        let arguments = try SystemMonitorRemoteProtocol.arguments(
            host: "server", platform: .linux, controlPath: path
        )
        XCTAssertTrue(arguments.contains("ControlMaster=auto"))
        XCTAssertTrue(arguments.contains("ControlPersist=600"))
        XCTAssertTrue(arguments.contains("ControlPath=\(path)"))
        XCTAssertEqual(Array(arguments.suffix(2)), ["server", SystemMonitorRemoteProtocol.command])
    }
}
