import AppKit
import Darwin
import OnePlusUI
import Observation
import Synchronization
import SwiftUI
import XCTest
@testable import powertoys

final class FanControlTests: XCTestCase {
    @MainActor
    func testExitRestorationWaitsAndRetainsControlAfterFailure() async throws {
        let writes = FanExitWrites()
        let service = FanControlService(readSnapshot: {
            FanSnapshot(fans: [FanReading(index: 0, actualRPM: 3000, maximumRPM: 5000, mode: "auto")],
                        profile: "auto", canControl: true)
        }, applyPreset: { try await writes.apply($0) })
        service.start(owner: "exit-test")
        defer { service.stop(owner: "exit-test") }
        await service.refresh()
        service.select(.max)
        for _ in 0..<100 where service.isChanging { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(service.selectedPreset, .max)

        let first = Task { try await service.restoreAutomaticOnExit() }
        for _ in 0..<100 {
            if await writes.hasPendingAuto { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(service.isChanging)
        service.select(.cool)
        XCTAssertEqual(service.selectedPreset, .max)
        await writes.finishAuto(failing: true)
        do { try await first.value; XCTFail("Quit must receive the restore error") }
        catch { XCTAssertEqual(error.localizedDescription, "Auto failed") }
        XCTAssertEqual(service.selectedPreset, .max)
        XCTAssertEqual(service.errorMessage, "Auto failed")

        let retry = Task { try await service.restoreAutomaticOnExit() }
        for _ in 0..<100 {
            if await writes.hasPendingAuto { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await writes.finishAuto(failing: false)
        try await retry.value
        XCTAssertEqual(service.selectedPreset, .auto)
        XCTAssertFalse(service.isChanging)
        let recorded = await writes.presets
        XCTAssertEqual(recorded, [.max, .auto, .auto])
    }

    @MainActor
    func testFanDisplayCoalescesSamplesAndStopsWithItsOwner() async throws {
        let rpm = Mutex(3_000)
        let publications = Mutex<[ContinuousClock.Instant]>([])
        let service = FanControlService(readSnapshot: {
            let value = rpm.withLock { $0 += 1; return $0 }
            return FanSnapshot(fans: [FanReading(index: 0, actualRPM: Double(value), maximumRPM: 5_000, mode: "auto")],
                               profile: "auto", canControl: true)
        })
        @MainActor @Sendable func observe() async {
            withObservationTracking { _ = service.display } onChange: {
                publications.withLock { $0.append(.now) }
                Task { @MainActor in await observe() }
            }
        }
        await observe()
        service.start(owner: "fan-display-cap-test")
        defer { service.stop(owner: "fan-display-cap-test") }
        for _ in 0..<80 {
            await service.refresh()
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(300))
        let times = publications.withLock { $0 }
        XCTAssertGreaterThanOrEqual(times.count, 3)
        for (previous, current) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(previous.duration(to: current), .milliseconds(250))
        }
        XCTAssertTrue(service.display.status.hasPrefix(rpm.withLock { $0 }.formatted()))
        service.stop(owner: "fan-display-cap-test")
        XCTAssertEqual(service.pollOwnerCount, 0)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(publications.withLock { $0.count }, times.count)
    }

    func testPreparedFanTextAndIndependentAutomaticRecovery() {
        let snapshot = FanSnapshot(fans: [FanReading(index: 0, actualRPM: 3_472, maximumRPM: 5_777, mode: "manual")],
                                   profile: nil, canControl: false)
        let data = FanControlPresentation(snapshot: snapshot, canRestoreAutomatic: true)
        XCTAssertEqual(data.status, 3_472.formatted() + " RPM · 60%")
        XCTAssertNil(data.activePreset)
        XCTAssertTrue(data.canSelect(.auto))
        XCTAssertFalse(data.canSelect(.cool))
        XCTAssertFalse(data.canSelect(.max))
        for canControl in [false, true] {
            for canRestore in [false, true] {
                for changing in [false, true] {
                    for preset in FanPreset.allCases {
                        XCTAssertEqual(FanControlPresentation.canSelect(preset, canControl: canControl,
                                                                       canRestoreAutomatic: canRestore, isChanging: changing),
                                       !changing && (canControl || (preset == .auto && canRestore)))
                    }
                }
            }
        }
        XCTAssertEqual(FanControlPresentation().status, "— RPM · —%")
        XCTAssertEqual(FanControlService.minimumDisplayInterval, .milliseconds(250))
    }

    @MainActor
    func testFanViewStopsPollingWhileItsLayoutStaysMounted() async throws {
        let service = FanControlService.shared
        let owner = "fan-view-visibility-test"
        let host = NSHostingView(rootView: FanControlView(owner: owner, compact: true)
            .environment(\.onePlusIsVisible, false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 338, height: 30),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close(); window.contentView = nil; service.stop(owner: owner) }
        for visible in [false, true, false, true, false] {
            host.rootView = FanControlView(owner: owner, compact: true)
                .environment(\.onePlusIsVisible, visible)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(service.pollOwnerCount, visible ? 1 : 0)
        }
    }

    @MainActor
    func testVisibleOwnersShareAndReleaseOnePoller() {
        let service = FanControlService.shared
        for _ in 0..<25 {
            service.start(owner: "fan-test-home")
            service.start(owner: "fan-test-window")
            XCTAssertEqual(service.pollOwnerCount, 1)

            service.stop(owner: "fan-test-home")
            XCTAssertEqual(service.pollOwnerCount, 1)
            service.stop(owner: "fan-test-window")
            XCTAssertEqual(service.pollOwnerCount, 0)
        }
    }

    @MainActor
    func testFirstFanReadMarksUnavailableDataAsResolved() async {
        let service = FanControlService.shared
        service.start(owner: "fan-test-read")
        await service.refresh()
        XCTAssertTrue(service.hasCompletedRead)
        service.stop(owner: "fan-test-read")
        XCTAssertEqual(service.pollOwnerCount, 0)
    }

    func testRealFanTextReportsRPMAndPercentWithoutClaimingControl() throws {
        let sample = """
        Number of fans: 2.0

        0: Fan #0
        Actual speed: 3462.0
        Minimal speed: 1350.0
        Maximum speed: 5777.0
        Target speed: 3466.0
        Mode: forced

        1: Fan #1
        Actual speed: 3482.0
        Minimal speed: 1350.0
        Maximum speed: 5777.0
        Target speed: 3466.0
        Mode: forced
        """
        let snapshot = try XCTUnwrap(FanCommand.parseStatsFans(sample))

        XCTAssertEqual(snapshot.fans.map(\.index), [0, 1])
        XCTAssertEqual(snapshot.averageRPM, 3_472)
        XCTAssertEqual(snapshot.utilization, 60)
        XCTAssertFalse(snapshot.canControl)
        XCTAssertNil(snapshot.detectedPreset)
        XCTAssertTrue(snapshot.hasExternalManualControl)
    }

    func testReportedFanPresetDistinguishesAutomaticFromExternalControl() {
        func snapshot(_ modes: [String?]) -> FanSnapshot {
            FanSnapshot(fans: modes.enumerated().map {
                FanReading(index: $0.offset, actualRPM: 3_000, maximumRPM: 5_000, mode: $0.element)
            }, profile: nil, canControl: false)
        }
        XCTAssertEqual(FanControlView.reportedPreset(snapshot(["auto", "system"]), selectedPreset: nil), .auto)
        let cases: [[String?]] = [["manual"], ["forced"], ["auto", "manual"], ["unknown 2"], [nil], []]
        for modes in cases {
            XCTAssertNil(FanControlView.reportedPreset(snapshot(modes), selectedPreset: nil))
        }
        XCTAssertEqual(FanControlView.reportedPreset(snapshot(["manual"]), selectedPreset: .cool), .cool)
        XCTAssertNil(FanControlView.reportedPreset(nil, selectedPreset: nil))
    }

    func testNativeSMCFanDecodingAndKernelLayout() {
        XCTAssertTrue(NativeFanReader.hasExpectedLayout)
        XCTAssertEqual(NativeFanReader.decodeNumber([2], type: "ui8 "), 2)
        XCTAssertEqual(NativeFanReader.decodeNumber([0x00, 0x60, 0x58, 0x45], type: "flt "), 3_462)
        XCTAssertEqual(NativeFanReader.decodeNumber([0x36, 0x18], type: "fpe2"), 3_462)
        XCTAssertEqual(NativeFanReader.decodeNumber([0x12, 0x34], type: "ui16", littleEndianIntegers: true), 0x3412)
        XCTAssertEqual(NativeFanReader.decodeNumber([0x12, 0x34], type: "ui16", littleEndianIntegers: false), 0x1234)
        XCTAssertNil(NativeFanReader.decodeNumber([0x12], type: "ui16"))
        XCTAssertEqual(NativeFanReader.encodeNumber(3_462, type: "fpe2"), [0x36, 0x18])
        XCTAssertEqual(NativeFanReader.encodeNumber(3_462, type: "flt "), [0x00, 0x60, 0x58, 0x45])
        XCTAssertNil(NativeFanReader.encodeNumber(100_000, type: "fpe2"))
    }

    func testFanWritesRejectAnUnprivilegedProcess() {
        guard geteuid() != 0 else { return }
        XCTAssertThrowsError(try NativeFanReader.apply(.max))
    }

    func testCoolAndMaxOnlyRequestGuardedFullProfile() {
        XCTAssertEqual(FanCommand.arguments(for: .cool), ["fan", "profile", "full"])
        XCTAssertEqual(FanCommand.arguments(for: .max), ["fan", "profile", "full"])
        XCTAssertEqual(FanCommand.arguments(for: .auto), ["fan", "profile", "auto"])
    }

    func testSmctlStatusRequiresReadableFanModesForControl() throws {
        let output = """
        {"profile":"auto","fans":[
          {"index":0,"actualRPM":3462,"maximumRPM":5777,"mode":"auto"},
          {"index":1,"actualRPM":3482,"maximumRPM":5777,"mode":"system"}
        ]}
        """
        let snapshot = try XCTUnwrap(FanCommand.parseSmctlStatus(output))
        XCTAssertTrue(snapshot.canControl)
        XCTAssertEqual(snapshot.detectedPreset, .auto)
        XCTAssertEqual(snapshot.utilization, 60)

        let unknown = output.replacingOccurrences(of: "\"mode\":\"system\"", with: "\"mode\":\"unknown\"")
        XCTAssertFalse(try XCTUnwrap(FanCommand.parseSmctlStatus(unknown)).canControl)
    }

    func testFanCommandBoundsProcessOutputWithoutHardwareAccess() {
        XCTAssertThrowsError(try FanCommand.run("/usr/bin/printf", ["%262145s", "x"])) { error in
            XCTAssertEqual(error.localizedDescription, "The fan helper returned too much data.")
        }
    }

    func testFanCommandStopsProcessThatIgnoresTermination() {
        let started = Date()
        XCTAssertThrowsError(try FanCommand.run("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 30"]))
        XCTAssertLessThan(Date().timeIntervalSince(started), 9)
    }
}

private actor FanExitWrites {
    var presets: [FanPreset] = []
    private var pendingAuto: CheckedContinuation<Void, any Error>?
    var hasPendingAuto: Bool { pendingAuto != nil }
    func apply(_ preset: FanPreset) async throws {
        presets.append(preset)
        if preset == .auto {
            try await withCheckedThrowingContinuation { pendingAuto = $0 }
        }
    }
    func finishAuto(failing: Bool) {
        if failing { pendingAuto?.resume(throwing: Failure()) }
        else { pendingAuto?.resume() }
        pendingAuto = nil
    }
    private struct Failure: LocalizedError {
        var errorDescription: String? { "Auto failed" }
    }
}
