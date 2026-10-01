import Foundation
import NetToysCore

nonisolated enum SystemMonitorRemotePlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case linux = "Linux"
    case macOS = "macOS"
    case windows = "Windows"
    var id: String { rawValue }
}

nonisolated struct SystemMonitorRemoteProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var host: String
    var platform: SystemMonitorRemotePlatform
    var interval: Int
    var user: String
    var port: Int?

    init(
        id: String = UUID().uuidString,
        name: String,
        host: String,
        platform: SystemMonitorRemotePlatform = .linux,
        interval: Int = 30,
        user: String = "",
        port: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.platform = platform
        self.interval = Self.allowedIntervals.contains(interval) ? interval : 30
        self.user = user
        self.port = port
    }

    static let allowedIntervals = [0, 5, 10, 30, 60, 120, 300]

    private enum CodingKeys: String, CodingKey { case id, name, host, platform, interval, user, port }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        host = try values.decode(String.self, forKey: .host)
        platform = try values.decode(SystemMonitorRemotePlatform.self, forKey: .platform)
        interval = try values.decode(Int.self, forKey: .interval)
        if !Self.allowedIntervals.contains(interval) { interval = 30 }
        user = try values.decodeIfPresent(String.self, forKey: .user) ?? ""
        port = try values.decodeIfPresent(Int.self, forKey: .port)
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a name for this host." }
        if !SystemMonitorRemoteProtocol.validHost(host) { return SystemMonitorRemoteError.unsafeHost.errorDescription }
        if !user.isEmpty && !SystemMonitorRemoteProtocol.validUser(user) { return "Enter an SSH user without spaces or shell characters." }
        if !user.isEmpty, host.contains("@") { return "Enter the user in the User field and the host in the SSH host field." }
        if let port, !(1...65_535).contains(port) { return "Enter a port from 1 to 65535, or leave it blank to use SSH config." }
        if !Self.allowedIntervals.contains(interval) { return "Choose a supported refresh interval." }
        return nil
    }

    var destination: String { user.isEmpty ? host : "\(user)@\(host)" }
}

nonisolated enum SystemMonitorRemoteProfiles {
    static let key = "systemMonitor.remoteHosts"

    static func load(defaults: UserDefaults = .standard) -> [SystemMonitorRemoteProfile] {
        if let data = defaults.data(forKey: key),
           let profiles = try? JSONDecoder().decode([SystemMonitorRemoteProfile].self, from: data),
           !profiles.isEmpty {
            return profiles
        }
        guard let host = defaults.string(forKey: "systemMonitor.remoteHost"),
              SystemMonitorRemoteProtocol.validHost(host) else { return [] }
        let platform = defaults.string(forKey: "systemMonitor.remotePlatform")
            .flatMap(SystemMonitorRemotePlatform.init(rawValue:)) ?? .linux
        let interval = defaults.object(forKey: "systemMonitor.remoteInterval") as? Int ?? 30
        let shortName = host.split(separator: "@").last.map(String.init) ?? host
        return [SystemMonitorRemoteProfile(id: "legacy-\(host)", name: shortName, host: host, platform: platform, interval: interval)]
    }

    static func save(_ profiles: [SystemMonitorRemoteProfile], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: key) }
        guard let first = profiles.first else {
            defaults.removeObject(forKey: "systemMonitor.remoteHost")
            defaults.removeObject(forKey: "systemMonitor.remotePlatform")
            defaults.removeObject(forKey: "systemMonitor.remoteInterval")
            return
        }
        defaults.set(first.host, forKey: "systemMonitor.remoteHost")
        defaults.set(first.platform.rawValue, forKey: "systemMonitor.remotePlatform")
        defaults.set(first.interval, forKey: "systemMonitor.remoteInterval")
    }
}

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
    let cpuPercent: Double?
    var disks: [SystemMonitorRemoteDisk] = []
}

nonisolated struct SystemMonitorRemoteDisk: Sendable, Identifiable {
    let id: String
    let total: UInt64
    let used: UInt64
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
    var disks: [SystemMonitorRemoteDisk] = []
}

nonisolated enum SystemMonitorRemoteError: LocalizedError {
    case unsafeHost
    case invalidResponse
    case sshFailed(String)
    case invalidProfile(String)

    var errorDescription: String? {
        switch self {
        case .unsafeHost: "Enter an SSH host name or alias without spaces or shell characters."
        case .invalidResponse: "The host did not return valid system data. Check the selected operating system and SSH access."
        case .sshFailed(let message): "SSH failed: \(message)"
        case .invalidProfile(let message): message
        }
    }
}

nonisolated enum SystemMonitorRemoteProtocol {
    static let command = #"LC_ALL=C; export LC_ALL; printf 'MPT1\n'; head -n 1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; cat /proc/loadavg /proc/net/dev; df -Pk -x tmpfs -x devtmpfs | awk 'NR>1 {printf "MPTDISK %.0f %.0f ",$2*1024,$3*1024; for(i=6;i<=NF;i++) printf "%s%s",$i,(i<NF?" ":"\n")}'"#
    static let macCommand = #"""
    LC_ALL=C; export LC_ALL
    printf 'MPTMAC1\n'
    top -l 2 -s 1 -n 0 | awk '/CPU usage:/ { usage=$3+$5 } END { printf "CPU=%.2f\n", usage }'
    sysctl -n hw.memsize | awk '{print "MEM=" $1}'
    vm_stat | awk 'NR==1 { match($0, /[0-9]+/); page=substr($0,RSTART,RLENGTH) } /^Pages free:|^Pages inactive:|^Pages speculative:/ { gsub(/\./,"",$3); available+=$3 } END { printf "AVAILABLE=%.0f\n", available*page }'
    sysctl -n vm.loadavg | tr -d '{}' | awk '{printf "LOAD=%s,%s,%s\n",$1,$2,$3}'
    df -Pk / | awk 'NR==2 {printf "DISK=%.0f,%.0f\n",$2*1024,$3*1024}'
    df -Pk | awk 'NR>1 {printf "MPTDISK %.0f %.0f ",$2*1024,$3*1024; for(i=6;i<=NF;i++) printf "%s%s",$i,(i<NF?" ":"\n")}'
    netstat -ibn | awk 'NR==1 {for(i=1;i<=NF;i++) {if($i=="Ibytes") rx=i; if($i=="Obytes") tx=i}} $3 ~ /^<Link/ && $1 !~ /^lo/ && rx>0 && tx>0 {received+=$rx; sent+=$tx} END {printf "NET=%.0f,%.0f\n",received,sent}'
    """#
    static let windowsScript = #"""
    $ErrorActionPreference = 'Stop'
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | Where-Object Name -eq '_Total' | Select-Object -First 1
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $net = Get-CimInstance Win32_PerfRawData_Tcpip_NetworkInterface
    Write-Output 'MPTWIN1'
    Write-Output "CPU=$($cpu.PercentProcessorTime)"
    Write-Output "MEM=$([uint64]$os.TotalVisibleMemorySize * 1024)"
    Write-Output "AVAILABLE=$([uint64]$os.FreePhysicalMemory * 1024)"
    Write-Output "DISK=$([uint64]$disk.Size),$([uint64]($disk.Size - $disk.FreeSpace))"
    Write-Output "NET=$([uint64](($net | Measure-Object BytesReceivedPersec -Sum).Sum)),$([uint64](($net | Measure-Object BytesSentPersec -Sum).Sum))"
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        Write-Output "MPTDISK $([uint64]$_.Size) $([uint64]($_.Size - $_.FreeSpace)) $($_.DeviceID)"
    }
    """#

    static func validHost(_ host: String) -> Bool {
        let parts = host.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }),
              parts.count == 1 || validUser(String(parts[0])) else { return false }
        let address = String(parts.last ?? "")
        return address.utf8.count <= 253 && !address.hasPrefix("-") && address.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                || byte == 45 || byte == 46 || byte == 95 || byte == 58
        }
    }

    static func validUser(_ user: String) -> Bool {
        !user.isEmpty && user.utf8.count <= 128 && !user.hasPrefix("-") && user.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || [45, 46, 95].contains($0)
        }
    }

    static func arguments(host: String, platform: SystemMonitorRemotePlatform = .linux,
                          controlPath: String? = nil, user: String = "", port: Int? = nil) throws -> [String] {
        guard validHost(host) else { throw SystemMonitorRemoteError.unsafeHost }
        let profile = SystemMonitorRemoteProfile(name: host, host: host, platform: platform, user: user, port: port)
        if let message = profile.validationMessage { throw SystemMonitorRemoteError.invalidProfile(message) }
        let remoteCommand: String
        switch platform {
        case .linux: remoteCommand = command
        case .macOS: remoteCommand = macCommand
        case .windows:
            let encoded = Data(windowsScript.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }).base64EncodedString()
            remoteCommand = "powershell.exe -NoProfile -NonInteractive -EncodedCommand \(encoded)"
        }
        var options = [
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1",
            "-o", "LogLevel=ERROR"
        ]
        if let controlPath {
            options += ["-o", "ControlMaster=auto", "-o", "ControlPersist=600",
                        "-o", "ControlPath=\(controlPath)"]
        }
        if !user.isEmpty { options += ["-l", user] }
        if let port { options += ["-p", String(port)] }
        return options + ["-T", "--", host, remoteCommand]
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
        var disks: [SystemMonitorRemoteDisk] = []
        var hasNetwork = false
        for line in lines.dropFirst() {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let first = fields.first else { continue }
            if first == "MPTDISK" {
                let volume = try parseDisk(line)
                disks.append(volume)
                if volume.id == "/" || disk == nil { disk = (volume.total, volume.used) }
            } else if first == "cpu" {
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
                if values.count >= 9,
                   let rx = UInt64(values[0]), let tx = UInt64(values[8]) {
                    hasNetwork = true
                    if name == "lo" { continue }
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
              cpu.1 <= cpu.0, hasNetwork, disk.map({ $0.1 <= $0.0 }) ?? true else {
            throw SystemMonitorRemoteError.invalidResponse
        }
        return SystemMonitorRemoteCounters(
            cpuTotal: cpu.0, cpuIdle: cpu.1, memoryTotal: memoryTotal,
            memoryAvailable: memoryAvailable, received: received, sent: sent,
            diskTotal: disk?.0, diskUsed: disk?.1, load: load, cpuPercent: nil, disks: disks
        )
    }

    static func parseKeyed(_ output: String, platform: SystemMonitorRemotePlatform) throws -> SystemMonitorRemoteCounters {
        guard output.utf8.count <= 16_384 else { throw SystemMonitorRemoteError.invalidResponse }
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == (platform == .macOS ? "MPTMAC1" : "MPTWIN1") else {
            throw SystemMonitorRemoteError.invalidResponse
        }
        var values: [String: String] = [:]
        var disks: [SystemMonitorRemoteDisk] = []
        for line in lines.dropFirst() {
            if line.hasPrefix("MPTDISK ") { disks.append(try parseDisk(line)); continue }
            guard let equal = line.firstIndex(of: "=") else { continue }
            values[String(line[..<equal])] = String(line[line.index(after: equal)...])
        }
        guard let cpu = values["CPU"].flatMap(Double.init), cpu.isFinite, (0...100).contains(cpu),
              let total = values["MEM"].flatMap(UInt64.init), total > 0,
              let available = values["AVAILABLE"].flatMap(UInt64.init), available <= total,
              let diskParts = values["DISK"]?.split(separator: ",", omittingEmptySubsequences: false), diskParts.count == 2,
              let diskTotal = UInt64(diskParts[0]), diskTotal > 0,
              let diskUsed = UInt64(diskParts[1]), diskUsed <= diskTotal else {
            throw SystemMonitorRemoteError.invalidResponse
        }
        let network = values["NET"]?.split(separator: ",", omittingEmptySubsequences: false) ?? []
        guard network.count == 2, let received = UInt64(network[0]),
              let sent = UInt64(network[1]) else { throw SystemMonitorRemoteError.invalidResponse }
        let loadParts = values["LOAD"]?.split(separator: ",", omittingEmptySubsequences: false)
        let load = loadParts?.compactMap { Double($0) } ?? []
        guard loadParts == nil || loadParts?.count == 3 && load.count == 3 && load.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw SystemMonitorRemoteError.invalidResponse
        }
        return SystemMonitorRemoteCounters(cpuTotal: 0, cpuIdle: 0, memoryTotal: total,
                                           memoryAvailable: available, received: received,
                                           sent: sent, diskTotal: diskTotal, diskUsed: diskUsed,
                                           load: load, cpuPercent: cpu, disks: disks)
    }

    private static func parseDisk(_ line: String) throws -> SystemMonitorRemoteDisk {
        let fields = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
        guard fields.count == 4, let total = UInt64(fields[1]), total > 0,
              let used = UInt64(fields[2]), used <= total, !fields[3].isEmpty else {
            throw SystemMonitorRemoteError.invalidResponse
        }
        return SystemMonitorRemoteDisk(id: String(fields[3]), total: total, used: used)
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
    private var sessionHost: String?
    private var controlPath: String?
    private var sessionOptions: [String] = []
    private var closed = false

    func sample(host: String, platform: SystemMonitorRemotePlatform = .linux,
                user: String = "", port: Int? = nil) async throws -> SystemMonitorRemoteReading {
        guard !closed else { throw CancellationError() }
        try Task.checkCancellation()
        _ = try SystemMonitorRemoteProtocol.arguments(host: host, platform: platform, user: user, port: port)
        let path = try multiplexPath()
        let arguments = try SystemMonitorRemoteProtocol.arguments(host: host, platform: platform,
                                                                   controlPath: path, user: user, port: port)
        sessionHost = host
        sessionOptions = user.isEmpty ? [] : ["-l", user]
        if let port { sessionOptions += ["-p", String(port)] }
        let result: SSHProcessResult
        do {
            result = try await SSHProcessRunner.run(
                executableURL: SSHKeyAccessConfiguration.sshURL,
                arguments: arguments,
                maximumOutputBytes: 16_384,
                timeout: 8
            )
        } catch SSHKeyAccessError.timeout {
            throw SystemMonitorRemoteError.sshFailed("The host did not respond within 8 seconds.")
        } catch SSHKeyAccessError.outputLimit {
            throw SystemMonitorRemoteError.invalidResponse
        }
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        guard result.status == 0 else {
            let reason = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemMonitorRemoteError.sshFailed(reason.isEmpty ? "ssh exited with status \(result.status)." : reason)
        }
        let counters = try platform == .linux
            ? SystemMonitorRemoteProtocol.parse(result.standardOutput)
            : SystemMonitorRemoteProtocol.parseKeyed(result.standardOutput, platform: platform)
        let now = Date()
        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0
        let identity = "\(user)@\(host):\(port ?? 0):\(platform.rawValue)"
        let old = previousHost == identity ? previous : nil
        let cpu = counters.cpuPercent ?? old.flatMap {
            SystemMonitorDelta.cpuUsage(
                previous: (total: $0.cpuTotal, idle: $0.cpuIdle),
                current: (total: counters.cpuTotal, idle: counters.cpuIdle)
            )
        }
        let down = old.flatMap { SystemMonitorDelta.rate(previous: $0.received, current: counters.received, seconds: elapsed) }
        let up = old.flatMap { SystemMonitorDelta.rate(previous: $0.sent, current: counters.sent, seconds: elapsed) }
        previous = counters
        previousTime = now
        previousHost = identity
        return SystemMonitorRemoteReading(
            cpuPercent: cpu, memoryUsed: counters.memoryTotal - counters.memoryAvailable,
            memoryTotal: counters.memoryTotal, download: down, upload: up,
            diskUsed: counters.diskUsed, diskTotal: counters.diskTotal, load: counters.load, disks: counters.disks
        )
    }

    func close() async {
        closed = true
        previous = nil
        previousTime = nil
        previousHost = nil
        guard let sessionHost, let controlPath else { return }
        self.sessionHost = nil
        self.controlPath = nil
        _ = try? await SSHProcessRunner.run(
            executableURL: SSHKeyAccessConfiguration.sshURL,
            arguments: ["-o", "BatchMode=yes", "-S", controlPath, "-O", "exit"] + sessionOptions + ["--", sessionHost],
            maximumOutputBytes: 1_024,
            timeout: 3
        )
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: controlPath).deletingLastPathComponent())
    }

    private func multiplexPath() throws -> String {
        if let controlPath { return controlPath }
        let directory = URL(fileURLWithPath: "/tmp/mpt-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("ssh").path
        controlPath = path
        return path
    }
}
