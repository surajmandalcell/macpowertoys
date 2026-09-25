import Darwin
import AppKit
import SwiftUI
import XCTest
@testable import powertoys

final class PortmanTests: XCTestCase {
    func testClaudeSessionIDReadsOnlyEnvironmentAfterArguments() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        let bytes: [UInt8] = [2, 0, 0, 0] + Array(
            "/bin/node\0\0node\0server.js\0SECRET=private\0CLAUDE_CODE_SESSION_ID=\(id.uuidString)\0".utf8
        )
        XCTAssertEqual(PortmanSessionResolver.sessionID(in: bytes), id)
        let launch = PortmanLaunch.parse(bytes, folder: "/tmp")
        XCTAssertEqual(launch?.executable, "/bin/node")
        XCTAssertEqual(launch?.arguments, ["node", "server.js"])
        XCTAssertEqual(launch?.environment["SECRET"], "private")
        XCTAssertEqual(launch?.replayable, true)
        XCTAssertNil(PortmanSessionResolver.sessionID(in: [2, 0, 0, 0] + Array(
            "/bin/node\0\0node\0CLAUDE_CODE_SESSION_ID=bad\0".utf8
        )))
        let rewritten = PortmanLaunch.parse([1, 0, 0, 0] + Array(
            "/bin/node\0\0npm run dev\0PATH=/usr/bin\0".utf8
        ), folder: "/tmp")
        XCTAssertEqual(rewritten?.replayable, false)
    }

    func testGitHubLinksAcceptOnlyPlainGitHubRemotes() {
        let https = PortmanGitHubLookup.repository(from: "https://github.com/surajmandalcell/macpowertoys.git")
        XCTAssertEqual(https?.owner, "surajmandalcell")
        XCTAssertEqual(https?.name, "macpowertoys")
        let ssh = PortmanGitHubLookup.repository(from: "git@github.com:surajmandalcell/macpowertoys.git")
        XCTAssertEqual(ssh?.name, "macpowertoys")
        XCTAssertNil(PortmanGitHubLookup.repository(from: "https://other.example/owner/repo.git"))
        XCTAssertNil(PortmanGitHubLookup.repository(from: "https://token:secret@github.com/owner/repo.git"))
        XCTAssertNil(PortmanGitHubLookup.repository(from: "https://github.com/owner/repo.git?token=secret"))
    }

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
        XCTAssertTrue(arguments.contains("ConnectTimeout=5"))
        XCTAssertEqual(arguments.suffix(2), ["--", "my-server"])
        XCTAssertThrowsError(try PortmanScanner.tunnelArguments(host: "-oProxyCommand=bad", remotePort: 3000, localPort: 4200))
        XCTAssertThrowsError(try PortmanScanner.tunnelArguments(host: "my-server", remotePort: 0, localPort: 4200))
    }

    func testLocalRangeAndProcessTableParsing() {
        let lsof = "p42\ncnode\nn127.0.0.1:3000\nn127.0.0.1:9000\n"
        let ps = "42 1024 1.5 00:07:12 node server.js\n"
        XCTAssertEqual(PortmanScanner.parseLocal(lsof, ps, range: 8000...9999).map(\.port), [9000])
        let table = "42 1 1024 1.5 node\n43 42 512 0.2 vite\ninvalid\n"
        let processes = PortmanScanner.parseProcessTable(table)
        XCTAssertEqual(processes.map(\.pid), [42, 43])
        XCTAssertEqual(processes[1].parentPID, 42)
        XCTAssertEqual(processes[1].memoryBytes, 512 * 1_024)
    }

    func testDevelopmentListenerFilterKeepsCLIAndHidesSystemApps() {
        let user = geteuid()
        func port(_ command: String, _ launch: String, _ uid: UInt32) -> PortmanLocalPort {
            PortmanLocalPort(pid: 42, port: 3000, address: "127.0.0.1:3000",
                             command: command, launchCommand: launch, memoryBytes: 0,
                             cpuPercent: 0, uptime: "0:01", started: 1, userID: uid)
        }
        XCTAssertTrue(PortmanScanner.isDevelopmentListener(port("node", "node server.js", user)))
        XCTAssertFalse(PortmanScanner.isDevelopmentListener(port("ControlCenter", "/System/Library/ControlCenter.app/Contents/MacOS/ControlCenter", user)))
        XCTAssertFalse(PortmanScanner.isDevelopmentListener(port("adb", "/opt/homebrew/bin/adb", user)))
        XCTAssertFalse(PortmanScanner.isDevelopmentListener(port("node", "node server.js", user &+ 1)))
    }

    func testNotificationRearmsOnlyWellBelowBothLimits() {
        let mb: Int64 = 1_024 * 1_024
        XCTAssertFalse(PortmanService.canRearmNotification(
            memoryBytes: 1_900 * mb, growthBytes: 0,
            memoryLimit: 2_048 * mb, growthLimit: 500 * mb))
        XCTAssertFalse(PortmanService.canRearmNotification(
            memoryBytes: 100 * mb, growthBytes: 400 * mb,
            memoryLimit: 2_048 * mb, growthLimit: 500 * mb))
        XCTAssertTrue(PortmanService.canRearmNotification(
            memoryBytes: 100 * mb, growthBytes: 100 * mb,
            memoryLimit: 2_048 * mb, growthLimit: 500 * mb))
    }

    func testLocalScannerFindsAnActualListeningSocket() throws {
        let preference = "portman.showAllListeners"
        let previous = UserDefaults.standard.object(forKey: preference)
        UserDefaults.standard.set(true, forKey: preference)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: preference) }
            else { UserDefaults.standard.removeObject(forKey: preference) }
        }
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
        XCTAssertTrue(PortmanScanner.tunnelIsListening(pid: getpid(), localPort: port))
        XCTAssertFalse(PortmanScanner.tunnelIsListening(pid: getpid(), localPort: port + 1))
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

    @MainActor
    func testRestartReopensAListeningServer() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("The hosted Mac has no Python 3 executable.")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("portman-restart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(socketFD, 0)
        var chosenPort: UInt16?
        for candidate in UInt16(9000)...UInt16(9999) {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = candidate.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bound == 0 { chosenPort = candidate; break }
        }
        close(socketFD)
        let port = try XCTUnwrap(chosenPort)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(port), "--bind", "127.0.0.1"]
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        var restarted: PortmanLocalPort?
        defer {
            if let restarted { try? PortmanScanner.stop(restarted) }
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            let log = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/MacPowerToys/Portman/port-\(port).log")
            try? FileManager.default.removeItem(at: log)
        }

        var original: PortmanLocalPort?
        for _ in 0..<20 {
            original = try PortmanScanner.localPorts(range: port...port)
                .first { $0.pid == process.processIdentifier }
            if original != nil { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let listener = try XCTUnwrap(original)
        XCTAssertNotNil(PortmanLaunch.capture(listener, folder: folder.path))
        let service = PortmanService.shared
        service.beginMonitoring()
        defer { service.endMonitoring() }
        await service.refreshLocal()
        let panelHasListener = service.localPorts.contains { $0.pid == listener.pid && $0.port == port }
        XCTAssertTrue(panelHasListener)
        let host = NSHostingView(rootView: PortmanPanelView().environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(representation)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Portman — Live Server — Dark"
        attachment.lifetime = .keepAlways
        add(attachment)

        try await PortmanRestart.run(listener, folder: folder.path)

        for _ in 0..<20 {
            restarted = try PortmanScanner.localPorts(range: port...port)
                .first { $0.pid != process.processIdentifier }
            if restarted != nil { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertNotNil(restarted, "Restart must create a new listener on the same port.")
    }
}
