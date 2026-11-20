import AppKit
import Darwin
import ObjectiveC
import OnePlusUI
import Observation
import ServiceManagement
import Synchronization
import SwiftUI
import XCTest
@testable import powertoys

final class FanControlTests: XCTestCase {
    func testBlessedHelperNamesAndRequirementsMatchBothInfoPlists() throws {
        // SMJobBless refuses the install when the label, the app's SMPrivilegedExecutables, and the helper's
        // SMAuthorizedClients disagree with the requirements the XPC peers check.
        let contract = MacPowerToysHelperContract.self
        XCTAssertEqual(contract.machServiceName, contract.label)
        XCTAssertEqual(contract.installedPath, "/Library/PrivilegedHelperTools/" + contract.label)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        func plist(_ path: String) throws -> [String: Any] {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        }
        let app = try plist("powertoys/Info.plist")
        XCTAssertEqual(app["SMPrivilegedExecutables"] as? [String: String], [contract.label: contract.helperRequirement])
        let helper = try plist("NetToysHelper/Info.plist")
        XCTAssertEqual(helper["CFBundleIdentifier"] as? String, contract.label)
        XCTAssertEqual(helper["SMAuthorizedClients"] as? [String], [contract.mainAppRequirement])
        XCTAssertNotNil((helper["CFBundleVersion"] as? String).flatMap(Int.init))
        let launchd = try plist("NetToysHelper/launchd.plist")
        XCTAssertEqual(launchd["Label"] as? String, contract.label)
        XCTAssertEqual(launchd["MachServices"] as? [String: Bool], [contract.machServiceName: true])
        for name in ["writeFanKey:value:reply:","neighborSnapshotWithReply:", "restartAudioWithReply:"] {
            XCTAssertNotNil(protocol_getMethodDescription(MacPowerToysHelperXPCProtocol.self,
                                                          NSSelectorFromString(name), true, true).name, name)
        }
    }

    @MainActor
    func testFanHelperAndFanRowWorkWithoutNetToys() async throws {
        XCTAssertNil(ToolRegistry.tool(for: "nettoys"))
        // Registration follows the helper's own status, not a tool switch.
        let helper = FanHelperService(refreshOnInit: false, readStatus: { _ in .ready })
        XCTAssertFalse(helper.isEnabled)
        await helper.refresh()
        XCTAssertTrue(helper.isEnabled)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for path in ["powertoys/Core/FanControlService.swift", "powertoys/Core/FanHelperService.swift",
                     "powertoys/Core/MacPowerToysHelperXPC.swift", "NetToysHelper/NetToysHelperApp.swift",
                     "NetToysHelper/FanHelperDaemon.swift", "powertoys.xcodeproj/project.pbxproj"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(source.contains("import NetToys"), path)
            XCTAssertFalse(source.contains("nettoys.git"), path)
        }

        // The Fan row reads and applies through its service; the fake keeps every write out of the real helper.
        let applied = Mutex<[FanPreset]>([])
        let service = FanControlService(readSnapshot: {
            FanSnapshot(fans: [FanReading(index: 0, actualRPM: 2400, maximumRPM: 5000, mode: "auto")],
                        profile: "auto", canControl: true)
        }, applyPreset: { preset, completion in applied.withLock { $0.append(preset) }; completion(nil) })
        service.start(owner: "fan-without-nettoys")
        defer { service.stop(owner: "fan-without-nettoys") }
        await service.refresh()
        XCTAssertTrue(service.isAvailable)
        XCTAssertTrue(service.canControl)
        service.select(.max)
        for _ in 0..<100 where service.isChanging { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(applied.withLock { $0 }, [.max])
        XCTAssertEqual(service.selectedPreset, .max)
    }

    func testHelperRestoresAutoWhenTheManualClientIsLostOrSilent() {
        let store = FakeFanKeys()
        let clock = Mutex(0.0)
        let lease = FanManualLease(openStore: { store }, now: { clock.withLock { $0 } })
        let app = ObjectIdentifier(NSObject())
        let probe = ObjectIdentifier(NSObject())

        lease.clientEnded(app)
        XCTAssertTrue(store.writes.isEmpty, "A client lost while Auto must cause no write")

        XCTAssertEqual(lease.write("Ftst", value: 1, client: app), "")
        XCTAssertEqual(lease.write("F0Md", value: 1, client: app), "")
        XCTAssertNotEqual(lease.write("F0Tg", value: 9_000, client: app), "")
        lease.clientEnded(probe)
        XCTAssertTrue(lease.hasOwner, "Another client ending must not touch the fans")
        lease.clientEnded(app)
        XCTAssertFalse(lease.hasOwner)
        XCTAssertEqual(store.values["F0Md"], 0)
        XCTAssertEqual(store.values["Ftst"], 0)

        XCTAssertEqual(lease.write("Ftst", value: 1, client: app), "")
        clock.withLock { $0 = FanManualLease.timeout - 1 }
        lease.expireIfIdle()
        XCTAssertTrue(lease.hasOwner)
        clock.withLock { $0 = FanManualLease.timeout + 1 }
        lease.expireIfIdle()
        XCTAssertFalse(lease.hasOwner, "A silent client loses manual control")
        XCTAssertEqual(store.values["Ftst"], 0)
    }

    @MainActor
    func testPendingManualCommandIsQueuedBeforeExitAuto() async throws {
        let requests = Mutex<[(FanPreset, @Sendable (String?) -> Void)]>([])
        let service = FanControlService(readSnapshot: {
            FanSnapshot(fans: [FanReading(index: 0, actualRPM: 3000, maximumRPM: 5000, mode: "auto")],
                        profile: "auto", canControl: true)
        }, applyPreset: { preset, completion in requests.withLock { $0.append((preset, completion)) } })
        service.start(owner: "pending-exit-test")
        defer { service.stop(owner: "pending-exit-test") }
        await service.refresh()
        service.select(.max)
        XCTAssertEqual(requests.withLock { $0.map { $0.0 } }, [.max])
        let exit = Task { try await service.restoreAutomaticOnExit() }
        for _ in 0..<100 {
            if requests.withLock({ $0.count }) == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let queued = requests.withLock { $0 }
        XCTAssertEqual(queued.map { $0.0 }, [.max, .auto])
        queued[0].1(nil)
        queued[1].1(nil)
        try await exit.value
        XCTAssertEqual(service.selectedPreset, .auto)
    }

    @MainActor
    func testExitRestorationWaitsAndRetainsControlAfterFailure() async throws {
        let writes = FanExitWrites()
        let service = FanControlService(readSnapshot: {
            FanSnapshot(fans: [FanReading(index: 0, actualRPM: 3000, maximumRPM: 5000, mode: "auto")],
                        profile: "auto", canControl: true)
        }, applyPreset: { preset, completion in
            Task {
                do { try await writes.apply(preset); completion(nil) }
                catch { completion(error.localizedDescription) }
            }
        })
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
        }, applyPreset: { _, completion in completion(nil) })
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
        let host = NSHostingView(rootView: FanControlView(owner: owner)
            .environment(\.onePlusIsVisible, false))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 338, height: 30),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close(); window.contentView = nil; service.stop(owner: owner) }
        for visible in [false, true, false, true, false] {
            host.rootView = FanControlView(owner: owner)
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

    func testHelperWritesOnlyFanKeysInsideTheFanRange() {
        let store = FakeFanKeys()
        XCTAssertNil(FanKeyPolicy.refusal(for: "Ftst", value: 1, store: store))
        XCTAssertNil(FanKeyPolicy.refusal(for: "F1Md", value: 1, store: store))
        XCTAssertNil(FanKeyPolicy.refusal(for: "F0Tg", value: 5_777, store: store))
        XCTAssertNotNil(FanKeyPolicy.refusal(for: "F0Tg", value: 5_778, store: store))
        XCTAssertNotNil(FanKeyPolicy.refusal(for: "F0Tg", value: 1_000, store: store))
        XCTAssertNotNil(FanKeyPolicy.refusal(for: "F2Md", value: 1, store: store), "Only fans below FNum")
        XCTAssertNotNil(FanKeyPolicy.refusal(for: "F0Md", value: 2, store: store))
        XCTAssertNotNil(FanKeyPolicy.refusal(for: "Ftst", value: .nan, store: store))
        for key in ["CHTE", "F0Mx", "F0Mn", "BCLM", "Ftst0"] {
            XCTAssertNotNil(FanKeyPolicy.refusal(for: key, value: 0, store: store), key)
        }
        XCTAssertEqual(NativeFanReader.encodeNumber(1, type: "ui8 "), [1])
        XCTAssertNil(NativeFanReader.encodeNumber(1.5, type: "ui8 "))
    }

    func testCoolRampsBetweenFanMinimumAndMaximumWithSmoothSteps() {
        let target = { (hottest: Double, previous: Double?) in
            FanDriver.coolTarget(hottest: hottest, previous: previous, minimum: 1_350, maximum: 5_777)
        }
        XCTAssertEqual(target(40, nil), 1_350)
        XCTAssertEqual(target(65, 1_350), 1_350, "65 °C and below stays at the fan minimum")
        XCTAssertEqual(target(77.5, 3_500), 3_564, "Halfway between 65 and 90 °C is half the range")
        XCTAssertEqual(target(95, 5_700), 5_777)
        XCTAssertEqual(target(90, 1_350), 1_650, "Rises at most 300 RPM per tick")
        XCTAssertEqual(target(40, 5_777), 5_627, "Falls at most 150 RPM per tick")
        XCTAssertEqual(target(40, 1_400), 1_350)
        XCTAssertEqual(FanDriver.step(toward: 5_777, from: 1_350, rise: FanDriver.maxRise, fall: FanDriver.maxRise,
                                      minimum: 1_350, maximum: 5_777), 2_850, "Max climbs 1500 RPM per tick")
    }

    func testCoolCurveKeepsSpeedRisingAndFollowsEditedPoints() {
        let curve = FanCurve(points: [.init(celsius: 80, speed: 0.4), .init(celsius: 50, speed: 0.6),
                                      .init(celsius: 95, speed: 2), .init(celsius: 50, speed: 0.1)])
        XCTAssertEqual(curve.points.map(\.celsius), [50, 80, 95], "Sorted, repeated temperatures dropped")
        XCTAssertEqual(curve.points.map(\.speed), [0.6, 0.6, 1], "Speed never falls and stays inside 0...1")
        XCTAssertEqual(FanCurve(points: [.init(celsius: 70, speed: 0.5)]), .standard, "One point falls back to Cool")
        XCTAssertEqual(FanDriver.coolTarget(hottest: 87.5, previous: 5_777, minimum: 1_350, maximum: 5_777, curve: curve),
                       5_627, "An edited curve still falls at most 150 RPM per tick")
        XCTAssertFalse(FanCurve.standard.isEdited)
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

/// Two fans with this Mac's real ranges (M4 Pro: 1350-5777 RPM), all in Auto.
private final class FakeFanKeys: FanKeyStore, @unchecked Sendable {
    var values: [String: Double] = ["FNum": 2, "Ftst": 0, "F0Md": 0, "F1Md": 0, "F0Tg": 1_350, "F1Tg": 1_350,
                                    "F0Mn": 1_350, "F1Mn": 1_350, "F0Mx": 5_777, "F1Mx": 5_777]
    var writes: [String] = []

    func number(_ key: String) -> Double? { values[key] }

    func write(_ key: String, value: Double) -> String? {
        writes.append(key)
        values[key] = value
        return nil
    }
}
