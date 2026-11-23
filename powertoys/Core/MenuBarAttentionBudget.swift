import Foundation

/// When an animated menu bar glyph may move (DESIGN.md "Motion"): a trigger opens one short play window,
/// then the glyph holds still. Time comes in from the caller, so the rules are testable.
struct MenuBarAttentionBudget {
    enum Activity: Equatable {
        case idle
        case paused
        case running(eta: TimeInterval?)
        case failed
    }

    enum Glyph: Equatable {
        case idle
        case working
        case animating
        /// One last draw cycle after the work ends; the caller then shows `.idle`.
        case finishing
        case error
    }

    /// `.transfer` sizes the window from the ETA and plays a finish cycle; `.awake` pulses a fixed short window on
    /// turn-on and holds still when it turns off.
    enum Policy { case transfer, awake }

    static let cooldown: TimeInterval = 15 * 60
    static let awakeWindow: TimeInterval = 6
    static let noEtaWindow: TimeInterval = 45
    static let shortWindow: TimeInterval = 20
    static let longWindow: TimeInterval = 4 * 60

    private(set) var windowEnd: Date?
    private var lastTrigger: Date?
    private var lastFinish: Date?
    private var previous: Activity = .idle
    let policy: Policy

    init(policy: Policy = .transfer) { self.policy = policy }

    /// 8% of the ETA, between 20 s and 4 min; 45 s without an ETA. A job under 20 s plays to its end.
    static func windowLength(eta: TimeInterval?) -> TimeInterval {
        guard let eta else { return noEtaWindow }
        if eta < shortWindow { return .infinity }
        return min(max(eta * 0.08, shortWindow), longWindow)
    }

    mutating func update(_ activity: Activity, now: Date, motionAllowed: Bool) -> Glyph {
        defer { previous = activity }
        switch activity {
        case .failed:
            windowEnd = nil
            return .error
        case .paused:
            windowEnd = nil
            return .idle
        case .idle:
            let wasRunning = if case .running = previous { true } else { false }
            windowEnd = nil
            guard policy == .transfer, wasRunning, motionAllowed, lastFinish.map({ now.timeIntervalSince($0) >= Self.cooldown }) ?? true
            else { return .idle }
            lastFinish = now
            return .finishing
        case .running(let eta):
            let started = if case .running = previous { false } else { true }
            if started, lastTrigger.map({ now.timeIntervalSince($0) >= Self.cooldown }) ?? true {
                lastTrigger = now
                let length = policy == .awake ? Self.awakeWindow : Self.windowLength(eta: eta)
                windowEnd = length.isFinite ? now.addingTimeInterval(length) : .distantFuture
            }
            guard let end = windowEnd, now < end else {
                windowEnd = nil
                return .working
            }
            return motionAllowed ? .animating : .working
        }
    }
}
