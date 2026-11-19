import Foundation
import IOKit
import Darwin
import os

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

/// Numeric access to SMC keys. `write` returns nil on success or the reason.
nonisolated protocol FanKeyStore: AnyObject {
    func number(_ key: String) -> Double?
    func write(_ key: String, value: Double) -> String?
}

/// What the root helper may write. Only fan keys, only legal values, and targets inside the fan's own range.
nonisolated enum FanKeyPolicy {
    static func fanCount(_ store: FanKeyStore) -> Int {
        guard let count = store.number("FNum"), count.isFinite, count >= 0 else { return 0 }
        return min(Int(count), 8)
    }

    static func modeKey(_ index: Int, _ store: FanKeyStore) -> String? {
        ["F\(index)Md", "F\(index)md"].first { store.number($0) != nil }
    }

    static func targetKey(_ index: Int, _ store: FanKeyStore) -> String? {
        ["F\(index)Tg", "F\(index)tg"].first { store.number($0) != nil }
    }

    static func refusal(for key: String, value: Double, store: FanKeyStore) -> String? {
        guard value.isFinite else { return "\(key) needs a finite value." }
        if key == "Ftst" { return [0, 1].contains(value) ? nil : "Ftst takes only 0 or 1." }
        let chars = Array(key)
        guard chars.count == 4, chars[0] == "F", let index = Int(String(chars[1])), index < fanCount(store) else {
            return "The helper does not write SMC key \(key)."
        }
        switch String(chars[2...]) {
        case "Md", "md":
            return [0, 1].contains(value) ? nil : "\(key) takes only 0 or 1."
        case "Tg", "tg":
            guard let maximum = store.number("F\(index)Mx"), maximum > 0 else {
                return "Fan \(index) reports no maximum speed."
            }
            let minimum = min(store.number("F\(index)Mn") ?? 0, maximum)
            return (minimum...maximum).contains(value) ? nil
                : "Fan \(index) target \(Int(value)) RPM is outside \(Int(minimum))-\(Int(maximum)) RPM."
        default:
            return "The helper does not write SMC key \(key)."
        }
    }

    /// True when no fan is in manual mode and the fan unlock key is clear.
    static func isAutomatic(_ store: FanKeyStore) -> Bool {
        guard store.number("Ftst") != 1 else { return false }
        return (0..<fanCount(store)).allSatisfy { index in
            modeKey(index, store).flatMap { store.number($0) } != 1
        }
    }

    /// Hands every fan back to macOS: each mode key to 0, then the unlock key to 0. It writes without reading
    /// first, because SMC reads lag a write by up to about 0.7 s and would skip a key that was just set.
    static func restoreAutomatic(_ store: FanKeyStore) -> String? {
        for index in 0..<fanCount(store) {
            if let key = modeKey(index, store), let failure = store.write(key, value: 0) { return failure }
        }
        return store.number("Ftst") == nil ? nil : store.write("Ftst", value: 0)
    }
}

/// Helper-side owner of manual fan control. The last client whose write left the fans manual owns them. When
/// that client's connection ends (quit, crash, SIGKILL) or it sends nothing for `timeout` seconds, the helper
/// hands the fans back to macOS. A failed restore keeps the owner, so the next watchdog tick retries.
nonisolated final class FanManualLease: @unchecked Sendable {
    static let timeout: TimeInterval = 15
    static let logger = Logger(subsystem: MacPowerToysHelperContract.label, category: "fan")
    private let lock = NSLock()
    private let openStore: @Sendable () -> FanKeyStore?
    private let now: @Sendable () -> TimeInterval
    private var owner: ObjectIdentifier?
    private var lastTouch: TimeInterval = 0

    init(openStore: @escaping @Sendable () -> FanKeyStore? = { SMCSession() },
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.openStore = openStore
        self.now = now
    }

    var hasOwner: Bool { lock.withLock { owner != nil } }

    /// Writes one allowlisted key and replies "" on success or the reason.
    func write(_ key: String, value: Double, client: ObjectIdentifier) -> String {
        lock.withLock {
            guard let store = openStore() else { return "The fan controller could not be opened." }
            if let refusal = FanKeyPolicy.refusal(for: key, value: value, store: store) {
                Self.logger.error("Refused \(key, privacy: .public) = \(value): \(refusal, privacy: .public)")
                return refusal
            }
            if let failure = store.write(key, value: value) {
                Self.logger.error("\(failure, privacy: .public)")
                return failure
            }
            // Ftst = 0 is the last step of Auto. Every other write leaves the fans manual for this client.
            // Reads would lag the write, so ownership follows the write itself.
            if key == "Ftst", value == 0 {
                owner = nil
            } else {
                owner = client
                lastTouch = now()
            }
            return ""
        }
    }

    func clientEnded(_ client: ObjectIdentifier) {
        lock.withLock {
            guard owner == client else { return }
            Self.logger.notice("Fan client left while manual; restoring Auto")
            restoreLocked()
        }
    }

    func expireIfIdle() {
        lock.withLock {
            guard owner != nil, now() - lastTouch > Self.timeout else { return }
            Self.logger.notice("Fan client sent nothing for \(Self.timeout) s; restoring Auto")
            restoreLocked()
        }
    }

    private func restoreLocked() {
        for attempt in 0..<3 {
            if let store = openStore(), FanKeyPolicy.restoreAutomatic(store) == nil {
                owner = nil
                return
            }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.5) }
        }
        Self.logger.error("Auto restore failed 3 times; the watchdog retries")
    }

    func track(_ connection: NSXPCConnection) {
        let client = ObjectIdentifier(connection)
        let previousInvalidation = connection.invalidationHandler
        connection.interruptionHandler = { @Sendable [weak self] in self?.clientEnded(client) }
        connection.invalidationHandler = { @Sendable [weak self] in
            self?.clientEnded(client)
            previousInvalidation?()
        }
    }
}

// Adapted from smctl's MIT-licensed SMCCore at ca68174f8cdafc53778908c67d77117cb754e9ef.
/// One open AppleSMC connection. Reads work for any user; writes succeed only as root (the helper).
nonisolated final class SMCSession: FanKeyStore {
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

    struct Value {
        let type: String
        let bytes: [UInt8]
    }

    static var hasExpectedLayout: Bool { MemoryLayout<SMCRequest>.stride == 80 }
    private var connection: io_connect_t = 0

    init?() {
        guard Self.hasExpectedLayout else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(connection) }

    func number(_ key: String) -> Double? {
        guard let value = read(key) else { return nil }
        return NativeFanReader.decodeNumber(value.bytes, type: value.type)
    }

    func write(_ key: String, value: Double) -> String? {
        guard let code = Self.code(key) else { return "\(key) is not an SMC key." }
        var infoRequest = SMCRequest()
        infoRequest.key = code
        infoRequest.command = 9
        let (infoStatus, info) = call(infoRequest)
        guard let info else { return "The SMC has no key \(key) (\(infoStatus))." }
        let type = Self.typeName(info.keyInfo.dataType)
        guard let bytes = NativeFanReader.encodeNumber(value, type: type),
              info.keyInfo.dataSize == UInt32(bytes.count) else {
            return "\(key) uses type \(type.trimmingCharacters(in: .whitespaces)), which the helper does not write."
        }
        var request = SMCRequest()
        request.key = code
        request.keyInfo = info.keyInfo
        request.command = 6
        withUnsafeMutableBytes(of: &request.bytes) { $0.copyBytes(from: bytes) }
        let (status, written) = call(request)
        return written == nil ? "The SMC refused \(key) = \(Self.text(value)) (\(status))." : nil
    }

    func read(_ key: String) -> Value? {
        guard let code = Self.code(key) else { return nil }
        var infoRequest = SMCRequest()
        infoRequest.key = code
        infoRequest.command = 9
        guard let info = call(infoRequest).1, (1...32).contains(info.keyInfo.dataSize) else { return nil }
        var valueRequest = SMCRequest()
        valueRequest.key = code
        valueRequest.keyInfo = info.keyInfo
        valueRequest.command = 5
        guard let response = call(valueRequest).1 else { return nil }
        let bytes = withUnsafeBytes(of: response.bytes) { Array($0.prefix(Int(info.keyInfo.dataSize))) }
        return Value(type: Self.typeName(info.keyInfo.dataType), bytes: bytes)
    }

    /// Every key name the SMC lists, in its own order.
    func keyNames() -> [String] {
        guard let total = read("#KEY")?.bytes.prefix(4).reduce(0, { ($0 << 8) | Int($1) }), total < 10_000 else { return [] }
        return (0..<total).compactMap { index in
            var request = SMCRequest()
            request.command = 8
            request.data32 = UInt32(index)
            return call(request).1.map { Self.typeName($0.key) }
        }
    }

    private func call(_ request: SMCRequest) -> (String, SMCRequest?) {
        var input = request
        var output = SMCRequest()
        var outputSize = MemoryLayout<SMCRequest>.stride
        let result = IOConnectCallStructMethod(
            connection, 2, &input, MemoryLayout<SMCRequest>.stride, &output, &outputSize
        )
        guard result == KERN_SUCCESS else { return (String(format: "kernel 0x%08x", result), nil) }
        guard output.result == 0 else { return (String(format: "SMC code 0x%02x", output.result), nil) }
        return ("ok", output)
    }

    private static func code(_ key: String) -> UInt32? {
        let chars = Array(key.utf8)
        guard chars.count == 4 else { return nil }
        return chars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func typeName(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    static func text(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

nonisolated enum NativeFanReader {
    static var hasExpectedLayout: Bool { SMCSession.hasExpectedLayout }

    static func snapshot() -> FanSnapshot? {
        guard let smc = SMCSession() else { return nil }
        let count = smc.number("FNum").flatMap {
            $0.isFinite && $0 >= 0 && $0 < 1_024 ? min(Int($0), 8) : nil
        }
        let indices = 0..<(count ?? 8)
        let fans: [FanReading] = indices.compactMap { index in
            guard let actual = smc.number("F\(index)Ac"), actual.isFinite, actual >= 0, actual < 100_000 else { return nil }
            let modeValue = smc.read("F\(index)Md") ?? smc.read("F\(index)md")
            let mode: String? = switch modeValue?.bytes.first {
            case 0: "auto"
            case 1: "manual"
            case 3: "system"
            case .some(let raw): "unknown \(raw)"
            case nil: nil
            }
            return FanReading(index: index, actualRPM: actual, maximumRPM: smc.number("F\(index)Mx"), mode: mode)
        }
        guard count == 0 || !fans.isEmpty else { return nil }
        return FanSnapshot(fans: fans, profile: nil, canControl: false)
    }

    static func encodeNumber(_ value: Double, type: String) -> [UInt8]? {
        guard value.isFinite, value >= 0, value < 100_000 else { return nil }
        let normalized = [type, String(type.reversed())]
        if normalized.contains("ui8 ") {
            return value <= 255 && value.rounded() == value ? [UInt8(value)] : nil
        }
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
