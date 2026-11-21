import Foundation

/// One read of the chip's die sensors: the average of the live CPU dies (`Tp*` P-cores, `Te*` E-cores), the average
/// of the live GPU dies (`Tg*`), and the hottest single CPU die. Power-gated dies and stuck keys read -4, 0, or 40,
/// and some keys hold constants below 20, so only other readings in 20-110 °C count.
nonisolated struct FanTemperatures: Equatable, Sendable {
    var cpu: Double?
    var gpu: Double?
    var hottest: Double?

    static let dropouts: Set<Double> = [-4, 0, 40]

    static func live(_ readings: [Double]) -> [Double] {
        readings.filter { !dropouts.contains($0) && (20..<110).contains($0) }
    }

    static func reading(cpu: [Double], gpu: [Double]) -> FanTemperatures {
        let cpu = live(cpu), gpu = live(gpu)
        let mean = { (values: [Double]) in values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        return FanTemperatures(cpu: mean(cpu), gpu: mean(gpu), hottest: cpu.max())
    }
}

nonisolated enum CPUTemperatureSensor {
    static let diagnosticKey = "MPTDiagnosticCPUCelsius"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var keys: [String]?

    static func read(_ smc: SMCSession) -> FanTemperatures {
        lock.lock()
        if keys == nil {
            keys = smc.keyNames().filter { ["Tp", "Te", "Tg"].contains(String($0.prefix(2))) && smc.read($0)?.type == "flt " }
        }
        let names = keys ?? []
        lock.unlock()
        let gpu = names.filter { $0.hasPrefix("Tg") }
        return .reading(cpu: names.filter { !$0.hasPrefix("Tg") }.compactMap { smc.number($0) },
                        gpu: gpu.compactMap { smc.number($0) })
    }

    /// One raw reading for the UI. The `MPTDiagnosticCPUCelsius` default replaces the CPU average for screenshot checks.
    static func read() -> FanTemperatures? {
        let sample = UserDefaults.standard.double(forKey: diagnosticKey)
        if sample > 0 { return FanTemperatures(cpu: sample, gpu: nil, hottest: sample) }
        return SMCSession().map { read($0) }
    }
}

/// Heat steps for the Fan input, the CPU die average, which reads about 10-17 °C under the hottest core: idle and
/// light use sit under 46 °C, long builds and games hold 57-68 °C, and from 76 °C the hottest core is near the chip's
/// 100-105 °C limit. The steps are the hottest-core steps (56, 70, 85, 95 °C) through the 2026-11-21 trace fit.
nonisolated enum CPUHeat: Equatable, Sendable {
    case normal, warm, hot, veryHot, nearLimit

    init(celsius: Double) {
        self = switch celsius {
        case ..<46: .normal
        case ..<57: .warm
        case ..<68: .hot
        case ..<76: .veryHot
        default: .nearLimit
        }
    }

    var word: String {
        switch self {
        case .normal: "normal"
        case .warm: "warm"
        case .hot: "hot"
        case .veryHot: "very hot"
        case .nearLimit: "near the limit"
        }
    }

    static func help(_ celsius: Int, name: String = FanInput.cpuName) -> String {
        "\(name) \(celsius) °C · \(Self(celsius: Double(celsius)).word)"
    }
}
