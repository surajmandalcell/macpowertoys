import Foundation

/// The one Cool curve: fan speed for a CPU temperature. `speed` is a fraction of each fan's own range, 0 at Mn and
/// 1 at Mx. Speed never falls as the temperature rises, so an edit can never slow the fans when the chip is hotter.
nonisolated struct FanCurve: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        var celsius: Double
        var speed: Double
    }

    static let storageKey = "fan.coolCurve"
    static let temperatureRange = 30.0...100.0
    static let standard = FanCurve(points: [Point(celsius: 65, speed: 0), Point(celsius: 90, speed: 1)])

    private(set) var points: [Point]

    /// Sorts by temperature, clamps every value, drops repeated temperatures, and keeps speed rising.
    init(points: [Point]) {
        var floor = 0.0
        var cleaned: [Point] = []
        for point in points.filter({ $0.celsius.isFinite && $0.speed.isFinite }).sorted(by: { $0.celsius < $1.celsius }) {
            let celsius = min(max(point.celsius, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
            guard cleaned.last.map({ celsius > $0.celsius }) ?? true else { continue }
            floor = max(floor, min(max(point.speed, 0), 1))
            cleaned.append(Point(celsius: celsius, speed: floor))
        }
        self.points = cleaned.count >= 2 ? cleaned : Self.standard.points
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(points: try container.decode([Point].self, forKey: .points))
    }

    static let maxPoints = 8
    /// The safety floor no curve can undercut: 0% up to 90 °C, rising to full speed at 95 °C, where Apple Silicon
    /// is close to throttling.
    static let safetyStart = 90.0
    static let safetyFull = 95.0

    var isEdited: Bool { self != Self.standard }

    /// The speed the fans run at: the drawn curve, but never below the safety floor.
    func speed(at celsius: Double) -> Double {
        max(curveSpeed(at: celsius), Self.safetyFloor(at: celsius))
    }

    static func safetyFloor(at celsius: Double) -> Double {
        min(max((celsius - safetyStart) / (safetyFull - safetyStart), 0), 1)
    }

    /// The drawn curve: a monotone cubic (Fritsch-Carlson) through the points, so it is smooth, never overshoots,
    /// and never falls. Flat at the first point's speed below it and the last point's speed above it.
    func curveSpeed(at celsius: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if celsius <= first.celsius { return first.speed }
        if celsius >= last.celsius { return last.speed }
        let upper = points.firstIndex { $0.celsius >= celsius } ?? points.count - 1
        let k = upper - 1
        let low = points[k], high = points[upper]
        let width = high.celsius - low.celsius
        let t = (celsius - low.celsius) / width
        let m = tangents
        let t2 = t * t, t3 = t2 * t
        let value = (2 * t3 - 3 * t2 + 1) * low.speed + (t3 - 2 * t2 + t) * width * m[k]
            + (-2 * t3 + 3 * t2) * high.speed + (t3 - t2) * width * m[upper]
        return min(max(value, low.speed), high.speed)
    }

    private var tangents: [Double] {
        let secants = zip(points, points.dropFirst()).map { ($1.speed - $0.speed) / ($1.celsius - $0.celsius) }
        var m = [secants[0]] + zip(secants, secants.dropFirst()).map { $0 * $1 <= 0 ? 0 : ($0 + $1) / 2 } + [secants[secants.count - 1]]
        for (k, secant) in secants.enumerated() {
            if secant == 0 { m[k] = 0; m[k + 1] = 0; continue }
            let a = m[k] / secant, b = m[k + 1] / secant
            let length = a * a + b * b
            if length > 9 {
                let scale = 3 / length.squareRoot()
                m[k] = scale * a * secant
                m[k + 1] = scale * b * secant
            }
        }
        return m
    }

    static func load(_ defaults: UserDefaults = .standard) -> FanCurve {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(FanCurve.self, from: $0) } ?? standard
    }

    func save(_ defaults: UserDefaults = .standard) {
        if isEdited, let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
