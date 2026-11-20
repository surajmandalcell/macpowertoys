import Foundation

/// The one Cool curve: fan speed for a CPU temperature. `speed` is a fraction of each fan's own range, 0 at Mn and
/// 1 at Mx. Speed never falls as the temperature rises, so an edit can never slow the fans when the chip is hotter.
/// The user's points stay below `lockedEnd`, the fixed full-speed point at 90 °C where Apple Silicon is close to
/// throttling; the curve always runs through it and stays at full speed above it.
nonisolated struct FanCurve: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        var celsius: Double
        var speed: Double
    }

    static let storageKey = "fan.coolCurve"
    static let temperatureRange = 30.0...100.0
    static let lockedEnd = Point(celsius: 90, speed: 1)
    /// The highest temperature a user point may take.
    static let userCeiling = lockedEnd.celsius - 1
    static let standard = FanCurve(points: [Point(celsius: 65, speed: 0)])
    static let maxPoints = 8

    /// The user's points, all below `lockedEnd`.
    private(set) var points: [Point]

    /// Sorts by temperature, clamps every value, drops repeated temperatures and points in the locked zone, and
    /// keeps speed rising.
    init(points: [Point]) {
        var floor = 0.0
        var cleaned: [Point] = []
        for point in points.filter({ $0.celsius.isFinite && $0.speed.isFinite && $0.celsius <= Self.userCeiling })
            .sorted(by: { $0.celsius < $1.celsius }) {
            let celsius = max(point.celsius, Self.temperatureRange.lowerBound)
            guard cleaned.last.map({ celsius > $0.celsius }) ?? true else { continue }
            floor = max(floor, min(max(point.speed, 0), 1))
            cleaned.append(Point(celsius: celsius, speed: floor))
        }
        self.points = cleaned.isEmpty ? Self.standard.points : cleaned
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(points: try container.decode([Point].self, forKey: .points))
    }

    var isEdited: Bool { self != Self.standard }

    /// The user's points plus the locked end: what the curve runs through.
    private var plotted: [Point] { points + [Self.lockedEnd] }

    /// The speed the fans run at: a monotone cubic (Fritsch-Carlson) through the points and the locked end, so it
    /// is smooth, never overshoots, and never falls. Flat at the first point's speed below it, full speed from 90 °C.
    func speed(at celsius: Double) -> Double {
        let points = plotted
        guard let first = points.first, let last = points.last else { return 1 }
        if celsius <= first.celsius { return first.speed }
        if celsius >= last.celsius { return last.speed }
        let upper = points.firstIndex { $0.celsius >= celsius } ?? points.count - 1
        let k = upper - 1
        let low = points[k], high = points[upper]
        let width = high.celsius - low.celsius
        let t = (celsius - low.celsius) / width
        let m = Self.tangents(points)
        let t2 = t * t, t3 = t2 * t
        let value = (2 * t3 - 3 * t2 + 1) * low.speed + (t3 - 2 * t2 + t) * width * m[k]
            + (-2 * t3 + 3 * t2) * high.speed + (t3 - t2) * width * m[upper]
        return min(max(value, low.speed), high.speed)
    }

    private static func tangents(_ points: [Point]) -> [Double] {
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

    /// Saving a curve picks it, so it also turns Keep off: a curve and a Keep target are never on together.
    func save(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: FanHold.storageKey)
        if isEdited, let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}

/// Keep: holds the CPU near one temperature with a PI loop instead of a curve. Each 1 s tick it adds speed for every
/// degree over the target (`gain`), slowly learns the speed that holds the target (`reset`, frozen while the speed is
/// pinned at 0 or 1 so it never winds up), and moves the speed at most `ramp` a tick so the fans do not hunt.
nonisolated struct FanHold: Equatable, Sendable {
    static let storageKey = "fan.keepCelsius"
    /// 2026-11-20, normal desktop use: the hottest die read 50-78 °C, median 67 °C, over 2 minutes. A target below
    /// that would hold the fans near full speed all day, so the range starts a few degrees above the median.
    static let range = 70.0...85.0
    static let gain = 0.05
    static let reset = 0.002
    static let ramp = 0.03

    private(set) var target: Double
    private(set) var integral: Double
    private(set) var speed: Double

    /// Starts bumpless from the fans' current speed (a fraction of their range), so taking over never drops them.
    init(target: Double, speed: Double = 0) {
        self.target = Self.clamped(target)
        self.speed = min(max(speed, 0), 1)
        integral = self.speed
    }

    /// A new target keeps the learned speed, so the fans do not restart from the bottom.
    mutating func retarget(_ celsius: Double) { target = Self.clamped(celsius) }

    private static func clamped(_ celsius: Double) -> Double { min(max(celsius, range.lowerBound), range.upperBound) }

    mutating func next(celsius: Double) -> Double {
        let error = celsius - target
        let learned = integral + Self.reset * error
        let raw = Self.gain * error + learned
        if (raw < 1 || error < 0) && (raw > 0 || error > 0) { integral = min(max(learned, 0), 1) }
        let desired = min(max(Self.gain * error + integral, 0), 1)
        speed += min(max(desired - speed, -Self.ramp), Self.ramp)
        return speed
    }

    static func savedTarget(_ defaults: UserDefaults = .standard) -> Double? {
        (defaults.object(forKey: storageKey) as? Double).map(clamped)
    }

    /// Picks Keep; the saved curve stays as Custom but is not used while Keep is on.
    static func save(_ celsius: Double, _ defaults: UserDefaults = .standard) {
        defaults.set(clamped(celsius), forKey: storageKey)
    }
}
