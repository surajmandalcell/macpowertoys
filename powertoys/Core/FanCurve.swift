import Foundation

/// The one Cool curve: fan speed for a `FanInput` temperature, the 20 s CPU (or GPU) die average. `speed` is a
/// fraction of each fan's own range, 0 at Mn and 1 at Mx. Speed never falls as the temperature rises, so an edit can
/// never slow the fans when the chip is hotter. The user's points stay below `lockedEnd`, the fixed full-speed point
/// at an 80 °C average, where the hottest core reads about 100 °C and Apple Silicon is close to throttling; the curve
/// always runs through it and stays at full speed above it.
nonisolated struct FanCurve: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        var celsius: Double
        var speed: Double
    }

    static let storageKey = "fan.coolCurve"
    static let temperatureRange = 30.0...90.0
    static let lockedEnd = Point(celsius: 80, speed: 1)
    /// The highest temperature a user point may take.
    static let userCeiling = lockedEnd.celsius - 1
    static let standard = FanCurve(points: [Point(celsius: 50, speed: 0)])

    /// The 2026-11-21 trace fit from the hottest core (the old input) to the CPU die average, both over 20 s:
    /// average = 1.4 + 0.788 × hottest. Saved temperatures from before the change move through it once.
    static let scaleKey = "fan.inputScale"
    static func averageScale(fromHottest celsius: Double) -> Double { (1.4 + 0.788 * celsius).rounded() }

    /// Moves a Custom curve and a Hold target saved on the hottest-core scale to the average scale, once. Returns a
    /// log line when something moved.
    static func migrateToAverageScale(_ defaults: UserDefaults = .standard) -> String? {
        guard defaults.integer(forKey: scaleKey) < 2 else { return nil }
        defaults.set(2, forKey: scaleKey)
        var moved: [String] = []
        // Raw points: decoding a `FanCurve` would drop old points above the new ceiling before they move.
        if let data = defaults.data(forKey: storageKey),
           let old = (try? JSONDecoder().decode([String: [Point]].self, from: data))?["points"] {
            let new = FanCurve(points: old.map { Point(celsius: averageScale(fromHottest: $0.celsius), speed: $0.speed) })
            if let encoded = try? JSONEncoder().encode(new) { defaults.set(encoded, forKey: storageKey) }
            moved.append("Custom curve \(old.map { Int($0.celsius) }) °C to \(new.points.map { Int($0.celsius) }) °C")
        }
        if let target = defaults.object(forKey: FanHold.storageKey) as? Double {
            FanHold.save(averageScale(fromHottest: target), defaults)
            moved.append("Hold \(Int(target)) °C to \(Int(FanHold.savedTarget(defaults) ?? 0)) °C")
        }
        return moved.isEmpty ? nil : "Fan input is now the CPU average: moved " + moved.joined(separator: ", ")
    }
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

    /// The curve Cool follows: the picked preset's, else the user's own.
    static func load(_ defaults: UserDefaults = .standard) -> FanCurve {
        FanCurvePreset.saved(defaults).curve ?? custom(defaults)
    }

    /// The user's own curve (the Custom card), or the standard one before any edit.
    static func custom(_ defaults: UserDefaults = .standard) -> FanCurve {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(FanCurve.self, from: $0) } ?? standard
    }

    /// Saving a curve picks Custom, so it also turns Keep and any preset off: only one pick is ever on.
    func save(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: FanHold.storageKey)
        defaults.removeObject(forKey: FanCurvePreset.storageKey)
        if isEdited, let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}

/// The fixed picks on the CPU-average scale. Quiet is by sound: it leaves the minimum early, at 48 °C, and climbs
/// gently, so heat never builds to a loud spin-up. Cool is Hold at a fixed `FanHold.coolTarget`: the PI loop keeps the
/// average near 48 °C, not a curve. Custom is the user's own curve.
nonisolated enum FanCurvePreset: String, CaseIterable, Sendable {
    case quiet, cool, custom

    static let storageKey = "fan.curvePreset"
    /// Picks the owner removed on 2026-11-23, and the pick that replaces each.
    static let retired = ["silent": FanCurvePreset.quiet, "steady": .cool]

    var name: String { rawValue.capitalized }

    var curve: FanCurve? {
        switch self {
        case .quiet: FanCurve(points: [.init(celsius: 48, speed: 0), .init(celsius: 58, speed: 0.15),
                                       .init(celsius: 66, speed: 0.32), .init(celsius: 73, speed: 0.5)])
        case .cool, .custom: nil
        }
    }

    static func saved(_ defaults: UserDefaults = .standard) -> FanCurvePreset {
        FanCurvePreset(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .custom
    }

    /// Moves a saved Silent or Steady pick to its replacement, so nobody lands on a pick that no longer exists.
    static func migrateRetired(_ defaults: UserDefaults = .standard) -> String? {
        guard let old = defaults.string(forKey: storageKey), let new = retired[old] else { return nil }
        defaults.set(new.rawValue, forKey: storageKey)
        return "Fan pick \(old.capitalized) is gone: moved to \(new.name)"
    }

    /// Picks this curve and turns Keep off.
    func pick(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: FanHold.storageKey)
        if self == .custom { defaults.removeObject(forKey: Self.storageKey) } else { defaults.set(rawValue, forKey: Self.storageKey) }
    }
}

/// Keep: holds the CPU near one temperature with a PI loop instead of a curve. Each 1 s tick it adds speed for every
/// degree over the target (`gain`), slowly learns the speed that holds the target (`reset`, frozen while the speed is
/// pinned at 0 or 1 so it never winds up), and moves the speed at most `ramp` a tick so the fans do not hunt. Inside
/// the target ± `band` nothing changes, so the fans hold one steady speed.
nonisolated struct FanHold: Equatable, Sendable {
    static let storageKey = "fan.keepCelsius"
    /// On the CPU-average scale the chart shows. Normal desktop use averages about 54 °C, so a target below that keeps
    /// the fans up all day; the owner asked for that (Cool holds 48 °C), so the floor is 40.
    static let range = 40.0...70.0
    static let defaultTarget = 62.0
    static let coolTarget = 48.0
    static let band = 2.0
    static let gain = 0.05
    static let reset = 0.002
    static let ramp = 0.03

    /// The picture of what Hold does, for the charts and the website demo: minimum fan up to 4 °C under the target,
    /// half speed at it, full speed from 4 °C over. The PI loop, not this curve, drives the fans.
    static func displayCurve(target: Double) -> FanCurve {
        FanCurve(points: [.init(celsius: target - 4, speed: 0), .init(celsius: target, speed: 0.5),
                          .init(celsius: target + 4, speed: 1)])
    }

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
        guard abs(error) > Self.band else { return speed }
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

    /// The target the fans hold now: the user's Hold, else Cool's fixed 48 °C, else nil (a curve drives them).
    static func activeTarget(_ defaults: UserDefaults = .standard) -> Double? {
        savedTarget(defaults) ?? (FanCurvePreset.saved(defaults) == .cool ? coolTarget : nil)
    }

    /// Picks Keep; the saved curve stays as Custom but is not used while Keep is on.
    static func save(_ celsius: Double, _ defaults: UserDefaults = .standard) {
        defaults.set(clamped(celsius), forKey: storageKey)
    }
}

/// What Cool follows: the CPU die average and the GPU die
/// average, each over a 20 s average, so one busy core never spins the fans up. Each goes through the curve and the
/// higher request wins. The hottest single core only guards the chip: 10 s in a row at 90 °C or more forces full
/// speed until it reads below 85 °C.
nonisolated struct FanInput: Equatable, Sendable {
    static let timeConstant = 20.0
    static let hotCelsius = 90.0
    static let hotSeconds = 10.0
    static let releaseCelsius = 85.0
    static let cpuName = "CPU avg"
    static let gpuName = "GPU avg"

    private(set) var cpu: Double?
    private(set) var gpu: Double?
    private(set) var hotFor = 0.0
    private(set) var forcesFull = false

    /// Adds one read, `elapsed` seconds after the last one. The first read starts each average.
    mutating func update(_ reading: FanTemperatures, elapsed: Double = 1) {
        let share = 1 - exp(-elapsed / Self.timeConstant)
        cpu = Self.blend(cpu, reading.cpu, share)
        gpu = Self.blend(gpu, reading.gpu, share)
        guard let hottest = reading.hottest else { return }
        hotFor = hottest >= Self.hotCelsius ? hotFor + elapsed : 0
        if hotFor >= Self.hotSeconds { forcesFull = true } else if hottest < Self.releaseCelsius { forcesFull = false }
    }

    private static func blend(_ average: Double?, _ new: Double?, _ share: Double) -> Double? {
        guard let new else { return average }
        return average.map { $0 + share * (new - $0) } ?? new
    }

    /// The average that asks for more speed, with its name, such as ("CPU avg", 62).
    var driving: (name: String, celsius: Double)? {
        switch (cpu, gpu) {
        case let (cpu?, gpu?): gpu > cpu ? (Self.gpuName, gpu) : (Self.cpuName, cpu)
        case let (cpu?, nil): (Self.cpuName, cpu)
        case let (nil, gpu?): (Self.gpuName, gpu)
        case (nil, nil): nil
        }
    }

    /// The fan speed (0-1) the curve asks for: the higher of the two requests, or full speed while the safety holds.
    func speed(_ curve: FanCurve) -> Double {
        forcesFull ? 1 : max(cpu.map(curve.speed(at:)) ?? 0, gpu.map(curve.speed(at:)) ?? 0)
    }
}
