import Foundation

/// The fan presets, built in the app on top of the helper's one-key writes, so a rule change never needs a new
/// helper. Runs only on `FanCommand.controlQueue`.
///
/// Max: every fan's target is its own `F<n>Mx`. Cool: every 3 s the hottest CPU or GPU sensor sets the target;
/// at 55 °C or less the fans sit at `F<n>Mn`, at 75 °C or more at `F<n>Mx`, linear between (70 °C is 75%).
/// A step rises at most 800 RPM and falls at most 250 RPM per tick, so the sound changes smoothly.
nonisolated enum FanDriver {
    struct Fan {
        let index: Int
        let modeKey: String
        let targetKey: String
        let minimum: Double
        let maximum: Double
    }

    static let tick: TimeInterval = 3
    static let unlockDeadline: TimeInterval = 10
    static let coolStart = 55.0
    static let coolFull = 75.0
    static let coolRiseStep = 800.0
    static let coolFallStep = 250.0

    nonisolated(unsafe) private static var link: HelperFanKeys?
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    nonisolated(unsafe) private static var targets: [Int: Double] = [:]
    nonisolated(unsafe) private static var temperatureKeys: [String]?
    nonisolated(unsafe) static var onManualLost: (@Sendable (String) -> Void)?

    static func apply(_ preset: FanPreset) throws {
        stopTimer()
        guard let smc = SMCSession() else { throw FanError("The fan controller could not be opened.") }
        let fans = try readFans(smc)
        guard preset != .auto else { return try restoreAutomatic(smc) }
        let keys = helperKeys()
        do {
            try unlock(fans, keys: keys, smc: smc)
            let hottest: Double? = if preset == .cool { try hottestReading(smc) } else { nil }
            targets = [:]
            for fan in fans {
                let target = hottest.map { coolTarget(hottest: $0, previous: nil, minimum: fan.minimum, maximum: fan.maximum) }
                    ?? fan.maximum
                if let failure = keys.write(fan.targetKey, value: target) { throw FanError(failure) }
                targets[fan.index] = target
            }
            log("Fan \(preset.rawValue): targets \(fans.map { Int(targets[$0.index] ?? 0) }) RPM"
                + (hottest.map { ", hottest sensor \(Int($0)) °C" } ?? ""))
        } catch {
            try? restoreAutomatic(smc)
            throw error
        }
        startTimer(preset, fans: fans)
    }

    static func coolTarget(hottest: Double, previous: Double?, minimum: Double, maximum: Double) -> Double {
        let fraction = min(max((hottest - coolStart) / (coolFull - coolStart), 0), 1)
        let desired = (minimum + (maximum - minimum) * fraction).rounded()
        guard let previous else { return desired }
        let step = min(max(desired - previous, -coolFallStep), coolRiseStep)
        return min(max(previous + step, minimum), maximum).rounded()
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

    /// Apple silicon refuses `F<n>Md = 1` until `Ftst = 1` takes effect, which takes a few seconds, so the mode
    /// write repeats until it sticks or `unlockDeadline` passes.
    private static func unlock(_ fans: [Fan], keys: HelperFanKeys, smc: SMCSession) throws {
        let started = ProcessInfo.processInfo.systemUptime
        if smc.number("Ftst") == 0, let failure = keys.write("Ftst", value: 1) {
            throw FanError("macOS did not unlock fan control: \(failure)")
        }
        for fan in fans where smc.number(fan.modeKey) != 1 {
            var attempts = 0
            var lastFailure: String?
            repeat {
                attempts += 1
                lastFailure = keys.write(fan.modeKey, value: 1)
                if lastFailure == nil { break }
                Thread.sleep(forTimeInterval: 0.25)
            } while ProcessInfo.processInfo.systemUptime - started < unlockDeadline
            if let lastFailure {
                throw FanError("Fan \(fan.index) stayed under macOS control for \(Int(unlockDeadline)) s: \(lastFailure)")
            }
            log("Fan \(fan.index) manual after \(attempts) tries, "
                + String(format: "%.1f s", ProcessInfo.processInfo.systemUptime - started))
        }
    }

    private static func restoreAutomatic(_ smc: SMCSession) throws {
        defer { if FanKeyPolicy.isAutomatic(smc) { dropLink() } }
        guard !FanKeyPolicy.isAutomatic(smc) else { return }
        if let failure = FanKeyPolicy.restoreAutomatic(helperKeys()) {
            throw FanError("The fans could not return to macOS control: \(failure)")
        }
        guard FanKeyPolicy.isAutomatic(smc) else { throw FanError("A fan stayed in manual mode after Auto.") }
    }

    private static func startTimer(_ preset: FanPreset, fans: [Fan]) {
        let source = DispatchSource.makeTimerSource(queue: FanCommand.controlQueue)
        source.schedule(deadline: .now() + tick, repeating: tick, leeway: .milliseconds(250))
        source.setEventHandler { holdManual(preset, fans: fans) }
        timer = source
        source.resume()
    }

    private static func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    /// Each tick rewrites every target. That also renews the helper's lease, which returns the fans to Auto when
    /// the app stops writing for 15 s.
    private static func holdManual(_ preset: FanPreset, fans: [Fan]) {
        guard let smc = SMCSession(), let keys = link else { return manualLost("The fan controller could not be opened.") }
        guard fans.allSatisfy({ smc.number($0.modeKey) == 1 }) else {
            return manualLost("macOS took fan control back, so the fans are on Auto.")
        }
        let hottest: Double? = if preset == .cool { try? hottestReading(smc) } else { nil }
        if preset == .cool, hottest == nil { return manualLost("The chip temperature could not be read, so the fans are on Auto.") }
        for fan in fans {
            let target = hottest.map {
                coolTarget(hottest: $0, previous: targets[fan.index], minimum: fan.minimum, maximum: fan.maximum)
            } ?? fan.maximum
            if let failure = keys.write(fan.targetKey, value: target) { return manualLost(failure) }
            targets[fan.index] = target
        }
    }

    private static func manualLost(_ reason: String) {
        stopTimer()
        if let smc = SMCSession() { try? restoreAutomatic(smc) }
        dropLink()
        log("Fan manual control ended: \(reason)")
        onManualLost?(reason)
    }

    private static func hottestReading(_ smc: SMCSession) throws -> Double {
        if temperatureKeys == nil {
            // CPU performance (Tp), efficiency (Te), and GPU (Tg) dies; found once, the names differ per chip.
            temperatureKeys = smc.keyNames().filter { name in
                ["Tp", "Te", "Tg"].contains(String(name.prefix(2))) && smc.read(name)?.type == "flt "
            }
        }
        let readings = (temperatureKeys ?? []).compactMap { smc.number($0) }.filter { (10..<120).contains($0) }
        guard let hottest = readings.max() else { throw FanError("No CPU or GPU temperature sensor was found.") }
        return hottest
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

    /// Writes through the helper, then reads the key back here, so the check can change without a new helper.
    func write(_ key: String, value: Double) -> String? {
        let message = FanCommand.request(on: connection) { helper, reply in
            helper.writeFanKey(key, value: value, reply: reply)
        }
        guard message.isEmpty else { return message }
        guard let readBack = number(key), abs(readBack - value) <= 1 else {
            return "\(key) reads \(number(key).map(SMCSession.text) ?? "nothing") after writing \(SMCSession.text(value))."
        }
        return nil
    }
}
