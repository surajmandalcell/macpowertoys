import Foundation
import XCTest
@testable import powertoys

// MARK: Fixtures

private enum ServerFixture {
    static func linux(user: UInt64 = 10_132_153, idle: UInt64 = 46_828_483, rx: UInt64 = 9_876_543_210,
                      tx: UInt64 = 1_234_567_890, uptime: String = "350735.47", load: String = "0.52 0.58 0.59",
                      end: Bool = true) -> String {
        """
        @os Linux
        @stat
        cpu  \(user) 290696 3084719 \(idle) 16683 0 25195 0 0 0
        cpu0 2533038 72674 771179 11707120 4170 0 6298 0 0 0
        @mem
        MemTotal:       16314664 kB
        MemFree:         1234567 kB
        MemAvailable:    8157332 kB
        Buffers:          234567 kB
        Cached:          3456789 kB
        @df
        Filesystem     1024-blocks     Used Available Capacity Mounted on
        /dev/sda1        101445540 40578216  60850940      41% /
        @uptime
        \(uptime) 234388.90
        @load
        \(load) 1/389 12345
        @net
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
            lo: 123456789  1000    0    0    0     0          0         0 123456789  1000    0    0    0     0       0          0
          eth0: \(rx) 2000    0    0    0     0          0         0 \(tx) 3000    0    0    0     0       0          0
        \(end ? "@end" : "")
        """
    }

    static let linuxCPUTotal: UInt64 = 60_377_929
    static let linuxCPUIdle: UInt64 = 46_845_166

    static func mac(cpu: String = "CPU usage: 7.89% user, 5.26% sys, 86.84% idle ",
                    load: String = "{ 1.84 2.01 2.10 }") -> String {
        """
        @os Darwin
        @cpu
        \(cpu)
        @memsize
        17179869184
        @vm
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                                3000.
        Pages active:                            300000.
        Pages inactive:                          290000.
        Pages speculative:                         9000.
        Pages throttled:                              0.
        Pages wired down:                        150000.
        Pages purgeable:                          10000.
        "Translation faults":                 123456789.
        File-backed pages:                       250000.
        Anonymous pages:                         340000.
        Pages stored in compressor:              200000.
        Pages occupied by compressor:             60000.
        @df
        Filesystem     1024-blocks      Used Available Capacity  Mounted on
        /dev/disk3s5    971350180 512345678 400000000    57%    /System/Volumes/Data
        @boot
        { sec = 1732000000, usec = 123456 } Tue Nov 19 08:06:40 2024
        1732086400
        @load
        \(load)
        @net
        Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        lo0        16384 <Link#1>                        500000     0  400000000   500000     0  400000000     0
        lo0        16384 127           127.0.0.1         500000     -  400000000   500000     -  400000000     -
        en0        1500  <Link#11>   aa:bb:cc:dd:ee:ff  9000000     0 8000000000  4000000     0 1000000000     0
        en0        1500  192.168.1     192.168.1.20      9000000     - 8000000000  4000000     -  999000000     -
        utun0      1380  <Link#20>                          100     0       5000      200     0       6000     0
        @end
        """
    }
}

private func parse(_ output: String) throws -> PortmanServerCounters {
    try PortmanServerProtocol.parse(output)
}

private func parseFailure(_ output: String) -> PortmanServerFailure? {
    do {
        _ = try PortmanServerProtocol.parse(output)
        return nil
    } catch {
        return error
    }
}

// MARK: Parser

final class PortmanServerParserTests: XCTestCase {
    func testLinuxSampleReadsEveryValue() throws {
        let counters = try parse(ServerFixture.linux())
        XCTAssertEqual(counters.os, .linux)
        XCTAssertEqual(counters.cpuTotal, ServerFixture.linuxCPUTotal)
        XCTAssertEqual(counters.cpuIdle, ServerFixture.linuxCPUIdle)
        XCTAssertNil(counters.cpuPercent)
        XCTAssertEqual(counters.memoryTotal, 16_314_664 * 1_024)
        XCTAssertEqual(counters.memoryUsed, (16_314_664 - 8_157_332) * 1_024)
        XCTAssertEqual(counters.diskTotal, 101_445_540 * 1_024)
        XCTAssertEqual(counters.diskUsed, 40_578_216 * 1_024)
        XCTAssertEqual(counters.uptime ?? 0, 350_735.47, accuracy: 0.001)
        XCTAssertEqual(counters.load, [0.52, 0.58, 0.59])
        XCTAssertEqual(counters.received, 9_876_543_210, "loopback is excluded")
        XCTAssertEqual(counters.sent, 1_234_567_890)
    }

    func testMacSampleReadsEveryValue() throws {
        let counters = try parse(ServerFixture.mac())
        XCTAssertEqual(counters.os, .macOS)
        XCTAssertEqual(counters.cpuPercent ?? -1, 13.16, accuracy: 0.001)
        XCTAssertEqual(counters.memoryTotal, 17_179_869_184)
        XCTAssertEqual(counters.memoryUsed, (340_000 - 10_000 + 150_000 + 60_000) * 16_384)
        XCTAssertEqual(counters.diskTotal, 971_350_180 * 1_024)
        XCTAssertEqual(counters.diskUsed, 512_345_678 * 1_024)
        XCTAssertEqual(counters.uptime, 86_400)
        XCTAssertEqual(counters.load, [1.84, 2.01, 2.10])
        XCTAssertEqual(counters.received, 8_000_000_000 + 5_000, "lo0 skipped, utun without address counted")
        XCTAssertEqual(counters.sent, 1_000_000_000 + 6_000)
    }

    func testMacFirstSampleAlreadyHasCPU() throws {
        let sample = PortmanServerProtocol.sample(previous: nil, current: try parse(ServerFixture.mac()), at: Date())
        XCTAssertEqual(sample.cpuPercent ?? -1, 13.16, accuracy: 0.001)
        XCTAssertNil(sample.receiveRate)
    }

    func testMacWithoutAnonymousPagesUsesActivePages() throws {
        let output = ServerFixture.mac().replacingOccurrences(of: "Anonymous pages:                         340000.\n", with: "")
        let counters = try parse(output)
        XCTAssertEqual(counters.memoryUsed, (300_000 + 150_000 + 60_000) * 16_384)
    }

    func testMacMemoryIsClampedToTotal() throws {
        let output = ServerFixture.mac().replacingOccurrences(of: "17179869184", with: "1024")
        XCTAssertEqual(try parse(output).memoryUsed, 1_024)
    }

    func testDecimalCommasParse() throws {
        let linux = try parse(ServerFixture.linux(uptime: "350735,47", load: "0,52 0,58 0,59"))
        XCTAssertEqual(linux.load, [0.52, 0.58, 0.59])
        XCTAssertEqual(linux.uptime ?? 0, 350_735.47, accuracy: 0.001)
        let mac = try parse(ServerFixture.mac(cpu: "CPU usage: 7,89% user, 5,26% sys, 86,84% idle",
                                              load: "{ 1,84 2,01 2,10 }"))
        XCTAssertEqual(mac.cpuPercent ?? -1, 13.16, accuracy: 0.001)
        XCTAssertEqual(mac.load, [1.84, 2.01, 2.10])
    }

    func testNumberRejectsNonFiniteAndGarbage() {
        XCTAssertNil(PortmanServerProtocol.number("nan"))
        XCTAssertNil(PortmanServerProtocol.number("inf"))
        XCTAssertNil(PortmanServerProtocol.number("abc"))
        XCTAssertNil(PortmanServerProtocol.number(""))
        XCTAssertEqual(PortmanServerProtocol.number("12.5%"), 12.5)
        XCTAssertEqual(PortmanServerProtocol.number(" 3,25 "), 3.25)
    }

    func testEmptyOutputIsInvalid() {
        XCTAssertEqual(parseFailure(""), .invalidOutput)
        XCTAssertEqual(parseFailure("\n\n"), .invalidOutput)
    }

    func testGarbageOutputIsInvalid() {
        XCTAssertEqual(parseFailure("Welcome to Ubuntu!\nLast login: yesterday\n"), .invalidOutput)
        XCTAssertEqual(parseFailure("\u{0}\u{1}binary@@@"), .invalidOutput)
    }

    func testBannerBeforeMarkersIsIgnored() throws {
        let counters = try parse("This system is managed.\n" + ServerFixture.linux())
        XCTAssertEqual(counters.load, [0.52, 0.58, 0.59])
    }

    func testUnknownSystemIsUnsupported() {
        XCTAssertEqual(parseFailure("@os FreeBSD\n@end\n"), .unsupported("FreeBSD"))
        XCTAssertEqual(parseFailure("@os \n@end\n"), .unsupported(""), "uname missing prints nothing")
    }

    func testMarkersWithoutValuesAreInvalid() {
        XCTAssertEqual(parseFailure("@os Linux\n@stat\n@mem\n@df\n@uptime\n@load\n@net\n@end\n"), .invalidOutput)
    }

    func testCutOffOutputDropsTheUnfinishedSection() throws {
        var output = ServerFixture.linux(end: false)
        output = String(output[..<output.range(of: "eth0:")!.lowerBound])
        let counters = try parse(output)
        XCTAssertNil(counters.received, "the half network table is dropped")
        XCTAssertEqual(counters.load, [0.52, 0.58, 0.59])
        XCTAssertEqual(counters.cpuTotal, ServerFixture.linuxCPUTotal)
    }

    func testMissingCommandsLeaveOnlyThoseValuesEmpty() throws {
        let output = "@os Linux\n@stat\n@mem\nMemTotal: 1000 kB\nMemAvailable: 400 kB\n@df\nsh: df: not found\n@load\n0.1 0.2 0.3 1/2 3\n@end\n"
        let counters = try parse(output)
        XCTAssertNil(counters.cpuTotal)
        XCTAssertNil(counters.diskTotal)
        XCTAssertEqual(counters.memoryUsed, 600 * 1_024)
        XCTAssertEqual(counters.load, [0.1, 0.2, 0.3])
    }

    func testOldKernelWithoutMemAvailable() throws {
        let output = "@os Linux\n@mem\nMemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 50 kB\nCached: 250 kB\n@end\n"
        XCTAssertEqual(try parse(output).memoryUsed, 600 * 1_024)
    }

    func testAvailableAboveTotalGivesZeroUsed() throws {
        let output = "@os Linux\n@mem\nMemTotal: 1000 kB\nMemAvailable: 5000 kB\n@end\n"
        XCTAssertEqual(try parse(output).memoryUsed, 0)
    }

    func testMemoryOverflowIsDropped() {
        let output = "@os Linux\n@mem\nMemTotal: 18446744073709551615 kB\nMemAvailable: 1 kB\n@end\n"
        XCTAssertEqual(parseFailure(output), .invalidOutput)
    }

    func testBadCPULineLeavesCPUEmpty() throws {
        let output = "@os Linux\n@stat\ncpu  12 x 3 4\n@load\n1 2 3 1/2 3\n@end\n"
        let counters = try parse(output)
        XCTAssertNil(counters.cpuTotal)
        XCTAssertEqual(counters.load, [1, 2, 3])
        XCTAssertNil(try parse("@os Linux\n@stat\ncpu 1 2\n@load\n1 2 3\n@end\n").cpuTotal, "fewer than four ticks")
    }

    func testCPUTickOverflowIsDropped() throws {
        let max = UInt64.max
        let counters = try parse("@os Linux\n@stat\ncpu \(max) \(max) 1 1\n@load\n1 2 3\n@end\n")
        XCTAssertNil(counters.cpuTotal)
    }

    func testNegativeOrShortLoadIsDropped() throws {
        XCTAssertNil(try parse("@os Linux\n@load\n-1 2 3 1/2 3\n@uptime\n5 5\n@end\n").load)
        XCTAssertNil(try parse("@os Linux\n@load\n1 2\n@uptime\n5 5\n@end\n").load)
    }

    func testDiskRowWithSpacesAndZeroSize() throws {
        let spaced = "@os Linux\n@df\nFilesystem 1024-blocks Used Available Capacity Mounted on\nmy disk 1 1000 250 750 25% /\n@end\n"
        let counters = try parse(spaced)
        XCTAssertEqual(counters.diskTotal, 1_000 * 1_024)
        XCTAssertEqual(counters.diskUsed, 250 * 1_024)
        XCTAssertEqual(parseFailure("@os Linux\n@df\n/dev/x 0 0 0 0% /\n@end\n"), .invalidOutput)
    }

    func testMacBootTimeInTheFutureIsDropped() throws {
        let output = ServerFixture.mac().replacingOccurrences(of: "1732086400", with: "1731000000")
        XCTAssertNil(try parse(output).uptime)
    }

    func testMacCPUOutsideRangeIsDropped() throws {
        XCTAssertNil(try parse(ServerFixture.mac(cpu: "CPU usage: 1% user, 1% sys, 140% idle")).cpuPercent)
        XCTAssertNil(try parse(ServerFixture.mac(cpu: "")).cpuPercent)
    }

    func testOversizedOutputIsBounded() {
        XCTAssertEqual(PortmanServerProtocol.maximumOutputBytes, 65_536)
    }
}

// MARK: Deltas

final class PortmanServerDeltaTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func pair(_ first: String, _ second: String, seconds: TimeInterval = 2) throws -> PortmanServerSample {
        let old = try parse(first)
        return PortmanServerProtocol.sample(previous: (old, start), current: try parse(second),
                                            at: start.addingTimeInterval(seconds))
    }

    func testFirstLinuxSampleHasNoCPUOrRates() throws {
        let sample = PortmanServerProtocol.sample(previous: nil, current: try parse(ServerFixture.linux()), at: start)
        XCTAssertNil(sample.cpuPercent)
        XCTAssertNil(sample.receiveRate)
        XCTAssertNil(sample.sendRate)
        XCTAssertNotNil(sample.memoryUsed)
        XCTAssertEqual(sample.load, [0.52, 0.58, 0.59])
    }

    func testSecondLinuxSampleHasCPUAndRates() throws {
        let sample = try pair(
            ServerFixture.linux(),
            ServerFixture.linux(user: 10_132_153 + 750, idle: 46_828_483 + 250, rx: 9_876_543_210 + 2_000,
                                tx: 1_234_567_890 + 500, uptime: "350737.47")
        )
        XCTAssertEqual(sample.cpuPercent ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(sample.receiveRate, 1_000)
        XCTAssertEqual(sample.sendRate, 250)
    }

    func testRebootGivesNoCPUOrRates() throws {
        let sample = try pair(
            ServerFixture.linux(),
            ServerFixture.linux(user: 500, idle: 1_000, rx: 10, tx: 10, uptime: "30.00")
        )
        XCTAssertNil(sample.cpuPercent)
        XCTAssertNil(sample.receiveRate)
        XCTAssertNil(sample.sendRate)
        XCTAssertNotNil(sample.memoryUsed)
    }

    func testCountersGoingDownWithoutUptimeGiveNoCPU() throws {
        let first = "@os Linux\n@stat\ncpu 100 0 0 100\n@end\n"
        let second = "@os Linux\n@stat\ncpu 50 0 0 50\n@end\n"
        XCTAssertNil(try pair(first, second).cpuPercent)
    }

    func testUnchangedCPUCountersGiveNoCPU() throws {
        XCTAssertNil(try pair(ServerFixture.linux(), ServerFixture.linux()).cpuPercent)
    }

    func testThirtyTwoBitCounterWraps() {
        let old = UInt64(UInt32.max) - 99
        XCTAssertEqual(PortmanServerProtocol.counterDelta(old, 100, rebooted: false), 200)
    }

    func testSixtyFourBitCounterDropIsAReset() {
        XCTAssertNil(PortmanServerProtocol.counterDelta(10_000_000_000, 5, rebooted: false))
        XCTAssertNil(PortmanServerProtocol.counterDelta(5, 10, rebooted: true))
        XCTAssertNil(PortmanServerProtocol.counterDelta(nil, 10, rebooted: false))
        XCTAssertEqual(PortmanServerProtocol.counterDelta(5, 5, rebooted: false), 0)
    }

    func testWrappedNetworkCounterGivesARate() throws {
        let old = UInt64(UInt32.max) - 999
        let sample = try pair(ServerFixture.linux(rx: old, tx: 10, uptime: "100"),
                              ServerFixture.linux(rx: 1_000, tx: 20, uptime: "102"))
        XCTAssertEqual(sample.receiveRate, 1_000)
        XCTAssertEqual(sample.sendRate, 5)
    }

    func testZeroOrNegativeElapsedGivesNoRates() throws {
        let zero = try pair(ServerFixture.linux(), ServerFixture.linux(rx: 9_876_543_210 + 10), seconds: 0)
        XCTAssertNil(zero.receiveRate)
        let backwards = try pair(ServerFixture.linux(), ServerFixture.linux(rx: 9_876_543_210 + 10), seconds: -5)
        XCTAssertNil(backwards.receiveRate)
    }

    func testSystemChangeBetweenSamplesStartsOver() throws {
        let sample = try pair(ServerFixture.linux(), ServerFixture.mac())
        XCTAssertNil(sample.receiveRate)
        XCTAssertEqual(sample.cpuPercent ?? -1, 13.16, accuracy: 0.001)
    }

    func testSummaryLine() {
        let sample = PortmanServerSample(date: start, cpuPercent: 12.4, memoryUsed: 1_073_741_824,
                                         memoryTotal: 8_589_934_592, diskUsed: 40, diskTotal: 100,
                                         load: [0.52, 0.5, 0.4], uptime: 3 * 86_400)
        let summary = sample.summary
        XCTAssertTrue(summary.hasPrefix("CPU 12% · Mem "), summary)
        XCTAssertTrue(summary.contains("Disk 40%"), summary)
        XCTAssertTrue(summary.contains("Load 0.52"), summary)
        XCTAssertTrue(summary.hasSuffix("Up 3 d"), summary)
        XCTAssertEqual(PortmanServerSample(date: start).summary, "")
    }
}

// MARK: Errors and transport

final class PortmanServerFailureTests: XCTestCase {
    func testSSHErrorsMapToHonestStates() {
        let cases: [(Int32, String, PortmanServerFailure)] = [
            (255, "user@host: Permission denied (publickey).", .authFailed),
            (255, "Received disconnect: Too many authentication failures", .authFailed),
            (255, "Host key verification failed.", .hostKeyFailed),
            (255, "@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @", .hostKeyFailed),
            (255, "ssh: Could not resolve hostname nope: nodename nor servname provided", .unreachable),
            (255, "ssh: connect to host 10.0.0.9 port 22: No route to host", .unreachable),
            (255, "ssh: connect to host 10.0.0.9 port 22: Network is unreachable", .unreachable),
            (255, "ssh: connect to host box port 22: Connection refused", .offline),
            (255, "ssh: connect to host box port 22: Operation timed out", .offline),
            (255, "Connection closed by 10.0.0.9 port 22", .offline),
            (127, "sh: command not found", .commandNotFound),
            (127, "", .commandNotFound),
            (1, "bash: sh: not found", .commandNotFound),
        ]
        for (status, message, expected) in cases {
            XCTAssertEqual(PortmanServerProtocol.classify(status: status, standardError: message), expected, message)
        }
        XCTAssertEqual(PortmanServerProtocol.classify(status: 3, standardError: ""), .failed("ssh exited with status 3."))
        XCTAssertEqual(PortmanServerProtocol.classify(status: 3, standardError: "odd\n"), .failed("odd"))
    }

    func testLabelsAreHonest() {
        XCTAssertEqual(PortmanServerFailure.offline.label, "Offline")
        XCTAssertEqual(PortmanServerFailure.authFailed.label, "Auth failed")
        XCTAssertEqual(PortmanServerFailure.unsupported("SunOS").label, "Unsupported system (SunOS)")
    }

    func testTransportArgumentsNeverPromptAndKeepTheHostAfterDoubleDash() {
        let arguments = PortmanSSHServerTransport.arguments(PortmanServerTarget(destination: "sam@box", port: 2222),
                                                            controlPath: "/s/abc")
        XCTAssertTrue(arguments.contains("BatchMode=yes"))
        XCTAssertTrue(arguments.contains("ConnectTimeout=5"))
        XCTAssertEqual(Array(arguments.suffix(4)), ["--", "sam@box", "sh", "-s"])
        XCTAssertEqual(arguments[arguments.firstIndex(of: "-p")! + 1], "2222")
        XCTAssertFalse(PortmanSSHServerTransport.arguments(PortmanServerTarget(destination: "box"), controlPath: nil)
            .contains("-p"))
        XCTAssertLessThan(PortmanSSHServerTransport.deadline, 30)
    }

    func testSharedConnectionArguments() {
        let shared = PortmanSSHServerTransport.arguments(PortmanServerTarget(destination: "box"), controlPath: "/a b/c")
        XCTAssertTrue(shared.contains("ControlMaster=auto"))
        XCTAssertTrue(shared.contains("ControlPath=\"/a b/c\""), "a path with a space is quoted for ssh")
        XCTAssertTrue(shared.contains("ControlPersist=60"))
        let direct = PortmanSSHServerTransport.arguments(PortmanServerTarget(destination: "box"), controlPath: nil)
        XCTAssertTrue(direct.contains("ControlMaster=no"), "never reuse a master from the owner's ssh config")
        XCTAssertTrue(direct.contains("ControlPath=none"))
        XCTAssertEqual(PortmanSSHServerTransport.closeArguments(PortmanServerTarget(destination: "box"), controlPath: "/s/c"),
                       ["-o", "ControlPath=\"/s/c\"", "-O", "exit", "--", "box"])
    }

    func testControlPathIsShortStableAndPerHostAndPort() throws {
        let directory = URL(fileURLWithPath: "/Users/someone/Library/Application Support/MacPowerToys/ssh")
        let box = try XCTUnwrap(PortmanSSHServerTransport.controlPath(PortmanServerTarget(destination: "box"), in: directory))
        XCTAssertEqual(box, PortmanSSHServerTransport.controlPath(PortmanServerTarget(destination: "box"), in: directory))
        XCTAssertNotEqual(box, PortmanSSHServerTransport.controlPath(PortmanServerTarget(destination: "box", port: 22), in: directory))
        XCTAssertNotEqual(box, PortmanSSHServerTransport.controlPath(PortmanServerTarget(destination: "other"), in: directory))
        XCTAssertEqual(URL(fileURLWithPath: box).lastPathComponent.count, 12)
        XCTAssertLessThanOrEqual(box.utf8.count + 17, 104, "ssh's temporary suffix must still fit sun_path")
        let long = URL(fileURLWithPath: "/" + String(repeating: "d", count: 90))
        XCTAssertNil(PortmanSSHServerTransport.controlPath(PortmanServerTarget(destination: "box"), in: long),
                     "a path too long for a socket turns sharing off instead of failing")
        XCTAssertNil(PortmanSSHServerTransport.controlPath(PortmanServerTarget(destination: "box"), in: nil))
    }

    func testDeadConnectionIsDroppedSoTheNextRunConnectsFresh() {
        XCTAssertTrue(PortmanSSHServerTransport.shouldDropConnection(after: SSHKeyAccessError.timeout, status: nil))
        XCTAssertTrue(PortmanSSHServerTransport.shouldDropConnection(after: nil, status: 255))
        XCTAssertFalse(PortmanSSHServerTransport.shouldDropConnection(after: nil, status: 0))
        XCTAssertFalse(PortmanSSHServerTransport.shouldDropConnection(after: nil, status: 127))
        XCTAssertFalse(PortmanSSHServerTransport.shouldDropConnection(after: CancellationError(), status: nil))
        XCTAssertFalse(PortmanSSHServerTransport.shouldDropConnection(after: SSHKeyAccessError.outputLimit, status: nil))
    }

    func testCloseRemovesAStaleSocketFile() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/mpt-close-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = PortmanServerTarget(destination: "portman-test.invalid")
        let transport = PortmanSSHServerTransport(socketDirectory: directory)
        let path = try XCTUnwrap(PortmanSSHServerTransport.controlPath(target, in: directory))
        FileManager.default.createFile(atPath: path, contents: Data())
        transport.close(target)
        let gone = expectation(description: "socket removed")
        DispatchQueue.global().async {
            for _ in 0..<100 where FileManager.default.fileExists(atPath: path) { usleep(50_000) }
            gone.fulfill()
        }
        wait(for: [gone], timeout: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        transport.close(target)
    }

    func testScriptPicksTheParserByUname() {
        let script = PortmanServerProtocol.script
        XCTAssertTrue(script.contains("uname -s"))
        XCTAssertTrue(script.contains("Linux)"))
        XCTAssertTrue(script.contains("Darwin)"))
        XCTAssertTrue(script.contains("LC_ALL=C"))
        XCTAssertTrue(script.hasSuffix("echo @end"))
    }

    func testStatusText() {
        let now = Date(timeIntervalSince1970: 10_000)
        var state = PortmanServerState()
        XCTAssertEqual(state.statusText(now: now), "Connecting")
        state.status = .failed(.authFailed)
        XCTAssertEqual(state.statusText(now: now), "Auth failed · never seen")
        state.status = .failed(.offline)
        state.lastSeen = now.addingTimeInterval(-300)
        XCTAssertEqual(state.statusText(now: now), "Offline · seen 5 min ago")
        state.lastSeen = now.addingTimeInterval(-7_200)
        XCTAssertEqual(state.statusText(now: now), "Offline · seen 2 h ago")
        state.lastSeen = now.addingTimeInterval(10)
        XCTAssertEqual(state.statusText(now: now), "Offline · seen just now", "clock skew never shows a negative time")
        state.status = .online
        XCTAssertEqual(state.statusText(now: now), "Online")
    }
}

// MARK: Scheduler

private final class CloseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    var values: [String] { lock.withLock { items } }
    func append(_ value: String) { lock.withLock { items.append(value) } }
}

private actor FakeServerTransport: PortmanServerTransport {
    private var responses: [String: [Result<SSHProcessResult, any Error>]] = [:]
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holding = false
    private(set) var calls: [String] = []
    nonisolated let closed = CloseLog()

    nonisolated func close(_ target: PortmanServerTarget) { closed.append(target.destination) }

    func enqueue(_ destination: String, _ result: Result<SSHProcessResult, any Error>) {
        responses[destination, default: []].append(result)
    }

    func setHolding(_ value: Bool) { holding = value }

    func release() {
        holding = false
        held.forEach { $0.resume() }
        held = []
    }

    func run(_ target: PortmanServerTarget, script: String) async throws -> SSHProcessResult {
        calls.append(target.destination)
        if holding { await withCheckedContinuation { held.append($0) } }
        try Task.checkCancellation()
        guard var queue = responses[target.destination], !queue.isEmpty else {
            return SSHProcessResult(status: 0, standardOutput: ServerFixture.linux(), standardError: "")
        }
        let next = queue.removeFirst()
        responses[target.destination] = queue
        return try next.get()
    }

    func waitForCalls(_ count: Int) async {
        for _ in 0..<500 where calls.count < count { await Task.yield() }
    }
}

@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class PortmanServerSchedulerTests: XCTestCase {
    private var clock: TestClock!
    private var transport: FakeServerTransport!
    private var lowPower = false
    private var monitor: PortmanServerMonitor!

    override func setUp() async throws {
        clock = TestClock()
        transport = FakeServerTransport()
        lowPower = false
        let clock = clock!
        monitor = PortmanServerMonitor(transport: transport, now: { clock.now },
                                       lowPower: { [unowned self] in self.lowPower }, autoRun: false)
    }

    private let box = PortmanServerTarget(destination: "box")

    private func runOnce() async {
        monitor.tick()
        await monitor.settle()
    }

    func testIntervalsAndBackoff() {
        XCTAssertEqual(PortmanServerMonitor.interval(.fast, failures: 0), 2)
        XCTAssertEqual(PortmanServerMonitor.interval(.slow, failures: 0), 45)
        XCTAssertNil(PortmanServerMonitor.interval(.off, failures: 0))
        XCTAssertEqual(PortmanServerMonitor.interval(.fast, failures: 1), 4)
        XCTAssertEqual(PortmanServerMonitor.interval(.fast, failures: 3), 16)
        XCTAssertEqual(PortmanServerMonitor.interval(.fast, failures: 4), 30, "fast backoff caps at 30 s")
        XCTAssertEqual(PortmanServerMonitor.interval(.slow, failures: 2), 180)
        XCTAssertEqual(PortmanServerMonitor.interval(.slow, failures: 99), 600, "slow backoff caps at 10 min")
        XCTAssertEqual(PortmanServerMonitor.interval(.fast, failures: -1), 2)
    }

    func testCadenceFollowsPanelHostsAndLowPower() {
        XCTAssertEqual(monitor.currentCadence, .off, "no monitored host")
        monitor.sync([box])
        XCTAssertEqual(monitor.currentCadence, .slow, "panel closed")
        monitor.setPanel(open: true, forwardTab: true)
        XCTAssertEqual(monitor.currentCadence, .fast)
        monitor.setPanel(open: true, forwardTab: false)
        XCTAssertEqual(monitor.currentCadence, .slow, "Servers tab")
        monitor.setPanel(open: true, forwardTab: true)
        lowPower = true
        XCTAssertEqual(monitor.currentCadence, .off)
        lowPower = false
        monitor.setPanel(open: false, forwardTab: false)
        XCTAssertEqual(monitor.currentCadence, .slow, "closing the panel drops fast polling")
        XCTAssertEqual(monitor.cadence, .slow)
    }

    func testOnlyMonitoredHostsBecomeTargets() {
        let targets = PortmanServerMonitor.targets(from: [
            PortmanHost(destination: "fwd", mode: .forward),
            PortmanHost(destination: "mon", mode: .monitor, port: 2222),
            PortmanHost(destination: "both", mode: .both),
        ])
        XCTAssertEqual(targets, [PortmanServerTarget(destination: "mon", port: 2222),
                                 PortmanServerTarget(destination: "both")])
    }

    func testReorderedHostsKeepTheirMonitorState() async {
        let other = PortmanServerTarget(destination: "other")
        monitor.sync([box, other])
        await runOnce()
        let before = monitor.states
        monitor.sync([other, box])
        XCTAssertEqual(monitor.states["box"]?.status, .online)
        XCTAssertEqual(monitor.states["box"]?.history.count, before["box"]?.history.count)
        XCTAssertEqual(monitor.states["other"]?.lastSeen, before["other"]?.lastSeen)
        XCTAssertTrue(transport.closed.values.isEmpty, "a new order must not drop the SSH connections")
    }

    func testFirstTickSamplesAndGoesOnline() async {
        monitor.sync([box])
        await runOnce()
        let state = monitor.states["box"]
        XCTAssertEqual(state?.status, .online)
        XCTAssertEqual(state?.lastSeen, clock.now)
        XCTAssertEqual(state?.history.count, 1)
        XCTAssertNil(state?.latest?.cpuPercent, "first Linux sample has no CPU delta")
        let calls = await transport.calls
        XCTAssertEqual(calls, ["box"])
    }

    func testSecondSampleHasCPU() async {
        await transport.enqueue("box", .success(SSHProcessResult(status: 0, standardOutput: ServerFixture.linux(), standardError: "")))
        await transport.enqueue("box", .success(SSHProcessResult(
            status: 0, standardOutput: ServerFixture.linux(user: 10_132_153 + 500, idle: 46_828_483 + 500,
                                                           uptime: "350737.47"), standardError: "")))
        monitor.sync([box])
        await runOnce()
        clock.advance(45)
        await runOnce()
        XCTAssertEqual(monitor.states["box"]?.latest?.cpuPercent ?? -1, 50, accuracy: 0.001)
    }

    func testNoOverlappingSamples() async {
        await transport.setHolding(true)
        monitor.sync([box])
        monitor.tick()
        await transport.waitForCalls(1)
        XCTAssertTrue(monitor.isRunning("box"))
        clock.advance(120)
        monitor.tick()
        monitor.tick()
        XCTAssertNil(monitor.nextDue("box"), "a running host is never due")
        await transport.release()
        await monitor.settle()
        let calls = await transport.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(monitor.isRunning("box"))
    }

    func testSlowWaitsThenFastIsDueSooner() async {
        monitor.sync([box])
        await runOnce()
        let first = clock.now
        XCTAssertEqual(monitor.nextDue("box"), first.addingTimeInterval(45))
        clock.advance(10)
        await runOnce()
        var calls = await transport.calls
        XCTAssertEqual(calls.count, 1, "slow cadence is not due after 10 s")
        monitor.setPanel(open: true, forwardTab: true)
        XCTAssertEqual(monitor.nextDue("box"), first.addingTimeInterval(2))
        await runOnce()
        calls = await transport.calls
        XCTAssertEqual(calls.count, 2, "opening Forward samples at once")
        monitor.setPanel(open: false, forwardTab: false)
        XCTAssertEqual(monitor.nextDue("box"), clock.now.addingTimeInterval(45))
    }

    func testLowPowerStopsSampling() async {
        lowPower = true
        monitor.sync([box])
        await runOnce()
        let calls = await transport.calls
        XCTAssertEqual(calls, [])
        XCTAssertNil(monitor.nextDue("box"))
        XCTAssertEqual(monitor.states["box"]?.status, .waiting)
    }

    func testFailureBacksOffAndKeepsLastSeen() async {
        monitor.setPanel(open: true, forwardTab: true)
        monitor.sync([box])
        await runOnce()
        let seen = clock.now
        await transport.enqueue("box", .success(SSHProcessResult(status: 255, standardOutput: "",
            standardError: "ssh: connect to host box port 22: Connection refused")))
        await transport.enqueue("box", .failure(SSHKeyAccessError.timeout))
        clock.advance(2)
        await runOnce()
        var state = monitor.states["box"]
        XCTAssertEqual(state?.status, .failed(.offline))
        XCTAssertEqual(state?.failures, 1)
        XCTAssertEqual(state?.lastSeen, seen)
        XCTAssertEqual(monitor.nextDue("box"), clock.now.addingTimeInterval(4))
        XCTAssertEqual(state?.history.count, 1, "failures add no graph point")
        clock.advance(4)
        await runOnce()
        state = monitor.states["box"]
        XCTAssertEqual(state?.status, .failed(.offline), "a hard deadline reads as Offline")
        XCTAssertEqual(state?.failures, 2)
        XCTAssertEqual(monitor.nextDue("box"), clock.now.addingTimeInterval(8))
        clock.advance(60)
        XCTAssertEqual(state?.statusText(now: clock.now), "Offline · seen 1 min ago")
        await runOnce()
        state = monitor.states["box"]
        XCTAssertEqual(state?.status, .online)
        XCTAssertEqual(state?.failures, 0, "a good sample resets the backoff")
    }

    func testAuthAndHostKeyFailuresShowHonestly() async {
        await transport.enqueue("box", .success(SSHProcessResult(status: 255, standardOutput: "",
            standardError: "sam@box: Permission denied (publickey,password).")))
        monitor.sync([box])
        await runOnce()
        XCTAssertEqual(monitor.states["box"]?.statusText(now: clock.now), "Auth failed · never seen")
        await transport.enqueue("box", .success(SSHProcessResult(status: 255, standardOutput: "",
            standardError: "Host key verification failed.")))
        clock.advance(600)
        await runOnce()
        XCTAssertEqual(monitor.states["box"]?.status, .failed(.hostKeyFailed))
    }

    func testGarbageAndOversizedOutputFail() async {
        await transport.enqueue("box", .success(SSHProcessResult(status: 0, standardOutput: "garbage", standardError: "")))
        await transport.enqueue("box", .failure(SSHKeyAccessError.outputLimit))
        monitor.sync([box])
        await runOnce()
        XCTAssertEqual(monitor.states["box"]?.status, .failed(.invalidOutput))
        clock.advance(600)
        await runOnce()
        XCTAssertEqual(monitor.states["box"]?.status, .failed(.invalidOutput))
    }

    func testRemovalCancelsTheRunningSample() async {
        await transport.setHolding(true)
        monitor.sync([box])
        monitor.tick()
        await transport.waitForCalls(1)
        monitor.sync([])
        XCTAssertFalse(monitor.isRunning("box"))
        XCTAssertNil(monitor.states["box"])
        XCTAssertEqual(monitor.currentCadence, .off)
        await transport.release()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertNil(monitor.states["box"], "a cancelled run never writes state back")
        monitor.sync([box])
        XCTAssertEqual(monitor.states["box"], PortmanServerState(), "re-adding starts fresh")
    }

    func testChangingThePortRestartsTheHost() async {
        monitor.sync([box])
        await runOnce()
        monitor.sync([PortmanServerTarget(destination: "box", port: 2200)])
        XCTAssertEqual(monitor.states["box"]?.status, .waiting)
        XCTAssertEqual(transport.closed.values, ["box"], "the old port's shared connection is closed")
    }

    func testRemovingHostsClosesOnlyTheirConnections() async {
        let other = PortmanServerTarget(destination: "other")
        monitor.sync([box, other])
        await runOnce()
        XCTAssertEqual(transport.closed.values, [], "sampling keeps the connection open")
        monitor.sync([other])
        XCTAssertEqual(transport.closed.values, ["box"])
        monitor.sync([other])
        XCTAssertEqual(transport.closed.values, ["box"], "an unchanged host is not closed")
        monitor.sync([])
        XCTAssertEqual(transport.closed.values, ["box", "other"], "stopping closes every connection")
    }

    func testHistoryKeepsTheLastSixtyPoints() async {
        monitor.sync([box])
        for _ in 0..<75 {
            await runOnce()
            clock.advance(45)
        }
        XCTAssertEqual(monitor.states["box"]?.history.count, PortmanServerMonitor.historyLimit)
        XCTAssertEqual(monitor.states["box"]?.history.last?.date, clock.now.addingTimeInterval(-45))
    }

    func testHostsSampleIndependently() async {
        let other = PortmanServerTarget(destination: "other")
        await transport.enqueue("other", .success(SSHProcessResult(status: 255, standardOutput: "",
            standardError: "ssh: Could not resolve hostname other")))
        monitor.sync([box, other])
        await runOnce()
        XCTAssertEqual(monitor.states["box"]?.status, .online)
        XCTAssertEqual(monitor.states["other"]?.status, .failed(.unreachable))
    }

    func testSamplerReportsCancellationAsNoChange() async {
        let sampler = PortmanServerSampler()
        await transport.setHolding(true)
        let task = Task { await sampler.sample(box, transport: transport, at: Date()) }
        await transport.waitForCalls(1)
        task.cancel()
        await transport.release()
        let result = await task.value
        XCTAssertNil(result)
    }
}
