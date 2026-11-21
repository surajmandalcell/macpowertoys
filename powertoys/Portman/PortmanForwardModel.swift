import Foundation

/// Why a forward is down, in plain words, read from what ssh printed when the tunnel ended.
nonisolated enum PortmanForwardFailure: Equatable, Sendable {
    case portInUse, authFailed, hostOffline, hostKeyChanged, portDidNotOpen, tunnelClosed

    init(message: String) {
        let text = message.lowercased()
        func has(_ parts: String...) -> Bool { parts.contains { text.contains($0) } }
        if has("address already in use", "cannot listen", "could not request local forwarding", "bind") { self = .portInUse }
        else if PortmanScanner.passwordAvailable(in: message) || has("permission denied", "authentication") { self = .authFailed }
        else if has("host key", "host identification") { self = .hostKeyChanged }
        else if has("could not resolve", "connection refused", "timed out", "no route", "network is unreachable") { self = .hostOffline }
        else if has("did not open local port") { self = .portDidNotOpen }
        else { self = .tunnelClosed }
    }

    var label: String {
        switch self {
        case .portInUse: "Port in use"
        case .authFailed: "Auth failed"
        case .hostOffline: "Host offline"
        case .hostKeyChanged: "Host key changed"
        case .portDidNotOpen: "Port did not open"
        case .tunnelClosed: "Tunnel closed"
        }
    }
}

/// The state a forward row shows.
nonisolated enum PortmanForwardHealth: Equatable, Sendable {
    case connecting, forwarding, stopped, failed(PortmanForwardFailure)

    init(_ tunnel: PortmanTunnel?) {
        switch tunnel?.state {
        case nil: self = .stopped
        case .connecting: self = .connecting
        case .running: self = .forwarding
        case .failed(let message): self = .failed(PortmanForwardFailure(message: message))
        }
    }

    var label: String {
        switch self {
        case .connecting: "Connecting"
        case .forwarding: "Forwarding"
        case .stopped: "Stopped"
        case .failed(let failure): failure.label
        }
    }

    /// Down rows get the re-forward button, and make the host card show Reconnect all.
    var isDown: Bool {
        switch self { case .stopped, .failed: true; case .connecting, .forwarding: false }
    }
}

/// What re-forwarding one row does: ask for the SSH password first, or stop the dead tunnel and start it again.
nonisolated enum PortmanForwardRetry: Equatable, Sendable {
    case askPassword(tunnel: UUID)
    case restart(stop: UUID?, host: String, remotePort: UInt16, localPort: UInt16)

    static func plan(host: String, child: PortmanForwardChild) -> PortmanForwardRetry? {
        guard PortmanForwardHealth(child.tunnel).isDown else { return nil }
        if let tunnel = child.tunnel, case .failed(let message) = tunnel.state, PortmanScanner.passwordAvailable(in: message) {
            return .askPassword(tunnel: tunnel.id)
        }
        return .restart(stop: child.tunnel?.id, host: host, remotePort: child.spec.remotePort, localPort: child.spec.localPort)
    }

    /// Reconnect all: every down forward of the host. An auth failure asks once, and `afterPassword` then
    /// restarts every failed tunnel of the host.
    static func plan(group: PortmanHostGroup) -> [PortmanForwardRetry] {
        let steps = group.children.compactMap { plan(host: group.host.destination, child: $0) }
        if let ask = steps.first(where: { if case .askPassword = $0 { true } else { false } }) { return [ask] }
        return steps
    }

    /// After the password sheet: restart every failed tunnel of the host with the new password.
    static func afterPassword(host: String, tunnels: [PortmanTunnel]) -> [PortmanForwardRetry] {
        tunnels.compactMap { tunnel in
            guard tunnel.host == host, case .failed = tunnel.state else { return nil }
            return .restart(stop: tunnel.id, host: host, remotePort: tunnel.remotePort, localPort: tunnel.localPort)
        }
    }

    /// Runs the steps through the given seams: the panel passes the service and its password prompt.
    static func run(_ steps: [PortmanForwardRetry], stop: (UUID) -> Void,
                    forward: (String, UInt16, UInt16) -> Bool, askPassword: (UUID) -> Void) {
        for step in steps {
            switch step {
            case .askPassword(let tunnel): askPassword(tunnel)
            case .restart(let id, let host, let remotePort, let localPort):
                if let id { stop(id) }
                _ = forward(host, remotePort, localPort)
            }
        }
    }
}

/// The host card's readings, drawn from the monitor's state: caption, health, the row's CPU line and memory,
/// and the four chart tiles. Pure, so the mapping is tested without a view.
nonisolated struct PortmanHostCardModel: Equatable, Sendable {
    enum Health: Equatable, Sendable { case unmonitored, waiting, online, stale, offline(String) }
    enum Kind: Equatable, Sendable { case cpu, memory, disk, network }

    struct Tile: Equatable, Sendable {
        let kind: Kind
        let value: String
        let unit: String
        let meta: String
        let series: [Double]
        var secondary: [Double] = []
        let range: ClosedRange<Double>
    }

    /// No sample for three slow periods means the numbers on screen are old.
    static let staleAfter = PortmanServerMonitor.slowInterval * 3

    let health: Health
    let caption: String
    let memory: String?
    let sparkline: [Double]
    let tiles: [Tile]

    var online: Bool? {
        switch health { case .unmonitored: nil; case .online, .stale: true; case .waiting, .offline: false }
    }

    init(monitors: Bool, forwards: Int, state: PortmanServerState?, now: Date) {
        let forwardsText = forwards == 1 ? "1 forward" : "\(forwards) forwards"
        guard monitors else {
            health = .unmonitored; caption = forwardsText; memory = nil; sparkline = []; tiles = []
            return
        }
        let state = state ?? PortmanServerState()
        let samples = state.history
        sparkline = Self.clean(samples.suffix(14).map { $0.cpuPercent ?? .nan })
        tiles = samples.isEmpty ? [] : Self.tiles(samples)
        let latest = state.latest ?? samples.last
        memory = latest?.memoryUsed.map(PortmanServerSample.bytes)
        switch state.status {
        case .waiting:
            health = .waiting; caption = "Connecting"
        case .failed(let failure):
            health = .offline(failure.label)
            caption = state.lastSeen.map { "no answer for \(PortmanServerSample.duration(max(60, now.timeIntervalSince($0))))" }
                ?? "\(failure.label) · never seen"
        case .online:
            if let lastSeen = state.lastSeen, now.timeIntervalSince(lastSeen) > Self.staleAfter {
                health = .stale; caption = "last data \(PortmanServerState.ago(now.timeIntervalSince(lastSeen)))"
            } else {
                health = .online
                var parts: [String] = []
                if let uptime = latest?.uptime { parts.append("up \(PortmanServerSample.duration(uptime))") }
                if let load = latest?.load?.first, load.isFinite { parts.append(String(format: "load %.2f", load)) }
                caption = parts.isEmpty ? forwardsText : parts.joined(separator: " · ")
            }
        }
    }

    /// Non-finite values become gaps the chart skips; negative ones clamp to 0.
    static func clean(_ values: [Double]) -> [Double] { values.map { $0.isFinite ? max(0, $0) : .nan } }

    /// A rate chart's top: 15% over the highest finite value, never 0, so all zeros draw a flat floor line.
    static func ceiling(_ series: [Double]...) -> Double {
        let peak = series.joined().filter(\.isFinite).max() ?? 0
        return peak > 0 ? peak * 1.15 : 1
    }

    private static func percent(_ used: UInt64?, _ total: UInt64?) -> Double {
        guard let used, let total, total > 0 else { return .nan }
        return Double(used) / Double(total) * 100
    }

    /// "9.8 GB" becomes ("9.8", "GB"), so the unit draws smaller.
    static func split(_ text: String) -> (String, String) {
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }

    private static func tiles(_ samples: [PortmanServerSample]) -> [Tile] {
        let last = samples.last
        let cpu = clean(samples.map { $0.cpuPercent ?? .nan })
        let memory = clean(samples.map { percent($0.memoryUsed, $0.memoryTotal) })
        let disk = clean(samples.map { percent($0.diskUsed, $0.diskTotal) })
        let down = clean(samples.map { $0.receiveRate ?? .nan })
        let up = clean(samples.map { $0.sendRate ?? .nan })
        let cpuValue = last?.cpuPercent.flatMap { $0.isFinite ? String(Int($0.rounded())) : nil } ?? "–"
        let memoryText = split(last?.memoryUsed.map(PortmanServerSample.bytes) ?? "–")
        let diskValue = disk.last.flatMap { $0.isFinite ? String(Int($0.rounded())) : nil } ?? "–"
        let downText = split(last?.receiveRate.flatMap { $0.isFinite ? PortmanServerSample.bytes(UInt64(min(max(0, $0), 1e18))) + "/s" : nil } ?? "–")
        let upText = last?.sendRate.flatMap { $0.isFinite ? "↑ " + PortmanServerSample.bytes(UInt64(min(max(0, $0), 1e18))) + "/s" : nil } ?? ""
        let load = last?.load?.first.flatMap { $0.isFinite ? String(format: "load %.2f", $0) : nil } ?? ""
        return [
            Tile(kind: .cpu, value: cpuValue, unit: "%", meta: load, series: cpu, range: 0...100),
            Tile(kind: .memory, value: memoryText.0, unit: memoryText.1,
                 meta: last?.memoryTotal.map(PortmanServerSample.bytes) ?? "", series: memory, range: 0...100),
            Tile(kind: .disk, value: diskValue, unit: "%", meta: last?.diskTotal.map(PortmanServerSample.bytes) ?? "",
                 series: disk, range: 0...100),
            Tile(kind: .network, value: downText.0, unit: downText.1, meta: upText, series: down, secondary: up,
                 range: 0...ceiling(down, up)),
        ]
    }
}
