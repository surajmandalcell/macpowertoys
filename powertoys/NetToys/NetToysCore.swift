import Foundation

nonisolated struct IPv4Address: Hashable, Comparable, CustomStringConvertible, Sendable {
    let rawValue: UInt32

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        rawValue = value
    }

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    var description: String {
        [24, 16, 8, 0]
            .map { String((rawValue >> UInt32($0)) & 0xff) }
            .joined(separator: ".")
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated enum IPv4Targets {
    enum ParseError: LocalizedError {
        case invalid(String)
        case tooMany(Int)

        var errorDescription: String? {
            switch self {
            case .invalid(let value): "Invalid IPv4 target: \(value)"
            case .tooMany(let limit): "The target contains more than \(limit) addresses."
            }
        }
    }

    static func parse(_ input: String, limit: Int = 65_536) throws -> [IPv4Address] {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ParseError.invalid(input) }
        if value.contains("/") { return try cidr(value, limit: limit) }
        if value.contains("-") && !value.contains(",") { return try range(value, limit: limit) }

        var seen = Set<IPv4Address>()
        var addresses: [IPv4Address] = []
        for token in value.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let text = String(token)
            guard let address = IPv4Address(text) else { throw ParseError.invalid(text) }
            if seen.insert(address).inserted { addresses.append(address) }
            guard addresses.count <= limit else { throw ParseError.tooMany(limit) }
        }
        return addresses
    }

    private static func range(_ input: String, limit: Int) throws -> [IPv4Address] {
        let parts = input.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = IPv4Address(String(parts[0]).trimmingCharacters(in: .whitespaces)),
              let end = IPv4Address(String(parts[1]).trimmingCharacters(in: .whitespaces)),
              start <= end
        else { throw ParseError.invalid(input) }
        let count = UInt64(end.rawValue) - UInt64(start.rawValue) + 1
        guard count <= UInt64(limit) else { throw ParseError.tooMany(limit) }
        return (start.rawValue...end.rawValue).map(IPv4Address.init(rawValue:))
    }

    private static func cidr(_ input: String, limit: Int) throws -> [IPv4Address] {
        let parts = input.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let address = IPv4Address(String(parts[0]).trimmingCharacters(in: .whitespaces)),
              let prefix = UInt8(parts[1]), prefix <= 32
        else { throw ParseError.invalid(input) }

        let hostBits = 32 - Int(prefix)
        let count = UInt64(1) << UInt64(hostBits)
        let excluded = hostBits >= 2 ? 2 : 0
        guard count - UInt64(excluded) <= UInt64(limit) else { throw ParseError.tooMany(limit) }
        let mask = prefix == 0 ? UInt32(0) : UInt32.max << UInt32(hostBits)
        let network = address.rawValue & mask
        let first = network &+ UInt32(excluded == 2 ? 1 : 0)
        let last = network &+ UInt32(count - 1 - UInt64(excluded == 2 ? 1 : 0))
        return (first...last).map(IPv4Address.init(rawValue:))
    }
}

nonisolated struct SSHConfigEdit: Equatable {
    let data: Data
    let originalRange: Range<Int>
    let changedRange: Range<Int>
    let oldValue: String
    let newValue: String
}

nonisolated enum SSHConfigEditor {
    enum EditError: LocalizedError {
        case hostNotFound(String)
        case hostNameNotFound(String)
        case valueChanged(expected: String, actual: String)
        case invalidValue

        var errorDescription: String? {
            switch self {
            case .hostNotFound(let host): "SSH host not found: \(host)"
            case .hostNameNotFound(let host): "HostName is missing for SSH host: \(host)"
            case .valueChanged(let expected, let actual): "HostName changed from \(expected) to \(actual)."
            case .invalidValue: "The replacement HostName contains unsupported characters."
            }
        }
    }

    static func replacingHostName(
        in data: Data,
        hostAlias: String,
        expectedHostName: String,
        newHostName: String
    ) throws -> SSHConfigEdit {
        guard isSafeToken(newHostName) else { throw EditError.invalidValue }
        let bytes = [UInt8](data)
        let lines = lineRanges(bytes)
        guard let hostLine = lines.firstIndex(where: {
            guard let directive = directive(in: bytes, range: $0), directive.key == "host" else { return false }
            return tokens(in: bytes, range: directive.valueRange).contains {
                asciiString(bytes[$0]).caseInsensitiveCompare(hostAlias) == .orderedSame
            }
        }) else { throw EditError.hostNotFound(hostAlias) }

        let stanzaEnd = lines[(hostLine + 1)...].firstIndex(where: {
            guard let item = directive(in: bytes, range: $0) else { return false }
            return item.key == "host" || item.key == "match"
        }) ?? lines.endIndex

        for index in (hostLine + 1)..<stanzaEnd {
            guard let item = directive(in: bytes, range: lines[index]), item.key == "hostname",
                  let token = valueToken(in: bytes, range: item.valueRange)
            else { continue }
            let oldValue = asciiString(bytes[token])
            guard oldValue == expectedHostName else {
                throw EditError.valueChanged(expected: expectedHostName, actual: oldValue)
            }
            let replacement = Array(newHostName.utf8)
            var output = bytes
            output.replaceSubrange(token, with: replacement)
            return SSHConfigEdit(
                data: Data(output),
                originalRange: token,
                changedRange: token.lowerBound..<(token.lowerBound + replacement.count),
                oldValue: oldValue,
                newValue: newHostName
            )
        }
        throw EditError.hostNameNotFound(hostAlias)
    }

    private struct Directive {
        let key: String
        let valueRange: Range<Int>
    }

    private static func lineRanges(_ bytes: [UInt8]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0a {
            result.append(start..<index)
            start = index + 1
        }
        if start < bytes.count { result.append(start..<bytes.count) }
        return result
    }

    private static func directive(in bytes: [UInt8], range: Range<Int>) -> Directive? {
        var index = range.lowerBound
        while index < range.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        guard index < range.upperBound, bytes[index] != 0x23 else { return nil }
        let keyStart = index
        while index < range.upperBound, isKeyByte(bytes[index]) { index += 1 }
        guard index > keyStart else { return nil }
        let key = asciiString(bytes[keyStart..<index]).lowercased()
        while index < range.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        if index < range.upperBound, bytes[index] == 0x3d {
            index += 1
            while index < range.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        }
        return Directive(key: key, valueRange: index..<range.upperBound)
    }

    private static func tokens(in bytes: [UInt8], range: Range<Int>) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var index = range.lowerBound
        while index < range.upperBound {
            while index < range.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
            guard index < range.upperBound, bytes[index] != 0x23, bytes[index] != 0x0d else { break }
            let start = index
            while index < range.upperBound,
                  bytes[index] != 0x20, bytes[index] != 0x09,
                  bytes[index] != 0x23, bytes[index] != 0x0d { index += 1 }
            result.append(start..<index)
        }
        return result
    }

    private static func valueToken(in bytes: [UInt8], range: Range<Int>) -> Range<Int>? {
        var start = range.lowerBound
        guard start < range.upperBound, bytes[start] != 0x23, bytes[start] != 0x0d else { return nil }
        if bytes[start] == 0x22 {
            start += 1
            var end = start
            while end < range.upperBound, bytes[end] != 0x22, bytes[end] != 0x0d { end += 1 }
            return start..<end
        }
        var end = start
        while end < range.upperBound,
              bytes[end] != 0x20, bytes[end] != 0x09,
              bytes[end] != 0x23, bytes[end] != 0x0d { end += 1 }
        return start < end ? start..<end : nil
    }

    private static func isKeyByte(_ byte: UInt8) -> Bool {
        (0x41...0x5a).contains(byte) || (0x61...0x7a).contains(byte)
    }

    private static func asciiString(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    private static func isSafeToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            byte > 0x20 && byte != 0x23 && byte != 0x22 && byte != 0x7f
        }
    }
}

nonisolated struct AnchorCandidate: Equatable, Sendable {
    let ip: String
    let macAddress: String?
    let hostname: String?
}

nonisolated enum AnchorIdentity: Equatable, Sendable {
    case stableMAC(String)
    case randomizedMAC(hostname: String, learnedMACs: Set<String>)
}

nonisolated enum AnchorMatcher {
    static func match(candidates: [AnchorCandidate], identity: AnchorIdentity) -> AnchorCandidate? {
        let matches: [AnchorCandidate]
        switch identity {
        case .stableMAC(let mac):
            let expected = normalizedMAC(mac)
            matches = candidates.filter { $0.macAddress.map(normalizedMAC) == expected }
        case .randomizedMAC(let hostname, let learnedMACs):
            let expected = normalizedHostname(hostname)
            let hostnameMatches = candidates.filter { $0.hostname.map(normalizedHostname) == expected }
            if !hostnameMatches.isEmpty {
                matches = hostnameMatches
            } else {
                let learned = Set(learnedMACs.map(normalizedMAC))
                matches = candidates.filter { candidate in
                    candidate.macAddress.map { learned.contains(normalizedMAC($0)) } ?? false
                }
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func normalizedMAC(_ value: String) -> String {
        value.lowercased().filter(\.isHexDigit)
    }

    static func normalizedHostname(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

nonisolated enum NetworkReachability: String, Codable, Equatable, Sendable {
    case reachable
    case unreachable
    case unknown
}

nonisolated enum NetworkTransitionChange: Equatable, Sendable {
    case gateway(from: NetworkReachability, to: NetworkReachability)
    case internet(from: NetworkReachability, to: NetworkReachability)
}

nonisolated struct NetworkTransitionEvent: Equatable, Sendable {
    let networkID: String
    let date: Date
    let changes: [NetworkTransitionChange]
}

nonisolated struct NetworkTransitionRecorder: Sendable {
    private var previous: (networkID: String, gateway: NetworkReachability, internet: NetworkReachability)?

    mutating func observe(
        networkID: String,
        gateway: NetworkReachability,
        internet: NetworkReachability,
        at date: Date
    ) -> NetworkTransitionEvent? {
        defer { previous = (networkID, gateway, internet) }
        guard let previous, previous.networkID == networkID else { return nil }
        var changes: [NetworkTransitionChange] = []
        if previous.gateway != gateway { changes.append(.gateway(from: previous.gateway, to: gateway)) }
        if previous.internet != internet { changes.append(.internet(from: previous.internet, to: internet)) }
        return changes.isEmpty ? nil : NetworkTransitionEvent(networkID: networkID, date: date, changes: changes)
    }
}
