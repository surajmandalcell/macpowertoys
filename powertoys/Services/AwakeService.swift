import Darwin
import Foundation
import IOKit.pwr_mgt
import Observation

@Observable
@MainActor
final class AwakeService {
    static let shared = AwakeService()

    private(set) var configuration: AwakeConfiguration
    private(set) var remaining: TimeInterval?
    private(set) var assertionError: String?

    private var assertionID = IOPMAssertionID(0)
    private var timer: Timer?
    private var timedDeadline: ContinuousClock.Instant?
    private let key = "awake.configuration.v1"

    var isActive: Bool { configuration.mode != .passive && assertionID != 0 }
    var statusText: String {
        guard configuration.mode != .passive else { return "Awake is off" }
        if let remaining { return "\(configuration.mode.title) · \(Self.duration(remaining)) remaining" }
        return configuration.mode.title
    }

    private init() {
        configuration = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(AwakeConfiguration.self, from: $0) }
            ?? AwakeConfiguration()
        if configuration.mode == .timed, let expiry = configuration.expiresAt {
            timedDeadline = .now.advanced(by: .seconds(max(0, expiry.timeIntervalSinceNow)))
        }
        NotificationCenter.default.addObserver(forName: .toolActionRequested, object: nil, queue: .main) { [weak self] note in
            guard let self, let action = note.object as? ToolActionID else { return }
            let parameters = note.userInfo as? [String: String] ?? [:]
            Task { @MainActor [self, action, parameters] in
                self.handle(action, parameters: parameters)
            }
        }
        if SettingsManager.shared.isToolEnabled("awake") {
            applyConfiguration()
        }
    }

    func setMode(_ mode: AwakeMode, duration: TimeInterval? = nil, until date: Date? = nil) {
        configuration.mode = mode
        switch mode {
        case .passive, .indefinite:
            configuration.expiresAt = nil
            timedDeadline = nil
        case .timed:
            let seconds = max(1, duration ?? configuration.intervalSeconds)
            configuration.intervalSeconds = seconds
            configuration.expiresAt = Date().addingTimeInterval(seconds)
            timedDeadline = .now.advanced(by: .seconds(seconds))
        case .until:
            configuration.expiresAt = date ?? configuration.expiresAt ?? Date().addingTimeInterval(3600)
            timedDeadline = nil
        }
        applyConfiguration()
    }

    func setKeepDisplayOn(_ enabled: Bool) {
        configuration.keepDisplayOn = enabled
        applyConfiguration()
    }

    func attach(to processID: Int32?) {
        configuration.attachedProcessID = processID
        applyConfiguration()
    }

    func setPresets(_ presets: [TimeInterval]) {
        configuration.presets = Array(Set(presets.filter { $0 >= 60 })).sorted().prefix(8).map { $0 }
        save()
    }

    func toggle() {
        setMode(configuration.mode == .passive ? .indefinite : .passive)
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        releaseAssertion()
    }

    func resume() {
        applyConfiguration()
    }

    private func applyConfiguration() {
        releaseAssertion()
        assertionError = nil

        if configuration.mode == .timed, timedDeadline == nil {
            timedDeadline = .now.advanced(by: .seconds(max(1, configuration.intervalSeconds)))
            configuration.expiresAt = Date().addingTimeInterval(max(1, configuration.intervalSeconds))
        }

        if configuration.mode == .timed,
           let timedDeadline,
           ContinuousClock.now >= timedDeadline {
            configuration.mode = .passive
            configuration.expiresAt = nil
            self.timedDeadline = nil
        }

        if configuration.mode == .until, let expiry = configuration.expiresAt, expiry <= Date() {
            configuration.mode = .passive
            configuration.expiresAt = nil
        }

        guard configuration.mode != .passive else {
            remaining = nil
            save()
            scheduleTimer()
            return
        }

        let assertionType = configuration.keepDisplayOn
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithName(
            assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MacPowerToys Awake is active" as CFString,
            &assertionID
        )
        if result != kIOReturnSuccess {
            assertionID = 0
            assertionError = "macOS could not create the power assertion (\(result))."
        }
        updateRemaining()
        save()
        scheduleTimer()
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard configuration.mode != .passive || configuration.attachedProcessID != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.tick() }
        }
        timer?.tolerance = 0.2
    }

    private func tick() {
        if let processID = configuration.attachedProcessID, kill(processID, 0) != 0 {
            configuration.attachedProcessID = nil
            setMode(.passive)
            return
        }
        switch configuration.mode {
        case .timed:
            if let timedDeadline, ContinuousClock.now >= timedDeadline {
                setMode(.passive)
                return
            }
        case .until:
            if let expiry = configuration.expiresAt, expiry <= Date() {
                setMode(.passive)
                return
            }
        case .passive, .indefinite:
            break
        }
        updateRemaining()
    }

    private func updateRemaining() {
        switch configuration.mode {
        case .timed:
            remaining = timedDeadline.map { deadline in
                let components = ContinuousClock.now.duration(to: deadline).components
                return max(0, Double(components.seconds) + Double(components.attoseconds) / 1e18)
            }
        case .until:
            remaining = configuration.expiresAt.map { max(0, $0.timeIntervalSinceNow) }
        case .passive, .indefinite:
            remaining = nil
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(configuration), forKey: key)
    }

    private func handle(_ action: ToolActionID, parameters: [String: String]) {
        switch action {
        case .awakeToggle: toggle()
        case .awakeIndefinite: setMode(.indefinite)
        case .awakeTimed:
            setMode(.timed, duration: parameters["seconds"].flatMap(TimeInterval.init) ?? 1800)
        case .awakeUntil:
            let date = parameters["date"].flatMap(ISO8601DateFormatter().date(from:))
            setMode(.until, until: date)
        default: break
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let remainingSeconds = value % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds) }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
