import XCTest
@testable import powertoys

final class NetToysSSHAnchorRecoveryTests: XCTestCase {
    func testLocalCandidateSwitchDecisionMatrix() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var routeMonitor = SSHAnchorRouteMonitor()
        routeMonitor.didSwitch(to: .tailscale, at: startedAt)
        let candidate = SSHAnchorConfiguration(
            hostAlias: "test-anchor",
            hostName: "192.0.2.2",
            port: 22,
            identity: .stableMAC("00:00:5e:00:53:01")
        )
        let cases: [(String, TimeInterval, SSHAnchorConfiguration?, SSHAnchorRouteAction, Bool)] = [
            ("fallback off after one success", 10, candidate, .none, false),
            ("Tailscale down after two successes", 20, candidate, .none, false),
            ("three successes before dwell", 29, candidate, .none, false),
            ("stable success after dwell", 31, candidate, .useLocal, true),
            ("no candidate after gate", 32, nil, .useLocal, false),
        ]

        for (name, seconds, discovered, expectedAction, shouldSwitch) in cases {
            let action = routeMonitor.observe(
                route: .tailscale,
                localIsOpen: true,
                at: startedAt.addingTimeInterval(seconds)
            )
            let result = NetToysHelperRuntime.localSwitchCandidate(
                discovered,
                routeAction: action
            )
            XCTAssertEqual(action, expectedAction, name)
            XCTAssertEqual(result != nil, shouldSwitch, name)
        }
    }
}
