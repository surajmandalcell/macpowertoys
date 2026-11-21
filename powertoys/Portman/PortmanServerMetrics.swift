import Foundation

nonisolated enum PortmanServerOS: String, Sendable { case linux = "Linux", macOS = "Darwin" }

/// Raw readings from one SSH run. Counters are cumulative; rates and CPU need two runs.
nonisolated struct PortmanServerCounters: Equatable, Sendable {
    var os: PortmanServerOS
    var cpuTotal: UInt64?
    var cpuIdle: UInt64?
    var cpuPercent: Double?
    var memoryUsed: UInt64?
    var memoryTotal: UInt64?
    var diskUsed: UInt64?
    var diskTotal: UInt64?
    var load: [Double]?
    var uptime: TimeInterval?
    var received: UInt64?
    var sent: UInt64?

    init(os: PortmanServerOS) { self.os = os }

    var isEmpty: Bool {
        cpuTotal == nil && cpuPercent == nil && memoryTotal == nil && diskTotal == nil
            && load == nil && uptime == nil && received == nil
    }
}

/// One point for the graphs. A value is nil when this run could not measure it, such as CPU on the first run.
nonisolated struct PortmanServerSample: Equatable, Sendable {
    var date: Date
    var cpuPercent: Double?
    var memoryUsed: UInt64?
    var memoryTotal: UInt64?
    var diskUsed: UInt64?
    var diskTotal: UInt64?
    var load: [Double]?
    var uptime: TimeInterval?
    var receiveRate: Double?
    var sendRate: Double?
}

nonisolated enum PortmanServerFailure: Error, Equatable, Sendable {
    case offline, unreachable, authFailed, hostKeyFailed, commandNotFound, invalidOutput
    case unsupported(String)
    case failed(String)

    var label: String {
        switch self {
        case .offline: "Offline"
        case .unreachable: "Unreachable"
        case .authFailed: "Auth failed"
        case .hostKeyFailed: "Host key failed"
        case .commandNotFound: "Command not found"
        case .invalidOutput: "Unreadable data"
        case .unsupported(let os): os.isEmpty ? "Unsupported system" : "Unsupported system (\(os))"
        case .failed: "SSH failed"
        }
    }

    var detail: String {
        switch self {
        case .offline: "The host did not answer over SSH."
        case .unreachable: "The host name did not resolve, or the network has no route to it."
        case .authFailed: "SSH refused the key. Portman monitors only hosts that accept your SSH key or agent."
        case .hostKeyFailed: "The host key is unknown or changed. Check it with ssh in Terminal."
        case .commandNotFound: "The host has no sh or uname."
        case .invalidOutput: "The host answered, but its output had no readable values."
        case .unsupported: "Portman reads Linux and macOS hosts."
        case .failed(let message): message
        }
    }
}

nonisolated enum PortmanServerProtocol {
    /// Sent on stdin to `sh -s`, so a fish or zsh login shell cannot change the syntax. Parsing stays in Swift.
    static let script = """
    LC_ALL=C; export LC_ALL
    os=$(uname -s 2>/dev/null)
    echo "@os $os"
    case "$os" in
    Linux)
      echo @stat; head -n 1 /proc/stat 2>/dev/null
      echo @mem; cat /proc/meminfo 2>/dev/null
      echo @df; df -kP / 2>/dev/null
      echo @uptime; cat /proc/uptime 2>/dev/null
      echo @load; cat /proc/loadavg 2>/dev/null
      echo @net; cat /proc/net/dev 2>/dev/null ;;
    Darwin)
      echo @cpu; top -l 2 -s 1 -n 0 2>/dev/null | grep 'CPU usage' | tail -n 1
      echo @memsize; sysctl -n hw.memsize 2>/dev/null
      echo @vm; vm_stat 2>/dev/null
      echo @df; if [ -d /System/Volumes/Data ]; then df -kP /System/Volumes/Data; else df -kP /; fi 2>/dev/null
      echo @boot; sysctl -n kern.boottime 2>/dev/null; date +%s
      echo @load; sysctl -n vm.loadavg 2>/dev/null
      echo @net; netstat -ibn 2>/dev/null ;;
    esac
    echo @end
    """

    static let maximumOutputBytes = 65_536

    static func parse(_ output: String) throws(PortmanServerFailure) -> PortmanServerCounters {
        var sections: [(String, [Substring])] = []
        var os: String?
        var complete = false
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("@os") {
                os = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            } else if line == "@end" {
                complete = true
                break
            } else if line.hasPrefix("@"), !line.contains(" ") {
                sections.append((String(line.dropFirst()), []))
            } else if !sections.isEmpty {
                sections[sections.count - 1].1.append(line)
            }
        }
        guard let os else { throw .invalidOutput }
        guard let system = PortmanServerOS(rawValue: os) else { throw .unsupported(os) }
        // A cut-off run can end mid-section; its last section may hold half a table.
        if !complete, !sections.isEmpty { sections.removeLast() }
        var counters = PortmanServerCounters(os: system)
        var memsize: UInt64?
        var vm: [Substring] = []
        for (name, lines) in sections {
            switch name {
            case "stat": parseStat(lines, into: &counters)
            case "mem": parseMeminfo(lines, into: &counters)
            case "df": parseDisk(lines, into: &counters)
            case "uptime": counters.uptime = lines.first.flatMap { firstNumber(in: $0) }.flatMap(nonNegative)
            case "load": counters.load = parseLoad(lines.first)
            case "net": system == .linux ? parseProcNet(lines, into: &counters) : parseNetstat(lines, into: &counters)
            case "cpu": counters.cpuPercent = lines.first.flatMap(parseTopCPU)
            case "memsize": memsize = lines.first.flatMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
            case "vm": vm = lines
            case "boot": counters.uptime = parseBoot(lines)
            default: break
            }
        }
        if let memsize, memsize > 0 {
            counters.memoryTotal = memsize
            counters.memoryUsed = parseVMStat(vm, total: memsize)
        }
        guard !counters.isEmpty else { throw .invalidOutput }
        return counters
    }

    /// Reads "1.5" and the decimal comma "1,5" that some locales print even when LC_ALL is set.
    static func number(_ text: Substring) -> Double? {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix("%") { value.removeLast() }
        if value.contains(","), !value.contains(".") { value = value.replacingOccurrences(of: ",", with: ".") }
        guard let number = Double(value), number.isFinite else { return nil }
        return number
    }

    private static func firstNumber(in line: Substring) -> Double? {
        line.split(whereSeparator: \.isWhitespace).first.flatMap(number)
    }

    private static func nonNegative(_ value: Double) -> Double? { value >= 0 ? value : nil }

    private static func kibibytes(_ text: Substring) -> UInt64? {
        guard let value = UInt64(text) else { return nil }
        let (bytes, overflow) = value.multipliedReportingOverflow(by: 1_024)
        return overflow ? nil : bytes
    }

    private static func parseStat(_ lines: [Substring], into counters: inout PortmanServerCounters) {
        guard let line = lines.first(where: { $0.hasPrefix("cpu ") }) else { return }
        let ticks = line.split(whereSeparator: \.isWhitespace).dropFirst().prefix(8).map { UInt64($0) }
        guard ticks.count >= 4, ticks.allSatisfy({ $0 != nil }) else { return }
        let values = ticks.compactMap { $0 }
        var total: UInt64 = 0
        for tick in values {
            let (sum, overflow) = total.addingReportingOverflow(tick)
            if overflow { return }
            total = sum
        }
        let idle = values[3] &+ (values.count > 4 ? values[4] : 0)
        guard idle <= total else { return }
        counters.cpuTotal = total
        counters.cpuIdle = idle
    }

    private static func parseMeminfo(_ lines: [Substring], into counters: inout PortmanServerCounters) {
        var values: [String: UInt64] = [:]
        for line in lines {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0].hasSuffix(":"), let bytes = kibibytes(fields[1]) else { continue }
            values[String(fields[0].dropLast())] = bytes
        }
        guard let total = values["MemTotal"], total > 0 else { return }
        // Kernels before 3.14 have no MemAvailable.
        let available = values["MemAvailable"]
            ?? values["MemFree"].map { $0 &+ (values["Buffers"] ?? 0) &+ (values["Cached"] ?? 0) }
        guard let available else { return }
        counters.memoryTotal = total
        counters.memoryUsed = total - min(available, total)
    }

    /// `df -kP` row, read from the end because a device name can hold spaces.
    private static func parseDisk(_ lines: [Substring], into counters: inout PortmanServerCounters) {
        for line in lines.reversed() {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 6, fields[fields.count - 2].hasSuffix("%"),
                  let total = kibibytes(fields[fields.count - 5]), total > 0,
                  let used = kibibytes(fields[fields.count - 4]) else { continue }
            counters.diskTotal = total
            counters.diskUsed = min(used, total)
            return
        }
    }

    private static func parseLoad(_ line: Substring?) -> [Double]? {
        guard let line else { return nil }
        let fields = line.split { $0.isWhitespace || $0 == "{" || $0 == "}" }.prefix(3).map(number)
        let values = fields.compactMap { $0 }.filter { $0 >= 0 }
        return values.count == 3 ? values : nil
    }

    private static func parseProcNet(_ lines: [Substring], into counters: inout PortmanServerCounters) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var found = false
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let values = line[line.index(after: colon)...].split(whereSeparator: \.isWhitespace)
            guard values.count >= 9, let rx = UInt64(values[0]), let tx = UInt64(values[8]) else { continue }
            found = true
            if name == "lo" { continue }
            received &+= rx
            sent &+= tx
        }
        if found { counters.received = received; counters.sent = sent }
    }

    /// `netstat -ibn` link rows. Columns are read from the end because interfaces without a MAC omit Address.
    private static func parseNetstat(_ lines: [Substring], into counters: inout PortmanServerCounters) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var found = false
        for line in lines {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 10, fields[2].hasPrefix("<Link"),
                  let rx = UInt64(fields[fields.count - 5]), let tx = UInt64(fields[fields.count - 2]) else { continue }
            found = true
            if fields[0].hasPrefix("lo") { continue }
            received &+= rx
            sent &+= tx
        }
        if found { counters.received = received; counters.sent = sent }
    }

    /// "CPU usage: 5.12% user, 10.25% sys, 84.62% idle"
    private static func parseTopCPU(_ line: Substring) -> Double? {
        let parts = line.split(separator: " ")
        guard let index = parts.firstIndex(where: { $0.hasPrefix("idle") }), index > 0,
              let idle = number(parts[index - 1]), (0...100).contains(idle) else { return nil }
        return 100 - idle
    }

    /// macOS has no MemAvailable; this matches Activity Monitor's Memory Used (app, wired, compressed).
    private static func parseVMStat(_ lines: [Substring], total: UInt64) -> UInt64? {
        var pageSize: UInt64 = 4_096
        var pages: [String: UInt64] = [:]
        for line in lines {
            if line.contains("page size of"),
               let size = line.split(separator: " ").compactMap({ UInt64($0) }).first, size > 0 {
                pageSize = size
                continue
            }
            guard let colon = line.lastIndex(of: ":"),
                  let value = UInt64(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))) else { continue }
            pages[String(line[..<colon])] = value
        }
        guard let wired = pages["Pages wired down"] else { return nil }
        let compressed = pages["Pages occupied by compressor"] ?? 0
        let app: UInt64
        if let anonymous = pages["Anonymous pages"] {
            app = anonymous - min(anonymous, pages["Pages purgeable"] ?? 0)
        } else if let active = pages["Pages active"] {
            app = active
        } else {
            return nil
        }
        let (used, overflow) = (app &+ wired &+ compressed).multipliedReportingOverflow(by: pageSize)
        return overflow ? nil : min(used, total)
    }

    /// "{ sec = 1732000000, usec = 1 } Thu Nov 19 ..." then the host's `date +%s`.
    private static func parseBoot(_ lines: [Substring]) -> TimeInterval? {
        guard lines.count >= 2, let range = lines[0].range(of: "sec = ") else { return nil }
        let digits = lines[0][range.upperBound...].prefix { $0.isNumber }
        guard let boot = Double(digits), let now = number(lines[1]) else { return nil }
        return now >= boot ? now - boot : nil
    }

    // MARK: Deltas

    /// Turns two runs into one point. A reboot or a counter that went down gives nil, never a spike.
    static func sample(previous: (counters: PortmanServerCounters, date: Date)?,
                       current: PortmanServerCounters, at date: Date) -> PortmanServerSample {
        var sample = PortmanServerSample(
            date: date, cpuPercent: current.cpuPercent, memoryUsed: current.memoryUsed,
            memoryTotal: current.memoryTotal, diskUsed: current.diskUsed, diskTotal: current.diskTotal,
            load: current.load, uptime: current.uptime
        )
        guard let previous, previous.counters.os == current.os else { return sample }
        let elapsed = date.timeIntervalSince(previous.date)
        let rebooted = previous.counters.uptime.flatMap { old in current.uptime.map { $0 < old } } ?? false
        if !rebooted, current.cpuPercent == nil,
           let total = current.cpuTotal, let idle = current.cpuIdle,
           let oldTotal = previous.counters.cpuTotal, let oldIdle = previous.counters.cpuIdle,
           total > oldTotal, idle >= oldIdle, idle - oldIdle <= total - oldTotal {
            let busy = Double((total - oldTotal) - (idle - oldIdle))
            sample.cpuPercent = min(100, max(0, busy / Double(total - oldTotal) * 100))
        }
        guard elapsed > 0 else { return sample }
        sample.receiveRate = counterDelta(previous.counters.received, current.received, rebooted: rebooted)
            .map { Double($0) / elapsed }
        sample.sendRate = counterDelta(previous.counters.sent, current.sent, rebooted: rebooted)
            .map { Double($0) / elapsed }
        return sample
    }

    /// 32-bit kernels wrap /proc/net/dev at 2^32; a larger counter that drops was reset, so skip that point.
    static func counterDelta(_ old: UInt64?, _ new: UInt64?, rebooted: Bool) -> UInt64? {
        guard let old, let new, !rebooted else { return nil }
        if new >= old { return new - old }
        guard old <= UInt64(UInt32.max) else { return nil }
        return UInt64(UInt32.max) - old + new + 1
    }

    // MARK: Errors

    static func classify(status: Int32, standardError: String) -> PortmanServerFailure {
        let text = standardError.lowercased()
        if text.contains("host key verification failed") || text.contains("remote host identification has changed")
            || text.contains("no matching host key") || text.contains("host key for") {
            return .hostKeyFailed
        }
        if text.contains("permission denied") || text.contains("too many authentication failures")
            || text.contains("no supported authentication methods") {
            return .authFailed
        }
        if text.contains("could not resolve hostname") || text.contains("no route to host")
            || text.contains("network is unreachable") || text.contains("name or service not known") {
            return .unreachable
        }
        if text.contains("connection refused") || text.contains("timed out") || text.contains("connection closed")
            || text.contains("connection reset") || text.contains("broken pipe") {
            return .offline
        }
        if status == 127 || text.contains("command not found") || text.contains("not found") && status != 255 {
            return .commandNotFound
        }
        let message = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(message.isEmpty ? "ssh exited with status \(status)." : String(message.prefix(200)))
    }
}
