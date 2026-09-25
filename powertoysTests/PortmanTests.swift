import Darwin
import AppKit
import SwiftUI
import XCTest
@testable import powertoys

final class PortmanTests: XCTestCase {
    private static let rclonePath = ["/opt/homebrew/bin/rclone", "/usr/local/bin/rclone"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

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

    func testEditorChoiceUsesOnlyKnownAppsAndPrefersSelectedApp() {
        let available = PortmanEditor.choices.map(\.id)
        XCTAssertEqual(PortmanEditor.bundleIDs(for: "com.microsoft.VSCode").first,
                       "com.microsoft.VSCode")
        XCTAssertEqual(PortmanEditor.bundleIDs(for: "untrusted.bundle"), available)
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

    @MainActor
    func testSSHForwardCarriesTrafficThroughLoopback() async throws {
        let rclone = try XCTUnwrap(Self.rclonePath, "Homebrew rclone is required for hosted Portman tests.")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("portman-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("portman-forward-ok".utf8).write(to: source.appendingPathComponent("probe.txt"))

        func unusedPort() throws -> UInt16 {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw NSError(domain: "PortmanTests", code: 1) }
            defer { close(descriptor) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0 else { throw NSError(domain: "PortmanTests", code: 2) }
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(descriptor, $0, &size)
                }
            }
            guard named == 0 else { throw NSError(domain: "PortmanTests", code: 3) }
            return UInt16(bigEndian: address.sin_port)
        }

        let remotePort = try unusedPort()
        let server = Process()
        server.executableURL = URL(fileURLWithPath: rclone)
        server.arguments = ["serve", "http", source.path, "--addr", "127.0.0.1:\(remotePort)",
                            "--config", "/dev/null"]
        server.standardInput = FileHandle.nullDevice
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }

        let hostKey = folder.appendingPathComponent("host_key")
        let clientKey = folder.appendingPathComponent("client_key")
        for key in [hostKey, clientKey] {
            _ = try PortmanScanner.run("/usr/bin/ssh-keygen",
                                       ["-q", "-t", "ed25519", "-N", "", "-f", key.path])
        }
        let sshPort = try unusedPort()
        let knownHosts = folder.appendingPathComponent("known_hosts")
        let publicHostKey = try String(contentsOf: hostKey.appendingPathExtension("pub"), encoding: .utf8)
        try "portman-test \(publicHostKey)".write(to: knownHosts, atomically: true, encoding: .utf8)
        let authorizedKeys = folder.appendingPathComponent("authorized_keys")
        try FileManager.default.copyItem(at: clientKey.appendingPathExtension("pub"), to: authorizedKeys)
        let serverConfig = folder.appendingPathComponent("sshd_config")
        try """
        Port \(sshPort)
        ListenAddress 127.0.0.1
        HostKey \(hostKey.path)
        AuthorizedKeysFile \(authorizedKeys.path)
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        UsePAM no
        StrictModes no
        PidFile \(folder.appendingPathComponent("sshd.pid").path)
        """.write(to: serverConfig, atomically: true, encoding: .utf8)
        let clientConfig = folder.appendingPathComponent("ssh_config")
        try """
        Host portman-test
            HostName 127.0.0.1
            Port \(sshPort)
            User \(NSUserName())
            IdentityFile \(clientKey.path)
            IdentitiesOnly yes
            HostKeyAlias portman-test
            UserKnownHostsFile \(knownHosts.path)
            GlobalKnownHostsFile /dev/null
        """.write(to: clientConfig, atomically: true, encoding: .utf8)
        let sshLog = folder.appendingPathComponent("sshd.log")
        FileManager.default.createFile(atPath: sshLog.path, contents: nil)
        let sshLogHandle = try FileHandle(forWritingTo: sshLog)
        defer { try? sshLogHandle.close() }
        let sshd = Process()
        sshd.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        sshd.arguments = ["-D", "-e", "-f", serverConfig.path]
        sshd.standardInput = FileHandle.nullDevice
        sshd.standardOutput = sshLogHandle
        sshd.standardError = sshLogHandle
        try sshd.run()
        defer { if sshd.isRunning { sshd.terminate(); sshd.waitUntilExit() } }
        var sshReady = false
        for _ in 0..<20 {
            sshReady = PortmanScanner.tunnelIsListening(pid: sshd.processIdentifier, localPort: sshPort)
            if sshReady { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(sshReady, (try? String(contentsOf: sshLog, encoding: .utf8)) ?? "sshd did not listen")

        let service = PortmanService.shared
        defer { service.stopAll() }
        await service.refreshRemote(host: "portman-test", configurationFile: clientConfig)
        XCTAssertTrue(service.remotePorts.contains(remotePort),
                      service.forwardingError ?? "SSH scan missed the HTTP listener")

        let localPort = try unusedPort()
        XCTAssertTrue(service.forward(host: "portman-test", remotePort: remotePort,
                                      localPort: localPort, configurationFile: clientConfig),
                      service.forwardingError ?? "SSH did not start")
        let tunnelID = try XCTUnwrap(service.tunnels.first { $0.localPort == localPort }?.id)
        func tunnelRunning() -> Bool {
            guard let tunnel = service.tunnels.first(where: { $0.id == tunnelID }) else { return false }
            if case .running = tunnel.state { return true }
            return false
        }

        var response: String?
        for _ in 0..<30 {
            if tunnelRunning() {
                response = try? PortmanScanner.run("/usr/bin/curl",
                    ["--silent", "--show-error", "--fail", "--max-time", "2",
                     "http://127.0.0.1:\(localPort)/probe.txt"])
                if response != nil { break }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        let log = (try? String(contentsOf: sshLog, encoding: .utf8)) ?? ""
        XCTAssertEqual(response, "portman-forward-ok",
                       "SSH forwarding failed: \(service.forwardingError ?? "") \(log)")
        XCTAssertFalse(service.forward(host: "portman-test", remotePort: remotePort,
                                       localPort: localPort, configurationFile: clientConfig))
        XCTAssertTrue(service.forwardingError?.contains("already has a Portman tunnel") == true)
        XCTAssertTrue(tunnelRunning())
        service.forwardingError = nil

        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: PortmanPanelView(initialPage: .forward)
                .environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
            host.layoutSubtreeIfNeeded()
            host.frame.size = host.fittingSize
            host.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(representation)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Portman — Active Forward — \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        service.stopTunnel(tunnelID)
        XCTAssertFalse(service.tunnels.contains { $0.id == tunnelID })

        let occupiedPort = try unusedPort()
        let blocker = socket(AF_INET, SOCK_STREAM, 0)
        guard blocker >= 0 else { throw NSError(domain: "PortmanTests", code: 4) }
        defer { close(blocker) }
        var blockedAddress = sockaddr_in()
        blockedAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        blockedAddress.sin_family = sa_family_t(AF_INET)
        blockedAddress.sin_port = occupiedPort.bigEndian
        blockedAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &blockedAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(blocker, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(blocker, 1) == 0 else {
            throw NSError(domain: "PortmanTests", code: 5)
        }
        XCTAssertTrue(service.forward(host: "portman-test", remotePort: remotePort,
                                      localPort: occupiedPort, configurationFile: clientConfig))
        let failedID = try XCTUnwrap(service.tunnels.first { $0.localPort == occupiedPort }?.id)
        var failure: String?
        for _ in 0..<30 {
            if let tunnel = service.tunnels.first(where: { $0.id == failedID }),
               case .failed(let message) = tunnel.state {
                failure = message
                break
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertNotNil(failure, "A local port already in use must leave a failed tunnel, not Connecting.")
        service.stopTunnel(failedID)

        let droppedPort = try unusedPort()
        XCTAssertTrue(service.forward(host: "portman-test", remotePort: remotePort,
                                      localPort: droppedPort, configurationFile: clientConfig))
        let droppedID = try XCTUnwrap(service.tunnels.first { $0.localPort == droppedPort }?.id)
        let sshPID = try XCTUnwrap(service.processID(forTunnel: droppedID))
        var wasRunning = false
        for _ in 0..<30 {
            if let tunnel = service.tunnels.first(where: { $0.id == droppedID }),
               case .running = tunnel.state { wasRunning = true; break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertTrue(wasRunning, "The second tunnel must reach Forwarding before an unexpected exit.")
        XCTAssertTrue(PortmanScanner.tunnelIsListening(pid: sshPID, localPort: droppedPort))
        XCTAssertEqual(Darwin.kill(sshPID, SIGTERM), 0)
        var dropped = false
        for _ in 0..<30 {
            if let tunnel = service.tunnels.first(where: { $0.id == droppedID }),
               case .failed = tunnel.state { dropped = true; break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertTrue(dropped, "An unexpected SSH exit must replace Forwarding with a failed state. "
            + "Listener remains: \(PortmanScanner.tunnelIsListening(pid: sshPID, localPort: droppedPort)); "
            + "process remains: \(Darwin.kill(sshPID, 0) == 0); "
            + "tunnel: \(String(describing: service.tunnels.first { $0.id == droppedID })).")
        if dropped {
            XCTAssertNil(service.processID(forTunnel: droppedID), "A failed tunnel must release its SSH process.")
        }
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: PortmanPanelView(initialPage: .forward)
                .environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
            host.layoutSubtreeIfNeeded()
            host.frame.size = host.fittingSize
            host.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(representation)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Portman — Failed Forward — \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        service.stopTunnel(droppedID)
        XCTAssertFalse(service.tunnels.contains { $0.id == droppedID })
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
        XCTAssertTrue(PortmanScanner.isDevelopmentListener(port(
            "Python", "/Library/Developer/Python.app/Contents/MacOS/Python -m http.server 3000", user
        )))
        XCTAssertFalse(PortmanScanner.isDevelopmentListener(port("ControlCenter", "/System/Library/ControlCenter.app/Contents/MacOS/ControlCenter", user)))
        XCTAssertFalse(PortmanScanner.isDevelopmentListener(port(
            "Chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", user
        )))
        XCTAssertFalse(PortmanScanner.isDevelopmentListener(port("adb", "/opt/homebrew/bin/adb", user)))
        XCTAssertFalse(PortmanScanner.isDevelopmentListener(port("node", "node server.js", user &+ 1)))
    }

    func testCleanupSuggestionsProtectWarningsAndUseReferenceAges() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func port(started: TimeInterval, command: String = "node", connected: Bool = false) -> PortmanLocalPort {
            var result = PortmanLocalPort(pid: 42, port: 3000, address: "127.0.0.1:3000",
                                          command: command, launchCommand: "node server.js", memoryBytes: 0,
                                          cpuPercent: 0, uptime: "", started: UInt64(started * 1_000_000),
                                          userID: geteuid())
            result.hasConnections = connected
            return result
        }
        func suggested(_ port: PortmanLocalPort, warning: Bool = false, folder: String? = nil,
                       lastConnection: Date? = nil, mode: PortmanCleanupMode = .ask,
                       includeDeleted: Bool = true) -> Bool {
            PortmanCleanupPolicy.suggested(
                port: port, hasWarning: warning, folder: folder, lastConnectionAt: lastConnection,
                now: now, idleHours: 4, runningDays: 3,
                mode: mode, includeDeletedFolders: includeDeleted
            )
        }
        let threeDaysAgo = now.timeIntervalSince1970 - 3 * 86_400
        XCTAssertFalse(suggested(port(started: threeDaysAgo + 1, connected: true)))
        XCTAssertTrue(suggested(port(started: threeDaysAgo, connected: true)))
        XCTAssertFalse(suggested(port(started: threeDaysAgo), warning: true))
        XCTAssertFalse(suggested(port(started: threeDaysAgo, command: "postgres")))
        XCTAssertFalse(suggested(port(started: threeDaysAgo), mode: .off))
        XCTAssertTrue(suggested(port(started: now.timeIntervalSince1970 - 60),
                                folder: "/project (deleted)"))
        let removedFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("portman-removed-\(UUID().uuidString)").path
        XCTAssertTrue(suggested(port(started: now.timeIntervalSince1970 - 60), folder: removedFolder))
        XCTAssertFalse(suggested(port(started: now.timeIntervalSince1970 - 60),
                                 folder: "/project (deleted)", includeDeleted: false))
        let oneDayAgo = now.timeIntervalSince1970 - 86_400
        XCTAssertFalse(suggested(port(started: oneDayAgo),
                                 lastConnection: now.addingTimeInterval(-4 * 3_600 + 1)))
        XCTAssertTrue(suggested(port(started: oneDayAgo),
                                lastConnection: now.addingTimeInterval(-4 * 3_600)))
        XCTAssertFalse(suggested(port(started: 0), folder: "/project (deleted)"))
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

    func testClosedPortmanUsesLowDutyScanInterval() {
        let now = Date(timeIntervalSince1970: 100)
        func shouldScan(_ owners: Int, _ secondsAgo: TimeInterval, interval: TimeInterval = 2) -> Bool {
            PortmanService.shouldRunScan(ownerCount: owners,
                                         lastScanAt: now.addingTimeInterval(-secondsAgo),
                                         now: now, interval: interval)
        }
        XCTAssertFalse(shouldScan(0, 60))
        XCTAssertFalse(shouldScan(1, 29))
        XCTAssertTrue(shouldScan(1, 30))
        XCTAssertFalse(shouldScan(1, 30, interval: 60))
        XCTAssertTrue(shouldScan(2, 0))
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
        PortmanScanner.forceStopIfUnchanged(stale)
        XCTAssertTrue(child.isRunning)
        let exited = expectation(description: "Matched process exits after force quit")
        child.terminationHandler = { _ in exited.fulfill() }
        let current = PortmanLocalPort(pid: child.processIdentifier, port: 9000, address: "127.0.0.1:9000",
                                       command: "sleep", launchCommand: "sleep 30", memoryBytes: 0,
                                       cpuPercent: 0, uptime: "0:01", started: started, userID: geteuid())
        PortmanScanner.forceStopIfUnchanged(current)
        wait(for: [exited], timeout: 2)
        XCTAssertEqual(child.terminationStatus, SIGKILL)
    }

    @MainActor
    func testPortmanForwardAndSettingsRenderInBothAppearances() throws {
        for page in [PortmanPanelView.Page.forward, .settings] {
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(rootView: PortmanPanelView(initialPage: page)
                    .environment(\.colorScheme, scheme))
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
                host.layoutSubtreeIfNeeded()
                host.frame.size = host.fittingSize
                host.layoutSubtreeIfNeeded()
                let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: representation)
                let image = NSImage(size: host.bounds.size)
                image.addRepresentation(representation)
                let attachment = XCTAttachment(image: image)
                attachment.name = "Portman — \(page.rawValue) — \(scheme == .dark ? "Dark" : "Light")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testRestartReopensAListeningServer() async throws {
        let rclone = try XCTUnwrap(Self.rclonePath, "Homebrew rclone is required for hosted Portman tests.")
        let preference = "portman.showAllListeners"
        let previous = UserDefaults.standard.object(forKey: preference)
        UserDefaults.standard.set(true, forKey: preference)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: preference) }
            else { UserDefaults.standard.removeObject(forKey: preference) }
        }
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("portman-restart-\(UUID().uuidString)")
        let folder = fixture.appendingPathComponent("preview-server")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

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
        process.executableURL = URL(fileURLWithPath: rclone)
        process.arguments = ["serve", "http", folder.path, "--addr", "127.0.0.1:\(port)",
                             "--config", "/dev/null"]
        process.environment = ["PATH": "/usr/bin:/bin"]
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
        let launch = try XCTUnwrap(PortmanLaunch.capture(listener, folder: folder.path))
        XCTAssertEqual(launch.environment["PATH"], "/usr/bin:/bin")
        let service = PortmanService.shared
        service.beginMonitoring()
        defer { service.endMonitoring() }
        await service.refreshLocal()
        await service.refreshLocal()
        let panelHasListener = service.localPorts.contains { $0.pid == listener.pid && $0.port == port }
        XCTAssertTrue(panelHasListener)
        XCTAssertGreaterThanOrEqual(service.history[listener.id]?.count ?? 0, 2)
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

        let observed = try XCTUnwrap(service.localPorts.first { $0.pid == listener.pid && $0.port == port })
        await service.loadMetadata(for: observed)
        await service.loadRestartAvailability(for: observed)
        for scheme in [ColorScheme.light, .dark] {
            let cleanup = NSHostingView(rootView: PortmanPanelView(initialCleanupProcessID: observed.processID)
                .environment(\.colorScheme, scheme))
            cleanup.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            cleanup.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
            cleanup.layoutSubtreeIfNeeded()
            cleanup.frame.size = cleanup.fittingSize
            cleanup.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(cleanup.bitmapImageRepForCachingDisplay(in: cleanup.bounds))
            cleanup.cacheDisplay(in: cleanup.bounds, to: representation)
            let image = NSImage(size: cleanup.bounds.size)
            image.addRepresentation(representation)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Portman — Cleanup Selection — \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for scheme in [ColorScheme.light, .dark] {
            let detail = NSHostingView(rootView: PortmanPanelView(initialPortID: observed.id)
                .environment(\.colorScheme, scheme))
            detail.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            detail.frame = NSRect(x: 0, y: 0, width: 400, height: 620)
            detail.layoutSubtreeIfNeeded()
            detail.frame.size = detail.fittingSize
            detail.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(detail.bitmapImageRepForCachingDisplay(in: detail.bounds))
            detail.cacheDisplay(in: detail.bounds, to: representation)
            let image = NSImage(size: detail.bounds.size)
            image.addRepresentation(representation)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Portman — Server Detail — \(scheme == .dark ? "Dark" : "Light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

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
