import Foundation
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
}
