import CoreGraphics
import Foundation
import os

/// Serves the app's event taps on their own run loop, so a busy main thread never holds system input.
nonisolated final class EventTapThread: @unchecked Sendable {
    static let shared = EventTapThread()

    private let loop: CFRunLoop

    private init() {
        let ready = DispatchSemaphore(value: 0)
        let box = OSAllocatedUnfairLock<CFRunLoop?>(uncheckedState: nil)
        let thread = Thread {
            box.withLockUnchecked { $0 = CFRunLoopGetCurrent() }
            // A port keeps the run loop alive while no tap source is attached.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            while true { CFRunLoopRun() }
        }
        thread.name = "MacPowerToys event taps"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        loop = box.withLockUnchecked { $0 }!
    }

    func add(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(loop, source, .commonModes)
        CFRunLoopWakeUp(loop)
    }

    func remove(_ source: CFRunLoopSource) {
        CFRunLoopRemoveSource(loop, source, .commonModes)
    }

    func add(_ timer: CFRunLoopTimer) {
        CFRunLoopAddTimer(loop, timer, .commonModes)
    }

    @MainActor private static var lastDisabledLog: [String: Date] = [:]

    @MainActor static func logDisabled(source: String, timeout: Bool, trusted: Bool) {
        let now = Date()
        if let last = lastDisabledLog[source], now.timeIntervalSince(last) < 10 { return }
        lastDisabledLog[source] = now
        let reason = timeout ? "a timeout" : "user input"
        let outcome = trusted ? "re-enabled it" : "stopped it because Accessibility access is off"
        LogManager.shared.warning("macOS disabled the event tap after \(reason); MacPowerToys \(outcome).", source: source)
    }
}
