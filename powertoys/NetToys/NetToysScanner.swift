import Darwin
import Foundation

nonisolated enum PortList {
    enum ParseError: LocalizedError {
        case invalid(String)
        case tooMany(Int)

        var errorDescription: String? {
            switch self {
            case .invalid(let value): "Invalid TCP port: \(value)"
            case .tooMany(let limit): "Select no more than \(limit) TCP ports."
            }
        }
    }

    static func parse(_ input: String, limit: Int = 4_096) throws -> [UInt16] {
        var seen = Set<UInt16>()
        var result: [UInt16] = []
        for part in input.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let text = String(part)
            if text.contains("-") {
                let bounds = text.split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2,
                      let start = UInt16(bounds[0]), start > 0,
                      let end = UInt16(bounds[1]), end >= start
                else { throw ParseError.invalid(text) }
                for port in start...end where seen.insert(port).inserted {
                    result.append(port)
                    guard result.count <= limit else { throw ParseError.tooMany(limit) }
                }
            } else {
                guard let port = UInt16(text), port > 0 else { throw ParseError.invalid(text) }
                if seen.insert(port).inserted { result.append(port) }
                guard result.count <= limit else { throw ParseError.tooMany(limit) }
            }
        }
        guard !result.isEmpty else { throw ParseError.invalid(input) }
        return result
    }
}

nonisolated enum NetToysTargetInput: Equatable, Sendable {
    case addresses([IPv4Address], port: UInt16?)
    case hostname(String, port: UInt16?)

    enum ParseError: LocalizedError, Equatable {
        case invalid(String)
        case unsupportedIPv6(String)
        case tooMany(Int)

        var errorDescription: String? {
            switch self {
            case .invalid(let value): "Invalid scan target: \(value)"
            case .unsupportedIPv6(let value): "IPv6 scanning is not supported for this target: \(value)"
            case .tooMany(let limit): "The target contains more than \(limit) addresses."
            }
        }
    }

    static func parse(_ input: String, limit: Int = 65_536) throws -> [Self] {
        let parts = input.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        guard !parts.isEmpty else { throw ParseError.invalid(input) }
        var result: [Self] = []
        var addressCount = 0
        for part in parts {
            let token = String(part)
            let (target, port) = try splitPort(token)
            if target.contains(":") { throw ParseError.unsupportedIPv6(token) }
            if let addresses = try? IPv4Targets.parse(target, limit: max(1, limit - addressCount)) {
                addressCount += addresses.count
                guard addressCount <= limit else { throw ParseError.tooMany(limit) }
                result.append(.addresses(addresses, port: port))
            } else if isHostname(target) {
                result.append(.hostname(target, port: port))
            } else {
                throw ParseError.invalid(token)
            }
        }
        return result
    }

    private static func splitPort(_ token: String) throws -> (String, UInt16?) {
        let colons = token.indices.filter { token[$0] == ":" }
        guard colons.count <= 1 else { throw ParseError.unsupportedIPv6(token) }
        guard let separator = colons.first else { return (token, nil) }
        let target = String(token[..<separator])
        let value = String(token[token.index(after: separator)...])
        guard !target.isEmpty, let port = UInt16(value), port > 0 else {
            throw ParseError.invalid(token)
        }
        return (target, port)
    }

    private static func isHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253,
              !value.contains("/"), !value.contains("-") || value.contains(where: \.isLetter)
        else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: true)
        guard !labels.isEmpty else { return false }
        return labels.allSatisfy { label in
            guard label.utf8.count <= 63,
                  label.first != "-", label.last != "-"
            else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}

nonisolated struct NetToysScanTarget: Equatable, Hashable, Sendable {
    let address: IPv4Address
    let ports: [UInt16]
}

nonisolated enum NetToysTargetResolver {
    static func resolve(
        _ input: String,
        defaultPorts: [UInt16],
        limit: Int = 65_536
    ) async throws -> [NetToysScanTarget] {
        let inputs = try NetToysTargetInput.parse(input, limit: limit)
        var order: [IPv4Address] = []
        var portsByAddress: [IPv4Address: Set<UInt16>] = [:]
        for item in inputs {
            let addresses: [IPv4Address]
            let port: UInt16?
            switch item {
            case .addresses(let values, let value):
                addresses = values
                port = value
            case .hostname(let hostname, let value):
                addresses = await HostResolver.forward(hostname)
                port = value
                guard !addresses.isEmpty else { throw NetToysTargetInput.ParseError.invalid(hostname) }
            }
            let selectedPorts = port.map { [$0] } ?? defaultPorts
            for address in addresses {
                if portsByAddress[address] == nil { order.append(address) }
                portsByAddress[address, default: []].formUnion(selectedPorts)
                guard order.count <= limit else { throw NetToysTargetInput.ParseError.tooMany(limit) }
            }
        }
        return order.map { address in
            NetToysScanTarget(address: address, ports: portsByAddress[address, default: []].sorted())
        }
    }
}

nonisolated enum TCPPortState: String, Codable, Sendable {
    case open
    case closed
    case unreachable
}

nonisolated struct TCPPortProbeResult: Equatable, Sendable {
    let state: TCPPortState
    let latencyMilliseconds: Double
}

nonisolated enum TCPPortProbe {
    static func check(host: String, port: UInt16, timeoutMilliseconds: Int) async -> TCPPortProbeResult {
        await Task.detached(priority: .userInitiated) {
            checkSynchronously(host: host, port: port, timeoutMilliseconds: timeoutMilliseconds)
        }.value
    }

    private static func checkSynchronously(
        host: String,
        port: UInt16,
        timeoutMilliseconds: Int
    ) -> TCPPortProbeResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return result(.unreachable, started: started) }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            return result(.unreachable, started: started)
        }
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            return result(.unreachable, started: started)
        }
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult == 0 { return result(.open, started: started) }
        if errno == ECONNREFUSED { return result(.closed, started: started) }
        guard errno == EINPROGRESS else { return result(.unreachable, started: started) }

        var item = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let pollResult = Darwin.poll(&item, 1, Int32(max(1, timeoutMilliseconds)))
        guard pollResult > 0 else { return result(.unreachable, started: started) }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
            return result(.unreachable, started: started)
        }
        switch socketError {
        case 0: return result(.open, started: started)
        case ECONNREFUSED: return result(.closed, started: started)
        default: return result(.unreachable, started: started)
        }
    }

    private static func result(_ state: TCPPortState, started: UInt64) -> TCPPortProbeResult {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return TCPPortProbeResult(state: state, latencyMilliseconds: elapsed)
    }
}

nonisolated struct PingProbeResult: Equatable, Sendable {
    let ttl: Int?
    let packetLossPercent: Double?
    let averageMilliseconds: Double?
}

nonisolated enum PingProbe {
    static func check(
        address: IPv4Address,
        count: Int,
        timeoutMilliseconds: Int
    ) async -> PingProbeResult? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = [
                "-n", "-c", String(min(max(count, 1), 5)),
                "-W", String(min(max(timeoutMilliseconds, 100), 5_000)),
                address.description
            ]
            process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return parse(String(decoding: data, as: UTF8.self))
            } catch {
                return nil
            }
        }.value
    }

    static func parse(_ output: String) -> PingProbeResult? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let ttl = lines.compactMap { line -> Int? in
            guard let range = line.range(of: "ttl=") else { return nil }
            return Int(line[range.upperBound...].prefix(while: \.isNumber))
        }.first
        let loss = lines.compactMap { line -> Double? in
            guard line.contains("packet loss"), let percent = line.firstIndex(of: "%") else { return nil }
            let prefix = line[..<percent]
            let value = prefix.split(whereSeparator: { $0 == " " || $0 == "," }).last
            return value.flatMap { Double($0) }
        }.first
        let average = lines.compactMap { line -> Double? in
            guard line.contains("min/avg/max"), let equals = line.firstIndex(of: "=") else { return nil }
            let values = line[line.index(after: equals)...].split(separator: "/")
            guard values.count >= 2 else { return nil }
            return Double(values[1].trimmingCharacters(in: .whitespaces))
        }.first
        guard ttl != nil || loss != nil || average != nil else { return nil }
        return PingProbeResult(ttl: ttl, packetLossPercent: loss, averageMilliseconds: average)
    }
}

nonisolated struct NetToysScanResult: Codable, Identifiable, Equatable, Sendable {
    var id: String { address.description }
    let address: IPv4Address
    let isReachable: Bool
    let responseMilliseconds: Double?
    let hostname: String?
    let macAddress: String?
    let vendor: String?
    let openPorts: [UInt16]
    let filteredPorts: [UInt16]?
    let ttl: Int?
    let packetLossPercent: Double?

    init(
        address: IPv4Address,
        isReachable: Bool,
        responseMilliseconds: Double?,
        hostname: String?,
        macAddress: String?,
        vendor: String?,
        openPorts: [UInt16],
        filteredPorts: [UInt16]? = nil,
        ttl: Int? = nil,
        packetLossPercent: Double? = nil
    ) {
        self.address = address
        self.isReachable = isReachable
        self.responseMilliseconds = responseMilliseconds
        self.hostname = hostname
        self.macAddress = macAddress
        self.vendor = vendor
        self.openPorts = openPorts
        self.filteredPorts = filteredPorts
        self.ttl = ttl
        self.packetLossPercent = packetLossPercent
    }
}

nonisolated struct NetToysScanRun: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    let date: Date
    let target: String
    let ports: [UInt16]
    let duration: TimeInterval
    let results: [NetToysScanResult]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        target: String,
        ports: [UInt16],
        duration: TimeInterval,
        results: [NetToysScanResult]
    ) {
        self.id = id
        self.date = date
        self.target = target
        self.ports = ports
        self.duration = duration
        self.results = results
    }
}

nonisolated struct NetToysScanArchive: Codable, Equatable, Sendable {
    var runs: [NetToysScanRun]

    init(runs: [NetToysScanRun] = [], limit: Int = 50) {
        self.runs = Array(runs.suffix(max(1, limit)))
    }

    mutating func append(_ run: NetToysScanRun, limit: Int = 50) {
        runs.append(run)
        if runs.count > limit { runs.removeFirst(runs.count - limit) }
    }
}

nonisolated struct NetToysHostAnnotation: Codable, Equatable, Sendable {
    var comment: String = ""
    var isFavorite = false
}

nonisolated enum NetToysScannerStore {
    static func archive() -> NetToysScanArchive {
        load(NetToysScanArchive.self, from: NetToysPaths.scanHistory) ?? NetToysScanArchive()
    }

    static func record(_ run: NetToysScanRun) throws {
        var value = archive()
        value.append(run)
        try save(value, to: NetToysPaths.scanHistory)
    }

    static func annotations() -> [String: NetToysHostAnnotation] {
        load([String: NetToysHostAnnotation].self, from: NetToysPaths.scannerAnnotations) ?? [:]
    }

    static func saveAnnotations(_ value: [String: NetToysHostAnnotation]) throws {
        try save(value, to: NetToysPaths.scannerAnnotations)
    }

    static func favoriteTargets() -> [String] {
        load([String].self, from: NetToysPaths.favoriteTargets) ?? []
    }

    static func saveFavoriteTargets(_ value: [String]) throws {
        try save(Array(value.prefix(50)), to: NetToysPaths.favoriteTargets)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(at: NetToysPaths.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

actor NetToysScanner {
    func scan(
        targets: [IPv4Address],
        ports: [UInt16],
        timeoutMilliseconds: Int = 750,
        concurrency: Int = 64,
        collectPingDetails: Bool = false,
        pingProbeCount: Int = 2,
        launchDelayMilliseconds: Int = 0,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [NetToysScanResult] {
        await scan(
            targets: targets.map { NetToysScanTarget(address: $0, ports: ports) },
            timeoutMilliseconds: timeoutMilliseconds,
            concurrency: concurrency,
            collectPingDetails: collectPingDetails,
            pingProbeCount: pingProbeCount,
            launchDelayMilliseconds: launchDelayMilliseconds,
            progress: progress
        )
    }

    func scan(
        targets: [NetToysScanTarget],
        timeoutMilliseconds: Int = 750,
        concurrency: Int = 64,
        collectPingDetails: Bool = false,
        pingProbeCount: Int = 2,
        launchDelayMilliseconds: Int = 0,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [NetToysScanResult] {
        let maximum = min(max(concurrency, 1), 256)
        var scanned: [NetToysScanResult] = []
        scanned.reserveCapacity(targets.count)
        var completed = 0
        for offset in stride(from: 0, to: targets.count, by: maximum) {
            if Task.isCancelled { break }
            let batch = targets[offset..<min(offset + maximum, targets.count)]
            let results = await withTaskGroup(of: NetToysScanResult?.self) { group in
                for (index, target) in batch.enumerated() {
                    group.addTask {
                        guard !Task.isCancelled else { return nil }
                        if launchDelayMilliseconds > 0, index > 0 {
                            try? await Task.sleep(for: .milliseconds(
                                min(1_000, launchDelayMilliseconds) * index
                            ))
                        }
                        return await Self.scanHost(
                            target.address,
                            ports: target.ports,
                            timeoutMilliseconds: timeoutMilliseconds,
                            collectPingDetails: collectPingDetails,
                            pingProbeCount: pingProbeCount
                        )
                    }
                }
                var values: [NetToysScanResult] = []
                for await value in group {
                    if let value { values.append(value) }
                    completed += 1
                    progress?(completed, targets.count)
                }
                return values
            }
            scanned.append(contentsOf: results)
        }
        let arp = await ARPTable.load()
        return scanned.map { result in
            NetToysScanResult(
                address: result.address,
                isReachable: result.isReachable,
                responseMilliseconds: result.responseMilliseconds,
                hostname: result.hostname,
                macAddress: arp[result.address.description],
                vendor: result.vendor,
                openPorts: result.openPorts,
                filteredPorts: result.filteredPorts,
                ttl: result.ttl,
                packetLossPercent: result.packetLossPercent
            )
        }.sorted { $0.address < $1.address }
    }

    private nonisolated static func scanHost(
        _ address: IPv4Address,
        ports: [UInt16],
        timeoutMilliseconds: Int,
        collectPingDetails: Bool,
        pingProbeCount: Int
    ) async -> NetToysScanResult {
        var reachable = false
        var openPorts: [UInt16] = []
        var filteredPorts: [UInt16] = []
        var fastest: Double?
        for port in ports {
            if Task.isCancelled { break }
            let probe = await TCPPortProbe.check(
                host: address.description,
                port: port,
                timeoutMilliseconds: timeoutMilliseconds
            )
            if probe.state != .unreachable {
                reachable = true
                fastest = min(fastest ?? probe.latencyMilliseconds, probe.latencyMilliseconds)
            }
            if probe.state == .open { openPorts.append(port) }
            if probe.state == .unreachable { filteredPorts.append(port) }
        }
        let ping = collectPingDetails
            ? await PingProbe.check(
                address: address,
                count: pingProbeCount,
                timeoutMilliseconds: timeoutMilliseconds
            )
            : nil
        if let loss = ping?.packetLossPercent, loss < 100 {
            reachable = true
            if let latency = ping?.averageMilliseconds {
                fastest = min(fastest ?? latency, latency)
            }
        }
        let hostname = reachable ? await HostResolver.reverse(address) : nil
        return NetToysScanResult(
            address: address,
            isReachable: reachable,
            responseMilliseconds: fastest,
            hostname: hostname,
            macAddress: nil,
            vendor: nil,
            openPorts: openPorts,
            filteredPorts: filteredPorts,
            ttl: ping?.ttl,
            packetLossPercent: ping?.packetLossPercent
        )
    }
}

nonisolated enum HostResolver {
    static func forward(_ hostname: String) async -> [IPv4Address] {
        await Task.detached(priority: .utility) { forwardSynchronously(hostname) }.value
    }

    static func reverse(_ address: IPv4Address) async -> String? {
        await Task.detached(priority: .utility) { reverseSynchronously(address) }.value
    }

    private static func forwardSynchronously(_ hostname: String) -> [IPv4Address] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &head) == 0, let head else { return [] }
        defer { freeaddrinfo(head) }
        var result: [IPv4Address] = []
        var seen = Set<IPv4Address>()
        var current: UnsafeMutablePointer<addrinfo>? = head
        while let item = current {
            if item.pointee.ai_family == AF_INET, let socketAddress = item.pointee.ai_addr {
                let value = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    IPv4Address(rawValue: UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
                }
                if seen.insert(value).inserted { result.append(value) }
            }
            current = item.pointee.ai_next
        }
        return result.sorted()
    }

    private static func reverseSynchronously(_ address: IPv4Address) -> String? {
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, address.description, &socketAddress.sin_addr) == 1 else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }
        return result == 0 ? String(cString: host) : nil
    }
}

nonisolated enum ARPTable {
    static func parse(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let addressStart = line.firstIndex(of: "("),
                  let addressEnd = line[addressStart...].firstIndex(of: ")"),
                  let marker = line.range(of: " at ", range: addressEnd..<line.endIndex)
            else { continue }
            let ip = String(line[line.index(after: addressStart)..<addressEnd])
            let macStart = marker.upperBound
            let macEnd = line[macStart...].firstIndex(where: \.isWhitespace) ?? line.endIndex
            let rawMAC = String(line[macStart..<macEnd])
            let normalized = AnchorMatcher.normalizedMAC(rawMAC)
            guard normalized.count == 12 else { continue }
            result[ip] = stride(from: 0, to: 12, by: 2)
                .map { offset in
                    let start = normalized.index(normalized.startIndex, offsetBy: offset)
                    let end = normalized.index(start, offsetBy: 2)
                    return String(normalized[start..<end])
                }
                .joined(separator: ":")
        }
        return result
    }

    static func load() async -> [String: String] {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
            process.arguments = ["-an"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return [:] }
                return parse(String(decoding: data, as: UTF8.self))
            } catch {
                return [:]
            }
        }.value
    }
}

nonisolated enum NetToysScanExport {
    private struct SavedResults: Codable {
        let version: Int
        let results: [NetToysScanResult]
    }

    static func savedResults(_ results: [NetToysScanResult]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(SavedResults(version: 1, results: results))
    }

    static func csv(_ results: [NetToysScanResult]) -> String {
        let rows = results.map { result in
            [
                result.address.description,
                result.isReachable ? "Up" : "Down",
                result.responseMilliseconds.map { String(format: "%.1f", $0) } ?? "",
                result.ttl.map(String.init) ?? "",
                result.packetLossPercent.map { String(format: "%.1f", $0) } ?? "",
                result.filteredPorts?.map(String.init).joined(separator: " ") ?? "",
                result.hostname ?? "",
                result.macAddress ?? "",
                result.vendor ?? "",
                result.openPorts.map(String.init).joined(separator: " ")
            ].map(quote).joined(separator: ",")
        }
        return (["IP Address,Status,Response ms,TTL,Packet Loss %,Filtered Ports,Hostname,MAC Address,Vendor,Open Ports"] + rows)
            .joined(separator: "\n")
    }

    static func text(_ results: [NetToysScanResult]) -> String {
        results.map { result in
            [
                result.address.description,
                result.isReachable ? "Up" : "Down",
                result.ttl.map(String.init) ?? "-",
                result.packetLossPercent.map { String(format: "%.1f%%", $0) } ?? "-",
                result.hostname ?? "-",
                result.macAddress ?? "-",
                result.openPorts.map(String.init).joined(separator: ","),
                result.filteredPorts?.map(String.init).joined(separator: ",") ?? ""
            ].joined(separator: "\t")
        }.joined(separator: "\n")
    }

    static func ipPorts(_ results: [NetToysScanResult]) -> String {
        results.flatMap { result in
            result.openPorts.map { "\(result.address):\($0)" }
        }.joined(separator: "\n")
    }

    static func xml(_ results: [NetToysScanResult]) -> String {
        let hosts = results.map { result in
            """
              <host ip="\(xmlEscape(result.address.description))" status="\(result.isReachable ? "up" : "down")">
                <hostname>\(xmlEscape(result.hostname ?? ""))</hostname>
                <mac>\(xmlEscape(result.macAddress ?? ""))</mac>
                <ttl>\(result.ttl.map(String.init) ?? "")</ttl>
                <packet-loss>\(result.packetLossPercent.map { String(format: "%.1f", $0) } ?? "")</packet-loss>
                <ports>\(xmlEscape(result.openPorts.map(String.init).joined(separator: " ")))</ports>
                <filtered-ports>\(xmlEscape(result.filteredPorts?.map(String.init).joined(separator: " ") ?? ""))</filtered-ports>
              </host>
            """
        }.joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<scan>\n\(hosts)\n</scan>"
    }

    static func sql(_ results: [NetToysScanResult]) -> String {
        let rows = results.map { result in
            let values = [
                result.address.description,
                result.isReachable ? "up" : "down",
                result.ttl.map(String.init) ?? "",
                result.packetLossPercent.map { String(format: "%.1f", $0) } ?? "",
                result.hostname ?? "",
                result.macAddress ?? "",
                result.openPorts.map(String.init).joined(separator: " "),
                result.filteredPorts?.map(String.init).joined(separator: " ") ?? ""
            ].map(sqlQuote).joined(separator: ", ")
            return "INSERT INTO nettoys_scan (ip_address, status, ttl, packet_loss, hostname, mac_address, open_ports, filtered_ports) VALUES (\(values));"
        }
        return ([
            "CREATE TABLE IF NOT EXISTS nettoys_scan (ip_address TEXT, status TEXT, ttl TEXT, packet_loss TEXT, hostname TEXT, mac_address TEXT, open_ports TEXT, filtered_ports TEXT);"
        ] + rows).joined(separator: "\n")
    }

    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func sqlQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

nonisolated enum NetToysScanImport {
    enum ImportError: LocalizedError {
        case unsupportedVersion(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version): "Unsupported NetToys results version: \(version)"
            case .empty: "The NetToys results file is empty."
            }
        }
    }

    private struct SavedResults: Codable {
        let version: Int
        let results: [NetToysScanResult]
    }

    static func savedResults(_ data: Data) throws -> [NetToysScanResult] {
        let value = try JSONDecoder().decode(SavedResults.self, from: data)
        guard value.version == 1 else { throw ImportError.unsupportedVersion(value.version) }
        guard !value.results.isEmpty else { throw ImportError.empty }
        return value.results
    }
}
