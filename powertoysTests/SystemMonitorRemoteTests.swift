import AppKit
import XCTest
@testable import powertoys

@MainActor
final class SystemMonitorRemoteTests: XCTestCase {
    private static let linux = """
    MPT1
    cpu 100 0 50 850 0 0 0 0 99 0
    MemTotal: 1000 kB
    MemAvailable: 250 kB
    0.25 0.50 1.00 1/100 123
    eth0: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0
    eth1: 300 0 0 0 0 0 0 0 400 0 0 0 0 0 0 0
    MPTDISK 4096000 1024000 /
    MPTDISK 8192000 2048000 /data store
    """

    func testLinuxCountersAndMultipleDisks() throws {
        let sample = try SystemMonitorRemoteProtocol.parse(Self.linux)
        XCTAssertEqual(sample.cpuTotal, 1000, "Guest ticks must not count twice")
        XCTAssertEqual(sample.cpuIdle, 850)
        XCTAssertEqual(sample.memoryTotal, 1_024_000)
        XCTAssertEqual(sample.memoryAvailable, 256_000)
        XCTAssertEqual(sample.received, 400)
        XCTAssertEqual(sample.sent, 600)
        XCTAssertEqual(sample.diskUsed, 1_024_000)
        XCTAssertEqual(sample.disks.map(\.id), ["/", "/data store"])
        let loopback = Self.linux.replacingOccurrences(of: "eth0:", with: "lo:")
            .components(separatedBy: "\n").filter { !$0.hasPrefix("eth1:") }.joined(separator: "\n")
        XCTAssertEqual(try SystemMonitorRemoteProtocol.parse(loopback).received, 0)
        for malformed in [Self.linux.replacingOccurrences(of: "MemTotal: 1000", with: "MemTotal: 18446744073709551615"),
                          Self.linux.replacingOccurrences(of: "4096000 1024000", with: "4096000 9999999"),
                          Self.linux.replacingOccurrences(of: "0.25 0.50 1.00", with: "nan 0.50 1.00"),
                          String(repeating: "a", count: 16_385)] {
            XCTAssertThrowsError(try SystemMonitorRemoteProtocol.parse(malformed))
        }
    }

    func testMacAndWindowsSamplesRejectMalformedLoadAndDisk() throws {
        for (platform, marker, volume) in [(SystemMonitorRemotePlatform.macOS, "MPTMAC1", "/"),
                                           (.windows, "MPTWIN1", "C:")] {
            let sample = "\(marker)\r\nCPU=25.5\r\nMEM=8000000\r\nAVAILABLE=2000000\r\nDISK=10000000,4000000\r\nNET=100,200\r\nMPTDISK 10000000 4000000 \(volume)\r\n"
            let parsed = try SystemMonitorRemoteProtocol.parseKeyed(sample, platform: platform)
            XCTAssertEqual(parsed.cpuPercent, 25.5)
            XCTAssertEqual(parsed.received, 100)
            XCTAssertEqual(parsed.sent, 200)
            XCTAssertEqual(parsed.disks.first?.id, volume)
            for invalid in ["LOAD=", "LOAD=bad", "LOAD=bad,0,0", "LOAD=1,,2", "LOAD=1,2,3,", "LOAD=nan,0,0", "LOAD=-1,0,0"] {
                XCTAssertThrowsError(try SystemMonitorRemoteProtocol.parseKeyed(sample + invalid, platform: platform))
            }
            XCTAssertThrowsError(try SystemMonitorRemoteProtocol.parseKeyed(
                sample.replacingOccurrences(of: "CPU=25.5", with: "CPU=101"), platform: platform))
            for (valid, invalid) in [("DISK=10000000,4000000", "DISK=10000000,,4000000"),
                                     ("NET=100,200", "NET=100,,200"),
                                     ("DISK=10000000,4000000", "DISK=0,0"),
                                     ("MPTDISK 10000000 4000000", "MPTDISK 10000000 40000001")] {
                XCTAssertThrowsError(try SystemMonitorRemoteProtocol.parseKeyed(
                    sample.replacingOccurrences(of: valid, with: invalid), platform: platform))
            }
        }
    }

    func testLegacyProfilesAndExplicitUserPortRoundTrip() throws {
        let data = Data(#"[{"id":"saved","name":"oci2","host":"oci2","platform":"Linux","interval":30}]"#.utf8)
        var profile = try XCTUnwrap(JSONDecoder().decode([SystemMonitorRemoteProfile].self, from: data).first)
        XCTAssertEqual(profile.user, "")
        XCTAssertNil(profile.port, "A blank port must preserve SSH config")
        profile.user = "builder"
        profile.port = 2222
        XCTAssertEqual(try JSONDecoder().decode(SystemMonitorRemoteProfile.self, from: JSONEncoder().encode(profile)), profile)
        let args = try SystemMonitorRemoteProtocol.arguments(host: profile.host, user: profile.user, port: profile.port)
        XCTAssertEqual(Array(args.suffix(8)), ["-l", "builder", "-p", "2222", "-T", "--", "oci2", SystemMonitorRemoteProtocol.command])
        XCTAssertTrue(try SystemMonitorRemoteTerminal.command(profile).contains("'-p' '2222'"))
        for host in ["", "-server", "a@@b", "@server", "user@", "host;reboot", "host\nreboot"] {
            XCTAssertFalse(SystemMonitorRemoteProtocol.validHost(host))
        }
        XCTAssertTrue(SystemMonitorRemoteProtocol.validHost("user@2001:db8::1"))
        profile.port = 65536
        XCTAssertNotNil(profile.validationMessage)
        profile.port = 22; profile.user = "-option"
        XCTAssertNotNil(profile.validationMessage)
    }

    @MainActor
    func testManualConnectionRefreshAndDisconnectClearReadings() async throws {
        let samples = RemoteSampleGate()
        let service = SystemMonitorRemoteSessions { _, _ in try await samples.next() }
        let host = SystemMonitorRemoteProfile(id: "manual", name: "Manual", host: "server", interval: 0)
        service.connect(host)
        XCTAssertEqual(service.state(for: host.id).phase, .connecting)
        try await samples.waitForRequest()
        await samples.respond()
        try await waitUntil { service.state(for: host.id).reading != nil && service.activeTaskCount == 0 }
        XCTAssertEqual(service.state(for: host.id).phase, .connected)
        XCTAssertEqual(service.state(for: host.id).reading?.cpuPercent, 25)
        XCTAssertEqual(service.activeTaskCount, 0)
        service.refresh(host)
        try await samples.waitForRequest()
        service.disconnect(host.id)
        await samples.respond()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(service.state(for: host.id).phase, .offline)
        XCTAssertNil(service.state(for: host.id).reading, "A late sample cannot restore a disconnected card")
        XCTAssertEqual(service.activeTaskCount, 0)
    }

    @MainActor
    func testSamplingFailureKeepsReasonAndSurfaceOwnersStopWork() async throws {
        let samples = RemoteSampleGate()
        let service = SystemMonitorRemoteSessions { _, _ in try await samples.next() }
        let host = SystemMonitorRemoteProfile(id: "host", name: "Host", host: "server", interval: 5)
        service.setVisible([host.id], owner: "panel")
        service.setVisible([host.id], owner: "window")
        service.connect(host)
        try await samples.waitForRequest()
        await samples.fail()
        try await waitUntil { service.state(for: host.id).phase == .offline }
        XCTAssertEqual(service.state(for: host.id).reason, "SSH failed: Connection refused")
        service.connect(host)
        try await samples.waitForRequest()
        service.setVisible([], owner: "panel")
        XCTAssertEqual(service.state(for: host.id).phase, .connecting)
        service.setVisible([], owner: "window")
        XCTAssertEqual(service.state(for: host.id).phase, .offline)
        XCTAssertEqual(service.activeTaskCount, 0)
        await samples.respond()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(service.state(for: host.id).reading)
    }

    @MainActor
    func testNativeWindowCloseStopsItsRemoteSession() async throws {
        let samples = RemoteSampleGate()
        let service = SystemMonitorRemoteSessions { _, _ in try await samples.next() }
        let host = SystemMonitorRemoteProfile(name: "Host", host: "server")
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        service.register(host.id, window: window)
        service.connect(host)
        try await samples.waitForRequest()
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        XCTAssertEqual(service.activeTaskCount, 0)
        XCTAssertEqual(service.state(for: host.id).phase, .offline)
        await samples.respond()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now >= deadline { throw SystemMonitorRemoteError.sshFailed("Test state did not change") }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private actor RemoteSampleGate {
    private var pending: CheckedContinuation<SystemMonitorRemoteReading, Error>?
    func next() async throws -> SystemMonitorRemoteReading {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitForRequest() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while pending == nil {
            if ContinuousClock.now >= deadline { throw SystemMonitorRemoteError.sshFailed("Test sample did not start") }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    func respond() {
        pending?.resume(returning: SystemMonitorRemoteReading(cpuPercent: 25, memoryUsed: 6_000_000,
            memoryTotal: 8_000_000, download: 100, upload: 50, diskUsed: 4_000_000, diskTotal: 10_000_000, load: []))
        pending = nil
    }
    func fail() {
        pending?.resume(throwing: SystemMonitorRemoteError.sshFailed("Connection refused"))
        pending = nil
    }
}
