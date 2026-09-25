import Darwin
import XCTest
@testable import powertoys

final class PortmanTests: XCTestCase {
    func testLocalScanKeepsListeningPortsAndProcessStats() {
        let lsof = """
        p42
        cnode
        n127.0.0.1:3000
        n127.0.0.1:3000
        n*:5173
        n*:22
        p51
        cpython3
        n[::1]:8000
        """
        let ps = """
         42 1024 1.5 00:07:12 node server.js
         51 2048 0.0 01:00 python3 app.py
        """
        let ports = PortmanScanner.parseLocal(lsof, ps)
        XCTAssertEqual(ports.map(\.port), [3000, 5173, 8000])
        XCTAssertEqual(ports[0].memoryBytes, 1_048_576)
        XCTAssertEqual(ports[0].cpuPercent, 1.5)
        XCTAssertEqual(ports[2].command, "python3")
    }

    func testRemotePortsAndTunnelStayOnLoopback() throws {
        let output = """
        LISTEN 0 4096 127.0.0.1:3000 0.0.0.0:*
        LISTEN 0 128 [::1]:6006 [::]:*
        LISTEN 0 4096 127.0.0.1:3000 0.0.0.0:*
        """
        XCTAssertEqual(PortmanScanner.parseRemote(output), [3000, 6006])
        let arguments = try PortmanScanner.tunnelArguments(host: "my-server", remotePort: 3000, localPort: 4200)
        XCTAssertTrue(arguments.contains("127.0.0.1:4200:localhost:3000"))
        XCTAssertEqual(arguments.suffix(2), ["--", "my-server"])
        XCTAssertThrowsError(try PortmanScanner.tunnelArguments(host: "-oProxyCommand=bad", remotePort: 3000, localPort: 4200))
        XCTAssertThrowsError(try PortmanScanner.tunnelArguments(host: "my-server", remotePort: 0, localPort: 4200))
    }

    func testLocalScannerFindsAnActualListeningSocket() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        var chosenPort: UInt16?
        for candidate in UInt16(9000)...UInt16(9999) {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = candidate.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 { chosenPort = candidate; break }
        }
        let port = try XCTUnwrap(chosenPort)
        XCTAssertEqual(listen(descriptor, 1), 0)
        let ports = try PortmanScanner.localPorts()
        XCTAssertTrue(ports.contains { $0.port == port && $0.pid == getpid() })
    }

    func testStopRejectsAChangedProcessIdentity() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        var info = proc_bsdinfo()
        let bytes = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(child.processIdentifier, PROC_PIDTBSDINFO, 0, $0,
                         Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        XCTAssertEqual(bytes, Int32(MemoryLayout<proc_bsdinfo>.size))
        let started = info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        let stale = PortmanLocalPort(pid: child.processIdentifier, port: 9000, address: "127.0.0.1:9000",
                                     command: "sleep", launchCommand: "sleep 30", memoryBytes: 0,
                                     cpuPercent: 0, uptime: "0:01", started: started + 1, userID: geteuid())
        XCTAssertThrowsError(try PortmanScanner.stop(stale))
        XCTAssertTrue(child.isRunning)
    }
}
