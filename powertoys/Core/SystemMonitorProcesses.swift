import Darwin
import Foundation

nonisolated struct SystemMonitorProcess: Identifiable, Sendable {
    let pid: Int32
    let started: UInt64
    let name: String
    let cpuPercent: Double?
    let residentBytes: UInt64
    let virtualBytes: UInt64
    let threads: Int32
    let parentPID: Int32
    let userID: UInt32
    let executablePath: String

    var id: String { "\(pid):\(started)" }
}

nonisolated enum SystemMonitorProcessUsage {
    static func percent(previous: UInt64, current: UInt64, elapsed: TimeInterval,
                        nanosecondsPerTick: Double) -> Double? {
        guard current >= previous, elapsed > 0 else { return nil }
        return Double(current - previous) * nanosecondsPerTick / 1_000_000_000 / elapsed * 100
    }
}

actor SystemMonitorProcessSampler {
    struct PublicProcessInfo: Sendable {
        let parentPID: Int32
        let userID: UInt32
        let residentBytes: UInt64
        let virtualBytes: UInt64
        let cpuPercent: Double?
        let path: String
    }
    private var previous: [String: UInt64] = [:]
    private var previousTime: Date?
    private let nanosecondsPerTick: Double

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        nanosecondsPerTick = Double(timebase.numer) / Double(max(timebase.denom, 1))
    }

    func sample() async -> [SystemMonitorProcess] {
        let now = Date()
        let estimated = max(Int(proc_listallpids(nil, 0)), 0)
        guard estimated > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: min(estimated + 128, 65_536))
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.size))
        }
        guard count > 0 else { return [] }

        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0
        var current: [String: UInt64] = [:]
        var processes: [SystemMonitorProcess] = []
        var restrictedPIDs = Set<Int32>()
        processes.reserveCapacity(Int(count))
        for pid in pids.prefix(Int(count)) where pid > 0 {
            if Task.isCancelled { break }
            var info = proc_taskallinfo()
            let bytes = withUnsafeMutablePointer(to: &info) {
                proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, $0, Int32(MemoryLayout<proc_taskallinfo>.size))
            }
            guard bytes == MemoryLayout<proc_taskallinfo>.size else {
                restrictedPIDs.insert(pid)
                var fallbackName = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
                let nameLength = proc_name(pid, &fallbackName, UInt32(fallbackName.count))
                processes.append(SystemMonitorProcess(
                    pid: pid, started: 0,
                    name: nameLength > 0 ? String(cString: fallbackName) : "PID \(pid)",
                    cpuPercent: nil, residentBytes: 0, virtualBytes: 0, threads: 0,
                    parentPID: 0, userID: UInt32.max, executablePath: "Protected process"
                ))
                continue
            }
            let started = info.pbsd.pbi_start_tvsec * 1_000_000 + info.pbsd.pbi_start_tvusec
            let identity = "\(pid):\(started)"
            let ticks = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            let cpu = previous[identity].flatMap {
                SystemMonitorProcessUsage.percent(previous: $0, current: ticks, elapsed: elapsed,
                                                  nanosecondsPerTick: nanosecondsPerTick)
            }
            let name = withUnsafeBytes(of: info.pbsd.pbi_name) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLength = proc_pidpath(pid, &path, UInt32(path.count))
            let executablePath = pathLength > 0 ? String(cString: path) : "Unavailable"
            current[identity] = ticks
            processes.append(SystemMonitorProcess(
                pid: pid, started: started, name: name.isEmpty ? "PID \(pid)" : name,
                cpuPercent: cpu, residentBytes: info.ptinfo.pti_resident_size,
                virtualBytes: info.ptinfo.pti_virtual_size,
                threads: info.ptinfo.pti_threadnum, parentPID: Int32(info.pbsd.pbi_ppid),
                userID: info.pbsd.pbi_uid, executablePath: executablePath
            ))
        }
        if !restrictedPIDs.isEmpty {
            let publicInfo = await Self.publicProcessInfo()
            processes = processes.map { process in
                guard restrictedPIDs.contains(process.pid), let info = publicInfo[process.pid] else {
                    return process
                }
                return SystemMonitorProcess(
                    pid: process.pid, started: 0, name: URL(fileURLWithPath: info.path).lastPathComponent,
                    cpuPercent: info.cpuPercent, residentBytes: info.residentBytes,
                    virtualBytes: info.virtualBytes, threads: 0, parentPID: info.parentPID,
                    userID: info.userID, executablePath: info.path
                )
            }
        }
        if !Task.isCancelled {
            previous = current
            previousTime = now
        }
        return processes
    }

    private static func publicProcessInfo() async -> [Int32: PublicProcessInfo] {
        guard let result = try? await SSHProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-A", "-o", "pid=,ppid=,uid=,rss=,vsz=,%cpu=,comm="],
            maximumOutputBytes: 2_000_000,
            timeout: 5
        ), result.status == 0 else { return [:] }
        return parsePublicProcessInfo(result.standardOutput)
    }

    nonisolated static func parsePublicProcessInfo(_ text: String) -> [Int32: PublicProcessInfo] {
        var result: [Int32: PublicProcessInfo] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 6, whereSeparator: \.isWhitespace)
            guard fields.count == 7, let pid = Int32(fields[0]),
                  let parentPID = Int32(fields[1]), let userID = UInt32(fields[2]),
                  let residentKiB = UInt64(fields[3]), let virtualKiB = UInt64(fields[4]),
                  let cpuPercent = Double(fields[5]), cpuPercent.isFinite,
                  !fields[6].isEmpty else { continue }
            let (residentBytes, residentOverflow) = residentKiB.multipliedReportingOverflow(by: 1_024)
            let (virtualBytes, virtualOverflow) = virtualKiB.multipliedReportingOverflow(by: 1_024)
            guard !residentOverflow, !virtualOverflow else { continue }
            result[pid] = PublicProcessInfo(parentPID: parentPID, userID: userID,
                                            residentBytes: residentBytes, virtualBytes: virtualBytes,
                                            cpuPercent: cpuPercent, path: String(fields[6]))
        }
        return result
    }
}

nonisolated enum SystemMonitorProcessControl {
    enum Failure: LocalizedError {
        case noLongerRunning
        case protectedProcess
        case systemError(Int32)

        var errorDescription: String? {
            switch self {
            case .noLongerRunning: "This process has already exited. Refresh the list."
            case .protectedProcess: "MacPowerToys and system startup cannot be quit here."
            case .systemError(let code): String(cString: strerror(code))
            }
        }
    }

    static func terminate(_ process: SystemMonitorProcess, force: Bool) throws {
        guard process.pid > 1, process.pid != getpid() else { throw Failure.protectedProcess }
        var info = proc_bsdinfo()
        let bytes = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(process.pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        let started = info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        guard bytes == MemoryLayout<proc_bsdinfo>.size, started == process.started else {
            throw Failure.noLongerRunning
        }
        guard kill(process.pid, force ? SIGKILL : SIGTERM) == 0 else {
            throw Failure.systemError(errno)
        }
    }
}
