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

    var isEdited: Bool { self != Self.standard }

    /// Linear between points; the first point's speed below it and the last point's speed above it.
    func speed(at celsius: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if celsius <= first.celsius { return first.speed }
        if celsius >= last.celsius { return last.speed }
        let upper = points.firstIndex { $0.celsius >= celsius } ?? points.count - 1
        let low = points[upper - 1], high = points[upper]
        return low.speed + (high.speed - low.speed) * (celsius - low.celsius) / (high.celsius - low.celsius)
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
