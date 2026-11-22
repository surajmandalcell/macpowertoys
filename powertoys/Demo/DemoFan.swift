//
//  DemoFan.swift
//  powertoys
//
//  Fake fan readings for the demo build. FanControlService reads these instead of the SMC, and every
//  preset change stays in memory.
//

#if MPT_DEMO
import Foundation

nonisolated enum DemoFanState {
    static let minimumRPM = 1_350.0
    static let maximumRPM = 5_777.0
    private static let lock = NSLock()
    nonisolated(unsafe) private static var celsius = 52.0
    nonisolated(unsafe) private static var rpm = 2_140.0

    static func set(celsius: Double, rpm: Double) {
        lock.withLock {
            self.celsius = celsius
            self.rpm = rpm
        }
    }

    static func snapshot() -> FanSnapshot? {
        let rpm = lock.withLock { self.rpm }
        return FanSnapshot(fans: [
            FanReading(index: 0, actualRPM: (rpm - 11).rounded(), maximumRPM: maximumRPM, mode: "manual"),
            FanReading(index: 1, actualRPM: (rpm + 11).rounded(), maximumRPM: maximumRPM, mode: "manual"),
        ], profile: nil, canControl: true)
    }

    static func temperatures() -> FanTemperatures? {
        let celsius = lock.withLock { self.celsius }
        return FanTemperatures(cpu: celsius, gpu: celsius - 9, hottest: celsius + 6)
    }

    static func apply(_ preset: FanPreset, _ done: @escaping @Sendable (String?) -> Void) {
        DemoSafety.record("fan.apply")
        done(nil)
    }
}

@MainActor
enum DemoFan {
    private static let sceneCelsius = 72.0
    private static let startSpeed = 0.45
    private static let endSpeed = 0.78
    private static let liftSteps = 20

    static func seed() {
        DemoFanState.set(celsius: 52, rpm: 2_140)
        curve(lastSpeed: startSpeed).save()
        FanControlService.shared.showDemoPreset(.cool)
    }

    /// The last curve point rises over 2 s, and the fans follow it at a steady 72 °C.
    static var scene: DemoScene {
        DemoScene(open: {
            DemoFanState.set(celsius: sceneCelsius, rpm: rpm(for: curve(lastSpeed: startSpeed)))
            ToolActionRouter.shared.open(toolID: FanPageView.pageID, activateApp: false)
        }, steps: (0...liftSteps).map { step in
            let progress = Double(step) / Double(liftSteps)
            let eased = progress * progress * (3 - 2 * progress)
            return DemoStep(at: 0.4 + progress * 2) { lift(to: startSpeed + (endSpeed - startSpeed) * eased) }
        }, tail: 2)
    }

    private static func lift(to speed: Double) {
        let curve = curve(lastSpeed: speed)
        curve.save()
        DemoFanState.set(celsius: sceneCelsius, rpm: rpm(for: curve))
        Task { await FanControlService.shared.refresh() }
    }

    private static func curve(lastSpeed: Double) -> FanCurve {
        FanCurve(points: [.init(celsius: 50, speed: 0.08), .init(celsius: 62, speed: 0.28),
                          .init(celsius: 70, speed: lastSpeed)])
    }

    private static func rpm(for curve: FanCurve) -> Double {
        DemoFanState.minimumRPM + (DemoFanState.maximumRPM - DemoFanState.minimumRPM) * curve.speed(at: sceneCelsius)
    }
}
#endif
