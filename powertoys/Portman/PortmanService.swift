import Darwin
import Foundation
import Observation
import UserNotifications

extension Notification.Name {
    static let portmanSnapshotChanged = Notification.Name("portmanSnapshotChanged")
}

nonisolated struct PortmanLocalPort: Identifiable, Sendable {
    let pid: Int32
    let port: UInt16
    let address: String
    let command: String
    let launchCommand: String
    var memoryBytes: Int64
    var cpuPercent: Double
    let uptime: String
    let started: UInt64
    let userID: UInt32
    var processes: [PortmanProcess] = []
    var hasConnections = false

    var processID: String { "\(pid):\(started)" }
    var id: String { "\(processID):\(port)" }
    var canStop: Bool {
        started > 0 && PortmanScanner.isDevelopmentListener(self)
            && pid > 1 && pid != getpid()
            && !PortmanPreferences.protectedCommands.contains(command.lowercased())
    }

    func isLongRunning(at now: Date, days: Double) -> Bool {
        started > 0 && now.timeIntervalSince1970 - Double(started) / 1_000_000 >= days * 86_400
    }
}

nonisolated enum PortmanCleanupMode: String, CaseIterable, Sendable {
    case off, ask, automatic
}

nonisolated enum PortmanPreferences {
    static var scanRange: ClosedRange<UInt16> {
        let defaults = UserDefaults.standard
        let lower = UInt16(clamping: defaults.integer(forKey: "portman.scanLowerPort"))
        let upper = UInt16(clamping: defaults.integer(forKey: "portman.scanUpperPort"))
        return lower > 0 && upper >= lower ? lower...upper : 3000...9999
    }

    static var scanInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "portman.scanInterval")
        return value >= 2 && value <= 60 ? value : 2
    }

    static var memoryAlertBytes: Int64 {
        let value = UserDefaults.standard.integer(forKey: "portman.memoryAlertMB")
        return Int64(value > 0 ? min(value, 1_000_000) : 2_048) * 1_024 * 1_024
    }

    static var growthAlertBytes: Int64 {
        let value = UserDefaults.standard.integer(forKey: "portman.growthAlertMB")
        return Int64(value > 0 ? min(value, 1_000_000) : 500) * 1_024 * 1_024
    }

    static var idleSuggestionHours: Double {
        let value = UserDefaults.standard.double(forKey: "portman.idleHours")
        return value >= 1 && value <= 72 ? value : 4
    }

    static var runningSuggestionDays: Double {
        let value = UserDefaults.standard.double(forKey: "portman.runningDays")
        return value >= 1 && value <= 30 ? value : 3
    }

    static var cleanupMode: PortmanCleanupMode {
        PortmanCleanupMode(rawValue: UserDefaults.standard.string(forKey: "portman.cleanupMode") ?? "") ?? .ask
    }

    static var includeDeletedFolders: Bool {
        let key = "portman.includeDeletedFolders"
        return UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }

    static var cleanupNotifications: Bool {
        let key = "portman.cleanupNotifications"
        return UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }

    static var showAllListeners: Bool {
        UserDefaults.standard.bool(forKey: "portman.showAllListeners")
    }

    static var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "portman.notificationsEnabled")
    }

    static var protectedCommands: Set<String> {
        let builtIn: Set<String> = ["postgres", "mysqld", "mariadbd", "mongod", "redis-server", "docker", "ssh"]
        let custom = UserDefaults.standard.string(forKey: "portman.protectedCommands") ?? ""
        return builtIn.union(custom.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }
}

nonisolated enum PortmanCleanupPolicy {
    static func suggested(
        port: PortmanLocalPort, hasWarning: Bool, folder: String?, lastConnectionAt: Date?,
        now: Date, idleHours: Double, runningDays: Double,
        mode: PortmanCleanupMode, includeDeletedFolders: Bool
    ) -> Bool {
        guard mode != .off, port.canStop, !hasWarning else { return false }
        if includeDeletedFolders, let folder, deleted(folder) { return true }
        if port.isLongRunning(at: now, days: runningDays) { return true }
        guard !port.hasConnections, let lastConnectionAt else { return false }
        return now.timeIntervalSince(lastConnectionAt) >= idleHours * 3_600
    }

    private static func deleted(_ folder: String) -> Bool {
        if folder.hasSuffix(" (deleted)") { return true }
        var info = stat()
        return Darwin.lstat(folder, &info) != 0 && (errno == ENOENT || errno == ENOTDIR)
    }
}

nonisolated struct PortmanProcess: Identifiable, Sendable {
    let pid: Int32
    let parentPID: Int32
    let command: String
    let memoryBytes: Int64
    let cpuPercent: Double
    let started: UInt64
    let userID: UInt32
    var id: Int32 { pid }
}

nonisolated struct PortmanMetadata: Sendable {
    let folder: String
    let project: String
    let branch: String?
    let root: String?
}

nonisolated struct PortmanSample: Identifiable, Sendable {
    let date: Date
    let memoryBytes: Int64
    let cpuPercent: Double
    var id: Date { date }
}

nonisolated struct PortmanTunnel: Identifiable, Sendable {
    enum State: Sendable { case connecting, running, failed(String) }
    let id: UUID
    let host: String
    let remotePort: UInt16
    let localPort: UInt16
    var state: State
}

nonisolated enum PortmanScanner {
    enum StopError: LocalizedError {
        case protected
        case changed
        case system(Int32)

        var errorDescription: String? {
            switch self {
            case .protected: "This process is protected or belongs to another user."
            case .changed: "The server process changed. Refresh before stopping it."
            case .system(let code): String(cString: strerror(code))
            }
        }
    }

    static func run(_ executable: String, _ arguments: [String], emptyExitIsSuccess: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if emptyExitIsSuccess && process.terminationStatus == 1 && data.isEmpty { return "" }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: data.prefix(512), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "Portman", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "The port scan failed." : message])
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func parseLocal(
        _ lsof: String, _ ps: String,
        identities: [Int32: (UInt64, UInt32)] = [:],
        range: ClosedRange<UInt16> = 3000...9999
    ) -> [PortmanLocalPort] {
        var details: [Int32: (Int64, Double, String, String)] = [:]
        for line in ps.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard fields.count == 5, let pid = Int32(fields[0]),
                  let rss = Int64(fields[1]), let cpu = Double(fields[2]) else { continue }
            details[pid] = (rss * 1024, cpu, String(fields[3]), String(fields[4]))
        }
        var pid: Int32?
        var command = ""
        var result: [PortmanLocalPort] = []
        var seen = Set<String>()
        for line in lsof.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())
            switch prefix {
            case "p": pid = Int32(value); command = ""
            case "c": command = value
            case "n":
                guard let pid, let port = UInt16(value.split(separator: ":").last ?? ""),
                      port > 0, range.contains(port) else { continue }
                let id = "\(pid):\(port)"
                guard seen.insert(id).inserted else { continue }
                let detail = details[pid]
                result.append(PortmanLocalPort(
                    pid: pid, port: port, address: value, command: command,
                    launchCommand: detail?.3 ?? command,
                    memoryBytes: detail?.0 ?? 0, cpuPercent: detail?.1 ?? 0,
                    uptime: detail?.2 ?? "", started: identities[pid]?.0 ?? 0,
                    userID: identities[pid]?.1 ?? UInt32.max
                ))
            default: break
            }
        }
        return result.sorted { $0.port < $1.port }
    }

    static func localPorts(range: ClosedRange<UInt16> = 3000...9999) throws -> [PortmanLocalPort] {
        let lsof = try run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"],
                           emptyExitIsSuccess: true)
        let pids = Set(lsof.split(whereSeparator: \.isNewline)
            .filter { $0.first == "p" }.compactMap { Int32($0.dropFirst()) })
        guard !pids.isEmpty else { return [] }
        let ps = (try? run("/bin/ps", ["-p", pids.sorted().map(String.init).joined(separator: ","),
                                        "-o", "pid=,rss=,%cpu=,etime=,command="])) ?? ""
        var identities: [Int32: (UInt64, UInt32)] = [:]
        for pid in pids {
            var info = proc_bsdinfo()
            let bytes = withUnsafeMutablePointer(to: &info) {
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
            }
            if bytes == MemoryLayout<proc_bsdinfo>.size {
                identities[pid] = (info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
                                   info.pbi_uid)
            }
        }
        var ports = parseLocal(lsof, ps, identities: identities, range: range)
        let established = (try? run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-Fp"],
                                    emptyExitIsSuccess: true)) ?? ""
        let connectedPIDs = Set(established.split(whereSeparator: \.isNewline)
            .filter { $0.first == "p" }.compactMap { Int32($0.dropFirst()) })
        let table = (try? run("/bin/ps", ["-A", "-o", "pid=,ppid=,rss=,%cpu=,comm="])) ?? ""
        let processes = parseProcessTable(table)
        let children = Dictionary(grouping: processes, by: \.parentPID)
        for index in ports.indices {
            var tree = [PortmanProcess]()
            var visited: Set<Int32> = [ports[index].pid]
            var pending = [ports[index].pid]
            while let parent = pending.popLast() {
                for child in children[parent] ?? [] where visited.insert(child.pid).inserted {
                    var info = proc_bsdinfo()
                    let size = withUnsafeMutablePointer(to: &info) {
                        proc_pidinfo(child.pid, PROC_PIDTBSDINFO, 0, $0,
                                     Int32(MemoryLayout<proc_bsdinfo>.size))
                    }
                    guard size == MemoryLayout<proc_bsdinfo>.size,
                          info.pbi_uid == ports[index].userID else { continue }
                    tree.append(PortmanProcess(
                        pid: child.pid, parentPID: child.parentPID, command: child.command,
                        memoryBytes: child.memoryBytes, cpuPercent: child.cpuPercent,
                        started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
                        userID: info.pbi_uid
                    ))
                    pending.append(child.pid)
                }
            }
            ports[index].processes = tree
            ports[index].hasConnections = connectedPIDs.contains(ports[index].pid)
                || tree.contains { connectedPIDs.contains($0.pid) }
            ports[index].memoryBytes += tree.reduce(0) { $0 + $1.memoryBytes }
            ports[index].cpuPercent += tree.reduce(0) { $0 + $1.cpuPercent }
        }
        return PortmanPreferences.showAllListeners ? ports : ports.filter(isDevelopmentListener)
    }

    static func isDevelopmentListener(_ port: PortmanLocalPort) -> Bool {
        guard port.userID == geteuid() else { return false }
        let command = port.command.lowercased()
        let launch = port.launchCommand.lowercased()
        if ["adb", "ardagent", "controlcenter", "ssh", "megasyn", "megasync"]
            .contains(command) { return false }
        guard !launch.hasPrefix("/system/"), !launch.hasPrefix("/usr/libexec/") else { return false }
        if launch.contains(".app/contents/macos/") {
            return ["node", "python", "python3", "ruby", "php", "java", "deno", "bun"]
                .contains(command)
        }
        return true
    }

    static func parseProcessTable(_ output: String) -> [PortmanProcess] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard fields.count == 5, let pid = Int32(fields[0]),
                  let parent = Int32(fields[1]), let rss = Int64(fields[2]),
                  let cpu = Double(fields[3]) else { return nil }
            return PortmanProcess(pid: pid, parentPID: parent, command: String(fields[4]),
                                  memoryBytes: rss * 1024, cpuPercent: cpu,
                                  started: 0, userID: UInt32.max)
        }
    }

    static func systemMemoryUsed() -> Int64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = Int64(vm_kernel_page_size)
        return Int64(stats.active_count + stats.inactive_count + stats.wire_count
                     + stats.compressor_page_count) * pageSize
    }

    static func stop(_ port: PortmanLocalPort) throws {
        guard port.canStop else { throw StopError.protected }
        var info = proc_bsdinfo()
        let bytes = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(port.pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        let started = info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        guard bytes == MemoryLayout<proc_bsdinfo>.size,
              started == port.started, info.pbi_uid == port.userID else { throw StopError.changed }
        for child in port.processes.reversed()
            where child.userID == port.userID && child.started > 0
                && !PortmanPreferences.protectedCommands.contains(
                    URL(fileURLWithPath: child.command).lastPathComponent.lowercased()) {
            var current = proc_bsdinfo()
            let size = withUnsafeMutablePointer(to: &current) {
                proc_pidinfo(child.pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
            }
            let identity = current.pbi_start_tvsec * 1_000_000 + current.pbi_start_tvusec
            if size == MemoryLayout<proc_bsdinfo>.size && identity == child.started
                && current.pbi_uid == port.userID && current.pbi_ppid == child.parentPID {
                _ = kill(child.pid, SIGTERM)
            }
        }
        guard kill(port.pid, SIGTERM) == 0 else { throw StopError.system(errno) }
    }

    static func parseRemote(_ output: String) -> [UInt16] {
        var ports = Set<UInt16>()
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            let endpoint: Substring?
            if line.first == "n" { endpoint = line.dropFirst() }
            else if fields.count >= 4, fields[0] == "LISTEN" { endpoint = fields[3] }
            else { endpoint = nil }
            if let endpoint, let port = UInt16(endpoint.split(separator: ":").last ?? ""), port > 0 {
                ports.insert(port)
            }
        }
        return ports.sorted()
    }

    static func remotePorts(host: String) async throws -> [UInt16] {
        guard SystemMonitorRemoteProtocol.validHost(host) else {
            throw NSError(domain: "Portman", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Enter a valid SSH host or alias."])
        }
        let command = "LC_ALL=C ss -ltnH 2>/dev/null || LC_ALL=C lsof -nP -iTCP -sTCP:LISTEN -Fn"
        let result = try await SSHProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                        "-o", "StrictHostKeyChecking=yes", "-T", "--", host, command],
            environment: ProcessInfo.processInfo.environment,
            standardInput: Data(),
            maximumOutputBytes: 1_048_576,
            timeout: 10
        )
        guard result.status == 0 || result.status == 1 && result.standardOutput.isEmpty
                && result.standardError.isEmpty else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "Portman", code: Int(result.status),
                          userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "The SSH scan failed." : message])
        }
        return parseRemote(result.standardOutput)
    }

    static func tunnelIsListening(pid: Int32, localPort: UInt16) -> Bool {
        guard let output = try? run("/usr/sbin/lsof", ["-nP", "-a", "-p", String(pid),
                                                     "-iTCP:\(localPort)", "-sTCP:LISTEN", "-Fn"],
                                    emptyExitIsSuccess: true) else { return false }
        return output.split(whereSeparator: \.isNewline)
            .contains { $0.first == "n" && $0.hasSuffix(":\(localPort)") }
    }

    static func metadata(pid: Int32) -> PortmanMetadata? {
        guard let output = try? run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]),
              let folder = output.split(whereSeparator: \.isNewline)
                .first(where: { $0.first == "n" }).map({ String($0.dropFirst()) }),
              !folder.isEmpty else { return nil }
        let project = (try? run("/usr/bin/git", ["-C", folder, "rev-parse", "--show-toplevel"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = (try? run("/usr/bin/git", ["-C", folder, "branch", "--show-current"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let projectFolder = project.flatMap { $0.isEmpty ? nil : $0 } ?? folder
        return PortmanMetadata(
            folder: folder,
            project: URL(fileURLWithPath: projectFolder).lastPathComponent,
            branch: branch?.isEmpty == false ? branch : nil,
            root: project?.isEmpty == false ? project : nil
        )
    }

    static func tunnelArguments(host: String, remotePort: UInt16, localPort: UInt16) throws -> [String] {
        guard SystemMonitorRemoteProtocol.validHost(host), remotePort > 0, localPort > 0 else {
            throw NSError(domain: "Portman", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Choose a valid SSH host and ports."])
        }
        return ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "StrictHostKeyChecking=yes", "-o", "ServerAliveInterval=15",
                "-o", "ServerAliveCountMax=2", "-N", "-L",
                "127.0.0.1:\(localPort):localhost:\(remotePort)", "--", host]
    }
}

@Observable
@MainActor
final class PortmanService {
    static let shared = PortmanService()

    private(set) var localPorts: [PortmanLocalPort] = []
    private(set) var remotePorts: [UInt16] = []
    private(set) var tunnels: [PortmanTunnel] = []
    private(set) var history: [String: [PortmanSample]] = [:]
    private(set) var metadata: [String: PortmanMetadata] = [:]
    private(set) var sessions: [String: PortmanSession] = [:]
    private(set) var githubLinks: [String: PortmanGitHubLinks] = [:]
    private(set) var restartableIDs = Set<String>()
    private(set) var restartingIDs = Set<String>()
    private(set) var systemMemoryUsedBytes: Int64 = 0
    private(set) var lastConnectionAt: [String: Date] = [:]
    private(set) var snoozedUntil: [String: Date] = [:]
    private(set) var notificationStatus = "Not requested"
    var notificationError: String?
    var localError: String?
    var controlError: String?
    var forwardingError: String?
    var isLoadingRemote = false

    private var monitoringCount = 0
    private var monitoringTask: Task<Void, Never>?
    private var lastScanAt = Date.distantPast
    private var processes: [UUID: Process] = [:]
    private var remoteRequestID = UUID()
    private var notifiedProcessIDs = Set<String>()
    private var handledCleanupProcessIDs = Set<String>()
    private var lastCleanupMode: PortmanCleanupMode?
    private var metadataCheckedIDs = Set<String>()

    var suggestedCleanupIDs: Set<String> {
        let now = Date()
        return Set(localPorts.filter { port in
            PortmanCleanupPolicy.suggested(
                port: port, hasWarning: warning(for: port) != nil,
                folder: metadata[port.id]?.folder,
                lastConnectionAt: lastConnectionAt[port.processID], now: now,
                idleHours: PortmanPreferences.idleSuggestionHours,
                runningDays: PortmanPreferences.runningSuggestionDays,
                mode: PortmanPreferences.cleanupMode,
                includeDeletedFolders: PortmanPreferences.includeDeletedFolders
            )
        }.map(\.processID))
    }

    func beginMonitoring() {
        monitoringCount += 1
        if monitoringCount == 2 {
            monitoringTask?.cancel()
            monitoringTask = nil
        }
        guard monitoringTask == nil else { return }
        monitoringTask = Task {
            while !Task.isCancelled {
                if Self.shouldRunScan(ownerCount: monitoringCount, lastScanAt: lastScanAt,
                                      now: Date(), interval: PortmanPreferences.scanInterval) {
                    await refreshLocal()
                }
                let interval = PortmanPreferences.scanInterval
                try? await Task.sleep(for: .seconds(monitoringCount > 1 ? interval : max(interval, 30)))
            }
        }
    }

    nonisolated static func shouldRunScan(
        ownerCount: Int, lastScanAt: Date, now: Date, interval: TimeInterval
    ) -> Bool {
        ownerCount > 0 && (ownerCount > 1 || now.timeIntervalSince(lastScanAt) >= max(interval, 30))
    }

    func endMonitoring() {
        monitoringCount = max(0, monitoringCount - 1)
        guard monitoringCount == 0 else { return }
        monitoringTask?.cancel()
        monitoringTask = nil
        lastScanAt = .distantPast
        localPorts = []
        history = [:]
        metadata = [:]
        metadataCheckedIDs = []
        sessions = [:]
        githubLinks = [:]
        restartableIDs = []
        restartingIDs = []
        lastConnectionAt = [:]
        notifiedProcessIDs = []
        handledCleanupProcessIDs = []
        lastCleanupMode = nil
    }

    func refreshLocal() async {
        lastScanAt = Date()
        do {
            let range = PortmanPreferences.scanRange
            let snapshot = try await Task.detached(priority: .utility) {
                (try PortmanScanner.localPorts(range: range), PortmanScanner.systemMemoryUsed())
            }.value
            guard !Task.isCancelled, monitoringCount > 0 else { return }
            let ports = snapshot.0
            localPorts = ports
            systemMemoryUsedBytes = snapshot.1
            localError = nil
            let now = Date()
            for port in ports {
                if port.hasConnections || lastConnectionAt[port.processID] == nil {
                    lastConnectionAt[port.processID] = now
                }
                history[port.id, default: []].append(PortmanSample(
                    date: now, memoryBytes: port.memoryBytes, cpuPercent: port.cpuPercent
                ))
                if history[port.id, default: []].count > 300 { history[port.id]?.removeFirst() }
            }
            history = history.filter { key, _ in ports.contains { $0.id == key } }
            metadata = metadata.filter { key, _ in ports.contains { $0.id == key } }
            metadataCheckedIDs.formIntersection(Set(ports.map(\.id)))
            if PortmanPreferences.cleanupMode != .off {
                let pending = ports.filter {
                    $0.canStop && metadata[$0.id] == nil && metadataCheckedIDs.insert($0.id).inserted
                }
                if !pending.isEmpty {
                    let found = await Task.detached(priority: .utility) {
                        pending.compactMap { port in
                            PortmanScanner.metadata(pid: port.pid).map { (port.id, $0) }
                        }
                    }.value
                    guard !Task.isCancelled, monitoringCount > 0 else { return }
                    for (id, details) in found where localPorts.contains(where: { $0.id == id }) {
                        metadata[id] = details
                    }
                }
            }
            sessions = sessions.filter { key, _ in ports.contains { $0.id == key } }
            githubLinks = githubLinks.filter { key, _ in ports.contains { $0.id == key } }
            restartableIDs.formIntersection(Set(ports.map(\.id)))
            lastConnectionAt = lastConnectionAt.filter { key, _ in ports.contains { $0.processID == key } }
            snoozedUntil = snoozedUntil.filter { key, until in
                until > now && ports.contains { $0.processID == key }
            }
            notifiedProcessIDs = notifiedProcessIDs.filter { processID in
                guard let port = ports.first(where: { $0.processID == processID }) else { return false }
                let growth = history[port.id].flatMap { samples in
                    samples.last.flatMap { last in
                        samples.first(where: { $0.date >= last.date.addingTimeInterval(-600) })
                            .map { last.memoryBytes - $0.memoryBytes }
                    }
                } ?? 0
                return !Self.canRearmNotification(
                    memoryBytes: port.memoryBytes, growthBytes: growth,
                    memoryLimit: PortmanPreferences.memoryAlertBytes,
                    growthLimit: PortmanPreferences.growthAlertBytes
                )
            }
            if PortmanPreferences.notificationsEnabled && notificationStatus == "Allowed" {
                for port in ports where (snoozedUntil[port.processID] ?? .distantPast) <= now {
                    guard let warning = warning(for: port),
                          notifiedProcessIDs.insert(port.processID).inserted else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "Port :\(port.port) needs attention"
                    content.body = warning
                    content.categoryIdentifier = "PORTMAN_ALERT"
                    content.userInfo = ["processID": port.processID]
                    do {
                        try await UNUserNotificationCenter.current().add(UNNotificationRequest(
                            identifier: "portman.\(port.processID)", content: content, trigger: nil
                        ))
                    } catch { notificationError = error.localizedDescription }
                }
            }
            await handleCleanupSuggestions()
            NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
        } catch {
            guard !Task.isCancelled, monitoringCount > 0 else { return }
            localError = error.localizedDescription
        }
    }

    func loadMetadata(for port: PortmanLocalPort) async {
        guard metadata[port.id] == nil else { return }
        let details = await Task.detached(priority: .utility) {
            PortmanScanner.metadata(pid: port.pid)
        }.value
        if let details, localPorts.contains(where: { $0.id == port.id }) {
            metadata[port.id] = details
        }
    }

    func loadSession(for port: PortmanLocalPort) async {
        guard UserDefaults.standard.bool(forKey: "portman.sessionLinksEnabled") else {
            sessions.removeValue(forKey: port.id)
            return
        }
        guard let folder = metadata[port.id]?.folder else { return }
        let session = await PortmanSessionResolver.shared.resolve(
            pid: port.pid, started: port.started, userID: port.userID, folder: folder
        )
        guard !Task.isCancelled,
              UserDefaults.standard.bool(forKey: "portman.sessionLinksEnabled"),
              localPorts.contains(where: { $0.id == port.id }) else { return }
        sessions[port.id] = session
    }

    func loadGitHubLinks(for port: PortmanLocalPort) async {
        guard UserDefaults.standard.bool(forKey: "portman.publicGitHubLinksEnabled") else {
            githubLinks.removeValue(forKey: port.id)
            return
        }
        guard let details = metadata[port.id],
              let root = details.root, let branch = details.branch else { return }
        let links = await PortmanGitHubLookup.shared.lookup(root: root, branch: branch)
        guard !Task.isCancelled,
              UserDefaults.standard.bool(forKey: "portman.publicGitHubLinksEnabled"),
              localPorts.contains(where: { $0.id == port.id }) else { return }
        githubLinks[port.id] = links
    }

    func loadRestartAvailability(for port: PortmanLocalPort) async {
        guard let folder = metadata[port.id]?.folder else { return }
        let available = await Task.detached(priority: .utility) {
            PortmanLaunch.capture(port, folder: folder) != nil
        }.value
        guard !Task.isCancelled, localPorts.contains(where: { $0.id == port.id }) else { return }
        if available { restartableIDs.insert(port.id) }
        else { restartableIDs.remove(port.id) }
    }

    func restartLocal(_ port: PortmanLocalPort) {
        guard let folder = metadata[port.id]?.folder,
              restartableIDs.contains(port.id),
              restartingIDs.insert(port.id).inserted else { return }
        controlError = nil
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try await PortmanRestart.run(port, folder: folder)
                }.value
                try? await Task.sleep(for: .seconds(1))
                await refreshLocal()
            } catch { controlError = "Restart failed: \(error.localizedDescription)" }
            restartingIDs.remove(port.id)
        }
    }

    func refreshRemote(host: String) async {
        let requestID = UUID()
        remoteRequestID = requestID
        isLoadingRemote = true
        do {
            let ports = try await PortmanScanner.remotePorts(host: host)
            guard remoteRequestID == requestID else { return }
            remotePorts = ports
            forwardingError = nil
        } catch {
            guard remoteRequestID == requestID else { return }
            remotePorts = []
            forwardingError = "Could not inspect \(host): \(error.localizedDescription)"
        }
        isLoadingRemote = false
    }

    @discardableResult
    func forward(host: String, remotePort: UInt16, localPort: UInt16) -> Bool {
        let arguments: [String]
        do { arguments = try PortmanScanner.tunnelArguments(host: host, remotePort: remotePort, localPort: localPort) }
        catch { forwardingError = error.localizedDescription; return false }
        guard !tunnels.contains(where: { $0.localPort == localPort && !$0.isFailed }) else {
            forwardingError = "Local port \(localPort) already has a Portman tunnel."
            return false
        }
        let id = UUID()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { [weak self] terminated in
            let status = terminated.terminationStatus
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data.prefix(2048), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor [weak self] in self?.tunnelEnded(id: id, status: status, message: message) }
        }
        do {
            try process.run()
            processes[id] = process
            tunnels.append(PortmanTunnel(id: id, host: host, remotePort: remotePort,
                                         localPort: localPort, state: .connecting))
            NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
            Task { [weak self] in
                for _ in 0..<25 {
                    guard let self, let index = tunnels.firstIndex(where: { $0.id == id }),
                          case .connecting = tunnels[index].state, process.isRunning else { return }
                    let pid = process.processIdentifier
                    let ready = await Task.detached(priority: .utility) {
                        PortmanScanner.tunnelIsListening(pid: pid, localPort: localPort)
                    }.value
                    guard let current = tunnels.firstIndex(where: { $0.id == id }),
                          case .connecting = tunnels[current].state, process.isRunning else { return }
                    if ready {
                        tunnels[current].state = .running
                        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                }
                guard let self, let index = tunnels.firstIndex(where: { $0.id == id }),
                      case .connecting = tunnels[index].state else { return }
                tunnels[index].state = .failed("SSH did not open local port \(localPort).")
                NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
                if process.isRunning { process.terminate() }
            }
            forwardingError = nil
            return true
        } catch {
            forwardingError = "Could not start forwarding: \(error.localizedDescription)"
            return false
        }
    }

    func stopTunnel(_ id: UUID) {
        if let process = processes[id], process.isRunning { process.terminate() }
        processes.removeValue(forKey: id)
        tunnels.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
    }

    func stopLocal(_ port: PortmanLocalPort) {
        do {
            try PortmanScanner.stop(port)
            controlError = nil
            Task { await refreshLocal() }
        } catch { controlError = error.localizedDescription }
    }

    func warning(for port: PortmanLocalPort) -> String? {
        let sustainedSamples = Array(history[port.id]?.suffix(3) ?? [])
        if sustainedSamples.count == 3
            && sustainedSamples.allSatisfy({ $0.memoryBytes >= PortmanPreferences.memoryAlertBytes }) {
            let limit = ByteCountFormatter.string(fromByteCount: PortmanPreferences.memoryAlertBytes,
                                                  countStyle: .memory)
            return "Memory above \(limit)"
        }
        guard let samples = history[port.id], let last = samples.last,
              let first = samples.first(where: { $0.date >= last.date.addingTimeInterval(-600) }),
              last.memoryBytes - first.memoryBytes >= PortmanPreferences.growthAlertBytes else {
            return nil
        }
        let minutes = max(1, Int(last.date.timeIntervalSince(first.date) / 60))
        let growth = (last.memoryBytes - first.memoryBytes) / (1_024 * 1_024)
        return "+\(growth) MB in \(minutes)m"
    }

    func snooze(_ port: PortmanLocalPort) {
        snooze(processID: port.processID)
    }

    func snooze(processID: String) {
        snoozedUntil[processID] = Date().addingTimeInterval(3_600)
        notifiedProcessIDs.remove(processID)
        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
    }

    func rearm(_ port: PortmanLocalPort) {
        snoozedUntil.removeValue(forKey: port.processID)
        notifiedProcessIDs.remove(port.processID)
        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
    }

    func resetNotificationDelivery() {
        notifiedProcessIDs = []
    }

    nonisolated static func canRearmNotification(
        memoryBytes: Int64, growthBytes: Int64, memoryLimit: Int64, growthLimit: Int64
    ) -> Bool {
        memoryBytes < memoryLimit * 85 / 100 && growthBytes < growthLimit * 60 / 100
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = switch settings.authorizationStatus {
        case .notDetermined: "Not requested"
        case .denied: "Denied in System Settings"
        case .authorized, .provisional, .ephemeral:
            settings.notificationCenterSetting == .disabled ? "Disabled in System Settings" : "Allowed"
        @unknown default: "Unavailable"
        }
    }

    func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            UserDefaults.standard.set(allowed, forKey: "portman.notificationsEnabled")
            notificationError = nil
        } catch {
            UserDefaults.standard.set(false, forKey: "portman.notificationsEnabled")
            notificationError = error.localizedDescription
        }
        await refreshNotificationStatus()
    }

    var activeAlerts: [PortmanLocalPort] {
        localPorts.filter { warning(for: $0) != nil && (snoozedUntil[$0.processID] ?? .distantPast) <= Date() }
    }

    private func handleCleanupSuggestions() async {
        let mode = PortmanPreferences.cleanupMode
        if mode != lastCleanupMode {
            handledCleanupProcessIDs = []
            lastCleanupMode = mode
        }
        let ids = suggestedCleanupIDs
        handledCleanupProcessIDs.formIntersection(ids)
        guard mode != .off else { return }
        var seen = Set<String>()
        let fresh = localPorts.filter {
            ids.contains($0.processID) && seen.insert($0.processID).inserted
                && !handledCleanupProcessIDs.contains($0.processID)
        }
        guard !fresh.isEmpty else { return }
        handledCleanupProcessIDs.formUnion(fresh.map(\.processID))
        if mode == .automatic { stopLocalProcesses(fresh) }
        guard PortmanPreferences.cleanupNotifications,
              PortmanPreferences.notificationsEnabled, notificationStatus == "Allowed" else { return }
        let content = UNMutableNotificationContent()
        content.title = mode == .automatic
            ? "Portman sent stop requests for \(fresh.count) servers"
            : "Portman found \(fresh.count) cleanup suggestions"
        content.body = "Open Portman to review the servers."
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "portman.cleanup.\(UUID().uuidString)", content: content, trigger: nil
            ))
        } catch { notificationError = error.localizedDescription }
    }

    func stopLocalProcesses(_ ports: [PortmanLocalPort]) {
        var stopped = Set<Int32>()
        var failures: [String] = []
        for port in ports where stopped.insert(port.pid).inserted {
            do { try PortmanScanner.stop(port) }
            catch { failures.append("PID \(port.pid): \(error.localizedDescription)") }
        }
        controlError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        Task { await refreshLocal() }
    }

    func stopAll() {
        for process in processes.values where process.isRunning { process.terminate() }
        processes.removeAll()
        tunnels.removeAll()
        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
    }

    private func tunnelEnded(id: UUID, status: Int32, message: String) {
        processes.removeValue(forKey: id)
        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }
        if case .failed = tunnels[index].state { return }
        tunnels[index].state = .failed(message.isEmpty ? "SSH exited with status \(status)." : message)
        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
    }
}

private extension PortmanTunnel {
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
