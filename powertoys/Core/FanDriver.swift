import Foundation

/// The fan presets, built in the app on top of the helper's one-key writes, so a rule change never needs a new
/// helper. Runs only on `FanCommand.controlQueue`.
///
/// Both manual presets start from the fans' current speed and move the target once per second. Max climbs at most
/// 1500 RPM a second. Cool follows the hottest CPU die sensor (`Tp*` P-cores, `Te*` E-cores), smoothed so a
/// one-core spike does not reach the fans, along the saved `FanCurve` (by default Mn at 65 °C or less, Mx at 90 °C
/// or more, linear between); it rises at most 300 RPM and falls at most 150 RPM a second.
///
/// SMC reads lag a write by up to about 0.7 s, so every check reads keys written at least one tick earlier.
nonisolated enum FanDriver {
    struct Fan {
        let index: Int
        let modeKey: String
        let targetKey: String
        let minimum: Double
        let maximum: Double
    }

    static let tick: TimeInterval = 1
    static let settle: TimeInterval = 1.5
    static let unlockDeadline: TimeInterval = 10
    static let coolRise = 300.0
    static let coolFall = 150.0
    static let maxRise = 1_500.0
    static let smoothing = 0.2

    nonisolated(unsafe) private static var link: HelperFanKeys?
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    nonisolated(unsafe) private static var targets: [Int: Double] = [:]
    nonisolated(unsafe) private static var smoothed: Double?
    nonisolated(unsafe) private static var mismatches = 0
    nonisolated(unsafe) static var onManualLost: (@Sendable (String) -> Void)?

    static func apply(_ preset: FanPreset) throws {
        stopTimer()
        guard let smc = SMCSession() else { throw FanError("The fan controller could not be opened.") }
        let fans = try readFans(smc)
        guard preset != .auto else { return try restoreAutomatic(smc) }
        let keys = helperKeys()
        do {
            try unlock(fans, keys: keys, smc: smc)
            targets = Dictionary(uniqueKeysWithValues: fans.map { fan in
                (fan.index, min(max(smc.number("F\(fan.index)Ac") ?? fan.minimum, fan.minimum), fan.maximum).rounded())
            })
            smoothed = nil
            mismatches = 0
            try writeTargets(preset, fans: fans, keys: keys, smc: smc)
            log("Fan \(preset.rawValue): from \(fans.map { Int(smc.number("F\($0.index)Ac") ?? 0) }) RPM"
                + (smoothed.map { ", CPU \(Int($0)) °C" } ?? ""))
        } catch {
            try? restoreAutomatic(smc)
            throw error
        }
        startTimer(preset, fans: fans)
    }

    /// One tick of Cool: the speed the smoothed CPU temperature asks for, reached in limited steps.
    static func coolTarget(hottest: Double, previous: Double?, minimum: Double, maximum: Double,
                           curve: FanCurve = .standard) -> Double {
        let desired = (minimum + (maximum - minimum) * curve.speed(at: hottest)).rounded()
        return step(toward: desired, from: previous ?? minimum, rise: coolRise, fall: coolFall,
                    minimum: minimum, maximum: maximum)
    }

    static func step(toward desired: Double, from previous: Double, rise: Double, fall: Double,
                     minimum: Double, maximum: Double) -> Double {
        let change = min(max(desired - previous, -fall), rise)
        return min(max(previous + change, minimum), maximum).rounded()
    }

    private static func readFans(_ smc: SMCSession) throws -> [Fan] {
        let count = FanKeyPolicy.fanCount(smc)
        guard count > 0 else { throw FanError("No supported fans were found.") }
        return try (0..<count).map { index in
            guard let modeKey = FanKeyPolicy.modeKey(index, smc), let targetKey = FanKeyPolicy.targetKey(index, smc),
                  let maximum = smc.number("F\(index)Mx"), maximum.isFinite, maximum > 0, maximum < 100_000 else {
                throw FanError("Fan \(index) reports no mode, target, or maximum speed.")
            }
            let minimum = min(max(smc.number("F\(index)Mn") ?? 0, 0), maximum)
            return Fan(index: index, modeKey: modeKey, targetKey: targetKey, minimum: minimum, maximum: maximum)
        }
    }

    /// Apple silicon refuses `F<n>Md = 1` until `Ftst = 1` takes effect, so the mode write repeats until the SMC
    /// accepts it or `unlockDeadline` passes.
    private static func unlock(_ fans: [Fan], keys: HelperFanKeys, smc: SMCSession) throws {
        let started = ProcessInfo.processInfo.systemUptime
        if smc.number("Ftst") != nil, let failure = keys.write("Ftst", value: 1) {
            throw FanError("macOS did not unlock fan control: \(failure)")
        }
        for fan in fans {
            var lastFailure: String?
            repeat {
                lastFailure = keys.write(fan.modeKey, value: 1)
                if lastFailure == nil { break }
                Thread.sleep(forTimeInterval: 0.25)
            } while ProcessInfo.processInfo.systemUptime - started < unlockDeadline
            if let lastFailure {
                throw FanError("Fan \(fan.index) stayed under macOS control for \(Int(unlockDeadline)) s: \(lastFailure)")
            }
        }
    }

    private static func writeTargets(_ preset: FanPreset, fans: [Fan], keys: HelperFanKeys, smc: SMCSession) throws {
        let temperature: Double? = if preset == .cool { try cpuTemperature(smc) } else { nil }
        let curve = temperature == nil ? FanCurve.standard : FanCurve.load()
        for fan in fans {
            let previous = targets[fan.index] ?? fan.minimum
            let target = temperature.map {
                coolTarget(hottest: $0, previous: previous, minimum: fan.minimum, maximum: fan.maximum, curve: curve)
            } ?? step(toward: fan.maximum, from: previous, rise: maxRise, fall: maxRise,
                      minimum: fan.minimum, maximum: fan.maximum)
            if let failure = keys.write(fan.targetKey, value: target) { throw FanError(failure) }
            targets[fan.index] = target
        }
    }

    /// Auto: every mode key to 0, then `Ftst` to 0, then a read after the SMC settles.
    private static func restoreAutomatic(_ smc: SMCSession) throws {
        defer { dropLink() }
        if link == nil, FanKeyPolicy.isAutomatic(smc) { return }
        if let failure = FanKeyPolicy.restoreAutomatic(helperKeys()) {
            throw FanError("The fans could not return to macOS control: \(failure)")
        }
        Thread.sleep(forTimeInterval: settle)
        guard FanKeyPolicy.isAutomatic(smc) else { throw FanError("A fan stayed in manual mode after Auto.") }
    }

    private static func startTimer(_ preset: FanPreset, fans: [Fan]) {
        let source = DispatchSource.makeTimerSource(queue: FanCommand.controlQueue)
        source.schedule(deadline: .now() + tick, repeating: tick, leeway: .milliseconds(100))
        source.setEventHandler { holdManual(preset, fans: fans) }
        timer = source
        source.resume()
    }

    private static func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    /// Each tick first reads back the previous tick's writes, then writes the next targets. The writes also renew
    /// the helper's lease, which returns the fans to Auto when the app stops writing for 15 s.
    private static func holdManual(_ preset: FanPreset, fans: [Fan]) {
        guard let smc = SMCSession(), let keys = link else { return manualLost("The fan controller could not be opened.") }
        let wrong = fans.first { fan in
            smc.number(fan.modeKey) != 1 || abs((smc.number(fan.targetKey) ?? -1) - (targets[fan.index] ?? -1)) > 1
        }
        mismatches = wrong == nil ? 0 : mismatches + 1
        if let wrong, mismatches >= 2 {
            return manualLost(smc.number(wrong.modeKey) != 1
                ? "macOS took fan control back, so the fans are on Auto."
                : "Fan \(wrong.index) did not keep its target speed, so the fans are on Auto.")
        }
        do { try writeTargets(preset, fans: fans, keys: keys, smc: smc) } catch { manualLost(error.localizedDescription) }
    }

    private static func manualLost(_ reason: String) {
        stopTimer()
        if let smc = SMCSession() { try? restoreAutomatic(smc) }
        log("Fan manual control ended: \(reason)")
        onManualLost?(reason)
    }

    /// The hottest CPU die sensor, smoothed over about 5 s.
    private static func cpuTemperature(_ smc: SMCSession) throws -> Double {
        guard let hottest = CPUTemperatureSensor.hottest(smc) else { throw FanError("No CPU temperature sensor was found.") }
        let next = smoothed.map { $0 + smoothing * (hottest - $0) } ?? hottest
        smoothed = next
        return next
    }

    private static func helperKeys() -> HelperFanKeys {
        if let link { return link }
        let created = HelperFanKeys()
        created.connection.interruptionHandler = { [weak created] in
            FanCommand.controlQueue.async {
                guard let created, link === created else { return }
                manualLost("The fan helper stopped, so the fans are on Auto.")
            }
        }
        link = created
        return created
    }

    private static func dropLink() {
        link?.connection.invalidate()
        link = nil
    }

    private static func log(_ message: String) {
        Task { @MainActor in LogManager.shared.info(message, source: "Fan") }
    }
}

/// Reads keys directly (no root needed) and writes them through the helper. Holding the connection holds the
/// helper's manual lease; closing it returns the fans to Auto.
nonisolated final class HelperFanKeys: FanKeyStore, @unchecked Sendable {
    let connection = FanCommand.helperConnection()
    private let reader = SMCSession()

    func number(_ key: String) -> Double? { reader?.number(key) }

    func write(_ key: String, value: Double) -> String? {
        let message = FanCommand.request(on: connection) { helper, reply in
            helper.writeFanKey(key, value: value, reply: reply)
        }
        return message.isEmpty ? nil : message
    }
}
