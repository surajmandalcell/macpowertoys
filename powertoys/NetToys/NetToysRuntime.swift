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

    static func active() -> LocalIPv4Network? {
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
        return candidates.sorted { preference($0.interfaceName) < preference($1.interfaceName) }.first
    }

    private static func preference(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        if name.hasPrefix("bridge") { return 2 }
        return 3
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

nonisolated struct SSHAnchorConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var isEnabled: Bool
    var hostAlias: String
    var hostName: String
    var port: UInt16
    var identity: AnchorIdentity

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        hostAlias: String,
        hostName: String,
        port: UInt16,
        identity: AnchorIdentity
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.hostAlias = hostAlias
        self.hostName = hostName
        self.port = port
        self.identity = identity
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

    init(
        probeInterval: TimeInterval = 2.5,
        anchors: [SSHAnchorConfiguration] = [],
        recordsNetworkHistory: Bool = true
    ) {
        self.probeInterval = min(max(probeInterval, 2), 3)
        self.anchors = Array(anchors.prefix(16))
        self.recordsNetworkHistory = recordsNetworkHistory
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            probeInterval: try values.decode(TimeInterval.self, forKey: .probeInterval),
            anchors: try values.decode([SSHAnchorConfiguration].self, forKey: .anchors),
            recordsNetworkHistory: try values.decode(Bool.self, forKey: .recordsNetworkHistory)
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

nonisolated struct NetworkHistory: Codable, Equatable, Sendable {
    var events: [NetworkTransitionEvent]

    init(events: [NetworkTransitionEvent] = [], limit: Int = 500) {
        self.events = Array(events.suffix(max(1, limit)))
    }

    mutating func append(_ event: NetworkTransitionEvent, limit: Int = 500) {
        events.append(event)
        if events.count > limit { events.removeFirst(events.count - limit) }
    }
}

nonisolated enum SSHAnchorRuntimeState: String, Codable, Sendable {
    case idle
    case healthy
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
        guard let components else { return networkID }
        return [ssid, components.0, components.1].compactMap { $0 }.joined(separator: " | ")
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
              let value = try? JSONDecoder().decode(NetworkHistory.self, from: data)
        else { return NetworkHistory() }
        return value
    }

    static func saveHistory(_ history: NetworkHistory) throws {
        try FileManager.default.createDirectory(at: NetToysPaths.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: NetToysPaths.history, options: .atomic)
    }
}
