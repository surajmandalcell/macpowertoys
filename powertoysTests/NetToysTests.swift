import Foundation
import Darwin
import XCTest
@testable import powertoys

final class NetToysTests: XCTestCase {
    private actor ProbeAnswers {
        private var values: [Bool]

        init(_ values: [Bool]) {
            self.values = values
        }

        func next() -> Bool {
            values.isEmpty ? false : values.removeFirst()
        }
    }

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

    func testSSHAnchorVerifiedUpdateCommitsAfterPreAndPostWriteProbes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let config = root.appendingPathComponent("config")
        let backup = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Host jetson\n  HostName 192.168.1.8\n".utf8).write(to: config)
        let original = SSHAnchorConfiguration(
            hostAlias: "jetson",
            hostName: "192.168.1.8",
            port: 22,
            identity: .stableMAC("aa:bb:cc:dd:ee:ff")
        )
        var recovered = original
        recovered.hostName = "192.168.1.44"
        let answers = ProbeAnswers([true, true])

        try await SSHAnchorVerifiedUpdate.apply(
            original: original,
            recovered: recovered,
            configURL: config,
            backupDirectory: backup,
            verify: { _, _ in await answers.next() },
            commit: {}
        )

        XCTAssertEqual(try Data(contentsOf: config), Data("Host jetson\n  HostName 192.168.1.44\n".utf8))
    }

    func testSSHAnchorVerifiedUpdateRollsBackWhenPostWriteProbeFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let config = root.appendingPathComponent("config")
        let backup = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let originalData = Data("Host jetson\n\tHostName\t192.168.1.8 # untouched\n".utf8)
        try originalData.write(to: config)
        let original = SSHAnchorConfiguration(
            hostAlias: "jetson",
            hostName: "192.168.1.8",
            port: 22,
            identity: .stableMAC("aa:bb:cc:dd:ee:ff")
        )
        var recovered = original
        recovered.hostName = "192.168.1.44"
        let answers = ProbeAnswers([true, false])

        do {
            try await SSHAnchorVerifiedUpdate.apply(
                original: original,
                recovered: recovered,
                configURL: config,
                backupDirectory: backup,
                verify: { _, _ in await answers.next() },
                commit: {}
            )
            XCTFail("The post-write probe should fail.")
        } catch {
            XCTAssertEqual(error as? SSHAnchorVerifiedUpdate.UpdateError, .postWriteProbeFailed)
        }

        XCTAssertEqual(try Data(contentsOf: config), originalData)
    }

    func testPortListParsesRangesAndRejectsInvalidPorts() throws {
        XCTAssertEqual(try PortList.parse("22, 80-82, 22"), [22, 80, 81, 82])
        XCTAssertThrowsError(try PortList.parse("0"))
        XCTAssertThrowsError(try PortList.parse("80-70000"))
    }

    func testScanTargetInputAcceptsHostnamesAndPerTargetPorts() throws {
        XCTAssertEqual(
            try NetToysTargetInput.parse("10.0.0.2:2222, jetson.local:22, 10.0.0.4-10.0.0.5"),
            [
                .addresses([try XCTUnwrap(IPv4Address("10.0.0.2"))], port: 2222),
                .hostname("jetson.local", port: 22),
                .addresses([
                    try XCTUnwrap(IPv4Address("10.0.0.4")),
                    try XCTUnwrap(IPv4Address("10.0.0.5"))
                ], port: nil)
            ]
        )
        XCTAssertThrowsError(try NetToysTargetInput.parse("fe80::1")) { error in
            XCTAssertEqual(error as? NetToysTargetInput.ParseError, .unsupportedIPv6("fe80::1"))
        }
    }

    func testScanTargetResolverResolvesLocalhostAndKeepsPerTargetPort() async throws {
        let targets = try await NetToysTargetResolver.resolve("localhost:2222", defaultPorts: [22, 80])

        XCTAssertTrue(targets.contains(NetToysScanTarget(
            address: try XCTUnwrap(IPv4Address("127.0.0.1")),
            ports: [2222]
        )))
        XCTAssertTrue(targets.allSatisfy { $0.ports == [2222] })
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

    func testMACVendorDatabaseUsesLongestPublicPrefixAndRejectsLocalAddresses() {
        let database = MACVendorDatabase(text: """
        24\t001122\tExample Holdings
        28\t0011223\tExample Products
        36\t001122334\tExample Device Lab
        """)

        XCTAssertEqual(database.vendor(for: "00:11:22:33:44:55"), "Example Device Lab")
        XCTAssertEqual(database.vendor(for: "00:11:22:3f:44:55"), "Example Products")
        XCTAssertEqual(database.vendor(for: "00:11:22:af:44:55"), "Example Holdings")
        XCTAssertNil(database.vendor(for: "02:11:22:33:44:55"))
        XCTAssertNil(database.vendor(for: "invalid"))
        XCTAssertEqual(
            MACVendorDatabase.bundled.vendor(for: "28:6f:b9:00:00:00"),
            "Nokia Shanghai Bell Co., Ltd."
        )
    }

    func testFilteredPortsAreReportedOnlyForReachableHosts() {
        XCTAssertEqual(NetToysScanner.reportedFilteredPorts([22, 443], reachable: true), [22, 443])
        XCTAssertEqual(NetToysScanner.reportedFilteredPorts([22, 443], reachable: false), [])
    }

    func testPingProbeParsesMacOSPacketLossLatencyAndTTL() {
        let output = """
        PING 10.0.0.2 (10.0.0.2): 56 data bytes
        64 bytes from 10.0.0.2: icmp_seq=0 ttl=63 time=0.200 ms
        64 bytes from 10.0.0.2: icmp_seq=1 ttl=63 time=0.400 ms

        --- 10.0.0.2 ping statistics ---
        3 packets transmitted, 2 packets received, 33.3% packet loss
        round-trip min/avg/max/stddev = 0.200/0.300/0.400/0.100 ms
        """

        XCTAssertEqual(
            PingProbe.parse(output),
            PingProbeResult(ttl: 63, packetLossPercent: 33.3, averageMilliseconds: 0.3)
        )
    }

    func testProtocolFetchersParseHTTPProxyCustomTextAndNetBIOSResponses() throws {
        let http = Data("HTTP/1.1 200 OK\r\nServer: nginx/1.27\r\nContent-Length: 0\r\n\r\n".utf8)
        XCTAssertEqual(NetToysProtocolFetchers.httpServer(from: http), "nginx/1.27")
        XCTAssertEqual(
            NetToysProtocolFetchers.proxy(from: Data("HTTP/1.1 200 Connection established\r\n\r\n".utf8)),
            "HTTP proxy"
        )
        XCTAssertNil(NetToysProtocolFetchers.proxy(from: http))

        let custom = NetToysCustomTextProbe(
            port: 22,
            request: "",
            responsePattern: #"SSH-([0-9.]+)"#
        )
        XCTAssertEqual(
            try custom.match(in: Data("SSH-2.0-OpenSSH_9.9\r\n".utf8)),
            "SSH-2.0"
        )
        XCTAssertThrowsError(try NetToysCustomTextProbe(port: 0, request: "", responsePattern: ".+").validate())
        XCTAssertThrowsError(try NetToysCustomTextProbe(port: 22, request: "", responsePattern: "").validate())

        var netBIOS = Data([0x12, 0x34, 0x85, 0x00, 0, 0, 0, 1, 0, 0, 0, 0])
        netBIOS.append(contentsOf: [0xC0, 0x0C, 0, 0x21, 0, 1, 0, 0, 0, 0, 0, 0x13, 1])
        netBIOS.append(contentsOf: Array("JETSON".utf8) + Array(repeating: 0x20, count: 9))
        netBIOS.append(contentsOf: [0, 0, 0])
        XCTAssertEqual(NetBIOSProbe.parse(netBIOS), "JETSON")
        XCTAssertEqual(Array(NetBIOSProbe.statusQuery()[13...16]), [0x43, 0x4B, 0x41, 0x41])
    }

    func testTCPTextProbeExchangesBoundedProtocolData() async throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        XCTAssertEqual(withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }, 0)
        XCTAssertEqual(listen(descriptor, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        XCTAssertEqual(withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }, 0)
        let port = UInt16(bigEndian: address.sin_port)
        let server = Task.detached { () -> String in
            var pollItem = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&pollItem, 1, 1_000) > 0 else { return "" }
            let client = Darwin.accept(descriptor, nil, nil)
            guard client >= 0 else { return "" }
            defer { close(client) }
            var request = [UInt8](repeating: 0, count: 1_024)
            let count = request.withUnsafeMutableBytes { recv(client, $0.baseAddress, $0.count, 0) }
            let response = Data("HTTP/1.1 200 OK\r\nServer: test-server\r\n\r\n".utf8)
            _ = response.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
            return count > 0 ? String(decoding: request.prefix(count), as: UTF8.self) : ""
        }

        let response = await TCPTextProbe.exchange(
            address: try XCTUnwrap(IPv4Address("127.0.0.1")),
            port: port,
            request: Data("HEAD / HTTP/1.0\r\n\r\n".utf8),
            timeoutMilliseconds: 500
        )

        XCTAssertEqual(response.flatMap(NetToysProtocolFetchers.httpServer), "test-server")
        let receivedRequest = await server.value
        XCTAssertTrue(receivedRequest.hasPrefix("HEAD /"))
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

    func testRandomTargetsStayInsideCIDRWithoutDuplicates() throws {
        let targets = try IPv4Targets.random(in: "10.20.30.0/24", count: 40)
        XCTAssertEqual(targets.count, 40)
        XCTAssertEqual(Set(targets).count, 40)
        XCTAssertTrue(targets.allSatisfy { address in
            address.rawValue > IPv4Address("10.20.30.0")!.rawValue
                && address.rawValue < IPv4Address("10.20.30.255")!.rawValue
        })
        XCTAssertThrowsError(try IPv4Targets.random(in: "10.20.30.0/30", count: 3))
    }

    func testScanArchiveAndExportsPreserveSpecialText() throws {
        let result = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("10.0.0.2")),
            isReachable: true,
            responseMilliseconds: 2,
            hostname: "dev<&'\".local",
            macAddress: "aa:bb:cc:dd:ee:ff",
            vendor: nil,
            openPorts: [22],
            filteredPorts: [443],
            ttl: 63,
            packetLossPercent: 1.5,
            httpServer: "80: nginx<&",
            httpProxy: "8080: HTTP proxy",
            netBIOSName: "JETSON",
            customText: "SSH-2.0"
        )
        let run = NetToysScanRun(target: "10.0.0.0/24", ports: [22], duration: 1, results: [result])
        let archive = NetToysScanArchive(runs: Array(repeating: run, count: 4), limit: 3)
        XCTAssertEqual(archive.runs.count, 3)
        XCTAssertEqual(try JSONDecoder().decode(NetToysScanArchive.self, from: JSONEncoder().encode(archive)), archive)
        XCTAssertTrue(NetToysScanExport.xml([result]).contains("dev&lt;&amp;&apos;&quot;.local"))
        XCTAssertTrue(NetToysScanExport.sql([result]).contains("dev<&amp;''\".local") == false)
        XCTAssertTrue(NetToysScanExport.sql([result]).contains("dev<&''\".local"))
        XCTAssertEqual(NetToysScanExport.ipPorts([result]), "10.0.0.2:22")
        XCTAssertTrue(NetToysScanExport.csv([result]).contains("TTL,Packet Loss %,Filtered Ports"))
        XCTAssertTrue(NetToysScanExport.csv([result]).contains("\"63\",\"1.5\",\"443\""))
        XCTAssertTrue(NetToysScanExport.csv([result]).contains("\"80: nginx<&\""))
        XCTAssertTrue(NetToysScanExport.xml([result]).contains("<http-server>80: nginx&lt;&amp;</http-server>"))
        XCTAssertTrue(NetToysScanExport.sql([result]).contains("'8080: HTTP proxy'"))
        XCTAssertEqual(try NetToysScanImport.savedResults(NetToysScanExport.savedResults([result])), [result])
    }

    func testSavedResultsFromBeforeProtocolFetchersStillImport() throws {
        let original = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("10.0.0.8")),
            isReachable: true,
            responseMilliseconds: 1,
            hostname: "host.local",
            macAddress: nil,
            vendor: nil,
            openPorts: [22]
        )
        let encoded = try NetToysScanExport.savedResults([original])
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var results = try XCTUnwrap(document["results"] as? [[String: Any]])
        for key in ["filteredPorts", "ttl", "packetLossPercent", "httpServer", "httpProxy", "netBIOSName", "customText"] {
            results[0].removeValue(forKey: key)
        }
        document["results"] = results

        let imported = try NetToysScanImport.savedResults(JSONSerialization.data(withJSONObject: document))

        XCTAssertEqual(imported, [original])
    }

    func testAppendExportKeepsExistingDataAndOmitsDuplicateHeaders() throws {
        let result = NetToysScanResult(
            address: try XCTUnwrap(IPv4Address("10.0.0.9")),
            isReachable: true,
            responseMilliseconds: 1,
            hostname: nil,
            macAddress: nil,
            vendor: nil,
            openPorts: [22]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scan.csv")
        try (NetToysScanExport.csv([result]) + "\n").write(to: url, atomically: true, encoding: .utf8)

        try NetToysScanExport.append(NetToysScanExport.csv([result], includeHeader: false), to: url)

        let value = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(value.components(separatedBy: "IP Address,Status").count - 1, 1)
        XCTAssertEqual(value.components(separatedBy: "\n").count, 3)
        XCTAssertFalse(NetToysScanExport.sql([result], includeSchema: false).contains("CREATE TABLE"))
    }

    func testOpenersResolveSafeURLTemplatesAndRejectCommands() throws {
        let address = try XCTUnwrap(IPv4Address("10.0.0.9"))
        let opener = NetToysOpener(
            name: "Device UI",
            urlTemplate: "https://{hostname}:{port}/status?device={ip}",
            requiredPort: 8443
        )
        try opener.validate()
        XCTAssertEqual(
            try opener.resolvedURL(address: address, hostname: "jetson.local").absoluteString,
            "https://jetson.local:8443/status?device=10.0.0.9"
        )
        XCTAssertEqual(
            try opener.resolvedURL(address: address, hostname: "bad host/@evil").host,
            "10.0.0.9"
        )
        XCTAssertThrowsError(try NetToysOpener(
            name: "Script",
            urlTemplate: "file:///tmp/{ip}",
            requiredPort: 22
        ).validate())
        XCTAssertThrowsError(try NetToysOpener(
            name: "Script",
            urlTemplate: "https://user:secret@{ip}:{port}/",
            requiredPort: 443
        ).validate())
        XCTAssertThrowsError(try NetToysOpener(
            name: "Script",
            urlTemplate: "ssh {ip}",
            requiredPort: 22
        ).validate())
        XCTAssertThrowsError(try NetToysOpener(
            name: "Unrelated",
            urlTemplate: "https://example.com/",
            requiredPort: 443
        ).validate())
        let result = NetToysScanResult(
            address: address,
            isReachable: true,
            responseMilliseconds: 1,
            hostname: nil,
            macAddress: nil,
            vendor: nil,
            openPorts: [22]
        )
        XCTAssertFalse(NetToysOpener(
            name: "Invalid port",
            urlTemplate: "ssh://{ip}:{port}",
            requiredPort: 100_000
        ).applies(to: result))
    }
}
