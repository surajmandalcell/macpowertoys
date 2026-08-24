import Foundation
import Darwin
import XCTest
@testable import powertoys

final class NetToysTests: XCTestCase {
    func testIPv4TargetsParseRangeCIDRAndListWithoutDuplicates() throws {
        XCTAssertEqual(
            try IPv4Targets.parse("192.168.1.3-192.168.1.5").map(\.description),
            ["192.168.1.3", "192.168.1.4", "192.168.1.5"]
        )
        XCTAssertEqual(
            try IPv4Targets.parse("10.0.0.0/30").map(\.description),
            ["10.0.0.1", "10.0.0.2"]
        )
        XCTAssertEqual(
            try IPv4Targets.parse("10.0.0.2, 10.0.0.1, 10.0.0.2").map(\.description),
            ["10.0.0.2", "10.0.0.1"]
        )
        XCTAssertThrowsError(try IPv4Targets.parse("10.0.0.0/8", limit: 1_024))
    }

    func testSSHConfigReplacementChangesOnlySelectedHostNameToken() throws {
        let input = Data("# keep\r\nHost jetson nano\r\n\tUser suraj\r\n\tHostName\t192.168.1.8   # keep this\r\n\tPort 2222\r\nHost other\r\n  HostName 10.0.0.2".utf8)

        let edit = try SSHConfigEditor.replacingHostName(
            in: input,
            hostAlias: "jetson",
            expectedHostName: "192.168.1.8",
            newHostName: "192.168.1.44"
        )

        let expected = Data("# keep\r\nHost jetson nano\r\n\tUser suraj\r\n\tHostName\t192.168.1.44   # keep this\r\n\tPort 2222\r\nHost other\r\n  HostName 10.0.0.2".utf8)
        XCTAssertEqual(edit.data, expected)
        XCTAssertEqual(edit.oldValue, "192.168.1.8")
        XCTAssertEqual(edit.newValue, "192.168.1.44")
        XCTAssertEqual(edit.data.prefix(edit.changedRange.lowerBound), input.prefix(edit.changedRange.lowerBound))
        XCTAssertEqual(edit.data.suffix(from: edit.changedRange.upperBound), input.suffix(from: edit.originalRange.upperBound))
    }

    func testSSHConfigReplacementRejectsUnexpectedValueAndMatchBlock() throws {
        let input = Data("Host jetson\n  HostName 192.168.1.8\nMatch host jetson\n  HostName 10.0.0.2\n".utf8)

        XCTAssertThrowsError(
            try SSHConfigEditor.replacingHostName(
                in: input,
                hostAlias: "jetson",
                expectedHostName: "192.168.1.9",
                newHostName: "192.168.1.44"
            )
        )
        let edit = try SSHConfigEditor.replacingHostName(
            in: input,
            hostAlias: "jetson",
            expectedHostName: "192.168.1.8",
            newHostName: "192.168.1.44"
        )
        XCTAssertEqual(
            edit.data,
            Data("Host jetson\n  HostName 192.168.1.44\nMatch host jetson\n  HostName 10.0.0.2\n".utf8)
        )
    }

    func testAnchorMatcherUsesExactMACOrUniqueHostnameEvidence() {
        let old = AnchorCandidate(ip: "192.168.1.8", macAddress: "AA:BB:CC:DD:EE:FF", hostname: "jetson.local")
        let moved = AnchorCandidate(ip: "192.168.1.44", macAddress: "aa-bb-cc-dd-ee-ff", hostname: nil)
        let stranger = AnchorCandidate(ip: "192.168.1.50", macAddress: "00:11:22:33:44:55", hostname: "printer.local")
        XCTAssertEqual(
            AnchorMatcher.match(candidates: [stranger, moved], identity: .stableMAC(old.macAddress!)),
            moved
        )

        let randomized = AnchorCandidate(ip: "192.168.1.45", macAddress: "12:34:56:78:9A:BC", hostname: "JETSON.local.")
        XCTAssertEqual(
            AnchorMatcher.match(
                candidates: [stranger, randomized],
                identity: .randomizedMAC(hostname: "jetson.local", learnedMACs: [])
            ),
            randomized
        )
        XCTAssertNil(
            AnchorMatcher.match(
                candidates: [randomized, AnchorCandidate(ip: "192.168.1.46", macAddress: nil, hostname: "jetson.local")],
                identity: .randomizedMAC(hostname: "jetson.local", learnedMACs: [])
            )
        )
    }

    func testNetworkHistoryRecordsTransitionsOnly() {
        var recorder = NetworkTransitionRecorder()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(recorder.observe(networkID: "en0|gateway", gateway: .reachable, internet: .reachable, at: start))
        XCTAssertNil(recorder.observe(networkID: "en0|gateway", gateway: .reachable, internet: .reachable, at: start.addingTimeInterval(30)))
        let event = recorder.observe(networkID: "en0|gateway", gateway: .reachable, internet: .unreachable, at: start.addingTimeInterval(60))
        XCTAssertEqual(event?.changes, [.internet(from: .reachable, to: .unreachable)])
        XCTAssertEqual(event?.date, start.addingTimeInterval(60))
    }

    func testSSHConfigFileUpdaterPreservesSymlinkAndPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backup = root.appendingPathComponent("backups", isDirectory: true)
        let config = root.appendingPathComponent("ssh-config")
        let link = root.appendingPathComponent("config-link")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Host jetson\n\tHostName 192.168.1.8\n".utf8).write(to: config)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config)

        let edit = try SSHConfigFileUpdater.update(
            configURL: link,
            backupDirectory: backup,
            hostAlias: "jetson",
            expectedHostName: "192.168.1.8",
            newHostName: "192.168.1.44"
        )

        XCTAssertEqual(edit.oldValue, "192.168.1.8")
        XCTAssertEqual(try Data(contentsOf: config), Data("Host jetson\n\tHostName 192.168.1.44\n".utf8))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as? NSNumber,
            NSNumber(value: 0o600)
        )
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), config.path)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "backup" }.count,
            1
        )
    }

    func testPortListParsesRangesAndRejectsInvalidPorts() throws {
        XCTAssertEqual(try PortList.parse("22, 80-82, 22"), [22, 80, 81, 82])
        XCTAssertThrowsError(try PortList.parse("0"))
        XCTAssertThrowsError(try PortList.parse("80-70000"))
    }

    func testARPTableParsesMacAddresses() {
        let output = """
        ? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]
        jetson.local (192.168.1.44) at 12-34-56-78-9a-bc on en0 ifscope [ethernet]
        ? (192.168.1.50) at (incomplete) on en0 ifscope [ethernet]
        """
        XCTAssertEqual(
            ARPTable.parse(output),
            ["192.168.1.1": "aa:bb:cc:dd:ee:ff", "192.168.1.44": "12:34:56:78:9a:bc"]
        )
    }

    func testTCPProbeAndScannerFindLocalListener() async throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        XCTAssertEqual(listen(descriptor, 4), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        XCTAssertEqual(
            withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(descriptor, $0, &length)
                }
            },
            0
        )
        let port = UInt16(bigEndian: address.sin_port)

        let probe = await TCPPortProbe.check(host: "127.0.0.1", port: port, timeoutMilliseconds: 500)
        XCTAssertEqual(probe.state, .open)

        let scanner = NetToysScanner()
        let results = await scanner.scan(
            targets: [try XCTUnwrap(IPv4Address("127.0.0.1"))],
            ports: [port],
            timeoutMilliseconds: 500,
            concurrency: 4
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isReachable)
        XCTAssertEqual(results[0].openPorts, [port])
    }

    func testSSHConfigEntriesExposeLiteralHostAddressAndPort() throws {
        let data = Data("Host jetson\n  User suraj\n  HostName 192.168.1.8\n  Port 2222\nMatch host other\n  HostName 10.0.0.2\n".utf8)
        XCTAssertEqual(
            SSHConfigEditor.entries(in: data),
            [SSHConfigEntry(aliases: ["jetson"], hostName: "192.168.1.8", port: 2222)]
        )
    }

    func testLocalIPv4NetworkProducesUsableHostsAndCapsLargeSubnets() throws {
        let network = try XCTUnwrap(
            LocalIPv4Network(interfaceName: "en0", address: "192.168.1.8", netmask: "255.255.255.252")
        )
        XCTAssertEqual(try network.targets(limit: 1_024).map(\.description), ["192.168.1.9", "192.168.1.10"])
        let large = try XCTUnwrap(
            LocalIPv4Network(interfaceName: "en0", address: "10.0.1.2", netmask: "255.255.0.0")
        )
        XCTAssertThrowsError(try large.targets(limit: 1_024))
    }

    func testNetToysConfigurationRoundTripsAndClampsProbeInterval() throws {
        let anchor = SSHAnchorConfiguration(
            hostAlias: "jetson",
            hostName: "192.168.1.8",
            port: 2222,
            identity: .stableMAC("aa:bb:cc:dd:ee:ff")
        )
        let configuration = NetToysConfiguration(probeInterval: 8, anchors: [anchor], recordsNetworkHistory: true)
        XCTAssertEqual(configuration.probeInterval, 3)
        XCTAssertEqual(
            try JSONDecoder().decode(NetToysConfiguration.self, from: JSONEncoder().encode(configuration)),
            configuration
        )
    }

    func testReplacingAnchorPreservesOtherConfiguration() throws {
        let first = SSHAnchorConfiguration(
            hostAlias: "jetson",
            hostName: "192.168.1.8",
            port: 22,
            identity: .randomizedMAC(hostname: "jetson.local", learnedMACs: [])
        )
        let second = SSHAnchorConfiguration(
            hostAlias: "nas",
            hostName: "192.168.1.4",
            port: 2222,
            identity: .stableMAC("aa:bb:cc:dd:ee:ff")
        )
        var changed = first
        changed.hostName = "192.168.1.44"
        let original = NetToysConfiguration(probeInterval: 2.5, anchors: [first, second], recordsNetworkHistory: false)

        let updated = try original.replacingAnchor(changed)

        XCTAssertEqual(updated.anchors, [changed, second])
        XCTAssertEqual(updated.probeInterval, original.probeInterval)
        XCTAssertEqual(updated.recordsNetworkHistory, original.recordsNetworkHistory)
    }

    func testNetworkHistoryKeepsNewestBoundedEvents() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let events = (0..<4).map { offset in
            NetworkTransitionEvent(
                networkID: "en0|192.168.1.1",
                date: start.addingTimeInterval(Double(offset)),
                changes: [.internet(from: .reachable, to: .unreachable)]
            )
        }

        let history = NetworkHistory(events: events, limit: 3)

        XCTAssertEqual(history.events.map(\.date), Array(events.suffix(3)).map(\.date))
        XCTAssertEqual(try JSONDecoder().decode(NetworkHistory.self, from: JSONEncoder().encode(history)), history)
    }

    func testAnchorRecoveryUsesOnlyTheConfiguredPortAndLearnsRandomizedMAC() throws {
        let anchor = SSHAnchorConfiguration(
            hostAlias: "jetson",
            hostName: "192.168.1.8",
            port: 2222,
            identity: .randomizedMAC(hostname: "jetson.local", learnedMACs: [])
        )
        let wrongPort = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.168.1.40")),
            isReachable: true,
            responseMilliseconds: 1,
            hostname: "jetson.local",
            macAddress: "00:11:22:33:44:55",
            vendor: nil,
            openPorts: [22]
        )
        let moved = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("192.168.1.44")),
            isReachable: true,
            responseMilliseconds: 2,
            hostname: "jetson.local.",
            macAddress: "AA:BB:CC:DD:EE:FF",
            vendor: nil,
            openPorts: [2222]
        )

        let recovered = try XCTUnwrap(SSHAnchorRecovery.resolve(anchor: anchor, scanResults: [wrongPort, moved]))

        XCTAssertEqual(recovered.hostName, "192.168.1.44")
        XCTAssertEqual(
            recovered.identity,
            .randomizedMAC(hostname: "jetson.local", learnedMACs: ["aabbccddeeff"])
        )
    }

    func testDefaultRouteParserExtractsInterfaceAndGateway() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.1.1
          interface: en0
        """
        XCTAssertEqual(
            DefaultRoute.parse(output),
            DefaultRoute(interfaceName: "en0", gateway: "192.168.1.1")
        )
    }

    func testHelperHeartbeatMustBeFresh() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(NetToysLoginItemManager.hasFreshHeartbeat(
            NetToysHelperStatus(version: 1, heartbeat: now.addingTimeInterval(-4), anchors: []),
            now: now
        ))
        XCTAssertFalse(NetToysLoginItemManager.hasFreshHeartbeat(
            NetToysHelperStatus(version: 1, heartbeat: now.addingTimeInterval(-8), anchors: []),
            now: now
        ))
        XCTAssertFalse(NetToysLoginItemManager.hasFreshHeartbeat(nil, now: now))
    }
}
