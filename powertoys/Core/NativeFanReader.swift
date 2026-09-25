import Foundation
import IOKit

// Adapted from smctl's MIT-licensed SMCCore at ca68174f8cdafc53778908c67d77117cb754e9ef.
// This reader never writes SMC keys; fan changes remain in smctl's guarded daemon.
nonisolated enum NativeFanReader {
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
