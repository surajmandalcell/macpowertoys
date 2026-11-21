import XCTest
@testable import powertoys

final class PortmanForwardModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func sample(_ offset: TimeInterval, cpu: Double? = 20, rx: Double? = 1_000, tx: Double? = 100) -> PortmanServerSample {
        PortmanServerSample(date: now.addingTimeInterval(offset), cpuPercent: cpu, memoryUsed: 4 << 30, memoryTotal: 16 << 30,
                            diskUsed: 40, diskTotal: 100, load: [0.42], uptime: 12 * 86_400, receiveRate: rx, sendRate: tx)
    }

    private func state(_ status: PortmanServerStatus, history: [PortmanServerSample], lastSeen: Date?) -> PortmanServerState {
        PortmanServerState(status: status, latest: history.last, history: history, lastSeen: lastSeen, lastAttempt: lastSeen, failures: 0)
    }

    // MARK: Host card mapping

    func testUnmonitoredHostShowsItsForwardCountAndNoDot() {
        let model = PortmanHostCardModel(monitors: false, forwards: 2, state: nil, now: now)
        XCTAssertEqual(model.health, .unmonitored)
        XCTAssertEqual(model.caption, "2 forwards")
        XCTAssertNil(model.online)
        XCTAssertTrue(model.tiles.isEmpty)
    }

    func testOnlineWithSixtyPointsFillsFourTiles() {
        let history = (0..<60).map { sample(Double($0 - 59) * 2) }
        let model = PortmanHostCardModel(monitors: true, forwards: 1, state: state(.online, history: history, lastSeen: now), now: now)
        XCTAssertEqual(model.health, .online)
        XCTAssertEqual(model.online, true)
        XCTAssertEqual(model.caption, "up 12 d · load 0.42")
        XCTAssertEqual(model.tiles.map(\.kind), [.cpu, .memory, .disk, .network])
        XCTAssertTrue(model.tiles.allSatisfy { $0.series.count == 60 })
        XCTAssertEqual(model.tiles[0].value, "20")
        XCTAssertEqual(model.tiles[2].value, "40")
        XCTAssertEqual(model.tiles[1].unit, "GB")
        XCTAssertEqual(model.tiles[3].secondary.count, 60)
        XCTAssertEqual(model.sparkline.count, 14)
        XCTAssertNotNil(model.memory)
    }

    func testOnePointAndEmptyHistory() {
        let one = PortmanHostCardModel(monitors: true, forwards: 1, state: state(.online, history: [sample(0)], lastSeen: now), now: now)
        XCTAssertEqual(one.tiles.count, 4)
        XCTAssertEqual(one.tiles[0].series, [20])
        let empty = PortmanHostCardModel(monitors: true, forwards: 1, state: state(.waiting, history: [], lastSeen: nil), now: now)
        XCTAssertEqual(empty.health, .waiting)
        XCTAssertEqual(empty.caption, "Connecting")
        XCTAssertTrue(empty.tiles.isEmpty)
        XCTAssertTrue(empty.sparkline.isEmpty)
        XCTAssertEqual(empty.online, false)
    }

    func testOfflineAndAuthFailedSayWhatHappened() {
        let seen = now.addingTimeInterval(-180)
        let offline = PortmanHostCardModel(monitors: true, forwards: 1,
                                           state: state(.failed(.offline), history: [sample(-180)], lastSeen: seen), now: now)
        XCTAssertEqual(offline.health, .offline("Offline"))
        XCTAssertEqual(offline.caption, "no answer for 3 min")
        XCTAssertEqual(offline.online, false)
        let auth = PortmanHostCardModel(monitors: true, forwards: 1, state: state(.failed(.authFailed), history: [], lastSeen: nil), now: now)
        XCTAssertEqual(auth.health, .offline("Auth failed"))
        XCTAssertEqual(auth.caption, "Auth failed · never seen")
    }

    func testOldDataIsStale() {
        let seen = now.addingTimeInterval(-(PortmanHostCardModel.staleAfter + 60))
        let model = PortmanHostCardModel(monitors: true, forwards: 1, state: state(.online, history: [sample(-200)], lastSeen: seen), now: now)
        XCTAssertEqual(model.health, .stale)
        XCTAssertTrue(model.caption.hasPrefix("last data"), model.caption)
    }

    // MARK: Chart scaling

    func testChartScalingHandlesZerosSpikesAndNaN() {
        XCTAssertEqual(PortmanHostCardModel.ceiling([0, 0, 0]), 1)
        XCTAssertEqual(PortmanHostCardModel.ceiling([]), 1)
        XCTAssertEqual(PortmanHostCardModel.ceiling([1, 2, 1_000]), 1_150, accuracy: 0.001)
        XCTAssertEqual(PortmanHostCardModel.ceiling([.nan, 10, .infinity], [20]), 23, accuracy: 0.001)
        let cleaned = PortmanHostCardModel.clean([.nan, -5, 3, .infinity])
        XCTAssertTrue(cleaned[0].isNaN)
        XCTAssertEqual(cleaned[1], 0)
        XCTAssertEqual(cleaned[2], 3)
        XCTAssertTrue(cleaned[3].isNaN)

        let history = [sample(-4, cpu: .nan, rx: .nan, tx: 0), sample(-2, cpu: 0, rx: 0, tx: 0), sample(0, cpu: 100, rx: 5_000_000, tx: 0)]
        let model = PortmanHostCardModel(monitors: true, forwards: 0, state: state(.online, history: history, lastSeen: now), now: now)
        XCTAssertEqual(model.tiles[3].range.upperBound, 5_750_000, accuracy: 1)
        XCTAssertEqual(model.tiles[0].value, "100")
        let nanLast = PortmanHostCardModel(monitors: true, forwards: 0,
                                           state: state(.online, history: [sample(0, cpu: .nan, rx: .nan, tx: .nan)], lastSeen: now), now: now)
        XCTAssertEqual(nanLast.tiles[0].value, "–")
        XCTAssertEqual(nanLast.tiles[3].range.upperBound, 1)
    }

    // MARK: Forward state and retry

    private func tunnel(_ state: PortmanTunnel.State, host: String = "gpu-lab", local: UInt16 = 8888) -> PortmanTunnel {
        PortmanTunnel(id: UUID(), host: host, remotePort: local, localPort: local, state: state)
    }

    func testForwardStateInPlainWords() {
        XCTAssertEqual(PortmanForwardHealth(nil), .stopped)
        XCTAssertEqual(PortmanForwardHealth(tunnel(.running)).label, "Forwarding")
        XCTAssertEqual(PortmanForwardHealth(tunnel(.connecting)).label, "Connecting")
        let cases: [(String, String)] = [
            ("bind [127.0.0.1]:8888: Address already in use", "Port in use"),
            ("channel_setup_fwd_listener_tcpip: cannot listen to port: 8888", "Port in use"),
            ("sam@gpu-lab: Permission denied (publickey,password).", "Auth failed"),
            ("ssh: connect to host gpu-lab port 22: Operation timed out", "Host offline"),
            ("ssh: Could not resolve hostname gpu-lab: nodename nor servname provided", "Host offline"),
            ("WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!", "Host key changed"),
            ("SSH did not open local port 8888.", "Port did not open"),
            ("SSH exited with status 255.", "Tunnel closed"),
        ]
        for (message, label) in cases {
            let health = PortmanForwardHealth(tunnel(.failed(message)))
            XCTAssertEqual(health.label, label, message)
            XCTAssertTrue(health.isDown)
        }
        XCTAssertFalse(PortmanForwardHealth(tunnel(.running)).isDown)
    }

    func testRetryRestartsADeadTunnelAndAsksForAPasswordOnAuthFailure() {
        let dead = tunnel(.failed("bind: Address already in use"))
        let spec = PortmanForwardSpec(remotePort: 8888, localPort: 8888)
        XCTAssertEqual(PortmanForwardRetry.plan(host: "gpu-lab", child: PortmanForwardChild(spec: spec, tunnel: dead)),
                       .restart(stop: dead.id, host: "gpu-lab", remotePort: 8888, localPort: 8888))
        XCTAssertEqual(PortmanForwardRetry.plan(host: "gpu-lab", child: PortmanForwardChild(spec: spec, tunnel: nil)),
                       .restart(stop: nil, host: "gpu-lab", remotePort: 8888, localPort: 8888))
        XCTAssertNil(PortmanForwardRetry.plan(host: "gpu-lab", child: PortmanForwardChild(spec: spec, tunnel: tunnel(.running))))
        let auth = tunnel(.failed("Permission denied (publickey,password)."))
        XCTAssertEqual(PortmanForwardRetry.plan(host: "gpu-lab", child: PortmanForwardChild(spec: spec, tunnel: auth)),
                       .askPassword(tunnel: auth.id))
    }

    func testReconnectAllRunsEveryDownForwardThroughTheSeams() {
        let dead = tunnel(.failed("SSH exited with status 255."), local: 8000)
        let live = tunnel(.running, local: 8080)
        let host = PortmanHost(destination: "gpu-lab", mode: .both, forwards: [
            PortmanForwardSpec(remotePort: 8000, localPort: 8000), PortmanForwardSpec(remotePort: 8080, localPort: 8080),
            PortmanForwardSpec(remotePort: 9000, localPort: 9000),
        ])
        let group = PortmanForwardTree.groups(hosts: [host], tunnels: [dead, live])[0]
        var stopped: [UUID] = [], forwarded: [UInt16] = [], asked: [UUID] = []
        PortmanForwardRetry.run(PortmanForwardRetry.plan(group: group), stop: { stopped.append($0) },
                                forward: { _, _, local in forwarded.append(local); return true }, askPassword: { asked.append($0) })
        XCTAssertEqual(stopped, [dead.id])
        XCTAssertEqual(forwarded, [8000, 9000])
        XCTAssertTrue(asked.isEmpty)

        let auth = tunnel(.failed("Permission denied (password)."), local: 8000)
        let authGroup = PortmanForwardTree.groups(hosts: [host], tunnels: [auth, live])[0]
        XCTAssertEqual(PortmanForwardRetry.plan(group: authGroup), [.askPassword(tunnel: auth.id)])
        XCTAssertEqual(PortmanForwardRetry.afterPassword(host: "gpu-lab", tunnels: [auth, live, tunnel(.failed("x"), host: "other")]),
                       [.restart(stop: auth.id, host: "gpu-lab", remotePort: 8000, localPort: 8000)])
    }

    // MARK: Open hosts

    func testOpenHostsDefaultToTheFirstAndRemember() {
        let first = PortmanPanelView.firstHostOpen
        XCTAssertTrue(PortmanPanelView.isOpen("build-box", first: true, in: first))
        XCTAssertFalse(PortmanPanelView.isOpen("staging-eu", first: false, in: first))
        let closed = PortmanPanelView.toggled("build-box", open: true, in: first)
        XCTAssertFalse(PortmanPanelView.isOpen("build-box", first: true, in: closed))
        let opened = PortmanPanelView.toggled("staging-eu", open: false, in: closed)
        XCTAssertTrue(PortmanPanelView.isOpen("staging-eu", first: false, in: opened))
        XCTAssertFalse(PortmanPanelView.isOpen("build-box", first: true, in: opened))
    }
}
