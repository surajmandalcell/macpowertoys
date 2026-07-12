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
    private let key = "awake.configuration.v1"

    var isActive: Bool { configuration.mode != .passive && assertionID != 0 }
    var statusText: String {
        guard configuration.mode != .passive else { return "Using normal Energy settings" }
        if let remaining { return "\(configuration.mode.title) · \(Self.duration(remaining)) remaining" }
        return configuration.mode.title
    }

    private init() {
        configuration = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(AwakeConfiguration.self, from: $0) }
            ?? AwakeConfiguration()
        NotificationCenter.default.addObserver(forName: .toolActionRequested, object: nil, queue: .main) { [weak self] note in
            guard let action = note.object as? ToolActionID else { return }
            Task { @MainActor in self?.handle(action, parameters: note.userInfo as? [String: String] ?? [:]) }
        }
        applyConfiguration()
    }

    func setMode(_ mode: AwakeMode, duration: TimeInterval? = nil, until date: Date? = nil) {
        configuration.mode = mode
        switch mode {
        case .passive, .indefinite:
            configuration.expiresAt = nil
        case .timed:
            let seconds = max(1, duration ?? configuration.intervalSeconds)
            configuration.intervalSeconds = seconds
            configuration.expiresAt = Date().addingTimeInterval(seconds)
        case .until:
            configuration.expiresAt = date ?? configuration.expiresAt ?? Date().addingTimeInterval(3600)
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

    private func applyConfiguration() {
        releaseAssertion()
        assertionError = nil

        if let expiry = configuration.expiresAt, expiry <= Date(), configuration.mode != .indefinite {
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
            "PowerToys Awake is active" as CFString,
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
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.2
    }

    private func tick() {
        if let processID = configuration.attachedProcessID, kill(processID, 0) != 0 {
            configuration.attachedProcessID = nil
            setMode(.passive)
            return
        }
        if let expiry = configuration.expiresAt, expiry <= Date(), configuration.mode != .indefinite {
            setMode(.passive)
            return
        }
        updateRemaining()
    }

    private func updateRemaining() {
        remaining = configuration.expiresAt.map { max(0, $0.timeIntervalSinceNow) }
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
