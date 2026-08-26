import Darwin
import Foundation
@preconcurrency import CoreWLAN

nonisolated struct LocalIPv4Network: Equatable, Sendable {
    enum NetworkError: LocalizedError {
        case tooManyTargets(Int)

        var errorDescription: String? {
            switch self {
            case .tooManyTargets(let limit): "The local subnet contains more than \(limit) usable addresses."
            }
        }
    }

    let interfaceName: String
    let address: IPv4Address
    let netmask: IPv4Address
    let prefixLength: Int

    init?(interfaceName: String, address: String, netmask: String) {
        guard let address = IPv4Address(address), let netmask = IPv4Address(netmask) else { return nil }
        let inverted = ~netmask.rawValue
        guard inverted &+ 1 != 0, (inverted & (inverted &+ 1)) == 0 else { return nil }
        self.interfaceName = interfaceName
        self.address = address
        self.netmask = netmask
        prefixLength = netmask.rawValue.nonzeroBitCount
    }

    var cidr: String {
        "\(IPv4Address(rawValue: address.rawValue & netmask.rawValue))/\(prefixLength)"
    }

    func contains(_ candidate: String) -> Bool {
        guard let candidate = IPv4Address(candidate) else { return false }
        return candidate.rawValue & netmask.rawValue == address.rawValue & netmask.rawValue
    }

    func targets(limit: Int) throws -> [IPv4Address] {
        let hostBits = 32 - prefixLength
        let total = UInt64(1) << UInt64(hostBits)
        let excluded = hostBits >= 2 ? 2 : 0
        let usable = total - UInt64(excluded)
        guard usable <= UInt64(limit) else { throw NetworkError.tooManyTargets(limit) }
        let network = address.rawValue & netmask.rawValue
        let first = network &+ UInt32(excluded == 2 ? 1 : 0)
        let last = network &+ UInt32(total - 1 - UInt64(excluded == 2 ? 1 : 0))
        return (first...last).map(IPv4Address.init(rawValue:))
    }

    static func active(preferredInterfaceName: String? = nil) -> LocalIPv4Network? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var candidates: [LocalIPv4Network] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            defer { current = item.pointee.ifa_next }
            let flags = Int32(item.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  item.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET),
                  let address = numericAddress(item.pointee.ifa_addr),
                  let mask = numericAddress(item.pointee.ifa_netmask)
            else { continue }
            let name = String(cString: item.pointee.ifa_name)
            guard !name.hasPrefix("awdl"), !name.hasPrefix("llw"), !name.hasPrefix("utun"),
                  let network = LocalIPv4Network(interfaceName: name, address: address, netmask: mask)
            else { continue }
            candidates.append(network)
        }
        return candidates.sorted {
            preference($0.interfaceName, preferred: preferredInterfaceName)
                < preference($1.interfaceName, preferred: preferredInterfaceName)
        }.first
    }

    private static func preference(_ name: String, preferred: String?) -> Int {
        if name == preferred { return 0 }
        if name == "en0" { return 1 }
        if name.hasPrefix("en") { return 2 }
        if name.hasPrefix("bridge") { return 3 }
        return 4
    }

    private static func numericAddress(_ pointer: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let pointer else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        return pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { address in
            var raw = address.pointee.sin_addr
            guard inet_ntop(AF_INET, &raw, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            return String(cString: buffer)
        }
    }
}

nonisolated struct TailscalePeer: Equatable, Identifiable, Sendable {
    var id: String { nodeID }
    let nodeID: String
    let hostName: String
    let dnsName: String
    let ipAddress: String
    let isOnline: Bool
}

nonisolated struct TailscaleFallbackConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    let nodeID: String
    let hostName: String
    let ipAddress: String
}

nonisolated enum TailscalePeerCatalog {
    enum CatalogError: LocalizedError {
        case unavailable
        case notRunning
        case invalidStatus
        case peerNotFound

        var errorDescription: String? {
            switch self {
            case .unavailable: "Tailscale is not installed or its status is unavailable."
            case .notRunning: "Connect Tailscale before enabling this fallback."
            case .invalidStatus: "Tailscale returned an unreadable device list."
            case .peerNotFound:
                "The saved Tailscale device is unavailable. Turn Tailscale off and on to choose it again."
            }
        }
    }

    private struct Status: Decodable {
        let backendState: String
        let peer: [String: Peer]?

        enum CodingKeys: String, CodingKey {
            case backendState = "BackendState"
            case peer = "Peer"
        }
    }

    private struct Peer: Decodable {
        let nodeID: String?
        let hostName: String?
        let dnsName: String?
        let tailscaleIPs: [String]?
        let isOnline: Bool?

        enum CodingKeys: String, CodingKey {
            case nodeID = "ID"
            case hostName = "HostName"
            case dnsName = "DNSName"
            case tailscaleIPs = "TailscaleIPs"
            case isOnline = "Online"
        }
    }

    static func load() async throws -> [TailscalePeer] {
        try await Task.detached(priority: .utility) {
            let paths = [
                "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
                "/opt/homebrew/bin/tailscale",
                "/usr/local/bin/tailscale",
            ]
            guard let path = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
                throw CatalogError.unavailable
            }
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["status", "--json"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw CatalogError.unavailable }
                return try parse(data)
            } catch let error as CatalogError {
                throw error
            } catch {
                throw CatalogError.unavailable
            }
        }.value
    }

    static func parse(_ data: Data) throws -> [TailscalePeer] {
        let status: Status
        do {
            status = try JSONDecoder().decode(Status.self, from: data)
        } catch {
            throw CatalogError.invalidStatus
        }
        guard status.backendState == "Running" else { throw CatalogError.notRunning }
        let peers = status.peer.map { Array($0.values) } ?? []
        return peers.compactMap { peer in
            guard let nodeID = peer.nodeID,
                  let ipAddress = peer.tailscaleIPs?.first(where: isTailscaleAddress),
                  let hostName = [peer.hostName, peer.dnsName]
                    .compactMap({ $0 })
                    .map(AnchorMatcher.hostnameLabel)
                    .first(where: { !$0.isEmpty })
            else {
                return nil
            }
            return TailscalePeer(
                nodeID: nodeID,
                hostName: hostName,
                dnsName: peer.dnsName ?? "",
                ipAddress: ipAddress,
                isOnline: peer.isOnline ?? false
            )
        }.sorted { $0.hostName.localizedCaseInsensitiveCompare($1.hostName) == .orderedAscending }
    }

    static func isTailscaleAddress(_ value: String) -> Bool {
        guard let address = IPv4Address(value) else { return false }
        return address.rawValue & 0xFFC0_0000 == 0x6440_0000
    }

    static func exactMatch(labels: [String], peers: [TailscalePeer]) -> TailscalePeer? {
        let expected = Set(labels.map(AnchorMatcher.hostnameLabel).filter { !$0.isEmpty })
        let matches = peers.filter {
            expected.contains(AnchorMatcher.hostnameLabel($0.hostName))
                || expected.contains(AnchorMatcher.hostnameLabel($0.dnsName))
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func endpoint(
        nodeID: String,
        peers: [TailscalePeer],
        isEnabled: Bool = true
    ) -> TailscaleFallbackConfiguration? {
        guard let peer = peers.first(where: { $0.nodeID == nodeID }) else { return nil }
        return TailscaleFallbackConfiguration(
            isEnabled: isEnabled,
            nodeID: peer.nodeID,
            hostName: peer.hostName,
            ipAddress: peer.ipAddress
        )
    }
}

nonisolated struct SSHAnchorConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var isEnabled: Bool
    var hostAlias: String
    var hostName: String
    var port: UInt16
    var identity: AnchorIdentity
    var localHostName: String?
    var tailscaleFallback: TailscaleFallbackConfiguration?

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        hostAlias: String,
        hostName: String,
        port: UInt16,
        identity: AnchorIdentity,
        localHostName: String? = nil,
        tailscaleFallback: TailscaleFallbackConfiguration? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.hostAlias = hostAlias
        self.hostName = hostName
        self.port = port
        self.identity = identity
        self.localHostName = localHostName
        self.tailscaleFallback = tailscaleFallback
    }

    var route: SSHAnchorRoute {
        tailscaleFallback?.ipAddress == hostName ? .tailscale : .local
    }

    var knownHostsAlias: String {
        "macpowertoys-\(id.uuidString.lowercased())"
    }
}

nonisolated enum SSHAnchorRoute: Equatable, Sendable {
    case local
    case tailscale
}

nonisolated enum SSHAnchorRouteAction: Equatable, Sendable {
    case none
    case useTailscale
    case useLocal
}

nonisolated struct SSHAnchorRouteMonitor: Sendable {
    static let fallbackFailureCount = 2
    static let restoreSuccessCount = 3
    static let minimumTailscaleDwell: TimeInterval = 30

    private var localFailures = 0
    private var localSuccesses = 0
    private var tailscaleSince: Date?

    mutating func observe(
        route: SSHAnchorRoute,
        localIsOpen: Bool,
        at date: Date
    ) -> SSHAnchorRouteAction {
        switch route {
        case .local:
            localSuccesses = 0
            tailscaleSince = nil
            if localIsOpen {
                localFailures = 0
                return .none
            }
            localFailures = min(localFailures + 1, Self.fallbackFailureCount)
            return localFailures >= Self.fallbackFailureCount ? .useTailscale : .none
        case .tailscale:
            localFailures = 0
            if tailscaleSince == nil { tailscaleSince = date }
            if localIsOpen {
                localSuccesses = min(localSuccesses + 1, Self.restoreSuccessCount)
            } else {
                localSuccesses = 0
            }
            guard localSuccesses >= Self.restoreSuccessCount,
                  date.timeIntervalSince(tailscaleSince ?? date) >= Self.minimumTailscaleDwell
            else { return .none }
            return .useLocal
        }
    }

    mutating func didSwitch(to route: SSHAnchorRoute, at date: Date) {
        localFailures = 0
        localSuccesses = 0
        tailscaleSince = route == .tailscale ? date : nil
    }
}

nonisolated enum SSHAnchorRecovery {
    static func resolve(
        anchor: SSHAnchorConfiguration,
        scanResults: [NetToysScanResult]
    ) -> SSHAnchorConfiguration? {
        let candidates = scanResults
            .filter { $0.openPorts.contains(anchor.port) }
            .map {
                AnchorCandidate(
                    ip: $0.address.description,
                    macAddress: $0.macAddress,
                    hostname: $0.hostname
                )
            }
        guard let match = AnchorMatcher.match(candidates: candidates, identity: anchor.identity) else { return nil }
        var recovered = anchor
        recovered.hostName = match.ip
        if case .randomizedMAC(let hostname, var learnedMACs) = recovered.identity,
           let mac = match.macAddress {
            learnedMACs.insert(AnchorMatcher.normalizedMAC(mac))
            recovered.identity = .randomizedMAC(hostname: hostname, learnedMACs: learnedMACs)
        }
        return recovered
    }
}

nonisolated struct NetToysConfiguration: Codable, Equatable, Sendable {
    enum ConfigurationError: LocalizedError {
        case anchorNotFound

        var errorDescription: String? { "The SSH Anchor no longer exists." }
    }

    var probeInterval: TimeInterval
    var anchors: [SSHAnchorConfiguration]
    var recordsNetworkHistory: Bool
    var wifiPriority: WiFiPriorityConfiguration

    init(
        probeInterval: TimeInterval = 2.5,
        anchors: [SSHAnchorConfiguration] = [],
        recordsNetworkHistory: Bool = true,
        wifiPriority: WiFiPriorityConfiguration = WiFiPriorityConfiguration()
    ) {
        self.probeInterval = min(max(probeInterval, 2), 3)
        self.anchors = Array(anchors.prefix(16))
        self.recordsNetworkHistory = recordsNetworkHistory
        self.wifiPriority = wifiPriority
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            probeInterval: try values.decode(TimeInterval.self, forKey: .probeInterval),
            anchors: try values.decode([SSHAnchorConfiguration].self, forKey: .anchors),
            recordsNetworkHistory: try values.decode(Bool.self, forKey: .recordsNetworkHistory),
            wifiPriority: try values.decodeIfPresent(
                WiFiPriorityConfiguration.self,
                forKey: .wifiPriority
            ) ?? WiFiPriorityConfiguration()
        )
    }

    func replacingAnchor(_ anchor: SSHAnchorConfiguration) throws -> Self {
        guard let index = anchors.firstIndex(where: { $0.id == anchor.id }) else {
            throw ConfigurationError.anchorNotFound
        }
        var copy = self
        copy.anchors[index] = anchor
        return copy
    }
}

nonisolated struct WiFiPriorityConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var outageThreshold: TimeInterval
    var ssids: [String]

    init(
        isEnabled: Bool = false,
        outageThreshold: TimeInterval = 10,
        ssids: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.outageThreshold = min(max(outageThreshold, 5), 60)
        self.ssids = Array(
            ssids.compactMap(NetworkIdentity.normalizedSSID).uniqued().prefix(16)
        )
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try values.decode(Bool.self, forKey: .isEnabled),
            outageThreshold: try values.decode(TimeInterval.self, forKey: .outageThreshold),
            ssids: try values.decode([String].self, forKey: .ssids)
        )
    }
}

nonisolated struct WiFiFailoverMonitor: Sendable {
    private(set) var outageBeganAt: Date?
    private(set) var lastAttemptAt: Date?

    mutating func shouldAttempt(
        isFailure: Bool,
        threshold: TimeInterval,
        at date: Date
    ) -> Bool {
        guard isFailure else {
            outageBeganAt = nil
            lastAttemptAt = nil
            return false
        }
        guard let outageBeganAt else {
            self.outageBeganAt = date
            return false
        }
        guard date.timeIntervalSince(outageBeganAt) >= threshold else { return false }
        return lastAttemptAt.map { date.timeIntervalSince($0) >= 30 } ?? true
    }

    mutating func didAttempt(at date: Date) {
        lastAttemptAt = date
    }

    static func nextSSID(
        after currentSSID: String?,
        priorities: [String],
        availableSSIDs: Set<String>
    ) -> String? {
        guard !priorities.isEmpty else { return nil }
        guard let currentSSID,
              let index = priorities.firstIndex(of: currentSSID)
        else { return priorities.first(where: availableSSIDs.contains) }
        let candidates = priorities[(index + 1)...] + priorities[..<index]
        return candidates.first(where: availableSSIDs.contains)
    }
}

nonisolated struct NetworkHistory: Codable, Equatable, Sendable {
    var events: [NetworkTransitionEvent]

    init(events: [NetworkTransitionEvent] = [], limit: Int = 500) {
        self.events = Array(events.suffix(max(1, limit)))
    }

    mutating func append(_ event: NetworkTransitionEvent, limit: Int = 500) {
        events.append(event)
        if events.count > limit { events.removeFirst(events.count - limit) }
    }

    mutating func migrateLegacySSIDs(currentNetwork: NetworkRuntimeSnapshot? = nil) -> Bool {
        var ssidsByNetworkID: [String: Set<String>] = [:]
        for event in events {
            if let ssid = NetworkIdentity.normalizedSSID(event.ssid) {
                ssidsByNetworkID[event.networkID, default: []].insert(ssid)
            }
        }
        if let currentNetwork,
           let ssid = NetworkIdentity.normalizedSSID(currentNetwork.ssid) {
            ssidsByNetworkID[currentNetwork.networkID, default: []].insert(ssid)
        }
        let unambiguousSSIDs = ssidsByNetworkID.compactMapValues { values in
            values.count == 1 ? values.first : nil
        }
        let ssidsByFallbackName = Dictionary(grouping: unambiguousSSIDs) {
            NetworkIdentity(networkID: $0.key, ssid: nil).displayName
        }.compactMapValues { entries in
            let values = Set(entries.map { $0.value })
            return values.count == 1 ? values.first : nil
        }
        var changed = false
        events = events.map { event in
            let ssid = event.ssid ?? unambiguousSSIDs[event.networkID]
            let changes = event.changes.map { change in
                guard case .network(let from, let to) = change else { return change }
                return .network(
                    from: ssidsByFallbackName[from] ?? from,
                    to: ssidsByFallbackName[to] ?? to
                )
            }
            guard ssid != event.ssid || changes != event.changes else { return event }
            changed = true
            return NetworkTransitionEvent(
                networkID: event.networkID,
                ssid: ssid,
                date: event.date,
                changes: changes
            )
        }
        return changed
    }
}

nonisolated enum SSHAnchorRuntimeState: String, Codable, Sendable {
    case idle
    case healthy
    case fallback
    case fallbackUnavailable
    case scanning
    case recovered
    case notFound
    case ambiguous
    case unavailable
    case error
}

nonisolated struct SSHAnchorStatus: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { anchorID }
    let anchorID: UUID
    let state: SSHAnchorRuntimeState
    let currentHostName: String
    let lastCheck: Date
    let message: String?
}

nonisolated struct NetToysHelperStatus: Codable, Equatable, Sendable {
    let version: Int
    let heartbeat: Date
    let anchors: [SSHAnchorStatus]
    var network: NetworkRuntimeSnapshot? = nil
    var sourceCommit: String? = nil
    var ssidAccess: NetToysSSIDAccessState? = nil
    var wifiFailover: WiFiFailoverStatus? = nil
}

nonisolated enum NetToysSSIDAccessState: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case allowed
}

nonisolated enum WiFiFailoverState: String, Codable, Equatable, Sendable {
    case monitoring
    case waiting
    case switching
    case failed
}

nonisolated struct WiFiFailoverStatus: Codable, Equatable, Sendable {
    let state: WiFiFailoverState
    let message: String
    let updatedAt: Date
}

nonisolated struct NetworkRuntimeSnapshot: Codable, Equatable, Sendable {
    let networkID: String
    let ssid: String?
    let gateway: NetworkReachability
    let internet: NetworkReachability
    let checkedAt: Date

    init(
        networkID: String,
        ssid: String? = nil,
        gateway: NetworkReachability,
        internet: NetworkReachability,
        checkedAt: Date
    ) {
        self.networkID = networkID
        self.ssid = ssid
        self.gateway = gateway
        self.internet = internet
        self.checkedAt = checkedAt
    }

    var displayName: String { NetworkIdentity(networkID: networkID, ssid: ssid).displayName }
}

nonisolated struct NetworkIdentity: Equatable, Sendable {
    let networkID: String
    let ssid: String?

    init(networkID: String, ssid: String?) {
        self.networkID = networkID
        self.ssid = Self.normalizedSSID(ssid)
    }

    var interfaceName: String? { components?.0 }
    var gateway: String? { components?.1 }

    var displayName: String {
        guard networkID != "disconnected" else { return "Disconnected" }
        if let ssid { return ssid }
        guard let components else { return networkID }
        return [components.0, components.1].joined(separator: " | ")
    }

    static func normalizedSSID(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private var components: (String, String)? {
        let parts = networkID.split(separator: "|", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
}

nonisolated enum NetworkSSID {
    static func isWiFi(interfaceName: String) -> Bool {
        CWWiFiClient.shared().interface(withName: interfaceName) != nil
    }

    static func current(interfaceName: String) -> String? {
        NetworkIdentity.normalizedSSID(
            CWWiFiClient.shared().interface(withName: interfaceName)?.ssid()
        )
    }
}

nonisolated enum WiFiNetworkController {
    enum WiFiError: LocalizedError {
        case interfaceUnavailable
        case joinFailed(String)

        var errorDescription: String? {
            switch self {
            case .interfaceUnavailable: "No Wi-Fi interface is available."
            case .joinFailed(let message): message
            }
        }
    }

    static func preferredNetworks() async -> [String] {
        guard let interfaceName = CWWiFiClient.shared().interface()?.interfaceName else { return [] }
        let result = await runNetworkSetup(["-listpreferredwirelessnetworks", interfaceName])
        guard result.status == 0 else { return [] }
        return parsePreferredNetworks(result.output)
    }

    static func availableSSIDs() async -> Set<String> {
        await Task.detached(priority: .utility) {
            guard let interface = CWWiFiClient.shared().interface(),
                  let networks = try? interface.scanForNetworks(withName: nil)
            else { return [] }
            return Set(networks.compactMap { NetworkIdentity.normalizedSSID($0.ssid) })
        }.value
    }

    static func join(_ ssid: String) async throws {
        guard let interfaceName = CWWiFiClient.shared().interface()?.interfaceName else {
            throw WiFiError.interfaceUnavailable
        }
        let result = await runNetworkSetup(["-setairportnetwork", interfaceName, ssid])
        guard result.status == 0 else {
            throw WiFiError.joinFailed(
                NetworkIdentity.normalizedSSID(result.output) ?? "macOS could not join \(ssid)."
            )
        }
    }

    static func parsePreferredNetworks(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).dropFirst().compactMap {
            NetworkIdentity.normalizedSSID(String($0))
        }.uniqued()
    }

    private static func runNetworkSetup(_ arguments: [String]) async -> (status: Int32, output: String) {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, String(decoding: data, as: UTF8.self))
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
    }
}

private nonisolated extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

nonisolated struct DefaultRoute: Equatable, Sendable {
    let interfaceName: String
    let gateway: String

    var networkID: String { "\(interfaceName)|\(gateway)" }

    static func parse(_ output: String) -> DefaultRoute? {
        var interfaceName: String?
        var gateway: String?
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard fields.count == 2 else { continue }
            if fields[0] == "interface" { interfaceName = fields[1] }
            if fields[0] == "gateway" { gateway = fields[1] }
        }
        guard let interfaceName, let gateway, IPv4Address(gateway) != nil else { return nil }
        return DefaultRoute(interfaceName: interfaceName, gateway: gateway)
    }

    static func load() async -> DefaultRoute? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/sbin/route")
            process.arguments = ["-n", "get", "default"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                return parse(String(decoding: data, as: UTF8.self))
            } catch {
                return nil
            }
        }.value
    }
}

nonisolated enum NetToysPaths {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPowerToys/NetToys", isDirectory: true)
    }

    static var configuration: URL { directory.appendingPathComponent("configuration.json") }
    static var helperStatus: URL { directory.appendingPathComponent("helper-status.json") }
    static var history: URL { directory.appendingPathComponent("history.json") }
    static var scanHistory: URL { directory.appendingPathComponent("scan-history.json") }
    static var scannerAnnotations: URL { directory.appendingPathComponent("scanner-annotations.json") }
    static var favoriteTargets: URL { directory.appendingPathComponent("favorite-targets.json") }
    static var backups: URL { directory.appendingPathComponent("SSH Backups", isDirectory: true) }
}

nonisolated enum NetToysConfigurationStore {
    static func load() -> NetToysConfiguration {
        guard let data = try? Data(contentsOf: NetToysPaths.configuration),
              let value = try? JSONDecoder().decode(NetToysConfiguration.self, from: data)
        else { return NetToysConfiguration() }
        return value
    }

    static func save(_ configuration: NetToysConfiguration) throws {
        try FileManager.default.createDirectory(at: NetToysPaths.directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: NetToysPaths.configuration, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: NetToysPaths.configuration.path)
    }

    static func status() -> NetToysHelperStatus? {
        guard let data = try? Data(contentsOf: NetToysPaths.helperStatus) else { return nil }
        return try? JSONDecoder().decode(NetToysHelperStatus.self, from: data)
    }

    static func saveStatus(_ status: NetToysHelperStatus) throws {
        try FileManager.default.createDirectory(at: NetToysPaths.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(status).write(to: NetToysPaths.helperStatus, options: .atomic)
    }

    static func history() -> NetworkHistory {
        guard let data = try? Data(contentsOf: NetToysPaths.history),
              var value = try? JSONDecoder().decode(NetworkHistory.self, from: data)
        else { return NetworkHistory() }
        if value.migrateLegacySSIDs(currentNetwork: status()?.network) {
            try? saveHistory(value)
        }
        return value
    }

    static func saveHistory(_ history: NetworkHistory) throws {
        try FileManager.default.createDirectory(at: NetToysPaths.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: NetToysPaths.history, options: .atomic)
    }
}
