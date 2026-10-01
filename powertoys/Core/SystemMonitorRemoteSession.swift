import AppKit
import Combine
import Foundation

nonisolated struct SystemMonitorRemoteState: Sendable {
    enum Phase: String, Sendable { case offline = "Offline", connecting = "Connecting", connected = "Connected" }
    var phase: Phase = .offline
    var reason: String?
    var reading: SystemMonitorRemoteReading?
    var history: [SystemMonitorRemoteReading] = []
    var updated: Date?
}

@MainActor
final class SystemMonitorRemoteSessions: ObservableObject {
    static let shared = SystemMonitorRemoteSessions()
    @Published private(set) var states: [String: SystemMonitorRemoteState] = [:]
    @Published var savedProfiles: [SystemMonitorRemoteProfile]?
    @Published var selectedID: String?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var pollers: [String: SystemMonitorRemotePoller] = [:]
    private var generations: [String: UUID] = [:]
    private var owners: [String: Set<String>] = [:]
    private var windowObservers: [String: NSObjectProtocol] = [:]
    private let sample: @Sendable (SystemMonitorRemoteProfile, SystemMonitorRemotePoller) async throws -> SystemMonitorRemoteReading

    init(sample: @escaping @Sendable (SystemMonitorRemoteProfile, SystemMonitorRemotePoller) async throws -> SystemMonitorRemoteReading = { profile, poller in
        try await poller.sample(host: profile.host, platform: profile.platform, user: profile.user, port: profile.port)
    }) {
        self.sample = sample
    }

    func state(for id: String) -> SystemMonitorRemoteState { states[id] ?? SystemMonitorRemoteState() }
    var activeTaskCount: Int { tasks.count }

    func report(_ error: Error, for id: String) {
        var state = state(for: id)
        state.reason = error.localizedDescription
        states[id] = state
    }

    func connect(_ profile: SystemMonitorRemoteProfile) {
        disconnect(profile.id)
        if let message = profile.validationMessage {
            states[profile.id] = SystemMonitorRemoteState(reason: message)
            return
        }
        states[profile.id] = SystemMonitorRemoteState(phase: .connecting)
        let poller = SystemMonitorRemotePoller()
        pollers[profile.id] = poller
        start(profile, poller: poller)
    }

    func refresh(_ profile: SystemMonitorRemoteProfile) {
        guard let poller = pollers[profile.id] else { return }
        start(profile, poller: poller)
    }

    func disconnect(_ id: String, reason: String? = nil) {
        generations.removeValue(forKey: id)
        let task = tasks.removeValue(forKey: id)
        task?.cancel()
        if let poller = pollers.removeValue(forKey: id) {
            Task {
                await task?.value
                await poller.close()
            }
        }
        states[id] = SystemMonitorRemoteState(reason: reason)
    }

    func remove(_ id: String) {
        disconnect(id)
        states.removeValue(forKey: id)
        for owner in owners.keys { owners[owner]?.remove(id) }
    }

    func setVisible(_ ids: Set<String>, owner: String) {
        let removed = (owners[owner] ?? []).subtracting(ids)
        if ids.isEmpty { owners.removeValue(forKey: owner) } else { owners[owner] = ids }
        for id in removed where !owners.values.contains(where: { $0.contains(id) }) {
            disconnect(id)
        }
    }

    func register(_ id: String, window: NSWindow) {
        let owner = "window-\(ObjectIdentifier(window))"
        owners[owner, default: []].insert(id)
        guard windowObservers[owner] == nil else { return }
        windowObservers[owner] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.setVisible([], owner: owner)
                if let observer = self.windowObservers.removeValue(forKey: owner) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }

    private func start(_ profile: SystemMonitorRemoteProfile, poller: SystemMonitorRemotePoller) {
        let previous = tasks[profile.id]
        previous?.cancel()
        let generation = UUID()
        generations[profile.id] = generation
        tasks[profile.id] = Task { [weak self, sample] in
            await previous?.value
            var needsBaseline = self?.state(for: profile.id).reading == nil
            while !Task.isCancelled {
                do {
                    let reading = try await sample(profile, poller)
                    guard !Task.isCancelled, let self, self.generations[profile.id] == generation else { return }
                    var state = self.state(for: profile.id)
                    state.phase = .connected
                    state.reason = nil
                    state.reading = reading
                    state.updated = Date()
                    state.history.append(reading)
                    if state.history.count > 120 { state.history.removeFirst(state.history.count - 120) }
                    self.states[profile.id] = state
                    if needsBaseline && (reading.cpuPercent == nil || reading.download == nil) {
                        needsBaseline = false
                        try await Task.sleep(for: .seconds(1))
                        continue
                    }
                    guard profile.interval > 0 else {
                        self.tasks.removeValue(forKey: profile.id)
                        return
                    }
                    try await Task.sleep(for: .seconds(profile.interval))
                } catch {
                    guard !Task.isCancelled, let self, self.generations[profile.id] == generation else { return }
                    self.disconnect(profile.id, reason: error.localizedDescription)
                    return
                }
            }
        }
    }
}
