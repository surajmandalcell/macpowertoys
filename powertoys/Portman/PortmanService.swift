import Darwin
import Foundation
import Observation

nonisolated struct PortmanLocalPort: Identifiable, Sendable {
    let pid: Int32
    let port: UInt16
    let address: String
    let command: String
    let launchCommand: String
    let memoryBytes: Int64
    let cpuPercent: Double
    let uptime: String
    let started: UInt64
    let userID: UInt32

    var processID: String { "\(pid):\(started)" }
    var id: String { "\(processID):\(port)" }
    var canStop: Bool {
        started > 0 && userID == geteuid() && pid > 1 && pid != getpid()
            && !["postgres", "mysqld", "mariadbd", "mongod", "redis-server", "docker", "ssh"]
                .contains(command.lowercased())
    }
}

nonisolated struct PortmanMetadata: Sendable {
    let folder: String
    let project: String
    let branch: String?
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
        identities: [Int32: (UInt64, UInt32)] = [:]
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
                      port > 0, (3000...9999).contains(port) else { continue }
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

    static func localPorts() throws -> [PortmanLocalPort] {
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
        return parseLocal(lsof, ps, identities: identities)
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
            branch: branch?.isEmpty == false ? branch : nil
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
    var localError: String?
    var controlError: String?
    var forwardingError: String?
    var isLoadingRemote = false

    private var monitoringCount = 0
    private var monitoringTask: Task<Void, Never>?
    private var processes: [UUID: Process] = [:]
    private var remoteRequestID = UUID()

    func beginMonitoring() {
        monitoringCount += 1
        guard monitoringTask == nil else { return }
        monitoringTask = Task {
            while !Task.isCancelled {
                await refreshLocal()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func endMonitoring() {
        monitoringCount = max(0, monitoringCount - 1)
        guard monitoringCount == 0 else { return }
        monitoringTask?.cancel()
        monitoringTask = nil
        localPorts = []
        history = [:]
        metadata = [:]
    }

    func refreshLocal() async {
        do {
            let ports = try await Task.detached(priority: .utility) { try PortmanScanner.localPorts() }.value
            guard !Task.isCancelled else { return }
            localPorts = ports
            localError = nil
            let now = Date()
            for port in ports {
                history[port.id, default: []].append(PortmanSample(
                    date: now, memoryBytes: port.memoryBytes, cpuPercent: port.cpuPercent
                ))
                if history[port.id, default: []].count > 300 { history[port.id]?.removeFirst() }
            }
            history = history.filter { key, _ in ports.contains { $0.id == key } }
            metadata = metadata.filter { key, _ in ports.contains { $0.id == key } }
        } catch {
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
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                }
                guard let self, let index = tunnels.firstIndex(where: { $0.id == id }),
                      case .connecting = tunnels[index].state else { return }
                tunnels[index].state = .failed("SSH did not open local port \(localPort).")
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
    }

    func stopLocal(_ port: PortmanLocalPort) {
        do {
            try PortmanScanner.stop(port)
            controlError = nil
            Task { await refreshLocal() }
        } catch { controlError = error.localizedDescription }
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
    }

    private func tunnelEnded(id: UUID, status: Int32, message: String) {
        processes.removeValue(forKey: id)
        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }
        if case .failed = tunnels[index].state { return }
        tunnels[index].state = .failed(message.isEmpty ? "SSH exited with status \(status)." : message)
    }
}

private extension PortmanTunnel {
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
