import Foundation
import IOKit
import IOKit.pwr_mgt
import Observation
import UserNotifications

@Observable
@MainActor
final class SleepTimerService {
    enum Outcome: Equatable { case waiting, warned, slept, missed }

    static let shared = SleepTimerService(
        now: Date.init,
        sleepNow: SystemSleep.now,
        warn: SleepTimerNotice.postWarning,
        endKeepAwake: {
            let awake = AwakeService.shared
            if awake.configuration.mode != .passive { awake.setMode(.passive) }
        }
    )

    static let warningLead: TimeInterval = 60
    static let lateTolerance: TimeInterval = 5
    static let maximumMinutes = 1_440

    private(set) var deadline: Date?
    private var warned = false
    private var source: DispatchSourceTimer?
    private let now: () -> Date
    private let sleepNow: () -> Void
    private let warn: () -> Void
    private let endKeepAwake: () -> Void

    var isRunning: Bool { deadline != nil }
    var timerOwnerCount: Int { source == nil ? 0 : 1 }

    init(now: @escaping () -> Date, sleepNow: @escaping () -> Void,
         warn: @escaping () -> Void, endKeepAwake: @escaping () -> Void) {
        self.now = now
        self.sleepNow = sleepNow
        self.warn = warn
        self.endKeepAwake = endKeepAwake
    }

    func remaining(at date: Date) -> TimeInterval? {
        deadline.map { max(0, $0.timeIntervalSince(date)) }
    }

    @discardableResult
    func start(minutes: Int) -> Bool {
        guard (1...Self.maximumMinutes).contains(minutes) else { return false }
        endKeepAwake()
        let seconds = TimeInterval(minutes * 60)
        deadline = now().addingTimeInterval(seconds)
        warned = seconds <= Self.warningLead
        scheduleNextEvent()
        return true
    }

    func cancel() {
        source?.cancel()
        source = nil
        deadline = nil
        warned = false
    }

    @discardableResult
    func evaluate() -> Outcome {
        guard let deadline else { return .waiting }
        let current = now()
        if current >= deadline {
            let lateness = current.timeIntervalSince(deadline)
            cancel()
            guard lateness <= Self.lateTolerance else { return .missed }
            sleepNow()
            return .slept
        }
        if !warned, deadline.timeIntervalSince(current) <= Self.warningLead {
            warned = true
            warn()
            scheduleNextEvent()
            return .warned
        }
        scheduleNextEvent()
        return .waiting
    }

    private func scheduleNextEvent() {
        source?.cancel()
        source = nil
        guard let deadline else { return }
        let next = warned ? deadline : deadline.addingTimeInterval(-Self.warningLead)
        let interval = max(0, next.timeIntervalSince(now()))
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + interval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { _ = self?.evaluate() }
        }
        source = timer
        timer.resume()
    }
}

enum SystemSleep {
    static func now() {
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        if port != 0 {
            let result = IOPMSleepSystem(port)
            IOServiceClose(port)
            if result == kIOReturnSuccess { return }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["sleepnow"]
        try? process.run()
    }
}

enum SleepTimerNotice {
    static func postWarning() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Your Mac sleeps in 1 minute"
            content.body = "Cancel the sleep timer to keep it awake."
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "sleep-timer.warning", content: content, trigger: nil)
            )
        }
    }
}
