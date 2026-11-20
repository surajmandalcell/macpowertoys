import Foundation

/// The hottest CPU die sensor: `Tp*` P-cores and `Te*` E-cores. Idle or power-gated cores read 0 and some keys hold
/// constants below 20, so only 20-110 °C counts.
nonisolated enum CPUTemperatureSensor {
    static let diagnosticKey = "MPTDiagnosticCPUCelsius"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var keys: [String]?

    static func hottest(_ smc: SMCSession) -> Double? {
        lock.lock()
        if keys == nil {
            keys = smc.keyNames().filter { ["Tp", "Te"].contains(String($0.prefix(2))) && smc.read($0)?.type == "flt " }
        }
        let names = keys ?? []
        lock.unlock()
        return names.compactMap { smc.number($0) }.filter { (20..<110).contains($0) }.max()
    }

    /// One raw reading for the UI. The `MPTDiagnosticCPUCelsius` default replaces it for screenshot checks.
    static func read() -> Double? {
        let sample = UserDefaults.standard.double(forKey: diagnosticKey)
        if sample > 0 { return sample }
        return SMCSession().flatMap(hottest)
    }
}

/// CPU temperature steps for Apple silicon. Idle and light use sit at 35-55 °C; long builds and games hold
/// 70-85 °C; the chip starts to slow itself near 100-105 °C, so 95 °C and up means it is close to that limit.
nonisolated enum CPUHeat: Equatable, Sendable {
    case normal, warm, hot, veryHot, nearLimit

    init(celsius: Double) {
        self = switch celsius {
        case ..<56: .normal
        case ..<70: .warm
        case ..<85: .hot
        case ..<95: .veryHot
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

    static func help(_ celsius: Int) -> String { "CPU \(celsius) °C · \(Self(celsius: Double(celsius)).word)" }
}
