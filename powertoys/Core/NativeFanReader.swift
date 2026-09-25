import Foundation
import IOKit
import Darwin

nonisolated enum FanPreset: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case cool = "Cool"
    case max = "Max"

    var id: String { rawValue }
}

nonisolated struct FanReading: Decodable, Sendable {
    let index: Int
    let actualRPM: Double?
    let maximumRPM: Double?
    let mode: String?
}

nonisolated struct FanSnapshot: Sendable {
    let fans: [FanReading]
    let profile: String?
    let canControl: Bool

    var averageRPM: Int? {
        let values = fans.compactMap(\.actualRPM).filter { $0.isFinite && $0 >= 0 }
        guard values.count == fans.count, !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return average < 100_000 ? Int(average.rounded()) : nil
    }

    var utilization: Int? {
        let fractions = fans.compactMap { fan -> Double? in
            guard let actual = fan.actualRPM, let maximum = fan.maximumRPM,
                  actual.isFinite, actual >= 0, maximum.isFinite, maximum > 0 else { return nil }
            return min(max(actual / maximum, 0), 1)
        }
        guard fractions.count == fans.count, !fractions.isEmpty else { return nil }
        return Int((fractions.reduce(0, +) / Double(fractions.count) * 100).rounded())
    }

    var detectedPreset: FanPreset? {
        guard !fans.isEmpty else { return nil }
        return switch profile {
        case "auto" where fans.allSatisfy({ ["auto", "system"].contains($0.mode?.lowercased() ?? "") }): .auto
        case "full": .max
        default: nil
        }
    }

    var hasExternalManualControl: Bool {
        profile == nil && fans.contains { ["manual", "forced"].contains($0.mode?.lowercased() ?? "") }
    }
}

// Adapted from smctl's MIT-licensed SMCCore at ca68174f8cdafc53778908c67d77117cb754e9ef.
// SMC writes run only inside the signed, privileged MacPowerToys helper.
nonisolated enum NativeFanReader {
    private struct ControlError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    private typealias Bytes20 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )
    private typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCRequest {
        var key: UInt32 = 0
        var version: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        var powerLimits: Bytes20 = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private struct Value {
        let type: String
        let bytes: [UInt8]
    }

    static var hasExpectedLayout: Bool { MemoryLayout<SMCRequest>.stride == 80 }

    static func snapshot() -> FanSnapshot? {
        guard hasExpectedLayout else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connection) }

        let count = number("FNum", connection: connection).flatMap {
            $0.isFinite && $0 >= 0 && $0 < 1_024 ? min(Int($0), 8) : nil
        }
        let indices = 0..<(count ?? 8)
        let fans: [FanReading] = indices.compactMap { index in
            guard let actual = number("F\(index)Ac", connection: connection),
                  actual.isFinite, actual >= 0, actual < 100_000 else { return nil }
            let maximum = number("F\(index)Mx", connection: connection)
            let modeValue = read("F\(index)Md", connection: connection)
                ?? read("F\(index)md", connection: connection)
            let mode: String? = switch modeValue?.bytes.first {
            case 0: "auto"
            case 1: "manual"
            case 3: "system"
            case .some(let raw): "unknown \(raw)"
            case nil: nil
            }
            return FanReading(index: index, actualRPM: actual, maximumRPM: maximum, mode: mode)
        }
        guard count == 0 || !fans.isEmpty else { return nil }
        return FanSnapshot(fans: fans, profile: nil, canControl: false)
    }

    static func apply(_ preset: FanPreset) throws {
        guard geteuid() == 0 else { throw ControlError("Fan control needs macOS approval.") }
        guard hasExpectedLayout else { throw ControlError("This Mac uses an unsupported SMC layout.") }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw ControlError("The fan controller is unavailable.") }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            throw ControlError("The fan controller could not be opened.")
        }
        defer { IOServiceClose(connection) }

        guard let countValue = number("FNum", connection: connection),
              countValue.isFinite, (1.0...8.0).contains(countValue) else {
            throw ControlError("No supported fans were found.")
        }
        let indices = 0..<Int(countValue)
        let modes = try indices.map { index -> String in
            guard let key = ["F\(index)Md", "F\(index)md"].first(where: { read($0, connection: connection) != nil }),
                  let raw = read(key, connection: connection)?.bytes.first,
                  [0, 1, 3].contains(raw) else {
                throw ControlError("Fan \(index) has no supported control mode.")
            }
            return key
        }
        let testKey = read("Ftst", connection: connection) == nil ? nil : "Ftst"
        if preset == .auto {
            for key in modes {
                guard write(key, bytes: [0], connection: connection) else {
                    throw ControlError("The fan could not return to macOS control.")
                }
            }
            if let testKey, !write(testKey, bytes: [0], connection: connection) {
                throw ControlError("The fan diagnostic mode could not be cleared.")
            }
            return
        }

        let targets = try indices.map { index -> (String, [UInt8]) in
            guard let maximum = number("F\(index)Mx", connection: connection),
                  maximum.isFinite, maximum > 0, maximum < 100_000,
                  let key = ["F\(index)Tg", "F\(index)tg"].first(where: { read($0, connection: connection) != nil }),
                  let value = read(key, connection: connection),
                  let encoded = encodeNumber(maximum, type: value.type) else {
                throw ControlError("Fan \(index) has no safe maximum target.")
            }
            return (key, encoded)
        }
        do {
            if let testKey {
                guard write(testKey, bytes: [1], connection: connection) else {
                    throw ControlError("macOS did not unlock fan control.")
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
            for index in indices {
                guard write(modes[index], bytes: [1], connection: connection),
                      write(targets[index].0, bytes: targets[index].1, connection: connection) else {
                    throw ControlError("Fan \(index) rejected the maximum speed.")
                }
            }
            guard indices.allSatisfy({ read(modes[$0], connection: connection)?.bytes.first == 1 }) else {
                throw ControlError("macOS did not retain manual fan control.")
            }
        } catch {
            for key in modes { _ = write(key, bytes: [0], connection: connection) }
            if let testKey { _ = write(testKey, bytes: [0], connection: connection) }
            throw error
        }
    }

    static func encodeNumber(_ value: Double, type: String) -> [UInt8]? {
        guard value.isFinite, value >= 0, value < 100_000 else { return nil }
        let normalized = [type, String(type.reversed())]
        if normalized.contains("flt ") {
            let bits = Float(value).bitPattern
            return [UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8),
                    UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 24)]
        }
        if normalized.contains("fpe2"), value * 4 <= Double(UInt16.max) {
            let bits = UInt16((value * 4).rounded())
            return [UInt8(truncatingIfNeeded: bits >> 8), UInt8(truncatingIfNeeded: bits)]
        }
        if normalized.contains("ui16"), value <= Double(UInt16.max) {
            let bits = UInt16(value.rounded())
            #if arch(arm64)
            return [UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8)]
            #else
            return [UInt8(truncatingIfNeeded: bits >> 8), UInt8(truncatingIfNeeded: bits)]
            #endif
        }
        return nil
    }

    private static func write(_ key: String, bytes: [UInt8], connection: io_connect_t) -> Bool {
        let chars = Array(key.utf8)
        guard chars.count == 4 else { return false }
        let code = chars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        var infoRequest = SMCRequest()
        infoRequest.key = code
        infoRequest.command = 9
        guard let info = call(infoRequest, connection: connection),
              info.keyInfo.dataSize == UInt32(bytes.count) else { return false }
        var request = SMCRequest()
        request.key = code
        request.keyInfo = info.keyInfo
        request.command = 6
        withUnsafeMutableBytes(of: &request.bytes) { $0.copyBytes(from: bytes) }
        return call(request, connection: connection) != nil
    }

    private static func number(_ key: String, connection: io_connect_t) -> Double? {
        guard let value = read(key, connection: connection) else { return nil }
        return decodeNumber(value.bytes, type: value.type)
    }

    private static func read(_ key: String, connection: io_connect_t) -> Value? {
        let chars = Array(key.utf8)
        guard chars.count == 4 else { return nil }
        let code = chars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        var infoRequest = SMCRequest()
        infoRequest.key = code
        infoRequest.command = 9
        guard let infoResponse = call(infoRequest, connection: connection),
              (1...32).contains(infoResponse.keyInfo.dataSize) else { return nil }

        var valueRequest = SMCRequest()
        valueRequest.key = code
        valueRequest.keyInfo = infoResponse.keyInfo
        valueRequest.command = 5
        guard let valueResponse = call(valueRequest, connection: connection) else { return nil }

        let typeCode = infoResponse.keyInfo.dataType
        let typeBytes: [UInt8] = [
            UInt8(truncatingIfNeeded: typeCode >> 24), UInt8(truncatingIfNeeded: typeCode >> 16),
            UInt8(truncatingIfNeeded: typeCode >> 8), UInt8(truncatingIfNeeded: typeCode)
        ]
        let type = String(bytes: typeBytes, encoding: .ascii) ?? ""
        let bytes = withUnsafeBytes(of: valueResponse.bytes) { Array($0.prefix(Int(infoResponse.keyInfo.dataSize))) }
        return Value(type: type, bytes: bytes)
    }

    private static func call(_ request: SMCRequest, connection: io_connect_t) -> SMCRequest? {
        var input = request
        var output = SMCRequest()
        var outputSize = MemoryLayout<SMCRequest>.stride
        let result = IOConnectCallStructMethod(
            connection, 2, &input, MemoryLayout<SMCRequest>.stride, &output, &outputSize
        )
        return result == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    static func decodeNumber(_ bytes: [UInt8], type: String, littleEndianIntegers: Bool = {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }()) -> Double? {
        let normalized = [type, String(type.reversed())]
        if normalized.contains("flt "), bytes.count >= 4 {
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        }
        if normalized.contains("fpe2"), bytes.count >= 2 {
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        }
        if normalized.contains("ui8 "), let first = bytes.first { return Double(first) }
        if normalized.contains("ui16"), bytes.count >= 2 {
            let pair = littleEndianIntegers ? [bytes[1], bytes[0]] : [bytes[0], bytes[1]]
            return Double(UInt16(pair[0]) << 8 | UInt16(pair[1]))
        }
        if normalized.contains("ui32"), bytes.count >= 4 {
            let word = littleEndianIntegers ? Array(bytes.prefix(4).reversed()) : Array(bytes.prefix(4))
            return Double(word.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        }
        return nil
    }
}
