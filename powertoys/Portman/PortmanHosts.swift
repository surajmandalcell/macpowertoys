import Foundation
import Observation

/// What the owner wants from a host: forward its ports, watch its CPU, memory and disk, or both.
nonisolated enum PortmanHostMode: String, Codable, CaseIterable, Sendable {
    case forward, monitor, both

    var title: String {
        switch self {
        case .forward: "Forward ports"
        case .monitor: "Monitor"
        case .both: "Both"
        }
    }

    var monitors: Bool { self != .forward }
    var forwards: Bool { self != .monitor }
}

/// One saved forward under its host: localhost:localPort reaches remotePort on the host.
nonisolated struct PortmanForwardSpec: Codable, Hashable, Sendable {
    var remotePort: UInt16
    var localPort: UInt16
}

/// A saved SSH host, the parent row in Forward. `destination` is the alias or user@address passed to ssh.
nonisolated struct PortmanHost: Codable, Identifiable, Hashable, Sendable {
    var destination: String
    var mode: PortmanHostMode
    // shortcut: only the monitor passes -p; scans and tunnels still use the ssh config port. Wire it there when a host needs it.
    var port: UInt16?
    var forwards: [PortmanForwardSpec]

    var id: String { destination }
    var monitors: Bool { mode.monitors }

    init(destination: String, mode: PortmanHostMode, port: UInt16? = nil, forwards: [PortmanForwardSpec] = []) {
        self.destination = destination
        self.mode = mode
        self.port = port
        self.forwards = forwards
    }

    private enum CodingKeys: String, CodingKey { case destination, mode, port, forwards }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        destination = try values.decode(String.self, forKey: .destination)
        mode = (try? values.decode(PortmanHostMode.self, forKey: .mode)) ?? .forward
        port = try? values.decodeIfPresent(UInt16.self, forKey: .port)
        forwards = (try? values.decodeIfPresent([PortmanForwardSpec].self, forKey: .forwards)) ?? []
    }
}

/// Saves hosts under `portman.hosts` and migrates the remote hosts saved by the removed System Monitor.
/// Legacy keys stay untouched, so a downgrade still finds them.
nonisolated enum PortmanHostStore {
    static let key = "portman.hosts"
    static let unreadableKey = "portman.hosts.unreadable"
    static let legacyProfilesKey = "systemMonitor.remoteHosts"
    static let legacyHostKey = "systemMonitor.remoteHost"
    static let version = 1

    private struct Envelope: Codable {
        var version: Int
        var hosts: [PortmanHost]
    }

    private struct LegacyProfile: Decodable {
        var host: String
        var user: String?
        var port: Int?
    }

    static func load(_ defaults: UserDefaults = .standard) -> [PortmanHost] {
        if let data = defaults.data(forKey: key) {
            if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
                return normalized(envelope.hosts)
            }
            // Keep unreadable data instead of overwriting it with the next save.
            if defaults.data(forKey: unreadableKey) == nil { defaults.set(data, forKey: unreadableKey) }
            defaults.removeObject(forKey: key)
        }
        let migrated = legacyHosts(defaults)
        if !migrated.isEmpty { save(migrated, defaults) }
        return migrated
    }

    static func save(_ hosts: [PortmanHost], _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Envelope(version: version, hosts: normalized(hosts))) else { return }
        defaults.set(data, forKey: key)
    }

    static func legacyHosts(_ defaults: UserDefaults) -> [PortmanHost] {
        if let data = defaults.data(forKey: legacyProfilesKey),
           let profiles = try? JSONDecoder().decode([LegacyProfile].self, from: data), !profiles.isEmpty {
            return normalized(profiles.map { profile in
                let user = profile.user ?? ""
                return PortmanHost(destination: user.isEmpty ? profile.host : "\(user)@\(profile.host)",
                                   mode: .monitor,
                                   port: profile.port.flatMap { (1...65_535).contains($0) ? UInt16($0) : nil })
            })
        }
        guard let host = defaults.string(forKey: legacyHostKey) else { return [] }
        return normalized([PortmanHost(destination: host, mode: .monitor)])
    }

    /// Drops invalid destinations and merges duplicates, keeping the first host's settings and every forward.
    static func normalized(_ hosts: [PortmanHost]) -> [PortmanHost] {
        var result: [PortmanHost] = []
        for host in hosts {
            let destination = host.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard PortmanSSHHost.isValid(destination) else { continue }
            var clean = host
            clean.destination = destination
            clean.forwards = clean.forwards.filter { $0.remotePort > 0 && $0.localPort > 0 }
            if let index = result.firstIndex(where: { $0.destination == destination }) {
                for spec in clean.forwards where !result[index].forwards.contains(where: { $0.localPort == spec.localPort }) {
                    result[index].forwards.append(spec)
                }
            } else {
                var unique: [PortmanForwardSpec] = []
                for spec in clean.forwards where !unique.contains(where: { $0.localPort == spec.localPort }) {
                    unique.append(spec)
                }
                clean.forwards = unique
                result.append(clean)
            }
        }
        return result
    }
}

/// One child row under a host: a saved forward and its live tunnel, if one runs.
nonisolated struct PortmanForwardChild: Identifiable, Sendable {
    let spec: PortmanForwardSpec
    let tunnel: PortmanTunnel?
    var id: String { "\(spec.localPort)>\(spec.remotePort)" }
}

/// One parent row in Forward and its children.
nonisolated struct PortmanHostGroup: Identifiable, Sendable {
    let host: PortmanHost
    let saved: Bool
    let children: [PortmanForwardChild]
    var id: String { host.destination }
}

nonisolated enum PortmanForwardTree {
    /// Saved hosts in saved order, then hosts that only have live tunnels. Every tunnel lands under its host.
    static func groups(hosts: [PortmanHost], tunnels: [PortmanTunnel]) -> [PortmanHostGroup] {
        var groups = hosts.map { host in
            var children = host.forwards.map { spec in
                PortmanForwardChild(spec: spec, tunnel: tunnels.first {
                    $0.host == host.destination && $0.localPort == spec.localPort && $0.remotePort == spec.remotePort
                })
            }
            for tunnel in tunnels where tunnel.host == host.destination
                && !host.forwards.contains(where: { $0.localPort == tunnel.localPort && $0.remotePort == tunnel.remotePort }) {
                children.append(PortmanForwardChild(
                    spec: PortmanForwardSpec(remotePort: tunnel.remotePort, localPort: tunnel.localPort), tunnel: tunnel))
            }
            return PortmanHostGroup(host: host, saved: true, children: children)
        }
        let known = Set(hosts.map(\.destination))
        var extraOrder: [String] = []
        for tunnel in tunnels where !known.contains(tunnel.host) && !extraOrder.contains(tunnel.host) {
            extraOrder.append(tunnel.host)
        }
        for destination in extraOrder {
            let children = tunnels.filter { $0.host == destination }.map {
                PortmanForwardChild(spec: PortmanForwardSpec(remotePort: $0.remotePort, localPort: $0.localPort), tunnel: $0)
            }
            groups.append(PortmanHostGroup(host: PortmanHost(destination: destination, mode: .forward),
                                           saved: false, children: children))
        }
        return groups
    }
}

/// The saved host list. Every change saves and tells the server monitor which hosts to watch.
@Observable
@MainActor
final class PortmanHostList {
    /// Unit-test hosts share the app's preferences, so they get a separate suite.
    static let shared = PortmanHostList(defaults: AppRuntime.isRunningUnitTests
        ? UserDefaults(suiteName: "com.surajmandal.macpowertoys.unit-tests") ?? .standard : .standard)

    private(set) var hosts: [PortmanHost]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (([PortmanHost]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hosts = PortmanHostStore.load(defaults)
    }

    func host(_ destination: String) -> PortmanHost? { hosts.first { $0.destination == destination } }

    @discardableResult
    func add(_ destination: String, mode: PortmanHostMode) -> Bool {
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PortmanSSHHost.isValid(destination) else { return false }
        if let index = hosts.firstIndex(where: { $0.destination == destination }) {
            hosts[index].mode = mode
        } else {
            hosts.append(PortmanHost(destination: destination, mode: mode))
        }
        commit()
        return true
    }

    func setMode(_ mode: PortmanHostMode, for destination: String) {
        guard let index = hosts.firstIndex(where: { $0.destination == destination }) else { return }
        hosts[index].mode = mode
        commit()
    }

    func remove(_ destination: String) {
        hosts.removeAll { $0.destination == destination }
        commit()
    }

    /// Saves a started forward under its host. A monitor-only host becomes Both; a new host is Forward ports.
    func recordForward(host destination: String, remotePort: UInt16, localPort: UInt16) {
        guard PortmanSSHHost.isValid(destination) else { return }
        let spec = PortmanForwardSpec(remotePort: remotePort, localPort: localPort)
        if let index = hosts.firstIndex(where: { $0.destination == destination }) {
            hosts[index].forwards.removeAll { $0.localPort == localPort }
            hosts[index].forwards.append(spec)
            if hosts[index].mode == .monitor { hosts[index].mode = .both }
        } else {
            hosts.append(PortmanHost(destination: destination, mode: .forward, forwards: [spec]))
        }
        commit()
    }

    func removeForward(host destination: String, localPort: UInt16) {
        guard let index = hosts.firstIndex(where: { $0.destination == destination }) else { return }
        hosts[index].forwards.removeAll { $0.localPort == localPort }
        commit()
    }

    private func commit() {
        hosts = PortmanHostStore.normalized(hosts)
        PortmanHostStore.save(hosts, defaults)
        onChange?(hosts)
    }
}
