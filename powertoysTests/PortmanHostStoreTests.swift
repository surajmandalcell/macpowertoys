import Foundation
import XCTest
@testable import powertoys

@MainActor
final class PortmanHostStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "portman-host-store-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func savedJSON() throws -> [String: Any] {
        let data = try XCTUnwrap(defaults.data(forKey: PortmanHostStore.key))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Migration

    func testNothingSavedLoadsEmptyAndWritesNothing() {
        XCTAssertEqual(PortmanHostStore.load(defaults), [])
        XCTAssertNil(defaults.object(forKey: PortmanHostStore.key))
    }

    func testLegacySingleHostBecomesAMonitoredHost() throws {
        defaults.set("oci2", forKey: "systemMonitor.remoteHost")
        let hosts = PortmanHostStore.load(defaults)
        XCTAssertEqual(hosts, [PortmanHost(destination: "oci2", mode: .monitor)])
        XCTAssertEqual(try savedJSON()["version"] as? Int, 1)
        XCTAssertEqual(defaults.string(forKey: "systemMonitor.remoteHost"), "oci2", "legacy key stays for a downgrade")
        XCTAssertEqual(PortmanHostStore.load(defaults), hosts, "second load reads the new key")
    }

    func testLegacyProfilesKeepUserAndPort() throws {
        let profiles: [[String: Any]] = [
            ["id": "a", "name": "Box", "host": "box.example.com", "platform": "Linux", "interval": 30,
             "user": "sam", "port": 2222],
            ["id": "b", "name": "Mini", "host": "mini", "platform": "macOS", "interval": 5],
            ["id": "c", "name": "Bad", "host": "-oProxyCommand=x", "platform": "Linux", "interval": 30],
            ["id": "d", "name": "Port", "host": "edge", "platform": "Linux", "interval": 30, "port": 99_999],
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: profiles), forKey: "systemMonitor.remoteHosts")
        defaults.set("ignored", forKey: "systemMonitor.remoteHost")
        XCTAssertEqual(PortmanHostStore.load(defaults), [
            PortmanHost(destination: "sam@box.example.com", mode: .monitor, port: 2222),
            PortmanHost(destination: "mini", mode: .monitor),
            PortmanHost(destination: "edge", mode: .monitor),
        ])
    }

    func testEmptyLegacyProfilesFallBackToTheSingleHost() throws {
        defaults.set(Data("[]".utf8), forKey: "systemMonitor.remoteHosts")
        defaults.set("oci2", forKey: "systemMonitor.remoteHost")
        XCTAssertEqual(PortmanHostStore.load(defaults).map(\.destination), ["oci2"])
    }

    func testInvalidLegacyHostIsSkipped() {
        defaults.set("bad host; rm", forKey: "systemMonitor.remoteHost")
        XCTAssertEqual(PortmanHostStore.load(defaults), [])
        XCTAssertNil(defaults.object(forKey: PortmanHostStore.key))
    }

    func testNewKeyWinsOverLegacy() {
        PortmanHostStore.save([PortmanHost(destination: "lin1", mode: .forward)], defaults)
        defaults.set("oci2", forKey: "systemMonitor.remoteHost")
        XCTAssertEqual(PortmanHostStore.load(defaults).map(\.destination), ["lin1"])
    }

    func testSavedEmptyListStaysEmpty() {
        PortmanHostStore.save([], defaults)
        defaults.set("oci2", forKey: "systemMonitor.remoteHost")
        XCTAssertEqual(PortmanHostStore.load(defaults), [], "removing every host must not bring the legacy host back")
    }

    func testRoundTripKeepsForwardsAndPort() {
        let hosts = [
            PortmanHost(destination: "oci1", mode: .both, port: 2200, forwards: [
                PortmanForwardSpec(remotePort: 8080, localPort: 18080),
                PortmanForwardSpec(remotePort: 5432, localPort: 15432),
            ]),
            PortmanHost(destination: "sam@10.0.0.4", mode: .forward),
        ]
        PortmanHostStore.save(hosts, defaults)
        XCTAssertEqual(PortmanHostStore.load(defaults), hosts)
    }

    // MARK: Order

    private func list(_ names: [String]) -> PortmanHostList {
        PortmanHostStore.save(names.map { PortmanHost(destination: $0, mode: .forward) }, defaults)
        return PortmanHostList(defaults: defaults)
    }

    private func order(_ list: PortmanHostList) -> [String] { list.hosts.map(\.destination) }
    private func savedOrder() -> [String] { PortmanHostList(defaults: defaults).hosts.map(\.destination) }

    func testOrderMovedHandlesEveryEdge() {
        XCTAssertEqual(PortmanOrder.moved([1, 2, 3], from: 0, to: 2), [2, 3, 1])
        XCTAssertEqual(PortmanOrder.moved([1, 2, 3], from: 2, to: 0), [3, 1, 2])
        XCTAssertEqual(PortmanOrder.moved([1, 2, 3], from: 1, to: 2), [1, 3, 2])
        XCTAssertNil(PortmanOrder.moved([1, 2, 3], from: 1, to: 1), "no-op")
        XCTAssertNil(PortmanOrder.moved([1, 2, 3], from: 0, to: 3), "past the end")
        XCTAssertNil(PortmanOrder.moved([1, 2, 3], from: -1, to: 0), "negative")
        XCTAssertNil(PortmanOrder.moved([1], from: 0, to: 0), "one item")
        XCTAssertNil(PortmanOrder.moved([Int](), from: 0, to: 0), "empty")
    }

    func testMoveFirstHostToLastSavesAndSurvivesRelaunch() {
        let hosts = list(["a", "b", "c"])
        hosts.moveHost("a", to: 2)
        XCTAssertEqual(order(hosts), ["b", "c", "a"])
        XCTAssertEqual(savedOrder(), ["b", "c", "a"])
    }

    func testMoveLastHostToFirst() {
        let hosts = list(["a", "b", "c"])
        hosts.moveHost("c", to: 0)
        XCTAssertEqual(savedOrder(), ["c", "a", "b"])
    }

    func testNoOpAndOutOfRangeHostMovesChangeNothingAndDoNotSave() {
        let hosts = list(["a", "b", "c"])
        var changes = 0
        hosts.onChange = { _ in changes += 1 }
        hosts.moveHost("b", to: 1)
        hosts.moveHost("b", to: 3)
        hosts.moveHost("b", to: -1)
        hosts.moveHost("missing", to: 0)
        XCTAssertEqual(order(hosts), ["a", "b", "c"])
        XCTAssertEqual(changes, 0)
    }

    func testMoveWithOneHostDoesNothing() {
        let hosts = list(["solo"])
        hosts.moveHost("solo", to: 0)
        hosts.moveHost("solo", to: 1)
        XCTAssertEqual(savedOrder(), ["solo"])
    }

    func testRemovedAndAddedHostsKeepTheOthersOrder() {
        let hosts = list(["a", "b", "c", "d"])
        hosts.moveHost("d", to: 0)
        hosts.remove("b")
        XCTAssertEqual(savedOrder(), ["d", "a", "c"])
        hosts.add("e", mode: .monitor)
        hosts.recordForward(host: "f", remotePort: 80, localPort: 8080)
        XCTAssertEqual(savedOrder(), ["d", "a", "c", "e", "f"], "new hosts go at the end")
    }

    func testOldSavedDataLoadsInItsSavedOrderAndTakesAMove() throws {
        // Written by the build before reordering: version 1, no order field; the array order is the card order.
        let old = #"{"version":1,"hosts":[{"destination":"oci2","mode":"monitor"},{"destination":"lin1","mode":"both","forwards":[{"remotePort":5432,"localPort":5432},{"remotePort":80,"localPort":8080}]},{"destination":"oci1","mode":"forward"}]}"#
        defaults.set(Data(old.utf8), forKey: PortmanHostStore.key)
        let hosts = PortmanHostList(defaults: defaults)
        XCTAssertEqual(order(hosts), ["oci2", "lin1", "oci1"])
        hosts.moveHost("oci1", to: 0)
        hosts.moveForward(host: "lin1", localPort: 8080, to: 0)
        let reloaded = PortmanHostList(defaults: defaults)
        XCTAssertEqual(order(reloaded), ["oci1", "oci2", "lin1"])
        XCTAssertEqual(reloaded.host("lin1")?.forwards.map(\.localPort), [8080, 5432])
        XCTAssertEqual(try savedJSON()["version"] as? Int, PortmanHostStore.version)
    }

    func testForwardMovesStayInsideTheirHost() {
        PortmanHostStore.save([
            PortmanHost(destination: "a", mode: .forward, forwards: [.init(remotePort: 1, localPort: 1001),
                                                                     .init(remotePort: 2, localPort: 1002),
                                                                     .init(remotePort: 3, localPort: 1003)]),
            PortmanHost(destination: "b", mode: .forward, forwards: [.init(remotePort: 9, localPort: 1009)]),
        ], defaults)
        let hosts = PortmanHostList(defaults: defaults)
        hosts.moveForward(host: "a", localPort: 1001, to: 2)
        hosts.moveForward(host: "a", localPort: 1002, to: 5)
        hosts.moveForward(host: "b", localPort: 1001, to: 0)
        hosts.moveForward(host: "b", localPort: 1009, to: 1)
        let reloaded = PortmanHostList(defaults: defaults)
        XCTAssertEqual(reloaded.host("a")?.forwards.map(\.localPort), [1002, 1003, 1001])
        XCTAssertEqual(reloaded.host("b")?.forwards.map(\.localPort), [1009], "a forward never changes host")
        XCTAssertEqual(order(reloaded), ["a", "b"])
    }

    func testOrderIsKeptWhenTunnelAndMonitorStatesChange() {
        let hosts = list(["a", "b", "c"])
        hosts.moveHost("c", to: 0)
        hosts.setMode(.both, for: "a")
        hosts.setMode(.monitor, for: "c")
        let running = PortmanForwardTree.groups(hosts: hosts.hosts, tunnels: [tunnel("b", 80, 8080), tunnel("a", 81, 8081)])
        let failed = PortmanForwardTree.groups(hosts: hosts.hosts, tunnels: [
            PortmanTunnel(id: UUID(), host: "a", remotePort: 81, localPort: 8081, state: .failed("timed out")),
        ])
        XCTAssertEqual(running.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(failed.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(savedOrder(), ["c", "a", "b"])
    }

    func testUnreadableDataIsKeptAsideNotOverwritten() {
        let junk = Data("not json".utf8)
        defaults.set(junk, forKey: PortmanHostStore.key)
        defaults.set("oci2", forKey: "systemMonitor.remoteHost")
        XCTAssertEqual(PortmanHostStore.load(defaults).map(\.destination), ["oci2"])
        XCTAssertEqual(defaults.data(forKey: PortmanHostStore.unreadableKey), junk)
        defaults.set(Data("again".utf8), forKey: PortmanHostStore.key)
        _ = PortmanHostStore.load(defaults)
        XCTAssertEqual(defaults.data(forKey: PortmanHostStore.unreadableKey), junk, "the first backup is never replaced")
    }

    func testUnknownModeAndMissingFieldsDecode() throws {
        let json = #"{"version":2,"hosts":[{"destination":"a","mode":"future"},{"destination":"b","mode":"monitor","forwards":[{"remotePort":0,"localPort":1}]}]}"#
        defaults.set(Data(json.utf8), forKey: PortmanHostStore.key)
        XCTAssertEqual(PortmanHostStore.load(defaults), [
            PortmanHost(destination: "a", mode: .forward),
            PortmanHost(destination: "b", mode: .monitor),
        ])
    }

    func testNormalizedMergesDuplicatesAndDropsBadEntries() {
        let hosts = PortmanHostStore.normalized([
            PortmanHost(destination: " box ", mode: .monitor, forwards: [
                PortmanForwardSpec(remotePort: 80, localPort: 8080),
                PortmanForwardSpec(remotePort: 81, localPort: 8080),
            ]),
            PortmanHost(destination: "box", mode: .forward, forwards: [
                PortmanForwardSpec(remotePort: 443, localPort: 8443),
                PortmanForwardSpec(remotePort: 90, localPort: 8080),
            ]),
            PortmanHost(destination: "", mode: .both),
            PortmanHost(destination: "a b", mode: .both),
        ])
        XCTAssertEqual(hosts, [PortmanHost(destination: "box", mode: .monitor, forwards: [
            PortmanForwardSpec(remotePort: 80, localPort: 8080),
            PortmanForwardSpec(remotePort: 443, localPort: 8443),
        ])])
    }

    func testModeFlags() {
        XCTAssertFalse(PortmanHostMode.forward.monitors)
        XCTAssertTrue(PortmanHostMode.monitor.monitors)
        XCTAssertTrue(PortmanHostMode.both.monitors)
        XCTAssertTrue(PortmanHostMode.forward.forwards)
        XCTAssertFalse(PortmanHostMode.monitor.forwards)
        XCTAssertEqual(PortmanHostMode.allCases.map(\.title), ["Forward ports", "Monitor", "Both"])
    }

    // MARK: Host list

    func testHostListAddChangeAndRemoveSave() {
        let list = PortmanHostList(defaults: defaults)
        var reported: [[PortmanHost]] = []
        list.onChange = { reported.append($0) }
        XCTAssertTrue(list.add("oci2", mode: .monitor))
        XCTAssertFalse(list.add("bad host", mode: .both))
        XCTAssertTrue(list.add("oci2", mode: .both), "adding again updates the mode")
        XCTAssertEqual(list.hosts, [PortmanHost(destination: "oci2", mode: .both)])
        list.setMode(.forward, for: "oci2")
        XCTAssertEqual(PortmanHostList(defaults: defaults).hosts.first?.mode, .forward)
        list.remove("oci2")
        XCTAssertEqual(PortmanHostList(defaults: defaults).hosts, [])
        XCTAssertEqual(reported.count, 4)
    }

    func testRecordForwardAttachesToItsHost() {
        let list = PortmanHostList(defaults: defaults)
        list.add("mon", mode: .monitor)
        list.recordForward(host: "mon", remotePort: 3000, localPort: 13000)
        list.recordForward(host: "new", remotePort: 22, localPort: 2222)
        list.recordForward(host: "mon", remotePort: 3001, localPort: 13000)
        list.recordForward(host: "bad host", remotePort: 1, localPort: 1)
        XCTAssertEqual(list.hosts, [
            PortmanHost(destination: "mon", mode: .both, forwards: [PortmanForwardSpec(remotePort: 3001, localPort: 13000)]),
            PortmanHost(destination: "new", mode: .forward, forwards: [PortmanForwardSpec(remotePort: 22, localPort: 2222)]),
        ])
        list.removeForward(host: "mon", localPort: 13000)
        XCTAssertEqual(PortmanHostList(defaults: defaults).hosts.first?.forwards, [])
    }

    // MARK: Forward tree

    private func tunnel(_ host: String, _ remote: UInt16, _ local: UInt16) -> PortmanTunnel {
        PortmanTunnel(id: UUID(), host: host, remotePort: remote, localPort: local, state: .running)
    }

    func testTunnelsAttachToTheirSavedHost() {
        let hosts = [
            PortmanHost(destination: "a", mode: .both, forwards: [
                PortmanForwardSpec(remotePort: 80, localPort: 8080),
                PortmanForwardSpec(remotePort: 81, localPort: 8081),
            ]),
            PortmanHost(destination: "b", mode: .monitor),
        ]
        let live = tunnel("a", 80, 8080)
        let extra = tunnel("a", 9000, 9000)
        let groups = PortmanForwardTree.groups(hosts: hosts, tunnels: [live, tunnel("z", 1, 1001), extra, tunnel("z", 2, 1002)])
        XCTAssertEqual(groups.map(\.id), ["a", "b", "z"])
        XCTAssertEqual(groups[0].children.map(\.spec.localPort), [8080, 8081, 9000])
        XCTAssertEqual(groups[0].children[0].tunnel?.id, live.id)
        XCTAssertNil(groups[0].children[1].tunnel, "saved but stopped")
        XCTAssertEqual(groups[0].children[2].tunnel?.id, extra.id)
        XCTAssertTrue(groups[1].children.isEmpty)
        XCTAssertFalse(groups[2].saved)
        XCTAssertEqual(groups[2].children.map(\.spec.localPort), [1001, 1002])
    }

    func testTunnelWithADifferentRemotePortIsNotTheSavedForward() {
        let hosts = [PortmanHost(destination: "a", mode: .forward, forwards: [PortmanForwardSpec(remotePort: 80, localPort: 8080)])]
        let groups = PortmanForwardTree.groups(hosts: hosts, tunnels: [tunnel("a", 81, 8080)])
        XCTAssertEqual(groups[0].children.count, 2)
        XCTAssertNil(groups[0].children[0].tunnel)
    }

    func testNoHostsAndNoTunnelsGivesNoGroups() {
        XCTAssertTrue(PortmanForwardTree.groups(hosts: [], tunnels: []).isEmpty)
    }

    func testScanMarksSavedForwardsAndLiveTunnelsOfThatHostOnly() {
        let hosts = [PortmanHost(destination: "oci2", mode: .both, forwards: [PortmanForwardSpec(remotePort: 5432, localPort: 15432)]),
                     PortmanHost(destination: "oci1", mode: .monitor, forwards: [PortmanForwardSpec(remotePort: 80, localPort: 8080)])]
        let tunnels = [PortmanTunnel(id: UUID(), host: "oci2", remotePort: 6379, localPort: 6379, state: .running),
                       PortmanTunnel(id: UUID(), host: "oci1", remotePort: 22, localPort: 2222, state: .running)]
        XCTAssertEqual(PortmanForwardTree.addedRemotePorts(host: "oci2", hosts: hosts, tunnels: tunnels), [5432, 6379])
        XCTAssertEqual(PortmanForwardTree.addedRemotePorts(host: "lab", hosts: hosts, tunnels: tunnels), [])
    }
}
