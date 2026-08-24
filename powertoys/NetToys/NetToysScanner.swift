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

nonisolated struct NetToysScanResult: Identifiable, Equatable, Sendable {
    var id: String { address.description }
    let address: IPv4Address
    let isReachable: Bool
    let responseMilliseconds: Double?
    let hostname: String?
    let macAddress: String?
    let vendor: String?
    let openPorts: [UInt16]
}

actor NetToysScanner {
    func scan(
        targets: [IPv4Address],
        ports: [UInt16],
        timeoutMilliseconds: Int = 750,
        concurrency: Int = 64,
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
                for address in batch {
                    group.addTask {
                        guard !Task.isCancelled else { return nil }
                        return await Self.scanHost(
                            address,
                            ports: ports,
                            timeoutMilliseconds: timeoutMilliseconds
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
                openPorts: result.openPorts
            )
        }.sorted { $0.address < $1.address }
    }

    private nonisolated static func scanHost(
        _ address: IPv4Address,
        ports: [UInt16],
        timeoutMilliseconds: Int
    ) async -> NetToysScanResult {
        var reachable = false
        var openPorts: [UInt16] = []
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
        }
        let hostname = reachable ? await HostResolver.reverse(address) : nil
        return NetToysScanResult(
            address: address,
            isReachable: reachable,
            responseMilliseconds: fastest,
            hostname: hostname,
            macAddress: nil,
            vendor: nil,
            openPorts: openPorts
        )
    }
}

nonisolated enum HostResolver {
    static func reverse(_ address: IPv4Address) async -> String? {
        await Task.detached(priority: .utility) { reverseSynchronously(address) }.value
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
    static func csv(_ results: [NetToysScanResult]) -> String {
        let rows = results.map { result in
            [
                result.address.description,
                result.isReachable ? "Up" : "Down",
                result.responseMilliseconds.map { String(format: "%.1f", $0) } ?? "",
                result.hostname ?? "",
                result.macAddress ?? "",
                result.vendor ?? "",
                result.openPorts.map(String.init).joined(separator: " ")
            ].map(quote).joined(separator: ",")
        }
        return (["IP Address,Status,Response ms,Hostname,MAC Address,Vendor,Open Ports"] + rows)
            .joined(separator: "\n")
    }

    static func text(_ results: [NetToysScanResult]) -> String {
        results.map { result in
            [
                result.address.description,
                result.isReachable ? "Up" : "Down",
                result.hostname ?? "-",
                result.macAddress ?? "-",
                result.openPorts.map(String.init).joined(separator: ",")
            ].joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
