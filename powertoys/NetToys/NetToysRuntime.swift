import Darwin
import Foundation

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

nonisolated struct NetToysConfiguration: Codable, Equatable, Sendable {
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
}

nonisolated enum NetToysPaths {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPowerToys/NetToys", isDirectory: true)
    }

    static var configuration: URL { directory.appendingPathComponent("configuration.json") }
    static var helperStatus: URL { directory.appendingPathComponent("helper-status.json") }
    static var history: URL { directory.appendingPathComponent("history.json") }
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
}
