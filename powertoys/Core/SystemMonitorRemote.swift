import Foundation

nonisolated struct SystemMonitorRemoteCounters: Sendable {
    let cpuTotal: UInt64
    let cpuIdle: UInt64
    let memoryTotal: UInt64
    let memoryAvailable: UInt64
    let received: UInt64
    let sent: UInt64
    let diskTotal: UInt64?
    let diskUsed: UInt64?
    let load: [Double]
}

nonisolated struct SystemMonitorRemoteReading: Sendable {
    let cpuPercent: Double?
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let download: Double?
    let upload: Double?
    let diskUsed: UInt64?
    let diskTotal: UInt64?
    let load: [Double]
}

nonisolated enum SystemMonitorRemoteError: LocalizedError {
    case unsafeHost
    case invalidResponse
    case sshFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsafeHost: "Enter an SSH host name or alias without spaces or shell characters."
        case .invalidResponse: "This host did not return Linux system data. Check that /proc is available."
        case .sshFailed(let message): "SSH failed: \(message)"
        }
    }
}

nonisolated enum SystemMonitorRemoteProtocol {
    static let command = "LC_ALL=C; printf 'MPT1\\n'; head -n 1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; cat /proc/loadavg /proc/net/dev; df -Pk / | tail -n 1"

    static func validHost(_ host: String) -> Bool {
        !host.isEmpty && !host.hasPrefix("-") && host.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                || byte == 45 || byte == 46 || byte == 64 || byte == 95
        }
    }

    static func arguments(host: String) throws -> [String] {
        guard validHost(host) else { throw SystemMonitorRemoteError.unsafeHost }
        return [
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1",
            "-o", "LogLevel=ERROR", "-T", "--", host, command,
        ]
    }

    static func parse(_ output: String) throws -> SystemMonitorRemoteCounters {
        guard output.utf8.count <= 16_384 else { throw SystemMonitorRemoteError.invalidResponse }
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "MPT1" else { throw SystemMonitorRemoteError.invalidResponse }

        var cpu: (UInt64, UInt64)?
        var memoryTotal: UInt64?
        var memoryAvailable: UInt64?
        var load: [Double]?
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var disk: (UInt64, UInt64)?
        for line in lines.dropFirst() {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let first = fields.first else { continue }
            if first == "cpu" {
                let rawTicks = fields.dropFirst().prefix(8)
                let ticks = rawTicks.compactMap { UInt64($0) }
                guard ticks.count >= 4, ticks.count == rawTicks.count else {
                    throw SystemMonitorRemoteError.invalidResponse
                }
                var total: UInt64 = 0
                for tick in ticks {
                    let (sum, overflow) = total.addingReportingOverflow(tick)
                    guard !overflow else { throw SystemMonitorRemoteError.invalidResponse }
                    total = sum
                }
                let (idle, overflow) = ticks[3].addingReportingOverflow(ticks.count > 4 ? ticks[4] : 0)
                guard !overflow else { throw SystemMonitorRemoteError.invalidResponse }
                cpu = (total, idle)
            } else if first == "MemTotal:", fields.count >= 2, let value = UInt64(fields[1]) {
                memoryTotal = try bytes(fromKiB: value)
            } else if first == "MemAvailable:", fields.count >= 2, let value = UInt64(fields[1]) {
                memoryAvailable = try bytes(fromKiB: value)
            } else if fields.count >= 4, fields[3].contains("/"),
                      let one = Double(fields[0]), let five = Double(fields[1]), let fifteen = Double(fields[2]),
                      one.isFinite, five.isFinite, fifteen.isFinite, one >= 0, five >= 0, fifteen >= 0 {
                load = [one, five, fifteen]
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmingCharacters(in: .whitespaces)
                let values = line[line.index(after: colon)...].split(whereSeparator: \.isWhitespace)
                if name != "lo", values.count >= 9,
                   let rx = UInt64(values[0]), let tx = UInt64(values[8]) {
                    let (nextReceived, receivedOverflow) = received.addingReportingOverflow(rx)
                    let (nextSent, sentOverflow) = sent.addingReportingOverflow(tx)
                    guard !receivedOverflow, !sentOverflow else { throw SystemMonitorRemoteError.invalidResponse }
                    received = nextReceived
                    sent = nextSent
                }
            } else if fields.last == "/", fields.count >= 6,
                      let total = UInt64(fields[1]), let used = UInt64(fields[2]) {
                disk = (try bytes(fromKiB: total), try bytes(fromKiB: used))
            }
        }
        guard let cpu, let memoryTotal, let memoryAvailable, let load,
              memoryTotal > 0, memoryAvailable <= memoryTotal,
              cpu.1 <= cpu.0, disk.map({ $0.1 <= $0.0 }) ?? true else {
            throw SystemMonitorRemoteError.invalidResponse
        }
        return SystemMonitorRemoteCounters(
            cpuTotal: cpu.0, cpuIdle: cpu.1, memoryTotal: memoryTotal,
            memoryAvailable: memoryAvailable, received: received, sent: sent,
            diskTotal: disk?.0, diskUsed: disk?.1, load: load
        )
    }

    private static func bytes(fromKiB value: UInt64) throws -> UInt64 {
        let (bytes, overflow) = value.multipliedReportingOverflow(by: 1_024)
        guard !overflow else { throw SystemMonitorRemoteError.invalidResponse }
        return bytes
    }
}

actor SystemMonitorRemotePoller {
    private var previous: SystemMonitorRemoteCounters?
    private var previousTime: Date?
    private var previousHost: String?

    func sample(host: String) async throws -> SystemMonitorRemoteReading {
        let arguments = try SystemMonitorRemoteProtocol.arguments(host: host)
        // ponytail: one SSH handshake per sample; use a request-driven session if measured host cost is high.
        let result = try await SSHProcessRunner.run(
            executableURL: SSHKeyAccessConfiguration.sshURL,
            arguments: arguments,
            maximumOutputBytes: 16_384,
            timeout: 8
        )
        guard result.status == 0 else {
            throw SystemMonitorRemoteError.sshFailed(
                result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let counters = try SystemMonitorRemoteProtocol.parse(result.standardOutput)
        let now = Date()
        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0
        let old = previousHost == host ? previous : nil
        let cpu = old.flatMap {
            SystemMonitorDelta.cpuUsage(
                previous: (total: $0.cpuTotal, idle: $0.cpuIdle),
                current: (total: counters.cpuTotal, idle: counters.cpuIdle)
            )
        }
        let down = old.flatMap { SystemMonitorDelta.rate(previous: $0.received, current: counters.received, seconds: elapsed) }
        let up = old.flatMap { SystemMonitorDelta.rate(previous: $0.sent, current: counters.sent, seconds: elapsed) }
        previous = counters
        previousTime = now
        previousHost = host
        return SystemMonitorRemoteReading(
            cpuPercent: cpu, memoryUsed: counters.memoryTotal - counters.memoryAvailable,
            memoryTotal: counters.memoryTotal, download: down, upload: up,
            diskUsed: counters.diskUsed, diskTotal: counters.diskTotal, load: counters.load
        )
    }
}
