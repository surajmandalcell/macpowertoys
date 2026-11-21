import Foundation
import Observation

/// A monitored host: the ssh destination and an optional port from a migrated profile.
nonisolated struct PortmanServerTarget: Hashable, Sendable {
    let destination: String
    var port: UInt16?
}

nonisolated protocol PortmanServerTransport: Sendable {
    func run(_ target: PortmanServerTarget, script: String) async throws -> SSHProcessResult
}

/// Runs the script with the owner's ssh config, keys and agent. BatchMode never prompts; no password is stored.
nonisolated struct PortmanSSHServerTransport: PortmanServerTransport {
    static let connectTimeout = 5
    static let deadline: TimeInterval = 12

    static func arguments(_ target: PortmanServerTarget) -> [String] {
        var arguments = PortmanScanner.authenticationArguments(password: false) + [
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1",
            "-o", "StrictHostKeyChecking=accept-new", "-o", "LogLevel=ERROR",
        ]
        if let port = target.port { arguments += ["-p", String(port)] }
        return arguments + ["-T", "--", target.destination, "sh", "-s"]
    }

    func run(_ target: PortmanServerTarget, script: String) async throws -> SSHProcessResult {
        try await SSHProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: Self.arguments(target),
            standardInput: Data(script.utf8),
            maximumOutputBytes: PortmanServerProtocol.maximumOutputBytes,
            timeout: Self.deadline
        )
    }
}

/// Keeps the previous run per host for CPU and network deltas. Runs off the main actor.
actor PortmanServerSampler {
    private var previous: (counters: PortmanServerCounters, date: Date)?

    /// nil means the run was cancelled and must leave the host's state alone.
    func sample(_ target: PortmanServerTarget, transport: any PortmanServerTransport,
                at date: Date) async -> Result<PortmanServerSample, PortmanServerFailure>? {
        let result: SSHProcessResult
        do {
            result = try await transport.run(target, script: PortmanServerProtocol.script)
        } catch is CancellationError {
            return nil
        } catch SSHKeyAccessError.timeout {
            return .failure(.offline)
        } catch SSHKeyAccessError.outputLimit {
            return .failure(.invalidOutput)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        if Task.isCancelled { return nil }
        guard result.status == 0 else {
            return .failure(PortmanServerProtocol.classify(status: result.status, standardError: result.standardError))
        }
        do {
            let counters = try PortmanServerProtocol.parse(result.standardOutput)
            let sample = PortmanServerProtocol.sample(previous: previous, current: counters, at: date)
            previous = (counters, date)
            return .success(sample)
        } catch {
            return .failure(error)
        }
    }
}

nonisolated enum PortmanServerStatus: Equatable, Sendable {
    case waiting, online
    case failed(PortmanServerFailure)
}

nonisolated struct PortmanServerState: Equatable, Sendable {
    var status = PortmanServerStatus.waiting
    var latest: PortmanServerSample?
    var history: [PortmanServerSample] = []
    var lastSeen: Date?
    var lastAttempt: Date?
    var failures = 0

    /// "Online", "Offline · seen 5 min ago", "Auth failed · never seen".
    func statusText(now: Date) -> String {
        switch status {
        case .waiting: return "Connecting"
        case .online: return "Online"
        case .failed(let failure):
            guard let lastSeen else { return "\(failure.label) · never seen" }
            return "\(failure.label) · seen \(PortmanServerState.ago(now.timeIntervalSince(lastSeen)))"
        }
    }

    static func ago(_ seconds: TimeInterval) -> String {
        switch max(0, seconds) {
        case ..<60: "just now"
        case ..<3_600: "\(Int(seconds / 60)) min ago"
        case ..<86_400: "\(Int(seconds / 3_600)) h ago"
        default: "\(Int(seconds / 86_400)) d ago"
        }
    }
}

/// Samples monitored hosts over SSH. Fast while the panel shows Forward, slow otherwise, off in Low Power Mode.
/// One run per host at a time; failures back off; removing a host cancels its run.
@Observable
@MainActor
final class PortmanServerMonitor {
    enum Cadence: Equatable { case fast, slow, off }

    static let shared = PortmanServerMonitor()
    nonisolated static let fastInterval: TimeInterval = 2
    nonisolated static let slowInterval: TimeInterval = 45
    nonisolated static let fastBackoffCap: TimeInterval = 30
    nonisolated static let slowBackoffCap: TimeInterval = 600
    static let historyLimit = 60

    private(set) var states: [String: PortmanServerState] = [:]
    private(set) var cadence = Cadence.off

    @ObservationIgnored private var targets: [String: PortmanServerTarget] = [:]
    @ObservationIgnored private var samplers: [String: PortmanServerSampler] = [:]
    @ObservationIgnored private var running: [String: (generation: Int, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var panelOpen = false
    @ObservationIgnored private var forwardTab = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var powerObserver: NSObjectProtocol?
    @ObservationIgnored private let transport: any PortmanServerTransport
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let lowPower: @MainActor () -> Bool
    @ObservationIgnored private let autoRun: Bool

    /// Tests pass `autoRun: false` and drive `tick()` with their own clock.
    init(transport: any PortmanServerTransport = PortmanSSHServerTransport(),
         now: @escaping @MainActor () -> Date = { Date() },
         lowPower: @escaping @MainActor () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
         autoRun: Bool = true) {
        self.transport = transport
        self.now = now
        self.lowPower = lowPower
        self.autoRun = autoRun
    }

    // MARK: Inputs

    /// Connects the saved host list. Called once from the Portman status item; never in unit tests.
    func start() {
        guard powerObserver == nil else { return }
        let hosts = PortmanHostList.shared
        hosts.onChange = { [weak self] in self?.sync(Self.targets(from: $0)) }
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reschedule() } }
        sync(Self.targets(from: hosts.hosts))
    }

    func stop() {
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        powerObserver = nil
        PortmanHostList.shared.onChange = nil
        sync([])
    }

    nonisolated static func targets(from hosts: [PortmanHost]) -> [PortmanServerTarget] {
        hosts.filter(\.monitors).map { PortmanServerTarget(destination: $0.destination, port: $0.port) }
    }

    func sync(_ newTargets: [PortmanServerTarget]) {
        let wanted = Dictionary(newTargets.map { ($0.destination, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, target) in targets where wanted[id] != target {
            cancel(id)
            targets.removeValue(forKey: id)
            samplers.removeValue(forKey: id)
            states.removeValue(forKey: id)
        }
        for (id, target) in wanted where targets[id] == nil {
            targets[id] = target
            samplers[id] = PortmanServerSampler()
            states[id] = PortmanServerState()
        }
        reschedule()
    }

    /// The Portman panel reports when it opens, closes, or changes tab.
    func setPanel(open: Bool, forwardTab: Bool) {
        panelOpen = open
        self.forwardTab = forwardTab
        reschedule()
    }

    // MARK: Scheduling

    var currentCadence: Cadence {
        if targets.isEmpty || lowPower() { return .off }
        return panelOpen && forwardTab ? .fast : .slow
    }

    nonisolated static func interval(_ cadence: Cadence, failures: Int) -> TimeInterval? {
        let (base, cap): (TimeInterval, TimeInterval)
        switch cadence {
        case .off: return nil
        case .fast: (base, cap) = (fastInterval, fastBackoffCap)
        case .slow: (base, cap) = (slowInterval, slowBackoffCap)
        }
        return min(cap, base * pow(2, Double(min(max(failures, 0), 10))))
    }

    /// When the host is due next, or nil while it runs or polling is off.
    func nextDue(_ id: String) -> Date? {
        guard running[id] == nil, let state = states[id],
              let interval = Self.interval(currentCadence, failures: state.failures) else { return nil }
        return state.lastAttempt.map { $0.addingTimeInterval(interval) } ?? .distantPast
    }

    func isRunning(_ id: String) -> Bool { running[id] != nil }

    /// Starts a run for every due host that has none running.
    func tick() {
        updateCadence()
        let date = now()
        for id in targets.keys.sorted() {
            guard let due = nextDue(id), due <= date else { continue }
            start(id, at: date)
        }
    }

    /// Waits for every run in flight. Tests use it after `tick()`.
    func settle() async {
        while let next = running.values.first?.task { await next.value }
    }

    private func start(_ id: String, at date: Date) {
        guard let target = targets[id], let sampler = samplers[id] else { return }
        generation &+= 1
        let runID = generation
        let transport = transport
        let task = Task { [weak self] in
            let outcome = await sampler.sample(target, transport: transport, at: date)
            self?.finish(id, runID: runID, outcome: outcome)
        }
        running[id] = (runID, task)
    }

    private func finish(_ id: String, runID: Int, outcome: Result<PortmanServerSample, PortmanServerFailure>?) {
        guard running[id]?.generation == runID else { return }
        running.removeValue(forKey: id)
        guard targets[id] != nil, var state = states[id] else { return }
        guard let outcome else { return reschedule() }
        state.lastAttempt = now()
        switch outcome {
        case .success(let sample):
            state.status = .online
            state.latest = sample
            state.lastSeen = sample.date
            state.failures = 0
            state.history.append(sample)
            if state.history.count > Self.historyLimit { state.history.removeFirst(state.history.count - Self.historyLimit) }
        case .failure(let failure):
            state.status = .failed(failure)
            state.failures += 1
        }
        states[id] = state
        reschedule()
    }

    private func cancel(_ id: String) {
        running.removeValue(forKey: id)?.task.cancel()
    }

    /// One sleeping task wakes at the earliest due time. No timer runs while nothing is due.
    private func updateCadence() {
        let value = currentCadence
        if cadence != value { cadence = value }
    }

    private func reschedule() {
        updateCadence()
        loop?.cancel()
        loop = nil
        guard autoRun, cadence != .off else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                let date = self.now()
                guard let next = self.targets.keys.compactMap({ self.nextDue($0) }).min() else { return }
                let wait = max(0.05, next.timeIntervalSince(date))
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }
}

nonisolated extension PortmanServerSample {
    /// One plain line for the host row, such as "CPU 12% · Mem 3.1 GB of 8 GB · Disk 40% · Load 0.52 · Up 3 d".
    var summary: String {
        var parts: [String] = []
        if let cpuPercent { parts.append("CPU \(Int(cpuPercent.rounded()))%") }
        if let memoryUsed, let memoryTotal {
            parts.append("Mem \(Self.bytes(memoryUsed)) of \(Self.bytes(memoryTotal))")
        }
        if let diskUsed, let diskTotal, diskTotal > 0 {
            parts.append("Disk \(Int((Double(diskUsed) / Double(diskTotal) * 100).rounded()))%")
        }
        if let load = load?.first { parts.append(String(format: "Load %.2f", load)) }
        if let receiveRate, let sendRate {
            parts.append("↓\(Self.bytes(UInt64(receiveRate)))/s ↑\(Self.bytes(UInt64(sendRate)))/s")
        }
        if let uptime { parts.append("Up \(Self.duration(uptime))") }
        return parts.joined(separator: " · ")
    }

    private nonisolated(unsafe) static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()

    nonisolated static func bytes(_ value: UInt64) -> String {
        formatter.string(fromByteCount: Int64(clamping: value))
    }

    nonisolated static func duration(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<3_600: "\(Int(seconds / 60)) min"
        case ..<86_400: "\(Int(seconds / 3_600)) h"
        default: "\(Int(seconds / 86_400)) d"
        }
    }
}
