import Darwin
import Foundation
import Observation

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

nonisolated enum PortmanServerSort: String, CaseIterable, Sendable {
    case port, memory, name, cpu

    var label: String { rawValue.capitalized }

    func sorted(_ ports: [PortmanLocalPort]) -> [PortmanLocalPort] {
        ports.sorted { left, right in
            switch self {
            case .port:
                return left.port < right.port
            case .memory where left.memoryBytes != right.memoryBytes:
                return left.memoryBytes > right.memoryBytes
            case .name:
                let order = left.command.localizedStandardCompare(right.command)
                if order != .orderedSame { return order == .orderedAscending }
            case .cpu where left.cpuPercent != right.cpuPercent:
                return left.cpuPercent > right.cpuPercent
            default:
                break
            }
            return left.port < right.port
        }
    }
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

    static var idleSuggestionHours: Double {
        let value = UserDefaults.standard.double(forKey: "portman.idleHours")
        return value >= 1 && value <= 72 ? value : 4
    }

    static var runningSuggestionDays: Double {
        let value = UserDefaults.standard.double(forKey: "portman.runningDays")
        return value >= 1 && value <= 30 ? value : 3
    }

    static var forceQuitSeconds: Double {
        let value = UserDefaults.standard.double(forKey: "portman.forceQuitSeconds")
        return value >= 1 && value <= 30 ? value : 3
    }

    static var cleanupMode: PortmanCleanupMode {
        PortmanCleanupMode(rawValue: UserDefaults.standard.string(forKey: "portman.cleanupMode") ?? "") ?? .ask
    }

    static var includeDeletedFolders: Bool {
        let key = "portman.includeDeletedFolders"
        return UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }

    static var showAllListeners: Bool {
        UserDefaults.standard.bool(forKey: "portman.showAllListeners")
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
    private static let memoryLimitBytes: Int64 = 2_048 * 1_024 * 1_024
    private static let growthLimitBytes: Int64 = 500 * 1_024 * 1_024

    static func suggested(
        port: PortmanLocalPort, highUsage: Bool, folder: String?, lastConnectionAt: Date?,
        now: Date, idleHours: Double, runningDays: Double,
        mode: PortmanCleanupMode, includeDeletedFolders: Bool
    ) -> Bool {
        guard mode != .off, port.canStop, !highUsage else { return false }
        if includeDeletedFolders, let folder, deleted(folder) { return true }
        if port.isLongRunning(at: now, days: runningDays) { return true }
        guard !port.hasConnections, let lastConnectionAt else { return false }
        return now.timeIntervalSince(lastConnectionAt) >= idleHours * 3_600
    }

    static func highUsage(in samples: [PortmanSample]) -> Bool {
        let recent = samples.suffix(3)
        if recent.count == 3 && recent.allSatisfy({ $0.memoryBytes >= memoryLimitBytes }) {
            return true
        }
        guard let last = samples.last,
              let first = samples.first(where: { $0.date >= last.date.addingTimeInterval(-600) }) else {
            return false
        }
        return last.memoryBytes - first.memoryBytes >= growthLimitBytes
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

nonisolated struct PortmanRemotePort: Sendable {
    let port: UInt16
    var processName: String?
    var pid: Int32?
    var command: String? = nil
    var container: String? = nil

    var displayName: String {
        if let container { return "Docker: \(container)" }
        if let processName, let command,
           ["node", "bun", "deno", "python", "python3"].contains(processName.lowercased()),
           let script = command.split(whereSeparator: \.isWhitespace).first(where: { token in
               [".js", ".mjs", ".cjs", ".ts", ".py"].contains(where: { suffix in token.hasSuffix(suffix) })
           }) {
            return "\(processName): \(URL(fileURLWithPath: String(script)).lastPathComponent)"
        }
        return processName ?? "Unknown service"
    }
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

    static func stop(_ port: PortmanLocalPort) throws {
        guard port.canStop else { throw StopError.protected }
        guard matches(pid: port.pid, started: port.started, userID: port.userID) else {
            throw StopError.changed
        }
        for child in port.processes.reversed()
            where child.userID == port.userID && child.started > 0
                && !PortmanPreferences.protectedCommands.contains(
                    URL(fileURLWithPath: child.command).lastPathComponent.lowercased()) {
            if matches(pid: child.pid, started: child.started, userID: port.userID,
                       parentPID: child.parentPID) {
                _ = kill(child.pid, SIGTERM)
            }
        }
        guard kill(port.pid, SIGTERM) == 0 else { throw StopError.system(errno) }
    }

    static func forceStopIfUnchanged(_ port: PortmanLocalPort) {
        guard port.canStop else { return }
        for child in port.processes.reversed()
            where child.userID == port.userID && child.started > 0
                && !PortmanPreferences.protectedCommands.contains(
                    URL(fileURLWithPath: child.command).lastPathComponent.lowercased()) {
            if matches(pid: child.pid, started: child.started, userID: port.userID) {
                _ = kill(child.pid, SIGKILL)
            }
        }
        if matches(pid: port.pid, started: port.started, userID: port.userID) {
            _ = kill(port.pid, SIGKILL)
        }
    }

    private static func matches(
        pid: Int32, started: UInt64, userID: UInt32, parentPID: Int32? = nil
    ) -> Bool {
        var info = proc_bsdinfo()
        let bytes = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        return bytes == MemoryLayout<proc_bsdinfo>.size
            && info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec == started
            && info.pbi_uid == userID
            && (parentPID.map { info.pbi_ppid == $0 } ?? true)
    }

    static func parseRemote(_ output: String) -> [UInt16] {
        parseRemoteDetails(output).map(\.port)
    }

    static func parseRemoteDetails(_ output: String) -> [PortmanRemotePort] {
        var ports: [UInt16: PortmanRemotePort] = [:]
        var lsofPID: Int32?
        var lsofCommand: String?
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            let endpoint: Substring?
            var processName: String?
            var pid: Int32?
            if line.first == "p" { lsofPID = Int32(line.dropFirst()); continue }
            if line.first == "c" { lsofCommand = String(line.dropFirst()); continue }
            if line.first == "n" {
                endpoint = line.dropFirst()
                processName = lsofCommand
                pid = lsofPID
            } else if fields.count >= 4, fields[0] == "LISTEN" {
                endpoint = fields[3]
                if let nameStart = line.range(of: "users:((\"") {
                    let tail = line[nameStart.upperBound...]
                    processName = tail.split(separator: "\"", maxSplits: 1).first.map(String.init)
                    if let pidStart = tail.range(of: "pid=") {
                        pid = Int32(tail[pidStart.upperBound...].prefix(while: \.isNumber))
                    }
                }
            } else { continue }
            if let endpoint, let port = UInt16(endpoint.split(separator: ":").last ?? ""), port > 0 {
                let detail = PortmanRemotePort(port: port, processName: processName, pid: pid)
                if ports[port]?.processName == nil || detail.processName != nil { ports[port] = detail }
            }
        }
        return ports.values.sorted { $0.port < $1.port }
    }

    static func authenticationArguments(password: Bool) -> [String] {
        password
            ? ["-o", "BatchMode=no", "-o", "NumberOfPasswordPrompts=1",
               "-o", "PubkeyAuthentication=no",
               "-o", "PreferredAuthentications=password,keyboard-interactive"]
            : ["-o", "BatchMode=yes"]
    }

    static func passwordAvailable(in message: String) -> Bool {
        let output = message.lowercased()
        return output.contains("permission denied")
            && (output.contains("password") || output.contains("keyboard-interactive"))
    }

    static func remotePorts(host: String, password: String? = nil,
                            configurationFile: URL? = nil) async throws -> [PortmanRemotePort] {
        guard SystemMonitorRemoteProtocol.validHost(host) else {
            throw NSError(domain: "Portman", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Enter a valid SSH host or alias."])
        }
        let command = "LC_ALL=C ss -ltnpH 2>/dev/null || LC_ALL=C lsof -nP -iTCP -sTCP:LISTEN -Fpcn 2>/dev/null; "
            + "sudo -n ss -ltnpH 2>/dev/null || true; "
            + "printf '\\nMPT_DOCKER\\n'; "
            + "docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null "
            + "|| sudo -n docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null || true; "
            + "printf '\\nMPT_SYSTEMD\\n'; "
            + "LC_ALL=C systemctl list-sockets --all --no-legend --no-pager --plain 2>/dev/null || true"
        let configArguments = configurationFile.map { ["-F", $0.path] } ?? []
        let channel = try password.map { _ in try SSHAskpassChannel() }
        let delivery = channel.flatMap { channel in password.map { channel.startDelivery(password: $0) } }
        defer { delivery?.cancel(); channel?.cleanup() }
        let result = try await SSHProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: configArguments + authenticationArguments(password: password != nil)
                + ["-o", "ConnectTimeout=5",
                        "-o", "StrictHostKeyChecking=accept-new", "-T", "--", host, command],
            environment: channel?.environment ?? ProcessInfo.processInfo.environment,
            standardInput: Data(),
            maximumOutputBytes: 1_048_576,
            timeout: 10
        )
        guard result.status == 0 || result.status == 1 && result.standardOutput.isEmpty
                && result.standardError.isEmpty else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = passwordAvailable(in: message) ? "SSH password required."
                : (message.localizedCaseInsensitiveContains("Permission denied")
                   ? (password == nil ? "Permission denied. Check SSH key access."
                      : "Permission denied. This host did not accept password authentication.")
                   : (message.isEmpty ? "The SSH scan failed." : message))
            throw NSError(domain: "Portman", code: Int(result.status),
                          userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return parseRemoteDiscovery(result.standardOutput)
    }

    static func parseRemoteDiscovery(_ output: String) -> [PortmanRemotePort] {
        let dockerSplit = output.components(separatedBy: "\nMPT_DOCKER\n")
        var ports = parseRemoteDetails(dockerSplit[0])
        guard dockerSplit.count > 1 else { return ports }
        let systemdSplit = dockerSplit[1].components(separatedBy: "\nMPT_SYSTEMD\n")
        for line in systemdSplit[0].split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "|", maxSplits: 1)
            guard fields.count == 2 else { continue }
            let name = String(fields[0])
            for mapping in fields[1].split(separator: ",") {
                let sides = mapping.trimmingCharacters(in: .whitespaces).components(separatedBy: "->")
                guard sides.count == 2,
                      let port = UInt16(sides[0].split(separator: ":").last ?? ""),
                      let index = ports.firstIndex(where: { $0.port == port }) else { continue }
                ports[index].container = name
            }
        }
        if systemdSplit.count > 1 {
            for line in systemdSplit[1].split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 3,
                      let port = UInt16(fields[0].split(separator: ":").last ?? ""),
                      let index = ports.firstIndex(where: { $0.port == port }),
                      ports[index].processName == nil else { continue }
                let unit = fields.last ?? ""
                ports[index].processName = unit == "-" ? String(fields[1]) : String(unit)
            }
        }
        return ports
    }

    static func remoteProcessDetails(host: String, pid: Int32?, port: UInt16,
                                     password: String? = nil) async throws -> (command: String?, container: String?) {
        guard SystemMonitorRemoteProtocol.validHost(host) else { return (nil, nil) }
        let processCommand = pid.map { "LC_ALL=C ps -p \($0) -o args= 2>/dev/null" } ?? ":"
        let command = processCommand
            + "; printf '\\nMPT_CONTAINER\\n'; docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null || true"
        let channel = try password.map { _ in try SSHAskpassChannel() }
        let delivery = channel.flatMap { channel in password.map { channel.startDelivery(password: $0) } }
        defer { delivery?.cancel(); channel?.cleanup() }
        let result = try await SSHProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: authenticationArguments(password: password != nil)
                + ["-o", "ConnectTimeout=5",
                        "-o", "StrictHostKeyChecking=accept-new", "-T", "--", host,
                        command],
            environment: channel?.environment ?? ProcessInfo.processInfo.environment,
            standardInput: Data(), maximumOutputBytes: 16_384, timeout: 10
        )
        return parseRemoteProcessDetails(result.standardOutput, port: port)
    }

    static func parseRemoteProcessDetails(
        _ output: String, port: UInt16
    ) -> (command: String?, container: String?) {
        let parts = output.components(separatedBy: "\nMPT_CONTAINER\n")
        let process = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let container = parts.dropFirst().joined(separator: "\n")
            .split(whereSeparator: \.isNewline)
            .first { $0.contains(":\(port)->") }
            .flatMap { $0.split(separator: "|", maxSplits: 1).first }
            .map(String.init)
        return (process?.isEmpty == false ? process : nil, container)
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

    static func tunnelArguments(
        host: String, remotePort: UInt16, localPort: UInt16,
        password: Bool = false, configurationFile: URL? = nil
    ) throws -> [String] {
        guard SystemMonitorRemoteProtocol.validHost(host), remotePort > 0, localPort > 0 else {
            throw NSError(domain: "Portman", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Choose a valid SSH host and ports."])
        }
        return (configurationFile.map { ["-F", $0.path] } ?? [])
            + authenticationArguments(password: password)
            + ["-o", "ConnectTimeout=5",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "StrictHostKeyChecking=accept-new", "-o", "ServerAliveInterval=15",
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
    private(set) var remoteDetails: [UInt16: PortmanRemotePort] = [:]
    private(set) var tunnels: [PortmanTunnel] = []
    private(set) var history: [String: [PortmanSample]] = [:]
    private(set) var metadata: [String: PortmanMetadata] = [:]
    private(set) var sessions: [String: PortmanSession] = [:]
    private(set) var githubLinks: [String: PortmanGitHubLinks] = [:]
    private(set) var restartableIDs = Set<String>()
    private(set) var restartingIDs = Set<String>()
    private(set) var lastConnectionAt: [String: Date] = [:]
    var localError: String?
    var controlError: String?
    var forwardingError: String?
    var isLoadingRemote = false

    private var monitoringCount = 0
    private var monitoringTask: Task<Void, Never>?
    private var lastScanAt = Date.distantPast
    private var processes: [UUID: Process] = [:]
    private var authentication: [UUID: (SSHAskpassChannel, Task<Void, Never>)] = [:]
    private var remoteRequestID = UUID()
    private var handledCleanupProcessIDs = Set<String>()
    private var lastCleanupMode: PortmanCleanupMode?
    private var metadataCheckedIDs = Set<String>()

    var suggestedCleanupIDs: Set<String> {
        let now = Date()
        return Set(localPorts.filter { port in
            PortmanCleanupPolicy.suggested(
                port: port, highUsage: PortmanCleanupPolicy.highUsage(in: history[port.id] ?? []),
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
        handledCleanupProcessIDs = []
        lastCleanupMode = nil
    }

    func refreshLocal() async {
        lastScanAt = Date()
        do {
            let range = PortmanPreferences.scanRange
            let ports = try await Task.detached(priority: .utility) {
                try PortmanScanner.localPorts(range: range)
            }.value
            guard !Task.isCancelled, monitoringCount > 0 else { return }
            localPorts = ports
            localError = nil
            let now = Date()
            let historyCutoff = now.addingTimeInterval(-600)
            for port in ports {
                if port.hasConnections || lastConnectionAt[port.processID] == nil {
                    lastConnectionAt[port.processID] = now
                }
                history[port.id, default: []].append(PortmanSample(
                    date: now, memoryBytes: port.memoryBytes, cpuPercent: port.cpuPercent
                ))
                Self.pruneHistory(&history[port.id, default: []], before: historyCutoff)
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
            handleCleanupSuggestions()
            NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
        } catch {
            guard !Task.isCancelled, monitoringCount > 0 else { return }
            localError = error.localizedDescription
        }
    }

    nonisolated static func pruneHistory(_ samples: inout [PortmanSample], before cutoff: Date) {
        samples.removeAll { $0.date < cutoff }
        if samples.count > 300 { samples.removeFirst(samples.count - 300) }
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

    func refreshRemote(host: String, password: String? = nil, configurationFile: URL? = nil) async {
        let requestID = UUID()
        remoteRequestID = requestID
        isLoadingRemote = true
        do {
            let ports = try await PortmanScanner.remotePorts(
                host: host, password: password, configurationFile: configurationFile
            )
            guard remoteRequestID == requestID else { return }
            remotePorts = ports.map(\.port)
            remoteDetails = Dictionary(uniqueKeysWithValues: ports.map { ($0.port, $0) })
            forwardingError = nil
        } catch {
            guard remoteRequestID == requestID else { return }
            remotePorts = []
            remoteDetails = [:]
            forwardingError = "Could not inspect \(host): \(error.localizedDescription)"
        }
        isLoadingRemote = false
    }

    func cancelRemoteScan() {
        remoteRequestID = UUID()
        isLoadingRemote = false
    }

    func clearRemoteScan() {
        cancelRemoteScan()
        remotePorts = []
        remoteDetails = [:]
        forwardingError = nil
    }

    func loadRemoteDetails(host: String, port: UInt16, password: String? = nil) async {
        guard let detail = remoteDetails[port], detail.command == nil,
              detail.pid != nil else { return }
        let process = try? await PortmanScanner.remoteProcessDetails(
            host: host, pid: detail.pid, port: port, password: password
        )
        guard !Task.isCancelled, remoteDetails[port]?.pid == detail.pid else { return }
        remoteDetails[port]?.command = process?.command
        remoteDetails[port]?.container = process?.container ?? detail.container
    }

    @discardableResult
    func forward(host: String, remotePort: UInt16, localPort: UInt16,
                 password: String? = nil, configurationFile: URL? = nil) -> Bool {
        let arguments: [String]
        do {
            arguments = try PortmanScanner.tunnelArguments(
                host: host, remotePort: remotePort, localPort: localPort,
                password: password != nil, configurationFile: configurationFile
            )
        }
        catch { forwardingError = error.localizedDescription; return false }
        guard !tunnels.contains(where: { $0.localPort == localPort && !$0.isFailed }) else {
            forwardingError = "Local port \(localPort) already has a Portman tunnel."
            return false
        }
        let id = UUID()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments
        let channel: SSHAskpassChannel?
        do { channel = try password.map { _ in try SSHAskpassChannel() } }
        catch { forwardingError = "Could not prepare SSH password: \(error.localizedDescription)"; return false }
        let delivery = channel.flatMap { channel in password.map { channel.startDelivery(password: $0) } }
        if let channel { process.environment = channel.environment }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { [weak self] terminated in
            let status = terminated.terminationStatus
            // Report the exit before stderr draining, which can wait for an inherited writer.
            Task { @MainActor [weak self] in self?.tunnelEnded(id: id, status: status, message: "") }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data.prefix(2048), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                Task { @MainActor [weak self] in self?.tunnelEnded(id: id, status: status, message: message) }
            }
        }
        do {
            try process.run()
            if let channel, let delivery { authentication[id] = (channel, delivery) }
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
                        endAuthentication(for: id)
                        tunnels[current].state = .running
                        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                }
                guard let self, let index = tunnels.firstIndex(where: { $0.id == id }),
                      case .connecting = tunnels[index].state else { return }
                tunnels[index].state = .failed("SSH did not open local port \(localPort).")
                endAuthentication(for: id)
                NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
                if process.isRunning { process.terminate() }
            }
            forwardingError = nil
            return true
        } catch {
            delivery?.cancel()
            channel?.cleanup()
            forwardingError = "Could not start forwarding: \(error.localizedDescription)"
            return false
        }
    }

    func stopTunnel(_ id: UUID) {
        if let process = processes[id], process.isRunning { process.terminate() }
        endAuthentication(for: id)
        processes.removeValue(forKey: id)
        tunnels.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
    }

    func processID(forTunnel id: UUID) -> Int32? {
        processes[id]?.processIdentifier
    }

    func stopLocal(_ port: PortmanLocalPort) {
        do {
            try PortmanScanner.stop(port)
            controlError = nil
            scheduleForceStop(port)
            Task { await refreshLocal() }
        } catch { controlError = error.localizedDescription }
    }

    private func handleCleanupSuggestions() {
        let mode = PortmanPreferences.cleanupMode
        if mode != lastCleanupMode {
            handledCleanupProcessIDs = []
            lastCleanupMode = mode
        }
        guard mode == .automatic else { return }
        let ids = suggestedCleanupIDs
        handledCleanupProcessIDs.formIntersection(ids)
        var seen = Set<String>()
        let fresh = localPorts.filter {
            ids.contains($0.processID) && seen.insert($0.processID).inserted
                && !handledCleanupProcessIDs.contains($0.processID)
        }
        guard !fresh.isEmpty else { return }
        handledCleanupProcessIDs.formUnion(fresh.map(\.processID))
        stopLocalProcesses(fresh)
    }

    func stopLocalProcesses(_ ports: [PortmanLocalPort]) {
        var stopped = Set<Int32>()
        var failures: [String] = []
        for port in ports where stopped.insert(port.pid).inserted {
            do {
                try PortmanScanner.stop(port)
                scheduleForceStop(port)
            }
            catch { failures.append("PID \(port.pid): \(error.localizedDescription)") }
        }
        controlError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        Task { await refreshLocal() }
    }

    private func scheduleForceStop(_ port: PortmanLocalPort) {
        let delay = PortmanPreferences.forceQuitSeconds
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            PortmanScanner.forceStopIfUnchanged(port)
            await refreshLocal()
        }
    }

    func stopAll() {
        for process in processes.values where process.isRunning { process.terminate() }
        for id in Array(authentication.keys) { endAuthentication(for: id) }
        processes.removeAll()
        tunnels.removeAll()
        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
    }

    private func tunnelEnded(id: UUID, status: Int32, message: String) {
        endAuthentication(for: id)
        processes.removeValue(forKey: id)
        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }
        if case .failed = tunnels[index].state, message.isEmpty { return }
        tunnels[index].state = .failed(message.isEmpty ? "SSH exited with status \(status)." : message)
        NotificationCenter.default.post(name: .portmanSnapshotChanged, object: nil)
    }

    private func endAuthentication(for id: UUID) {
        guard let (channel, delivery) = authentication.removeValue(forKey: id) else { return }
        delivery.cancel()
        channel.cleanup()
    }
}

private extension PortmanTunnel {
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
