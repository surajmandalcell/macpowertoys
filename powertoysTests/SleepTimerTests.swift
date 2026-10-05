import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class SleepTimerTests: XCTestCase {
    private final class Clock { var date = Date(timeIntervalSinceReferenceDate: 1_000_000) }

    private struct Probe {
        let service: SleepTimerService
        let clock: Clock
        let log: Log
    }

    private final class Log { var sleeps = 0; var warnings = 0; var keepAwakeEnds = 0 }

    private func makeProbe() -> Probe {
        let clock = Clock()
        let log = Log()
        let service = SleepTimerService(
            now: { clock.date },
            sleepNow: { log.sleeps += 1 },
            warn: { log.warnings += 1 },
            endKeepAwake: { log.keepAwakeEnds += 1 }
        )
        return Probe(service: service, clock: clock, log: log)
    }

    func testStartSetsDeadlineEndsKeepAwakeAndReportsRemainingTime() {
        let probe = makeProbe()
        defer { probe.service.cancel() }
        XCTAssertTrue(probe.service.start(minutes: 30))
        XCTAssertEqual(probe.log.keepAwakeEnds, 1)
        XCTAssertEqual(probe.service.deadline, probe.clock.date.addingTimeInterval(1_800))
        XCTAssertEqual(probe.service.remaining(at: probe.clock.date), 1_800)
        XCTAssertEqual(probe.service.remaining(at: probe.clock.date.addingTimeInterval(600)), 1_200)
        XCTAssertEqual(probe.service.remaining(at: probe.clock.date.addingTimeInterval(5_000)), 0)
        XCTAssertEqual(probe.service.timerOwnerCount, 1)
    }

    func testInvalidMinutesAreRejectedWithoutEndingKeepAwake() {
        let probe = makeProbe()
        for minutes in [0, -5, SleepTimerService.maximumMinutes + 1] {
            XCTAssertFalse(probe.service.start(minutes: minutes))
        }
        XCTAssertNil(probe.service.deadline)
        XCTAssertEqual(probe.log.keepAwakeEnds, 0)
        XCTAssertEqual(probe.service.timerOwnerCount, 0)
    }

    func testWarnsOnceOneMinuteBeforeThenSleepsAtTheDeadline() {
        let probe = makeProbe()
        defer { probe.service.cancel() }
        probe.service.start(minutes: 15)

        probe.clock.date.addTimeInterval(15 * 60 - 61)
        XCTAssertEqual(probe.service.evaluate(), .waiting)
        probe.clock.date.addTimeInterval(1)
        XCTAssertEqual(probe.service.evaluate(), .warned)
        XCTAssertEqual(probe.service.evaluate(), .waiting)
        XCTAssertEqual(probe.log.warnings, 1)
        XCTAssertEqual(probe.log.sleeps, 0)

        probe.clock.date.addTimeInterval(60)
        XCTAssertEqual(probe.service.evaluate(), .slept)
        XCTAssertEqual(probe.log.sleeps, 1)
        XCTAssertNil(probe.service.deadline)
        XCTAssertEqual(probe.service.timerOwnerCount, 0)
        XCTAssertEqual(probe.service.evaluate(), .waiting)
        XCTAssertEqual(probe.log.sleeps, 1)
    }

    func testCancelStopsTheTimerAndNeverSleeps() {
        let probe = makeProbe()
        probe.service.start(minutes: 15)
        probe.service.cancel()
        XCTAssertNil(probe.service.deadline)
        XCTAssertEqual(probe.service.timerOwnerCount, 0)
        probe.clock.date.addTimeInterval(3_600)
        XCTAssertEqual(probe.service.evaluate(), .waiting)
        XCTAssertEqual(probe.log.sleeps, 0)
        XCTAssertEqual(probe.log.warnings, 0)
    }

    func testDeadlineThatPassedDuringSleepIsDroppedInsteadOfSleepingAgain() {
        let probe = makeProbe()
        probe.service.start(minutes: 15)
        probe.clock.date.addTimeInterval(15 * 60 + SleepTimerService.lateTolerance + 1)
        XCTAssertEqual(probe.service.evaluate(), .missed)
        XCTAssertEqual(probe.log.sleeps, 0)
        XCTAssertNil(probe.service.deadline)
    }

    func testShortTimerSkipsTheWarning() {
        let probe = makeProbe()
        defer { probe.service.cancel() }
        probe.service.start(minutes: 1)
        XCTAssertEqual(probe.service.evaluate(), .waiting)
        probe.clock.date.addTimeInterval(60)
        XCTAssertEqual(probe.service.evaluate(), .slept)
        XCTAssertEqual(probe.log.warnings, 0)
    }

    func testRestartReplacesThePendingDeadline() {
        let probe = makeProbe()
        defer { probe.service.cancel() }
        probe.service.start(minutes: 15)
        probe.clock.date.addTimeInterval(300)
        probe.service.start(minutes: 60)
        XCTAssertEqual(probe.service.deadline, probe.clock.date.addingTimeInterval(3_600))
        XCTAssertEqual(probe.service.timerOwnerCount, 1)
        XCTAssertEqual(probe.log.keepAwakeEnds, 2)
    }

    func testRendersTheTimerCardInBothAppearances() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("tmp/redesign/captures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = SleepTimerService(now: Date.init, sleepNow: {}, warn: {}, endKeepAwake: {})
        defer { service.cancel() }
        for running in [false, true] {
            if running { service.start(minutes: 30) } else { service.cancel() }
            for scheme in [ColorScheme.light, .dark] {
                let name = scheme == .dark ? "dark" : "light"
                let view = SleepTimerCard(service: service)
                    .padding(OnePlusMetrics.appletGutter)
                    .frame(width: OnePlusWindowCanvas.awake.size.width)
                    .background(OnePlusColor.window)
                    .environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                let height = host.fittingSize.height
                host.frame = CGRect(x: 0, y: 0, width: OnePlusWindowCanvas.awake.size.width, height: height)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                defer { window.close() }
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("kwake-sleep-timer-\(running ? "running" : "idle")-\(name).png"))
                XCTAssertLessThan(height, OnePlusWindowCanvas.awake.size.height)
            }
        }
    }
}
