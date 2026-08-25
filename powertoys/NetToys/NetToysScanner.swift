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

nonisolated enum NetToysLivenessMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case tcp = "TCP ports"
    case icmpAndTCP = "ICMP and TCP ports"

    var id: String { rawValue }
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

nonisolated struct NetToysCustomTextProbe: Codable, Equatable, Sendable {
    let port: UInt16
    let request: String
    let responsePattern: String

    enum ValidationError: LocalizedError {
        case invalidPort
        case requestTooLarge
        case patternRequired
        case patternTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidPort: "The custom text probe port must be between 1 and 65535."
            case .requestTooLarge: "The custom text request must be 16 KB or smaller."
            case .patternRequired: "Enter a response regular expression for the custom text probe."
            case .patternTooLarge: "The response regular expression must be 1 KB or smaller."
            }
        }
    }

    func validate() throws {
        guard port > 0 else { throw ValidationError.invalidPort }
        guard request.utf8.count <= 16_384 else { throw ValidationError.requestTooLarge }
        guard !responsePattern.isEmpty else { throw ValidationError.patternRequired }
        guard responsePattern.utf8.count <= 1_024 else { throw ValidationError.patternTooLarge }
        _ = try NSRegularExpression(pattern: responsePattern)
    }

    func match(in response: Data) throws -> String? {
        try validate()
        let text = String(decoding: response, as: UTF8.self)
        let expression = try NSRegularExpression(pattern: responsePattern)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              let valueRange = Range(match.range, in: text)
        else { return nil }
        return String(text[valueRange])
    }
}

nonisolated struct NetToysFetchOptions: Equatable, Sendable {
    var detectHTTPServer = false
    var detectHTTPProxy = false
    var detectNetBIOS = false
    var customTextProbe: NetToysCustomTextProbe?
}

nonisolated struct NetToysProtocolMetadata: Sendable {
    let httpServer: String?
    let httpProxy: String?
    let netBIOSName: String?
    let customText: String?
}

nonisolated enum TCPTextProbe {
    static func exchange(
        address: IPv4Address,
        port: UInt16,
        request: Data,
        timeoutMilliseconds: Int,
        responseLimit: Int = 16_384
    ) async -> Data? {
        await Task.detached(priority: .utility) {
            exchangeSynchronously(
                address: address,
                port: port,
                request: request,
                timeoutMilliseconds: timeoutMilliseconds,
                responseLimit: responseLimit
            )
        }.value
    }

    private static func exchangeSynchronously(
        address: IPv4Address,
        port: UInt16,
        request: Data,
        timeoutMilliseconds: Int,
        responseLimit: Int
    ) -> Data? {
        guard request.count <= 16_384 else { return nil }
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return nil }

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = port.bigEndian
        guard inet_pton(AF_INET, address.description, &socketAddress.sin_addr) == 1 else { return nil }
        let connected = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS,
                  poll(descriptor, events: Int16(POLLOUT), timeoutMilliseconds: timeoutMilliseconds)
            else { return nil }
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0,
                  socketError == 0
            else { return nil }
        }

        if !request.isEmpty {
            let sent = request.withUnsafeBytes { bytes -> Bool in
                guard let base = bytes.baseAddress else { return true }
                var offset = 0
                while offset < bytes.count {
                    guard poll(descriptor, events: Int16(POLLOUT), timeoutMilliseconds: timeoutMilliseconds) else {
                        return false
                    }
                    let count = Darwin.send(descriptor, base.advanced(by: offset), bytes.count - offset, 0)
                    if count > 0 { offset += count; continue }
                    if count < 0, errno == EINTR || errno == EAGAIN { continue }
                    return false
                }
                return true
            }
            guard sent else { return nil }
        }

        let limit = min(max(responseLimit, 1), 65_536)
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: min(4_096, limit))
        var wait = min(max(timeoutMilliseconds, 50), 5_000)
        while response.count < limit,
              poll(descriptor, events: Int16(POLLIN), timeoutMilliseconds: wait) {
            let capacity = min(buffer.count, limit - response.count)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.recv(descriptor, bytes.baseAddress, capacity, 0)
            }
            guard count > 0 else { break }
            response.append(buffer, count: count)
            wait = 10
        }
        return response.isEmpty ? nil : response
    }

    private static func poll(_ descriptor: Int32, events: Int16, timeoutMilliseconds: Int) -> Bool {
        var item = pollfd(fd: descriptor, events: events, revents: 0)
        let result = Darwin.poll(&item, 1, Int32(min(max(timeoutMilliseconds, 1), 5_000)))
        return result > 0 && item.revents & (events | Int16(POLLHUP)) != 0
    }
}

nonisolated enum NetToysProtocolFetchers {
    static func httpServer(from response: Data) -> String? {
        guard let headers = HTTPHeaders(response), headers.statusLine.hasPrefix("HTTP/") else { return nil }
        return headers["server"] ?? headers.statusLine
    }

    static func proxy(from response: Data) -> String? {
        guard let headers = HTTPHeaders(response), headers.statusLine.hasPrefix("HTTP/") else { return nil }
        if headers.statusLine.localizedCaseInsensitiveContains("connection established")
            || headers["proxy-agent"] != nil || headers["via"] != nil {
            return headers["proxy-agent"] ?? "HTTP proxy"
        }
        return nil
    }

    static func collect(
        address: IPv4Address,
        openPorts: [UInt16],
        timeoutMilliseconds: Int,
        options: NetToysFetchOptions
    ) async -> NetToysProtocolMetadata {
        async let httpServer = options.detectHTTPServer
            ? detectHTTPServer(address: address, ports: openPorts, timeoutMilliseconds: timeoutMilliseconds)
            : nil
        async let httpProxy = options.detectHTTPProxy
            ? detectProxy(address: address, ports: openPorts, timeoutMilliseconds: timeoutMilliseconds)
            : nil
        async let netBIOSName = options.detectNetBIOS
            ? NetBIOSProbe.check(address: address, timeoutMilliseconds: timeoutMilliseconds)
            : nil
        async let customText = detectCustomText(
            address: address,
            probe: options.customTextProbe,
            timeoutMilliseconds: timeoutMilliseconds
        )
        return await NetToysProtocolMetadata(
            httpServer: httpServer,
            httpProxy: httpProxy,
            netBIOSName: netBIOSName,
            customText: customText
        )
    }

    private static func detectHTTPServer(
        address: IPv4Address,
        ports: [UInt16],
        timeoutMilliseconds: Int
    ) async -> String? {
        for port in ports where port != 443 {
            let request = Data("HEAD / HTTP/1.0\r\nHost: \(address)\r\nConnection: close\r\n\r\n".utf8)
            if let response = await TCPTextProbe.exchange(
                address: address,
                port: port,
                request: request,
                timeoutMilliseconds: timeoutMilliseconds
            ), let value = httpServer(from: response) { return "\(port): \(value)" }
        }
        return nil
    }

    private static func detectProxy(
        address: IPv4Address,
        ports: [UInt16],
        timeoutMilliseconds: Int
    ) async -> String? {
        let request = Data("CONNECT 127.0.0.1:1 HTTP/1.0\r\nConnection: close\r\n\r\n".utf8)
        for port in ports {
            if let response = await TCPTextProbe.exchange(
                address: address,
                port: port,
                request: request,
                timeoutMilliseconds: timeoutMilliseconds
            ), let value = proxy(from: response) { return "\(port): \(value)" }
        }
        return nil
    }

    private static func detectCustomText(
        address: IPv4Address,
        probe: NetToysCustomTextProbe?,
        timeoutMilliseconds: Int
    ) async -> String? {
        guard let probe else { return nil }
        guard let response = await TCPTextProbe.exchange(
            address: address,
            port: probe.port,
            request: Data(probe.request.utf8),
            timeoutMilliseconds: timeoutMilliseconds
        ) else { return nil }
        return try? probe.match(in: response)
    }

    private struct HTTPHeaders {
        private let values: [String: String]
        let statusLine: String

        init?(_ data: Data) {
            let text = String(decoding: data.prefix(16_384), as: UTF8.self)
            let lines = text.components(separatedBy: .newlines)
            guard let status = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !status.isEmpty
            else { return nil }
            statusLine = status
            values = lines.dropFirst().reduce(into: [:]) { result, line in
                guard let separator = line.firstIndex(of: ":") else { return }
                let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !value.isEmpty { result[key] = value }
            }
        }

        subscript(_ name: String) -> String? { values[name.lowercased()] }
    }
}

nonisolated enum NetBIOSProbe {
    static func check(address: IPv4Address, timeoutMilliseconds: Int) async -> String? {
        await Task.detached(priority: .utility) {
            checkSynchronously(address: address, timeoutMilliseconds: timeoutMilliseconds)
        }.value
    }

    static func parse(_ response: Data) -> String? {
        let bytes = [UInt8](response)
        guard bytes.count >= 12 else { return nil }
        let questionCount = Int(readUInt16(bytes, at: 4) ?? 0)
        let answerCount = Int(readUInt16(bytes, at: 6) ?? 0)
        var offset = 12
        for _ in 0..<questionCount {
            guard let next = skipName(bytes, at: offset), next + 4 <= bytes.count else { return nil }
            offset = next + 4
        }
        for _ in 0..<answerCount {
            guard let nameEnd = skipName(bytes, at: offset), nameEnd + 10 <= bytes.count,
                  let type = readUInt16(bytes, at: nameEnd),
                  let length = readUInt16(bytes, at: nameEnd + 8)
            else { return nil }
            let dataStart = nameEnd + 10
            let dataEnd = dataStart + Int(length)
            guard dataEnd <= bytes.count else { return nil }
            defer { offset = dataEnd }
            guard type == 0x21, dataStart < dataEnd else { continue }
            let count = Int(bytes[dataStart])
            var preferred: String?
            for index in 0..<count {
                let entry = dataStart + 1 + index * 18
                guard entry + 18 <= dataEnd else { break }
                let suffix = bytes[entry + 15]
                let flags = readUInt16(bytes, at: entry + 16) ?? 0
                guard flags & 0x8000 == 0 else { continue }
                let name = String(decoding: bytes[entry..<(entry + 15)], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                if suffix == 0 { return name }
                if preferred == nil, suffix == 0x20 { preferred = name }
            }
            if let preferred { return preferred }
        }
        return nil
    }

    private static func checkSynchronously(address: IPv4Address, timeoutMilliseconds: Int) -> String? {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = UInt16(137).bigEndian
        guard inet_pton(AF_INET, address.description, &socketAddress.sin_addr) == 1 else { return nil }
        let query = statusQuery()
        let sent = query.withUnsafeBytes { bytes in
            withUnsafePointer(to: &socketAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == query.count else { return nil }
        var item = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&item, 1, Int32(min(max(timeoutMilliseconds, 50), 5_000))) > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let count = buffer.withUnsafeMutableBytes { bytes in
            recv(descriptor, bytes.baseAddress, bytes.count, 0)
        }
        guard count > 0 else { return nil }
        return parse(Data(buffer.prefix(count)))
    }

    static func statusQuery() -> Data {
        var bytes = Data([0x4D, 0x50, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0x20])
        let name = [UInt8(ascii: "*")] + Array(repeating: UInt8(0), count: 15)
        for byte in name {
            bytes.append(UInt8(ascii: "A") + (byte >> 4))
            bytes.append(UInt8(ascii: "A") + (byte & 0x0F))
        }
        bytes.append(contentsOf: [0, 0, 0x21, 0, 1])
        return bytes
    }

    private static func skipName(_ bytes: [UInt8], at start: Int) -> Int? {
        var offset = start
        while offset < bytes.count {
            let length = Int(bytes[offset])
            if length & 0xC0 == 0xC0 { return offset + 2 <= bytes.count ? offset + 2 : nil }
            offset += 1
            if length == 0 { return offset }
            guard length <= 63, offset + length <= bytes.count else { return nil }
            offset += length
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset + 1 < bytes.count else { return nil }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
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
    let httpServer: String?
    let httpProxy: String?
    let netBIOSName: String?
    let customText: String?

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
        packetLossPercent: Double? = nil,
        httpServer: String? = nil,
        httpProxy: String? = nil,
        netBIOSName: String? = nil,
        customText: String? = nil
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
        self.httpServer = httpServer
        self.httpProxy = httpProxy
        self.netBIOSName = netBIOSName
        self.customText = customText
    }
}

nonisolated struct NetToysScanStatistics: Equatable, Sendable {
    let addressCount: Int
    let reachableCount: Int
    let openPortHostCount: Int
    let openPortCount: Int
    let averageResponseMilliseconds: Double?
    let fastestResponseMilliseconds: Double?
    let slowestResponseMilliseconds: Double?
    let duration: TimeInterval?

    init(results: [NetToysScanResult], duration: TimeInterval?) {
        let responses = results.compactMap(\.responseMilliseconds)
        addressCount = results.count
        reachableCount = results.filter(\.isReachable).count
        openPortHostCount = results.filter { !$0.openPorts.isEmpty }.count
        openPortCount = results.reduce(0) { $0 + $1.openPorts.count }
        averageResponseMilliseconds = responses.isEmpty ? nil : responses.reduce(0, +) / Double(responses.count)
        fastestResponseMilliseconds = responses.min()
        slowestResponseMilliseconds = responses.max()
        self.duration = duration
    }

    var downCount: Int { addressCount - reachableCount }
    var addressesPerSecond: Double? {
        guard let duration, duration > 0 else { return nil }
        return Double(addressCount) / duration
    }
}

nonisolated struct NetToysOpener: Codable, Identifiable, Equatable, Sendable {
    enum ValidationError: LocalizedError {
        case nameRequired
        case nameTooLong
        case invalidPort
        case invalidTemplate
        case unsupportedScheme
        case credentialsNotAllowed
        case tooManyOpeners
        case duplicateName

        var errorDescription: String? {
            switch self {
            case .nameRequired: "Enter an opener name."
            case .nameTooLong: "Opener names must be 64 characters or shorter."
            case .invalidPort: "Opener ports must be between 1 and 65535."
            case .invalidTemplate: "Enter an absolute URL with a supported placeholder."
            case .unsupportedScheme: "Use HTTP, HTTPS, SSH, FTP, SFTP, Telnet, SMB, or VNC."
            case .credentialsNotAllowed: "Opener URLs cannot contain a user name or password."
            case .tooManyOpeners: "Use no more than 20 openers."
            case .duplicateName: "Give each opener a different name."
            }
        }
    }

    static let defaults = [
        Self(name: "Web", urlTemplate: "http://{ip}:{port}/", requiredPort: 80),
        Self(name: "Secure Web", urlTemplate: "https://{ip}:{port}/", requiredPort: 443),
        Self(name: "SSH", urlTemplate: "ssh://{ip}:{port}", requiredPort: 22),
        Self(name: "FTP", urlTemplate: "ftp://{ip}:{port}/", requiredPort: 21),
        Self(name: "Screen Sharing", urlTemplate: "vnc://{ip}:{port}", requiredPort: 5900)
    ]

    private static let allowedSchemes = Set(["http", "https", "ssh", "ftp", "sftp", "telnet", "smb", "vnc"])
    private static let placeholders = ["{ip}", "{hostname}", "{port}"]

    var id = UUID()
    var name: String
    var urlTemplate: String
    var requiredPort: Int

    func validate() throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ValidationError.nameRequired }
        guard cleanName.count <= 64 else { throw ValidationError.nameTooLong }
        guard (1...65_535).contains(requiredPort) else { throw ValidationError.invalidPort }
        guard !urlTemplate.isEmpty, urlTemplate.utf8.count <= 2_048 else {
            throw ValidationError.invalidTemplate
        }
        guard urlTemplate.contains("{ip}") || urlTemplate.contains("{hostname}") else {
            throw ValidationError.invalidTemplate
        }
        var remainder = urlTemplate
        for placeholder in Self.placeholders {
            remainder = remainder.replacingOccurrences(of: placeholder, with: "")
        }
        guard !remainder.contains("{") && !remainder.contains("}") else {
            throw ValidationError.invalidTemplate
        }
        _ = try resolvedURL(
            address: IPv4Address(rawValue: 0xC000_0201),
            hostname: "host.example"
        )
    }

    func applies(to result: NetToysScanResult) -> Bool {
        guard let port = UInt16(exactly: requiredPort) else { return false }
        return result.openPorts.contains(port)
    }

    func resolvedURL(address: IPv4Address, hostname: String?) throws -> URL {
        let safeHostname = hostname.flatMap(Self.safeHostname) ?? address.description
        let expanded = urlTemplate
            .replacingOccurrences(of: "{ip}", with: address.description)
            .replacingOccurrences(of: "{hostname}", with: safeHostname)
            .replacingOccurrences(of: "{port}", with: String(requiredPort))
        guard let components = URLComponents(string: expanded),
              let scheme = components.scheme?.lowercased(),
              components.host != nil,
              let url = components.url,
              url.absoluteString.utf8.count <= 4_096
        else { throw ValidationError.invalidTemplate }
        guard Self.allowedSchemes.contains(scheme) else { throw ValidationError.unsupportedScheme }
        guard components.user == nil, components.password == nil else {
            throw ValidationError.credentialsNotAllowed
        }
        return url
    }

    private static func safeHostname(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.utf8.count <= 253,
              clean.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII
                      && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-")
              })
        else { return nil }
        return clean
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
        livenessMethod: NetToysLivenessMethod = .tcp,
        pingTimeoutMilliseconds: Int = 750,
        adaptiveTCPTimeout: Bool = false,
        scanUnresponsiveHosts: Bool = true,
        launchDelayMilliseconds: Int = 0,
        fetchOptions: NetToysFetchOptions = NetToysFetchOptions(),
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [NetToysScanResult] {
        await scan(
            targets: targets.map { NetToysScanTarget(address: $0, ports: ports) },
            timeoutMilliseconds: timeoutMilliseconds,
            concurrency: concurrency,
            collectPingDetails: collectPingDetails,
            pingProbeCount: pingProbeCount,
            livenessMethod: livenessMethod,
            pingTimeoutMilliseconds: pingTimeoutMilliseconds,
            adaptiveTCPTimeout: adaptiveTCPTimeout,
            scanUnresponsiveHosts: scanUnresponsiveHosts,
            launchDelayMilliseconds: launchDelayMilliseconds,
            fetchOptions: fetchOptions,
            progress: progress
        )
    }

    func scan(
        targets: [NetToysScanTarget],
        timeoutMilliseconds: Int = 750,
        concurrency: Int = 64,
        collectPingDetails: Bool = false,
        pingProbeCount: Int = 2,
        livenessMethod: NetToysLivenessMethod = .tcp,
        pingTimeoutMilliseconds: Int = 750,
        adaptiveTCPTimeout: Bool = false,
        scanUnresponsiveHosts: Bool = true,
        launchDelayMilliseconds: Int = 0,
        fetchOptions: NetToysFetchOptions = NetToysFetchOptions(),
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
                            pingProbeCount: pingProbeCount,
                            livenessMethod: livenessMethod,
                            pingTimeoutMilliseconds: pingTimeoutMilliseconds,
                            adaptiveTCPTimeout: adaptiveTCPTimeout,
                            scanUnresponsiveHosts: scanUnresponsiveHosts,
                            fetchOptions: fetchOptions
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
            let macAddress = arp[result.address.description]
            return NetToysScanResult(
                address: result.address,
                isReachable: result.isReachable,
                responseMilliseconds: result.responseMilliseconds,
                hostname: result.hostname,
                macAddress: macAddress,
                vendor: MACVendorDatabase.bundled.vendor(for: macAddress),
                openPorts: result.openPorts,
                filteredPorts: result.filteredPorts,
                ttl: result.ttl,
                packetLossPercent: result.packetLossPercent,
                httpServer: result.httpServer,
                httpProxy: result.httpProxy,
                netBIOSName: result.netBIOSName,
                customText: result.customText
            )
        }.sorted { $0.address < $1.address }
    }

    private nonisolated static func scanHost(
        _ address: IPv4Address,
        ports: [UInt16],
        timeoutMilliseconds: Int,
        collectPingDetails: Bool,
        pingProbeCount: Int,
        livenessMethod: NetToysLivenessMethod,
        pingTimeoutMilliseconds: Int,
        adaptiveTCPTimeout: Bool,
        scanUnresponsiveHosts: Bool,
        fetchOptions: NetToysFetchOptions
    ) async -> NetToysScanResult {
        let needsPing = collectPingDetails || livenessMethod == .icmpAndTCP || adaptiveTCPTimeout
        let ping = needsPing
            ? await PingProbe.check(
                address: address,
                count: pingProbeCount,
                timeoutMilliseconds: pingTimeoutMilliseconds
            )
            : nil
        var reachable = pingResponded(ping) && (collectPingDetails || livenessMethod == .icmpAndTCP)
        var openPorts: [UInt16] = []
        var filteredPorts: [UInt16] = []
        var fastest = reachable ? ping?.averageMilliseconds : nil
        let tcpTimeout = effectiveTCPTimeout(
            configuredMilliseconds: timeoutMilliseconds,
            pingAverageMilliseconds: ping?.averageMilliseconds,
            adaptive: adaptiveTCPTimeout
        )
        if shouldScanPorts(
            ping: ping,
            livenessMethod: livenessMethod,
            scanUnresponsiveHosts: scanUnresponsiveHosts
        ) {
            for port in ports {
                if Task.isCancelled { break }
                let probe = await TCPPortProbe.check(
                    host: address.description,
                    port: port,
                    timeoutMilliseconds: tcpTimeout
                )
                if probe.state != .unreachable {
                    reachable = true
                    fastest = min(fastest ?? probe.latencyMilliseconds, probe.latencyMilliseconds)
                }
                if probe.state == .open { openPorts.append(port) }
                if probe.state == .unreachable { filteredPorts.append(port) }
            }
        }
        let hostname = reachable ? await HostResolver.reverse(address) : nil
        let metadata = reachable
            ? await NetToysProtocolFetchers.collect(
                address: address,
                openPorts: openPorts,
                timeoutMilliseconds: tcpTimeout,
                options: fetchOptions
            )
            : NetToysProtocolMetadata(httpServer: nil, httpProxy: nil, netBIOSName: nil, customText: nil)
        return NetToysScanResult(
            address: address,
            isReachable: reachable,
            responseMilliseconds: fastest,
            hostname: hostname,
            macAddress: nil,
            vendor: nil,
            openPorts: openPorts,
            filteredPorts: reportedFilteredPorts(filteredPorts, reachable: reachable),
            ttl: ping?.ttl,
            packetLossPercent: ping?.packetLossPercent,
            httpServer: metadata.httpServer,
            httpProxy: metadata.httpProxy,
            netBIOSName: metadata.netBIOSName,
            customText: metadata.customText
        )
    }

    nonisolated static func reportedFilteredPorts(_ ports: [UInt16], reachable: Bool) -> [UInt16] {
        reachable ? ports : []
    }

    nonisolated static func effectiveTCPTimeout(
        configuredMilliseconds: Int,
        pingAverageMilliseconds: Double?,
        adaptive: Bool
    ) -> Int {
        let configured = min(max(configuredMilliseconds, 100), 5_000)
        guard adaptive,
              let average = pingAverageMilliseconds,
              average.isFinite,
              average >= 0
        else { return configured }
        return min(configured, max(100, Int(ceil(average * 4))))
    }

    nonisolated static func shouldScanPorts(
        ping: PingProbeResult?,
        livenessMethod: NetToysLivenessMethod,
        scanUnresponsiveHosts: Bool
    ) -> Bool {
        guard livenessMethod == .icmpAndTCP,
              !scanUnresponsiveHosts,
              let loss = ping?.packetLossPercent
        else { return true }
        return loss < 100
    }

    private nonisolated static func pingResponded(_ ping: PingProbeResult?) -> Bool {
        guard let loss = ping?.packetLossPercent else { return false }
        return loss < 100
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
    static func load() async -> [String: String] {
        await Task.detached(priority: .utility) {
            var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
            var byteCount = 0
            let sizeStatus = mib.withUnsafeMutableBufferPointer {
                sysctl($0.baseAddress, UInt32($0.count), nil, &byteCount, nil, 0)
            }
            guard sizeStatus == 0, byteCount > 0 else { return [:] }
            var data = Data(count: byteCount)
            let readStatus = mib.withUnsafeMutableBufferPointer { mibBuffer in
                data.withUnsafeMutableBytes { dataBuffer in
                    sysctl(
                        mibBuffer.baseAddress,
                        UInt32(mibBuffer.count),
                        dataBuffer.baseAddress,
                        &byteCount,
                        nil,
                        0
                    )
                }
            }
            guard readStatus == 0 else { return [:] }
            return parseRoutingMessages(data.prefix(byteCount))
        }.value
    }

    static func parseRoutingMessages(_ data: Data) -> [String: String] {
        data.withUnsafeBytes { bytes in
            var result: [String: String] = [:]
            var messageOffset = 0
            let headerSize = MemoryLayout<rt_msghdr>.size
            while messageOffset + headerSize <= bytes.count {
                let header = bytes.loadUnaligned(
                    fromByteOffset: messageOffset,
                    as: rt_msghdr.self
                )
                let messageLength = Int(header.rtm_msglen)
                guard messageLength >= headerSize,
                      messageOffset + messageLength <= bytes.count
                else { break }
                var addressOffset = messageOffset + headerSize
                var ipAddress: String?
                var macAddress: String?
                for index in 0..<Int(RTAX_MAX) where header.rtm_addrs & (1 << index) != 0 {
                    guard addressOffset + 2 <= messageOffset + messageLength else { break }
                    let addressLength = Int(bytes[addressOffset])
                    let family = Int32(bytes[addressOffset + 1])
                    let alignedLength = addressLength > 0
                        ? (addressLength + MemoryLayout<UInt32>.size - 1)
                            & ~(MemoryLayout<UInt32>.size - 1)
                        : MemoryLayout<UInt32>.size
                    guard addressOffset + alignedLength <= messageOffset + messageLength else { break }
                    if index == Int(RTAX_DST), family == AF_INET, addressLength >= 8 {
                        ipAddress = (4..<8)
                            .map { String(bytes[addressOffset + $0]) }
                            .joined(separator: ".")
                    } else if index == Int(RTAX_GATEWAY), family == AF_LINK, addressLength >= 8 {
                        let nameLength = Int(bytes[addressOffset + 5])
                        let macLength = Int(bytes[addressOffset + 6])
                        let macOffset = addressOffset + 8 + nameLength
                        if macLength == 6, macOffset + macLength <= addressOffset + addressLength {
                            macAddress = (0..<macLength)
                                .map { String(format: "%02x", bytes[macOffset + $0]) }
                                .joined(separator: ":")
                        }
                    }
                    addressOffset += alignedLength
                }
                if let ipAddress, let macAddress { result[ipAddress] = macAddress }
                messageOffset += messageLength
            }
            return result
        }
    }
}

nonisolated struct MACVendorDatabase: Sendable {
    static let bundled: Self = {
        guard let url = Bundle.main.url(forResource: "ieee-mac-vendors", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return Self(text: "") }
        return Self(text: text)
    }()

    private let vendors: [String: String]

    init(text: String) {
        vendors = text.split(whereSeparator: \.isNewline).reduce(into: [:]) { result, line in
            guard !line.hasPrefix("#") else { return }
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let bits = Int(fields[0]), [24, 28, 36].contains(bits),
                  fields[1].count == bits / 4,
                  !fields[2].isEmpty
            else { return }
            result["\(bits):\(fields[1].uppercased())"] = String(fields[2])
        }
    }

    func vendor(for macAddress: String?) -> String? {
        guard let macAddress else { return nil }
        let normalized = AnchorMatcher.normalizedMAC(macAddress)
        guard normalized.count == 12,
              let firstOctet = UInt8(normalized.prefix(2), radix: 16),
              firstOctet & 0x02 == 0
        else { return nil }
        let hexadecimal = normalized.uppercased()
        return vendors["36:\(hexadecimal.prefix(9))"]
            ?? vendors["28:\(hexadecimal.prefix(7))"]
            ?? vendors["24:\(hexadecimal.prefix(6))"]
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

    static func csv(_ results: [NetToysScanResult], includeHeader: Bool = true) -> String {
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
                result.openPorts.map(String.init).joined(separator: " "),
                result.httpServer ?? "",
                result.httpProxy ?? "",
                result.netBIOSName ?? "",
                result.customText ?? ""
            ].map(quote).joined(separator: ",")
        }
        let header = "IP Address,Status,Response ms,TTL,Packet Loss %,Filtered Ports,Hostname,MAC Address,Vendor,Open Ports,HTTP Server,HTTP Proxy,NetBIOS,Custom Text"
        return ((includeHeader ? [header] : []) + rows).joined(separator: "\n")
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
                result.vendor ?? "-",
                result.openPorts.map(String.init).joined(separator: ","),
                result.filteredPorts?.map(String.init).joined(separator: ",") ?? "",
                result.httpServer ?? "-",
                result.httpProxy ?? "-",
                result.netBIOSName ?? "-",
                result.customText ?? "-"
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
                <mac-vendor>\(xmlEscape(result.vendor ?? ""))</mac-vendor>
                <ttl>\(result.ttl.map(String.init) ?? "")</ttl>
                <packet-loss>\(result.packetLossPercent.map { String(format: "%.1f", $0) } ?? "")</packet-loss>
                <ports>\(xmlEscape(result.openPorts.map(String.init).joined(separator: " ")))</ports>
                <filtered-ports>\(xmlEscape(result.filteredPorts?.map(String.init).joined(separator: " ") ?? ""))</filtered-ports>
                <http-server>\(xmlEscape(result.httpServer ?? ""))</http-server>
                <http-proxy>\(xmlEscape(result.httpProxy ?? ""))</http-proxy>
                <netbios>\(xmlEscape(result.netBIOSName ?? ""))</netbios>
                <custom-text>\(xmlEscape(result.customText ?? ""))</custom-text>
              </host>
            """
        }.joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<scan>\n\(hosts)\n</scan>"
    }

    static func sql(_ results: [NetToysScanResult], includeSchema: Bool = true) -> String {
        let rows = results.map { result in
            let values = [
                result.address.description,
                result.isReachable ? "up" : "down",
                result.ttl.map(String.init) ?? "",
                result.packetLossPercent.map { String(format: "%.1f", $0) } ?? "",
                result.hostname ?? "",
                result.macAddress ?? "",
                result.vendor ?? "",
                result.openPorts.map(String.init).joined(separator: " "),
                result.filteredPorts?.map(String.init).joined(separator: " ") ?? "",
                result.httpServer ?? "",
                result.httpProxy ?? "",
                result.netBIOSName ?? "",
                result.customText ?? ""
            ].map(sqlQuote).joined(separator: ", ")
            return "INSERT INTO nettoys_scan (ip_address, status, ttl, packet_loss, hostname, mac_address, mac_vendor, open_ports, filtered_ports, http_server, http_proxy, netbios, custom_text) VALUES (\(values));"
        }
        let schema = "CREATE TABLE IF NOT EXISTS nettoys_scan (ip_address TEXT, status TEXT, ttl TEXT, packet_loss TEXT, hostname TEXT, mac_address TEXT, mac_vendor TEXT, open_ports TEXT, filtered_ports TEXT, http_server TEXT, http_proxy TEXT, netbios TEXT, custom_text TEXT);"
        return ((includeSchema ? [schema] : []) + rows).joined(separator: "\n")
    }

    static func append(_ value: String, to url: URL) throws {
        guard !value.isEmpty else { return }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        var prefix = ""
        if size > 0 {
            try handle.seek(toOffset: size - 1)
            prefix = try handle.read(upToCount: 1) == Data([0x0A]) ? "" : "\n"
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: Data((prefix + value).utf8))
        try handle.synchronize()
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
