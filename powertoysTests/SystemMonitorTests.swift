import AppKit
import XCTest
@testable import powertoys

final class SystemMonitorTests: XCTestCase {
    func testDiskByteFormatterUsesDecimalUnits() {
        for (bytes, expected) in [(Int64(1_000), "1KB"), (1_000_000, "1MB"),
                                  (1_000_000_000, "1GB"), (1_000_000_000_000, "1TB")] {
            XCTAssertEqual(TrayPopoverLayout.diskBytes(bytes).replacingOccurrences(of: " ", with: ""), expected)
        }
    }

    @MainActor
    func testHomeMetricsGetSamplesWithoutTheRemovedTaskManager() async throws {
        XCTAssertFalse(ToolRegistry.builtInTools.contains { $0.id == "system-monitor" })
        let service = SystemMonitorService(observesWake: false)
        let owner = "main-tray-home-test"
        service.startDetailed(owner: owner, metrics: MenuPanelMetricSampling.metrics)
        defer { service.stopDetailed(owner: owner) }
        XCTAssertEqual(service.timerOwnerCount, 1)

        let deadline = Date().addingTimeInterval(5)
        while service.history.samples(for: .cpu).count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        for metric in MenuPanelMetricSampling.metrics {
            XCTAssertGreaterThanOrEqual(service.history.samples(for: metric).count, 2, metric.title)
        }
        XCTAssertTrue(service.history.samples(for: .thermal).isEmpty)
        let snapshot = try XCTUnwrap(service.snapshot)
        XCTAssertNotNil(snapshot.cpuUsage)
        XCTAssertNotNil(snapshot.memoryUsed)
        XCTAssertNotNil(snapshot.diskTotal)

        service.stopDetailed(owner: owner)
        XCTAssertEqual(service.timerOwnerCount, 0)
    }

    @MainActor
    func testTopProcessesListTheBusiestProcessesWithBundles() async {
        let model = MenuPanelTopProcesses()
        await model.refresh(limit: 3)
        await model.refresh(limit: 3)
        XCTAssertEqual(model.rows.count, 3)
        let usage = model.rows.map { $0.process.cpuPercent ?? -1 }
        XCTAssertEqual(usage, usage.sorted(by: >))
    }

    func testMonitorSubprocessOutputIsBounded() async throws {
        do {
            _ = try await SSHProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: [String(repeating: "x", count: 2_048)],
                maximumOutputBytes: 1_024,
                timeout: 5
            )
            XCTFail("Oversized output was accepted")
        } catch SSHKeyAccessError.outputLimit {
            // Expected: the runner drains excess output without retaining it.
        }
    }

    func testSubprocessDefaultOutputIsBounded() async throws {
        do {
            _ = try await SSHProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "/bin/dd if=/dev/zero bs=65536 count=65 2>/dev/null"],
                timeout: 5
            )
            XCTFail("Default subprocess output exceeded 4 MiB")
        } catch SSHKeyAccessError.outputLimit {
            // Every caller receives a cap, including SSH key setup.
        }
    }

    func testMonitorSubprocessHasDeadline() async throws {
        do {
            _ = try await SSHProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"], timeout: 0.1
            )
            XCTFail("A stalled process exceeded its deadline")
        } catch SSHKeyAccessError.timeout {
            // Expected: the same runner bounds protected-process fallback work.
        }
    }

    func testProcessCPUUsesElapsedTimeAndRejectsCounterReset() {
        let percent = SystemMonitorProcessUsage.percent(
            previous: 1_000, current: 5_000, elapsed: 2,
            nanosecondsPerTick: 1_000_000
        )
        XCTAssertEqual(percent, 200)
        XCTAssertNil(SystemMonitorProcessUsage.percent(
            previous: 5_000, current: 1_000, elapsed: 2, nanosecondsPerTick: 1_000_000
        ))
    }

    func testNativeProcessSampleIncludesCurrentProcess() async {
        let processes = await SystemMonitorProcessSampler().sample()
        XCTAssertTrue(processes.contains { $0.pid == getpid() && !$0.name.isEmpty && $0.cpuPercent != nil })
    }

    func testSmartBatteryPropertiesReadRegistryValues() {
        let details = SystemMonitorBatteryProperties.details(from: [
            "CycleCount": NSNumber(value: 92),
            "Voltage": NSNumber(value: 12_123),
            "Amperage": NSNumber(value: -840),
            "BatteryData": [
                "NominalChargeCapacity": NSNumber(value: 7_689),
                "DesignCapacity": NSNumber(value: 8_579),
            ],
        ])

        XCTAssertEqual(details.cycleCount, 92)
        XCTAssertEqual(details.health, "89%")
        XCTAssertEqual(details.voltageMillivolts, 12_123)
        XCTAssertEqual(details.amperageMilliamps, -840)
    }

    func testVersionOnlyProcessNamesUseTheirBundleOrParent() {
        let process = SystemMonitorProcess(
            pid: 42, started: 1, name: "2.1.284", cpuPercent: 0,
            residentBytes: 1, virtualBytes: 1, threads: 1, parentPID: 1, userID: 501,
            executablePath: "/Applications/Orca.app/Contents/MacOS/2.1.284"
        )
        let row = SystemMonitorProcessHierarchy.Row(process: process, parentName: "Parent")
        XCTAssertEqual(row.displayName, "Orca (2.1.284)")
        XCTAssertEqual(row.appBundlePath, "/Applications/Orca.app")
        let nested = SystemMonitorProcess(pid: 44, started: 1, name: "Helper", cpuPercent: nil,
                                          residentBytes: 0, virtualBytes: 0, threads: 1, parentPID: 42, userID: 501,
                                          executablePath: "/Applications/My App.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper")
        XCTAssertEqual(SystemMonitorProcessHierarchy.Row(process: nested).appBundlePath,
                       "/Applications/My App.app")
        XCTAssertEqual(row.symbol, "")
        let protected = SystemMonitorProcess(
            pid: 43, started: 0, name: "2.1.282", cpuPercent: nil,
            residentBytes: 0, virtualBytes: 0, threads: 0, parentPID: 42, userID: 501,
            executablePath: "Protected process"
        )
        let child = SystemMonitorProcessHierarchy.Row(process: protected, parentName: "Orca")
        XCTAssertEqual(child.displayName, "Orca (2.1.282)")
        XCTAssertEqual(child.symbol, "")
        XCTAssertNil(child.appBundlePath)
        for path in ["/usr/bin/ssh", "/System/Library/CoreServices/launchservicesd", "Unavailable"] {
            let command = SystemMonitorProcess(pid: 45, started: 0, name: "command", cpuPercent: nil,
                residentBytes: 0, virtualBytes: 0, threads: 0, parentPID: 1, userID: 501, executablePath: path)
            let commandRow = SystemMonitorProcessHierarchy.Row(process: command)
            XCTAssertEqual(commandRow.symbol, path.hasPrefix("/") ? "terminal" : "")
            XCTAssertNil(commandRow.appBundlePath)
        }
    }

    func testSelectedProcessCountersRefreshAcrossSamples() async throws {
        let sampler = SystemMonitorProcessSampler()
        let firstRows = await sampler.sample()
        let first = try XCTUnwrap(firstRows.first { $0.pid == getpid() })
        let deadline = Date().addingTimeInterval(0.12)
        var work = 0
        while Date() < deadline { work &+= 1 }
        XCTAssertGreaterThan(work, 0)
        let nextRows = await sampler.sample()
        let next = try XCTUnwrap(nextRows.first { $0.id == first.id })
        XCTAssertGreaterThan(next.cpuPercent ?? 0, 0)
    }

    func testProtectedProcessFallbackParsesPublicCountersAndPath() {
        let row = "   1   0   0  21344 488724304   0.6 /System/Example App.app/Contents/MacOS/Example App\n"
        let result = SystemMonitorProcessSampler.parsePublicProcessInfo(row)
        XCTAssertEqual(result[1]?.parentPID, 0)
        XCTAssertEqual(result[1]?.residentBytes, 21_344 * 1_024)
        XCTAssertEqual(result[1]?.cpuPercent, 0.6)
        XCTAssertEqual(result[1]?.path, "/System/Example App.app/Contents/MacOS/Example App")
    }

    func testProcessColumnsSortBothDirectionsWithoutRowLimit() {
        let processes = (1...60).map { index in
            SystemMonitorProcess(pid: Int32(index), started: UInt64(index),
                                 name: String(format: "Process %02d", index),
                                 cpuPercent: Double(index), residentBytes: UInt64(index * 1_024),
                                 virtualBytes: 0, threads: 1, parentPID: 1,
                                 userID: 501, executablePath: "/bin/test")
        }
        XCTAssertEqual(SystemMonitorProcessSorting.sorted(processes, by: .cpu, descending: true).first?.pid, 60)
        XCTAssertEqual(SystemMonitorProcessSorting.sorted(processes, by: .memory, descending: false).first?.pid, 1)
        XCTAssertEqual(SystemMonitorProcessSorting.sorted(processes, by: .pid, descending: true).count, 60)
        XCTAssertEqual(SystemMonitorProcessSorting.sorted(processes, by: .name, descending: false).first?.pid, 1)
    }

    func testPreparedProcessRowsSortLimitAndFormatBeforeRendering() {
        let processes = (1...12).map { index in
            SystemMonitorProcess(
                pid: Int32(index),
                started: UInt64(index),
                name: "Worker \(index)",
                cpuPercent: Double(index),
                residentBytes: UInt64(index * 1_024),
                virtualBytes: 0,
                threads: 1,
                parentPID: 1,
                userID: 501,
                executablePath: "/bin/worker-\(index)"
            )
        }

        let rows = SystemMonitorProcessRows.prepare(processes, column: .cpu, descending: true, limit: 5)

        XCTAssertEqual(rows.map(\.process.pid), [12, 11, 10, 9, 8])
        XCTAssertEqual(rows.first?.cpuText, "12.0%")
        XCTAssertNotEqual(rows.first?.memoryText, "—")
    }

    func testUnknownProcessUsageSortsLastInEitherDirection() {
        let known = SystemMonitorProcess(pid: 2, started: 1, name: "Known",
                                         cpuPercent: 10, residentBytes: 1_024, virtualBytes: 0,
                                         threads: 1, parentPID: 1, userID: 501, executablePath: "/bin/known")
        let protected = SystemMonitorProcess(pid: 1, started: 0, name: "Protected",
                                             cpuPercent: nil, residentBytes: 0, virtualBytes: 0,
                                             threads: 0, parentPID: 0, userID: UInt32.max,
                                             executablePath: "Protected process")
        for column in [ProcessSortColumn.cpu, .memory] {
            XCTAssertEqual(SystemMonitorProcessSorting.sorted([protected, known], by: column, descending: false).map(\.pid), [2, 1])
            XCTAssertEqual(SystemMonitorProcessSorting.sorted([protected, known], by: column, descending: true).map(\.pid), [2, 1])
        }
    }

    @MainActor
    func testTwentyFiveLifecycleCyclesReturnEveryOwnerToBaseline() async throws {
        let service = SystemMonitorService(observesWake: true)
        XCTAssertEqual(service.timerOwnerCount, 0)
        XCTAssertEqual(service.wakeObserverOwnerCount, 1)
        let baselineHistoryCount = service.history.samples(for: .cpu).count
        for _ in 0..<25 {
            service.startDetailed(owner: "panel")
            XCTAssertEqual(service.timerOwnerCount, 1)
            service.startDetailed(owner: "panel")
            XCTAssertEqual(service.timerOwnerCount, 1)

            service.stopDetailed(owner: "panel")
            XCTAssertEqual(service.timerOwnerCount, 0)
            service.stopDetailed(owner: "panel")
            XCTAssertEqual(service.timerOwnerCount, 0)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.history.samples(for: .cpu).count, baselineHistoryCount)
        XCTAssertNil(service.snapshot)
        XCTAssertEqual(service.wakeObserverOwnerCount, 1)
    }

    func testCounterDeltasRejectResetsAndCalculateRates() throws {
        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorDelta.cpuUsage(previous: (100, 60), current: (200, 100))),
            60,
            accuracy: 0.001
        )
        XCTAssertNil(SystemMonitorDelta.cpuUsage(previous: (200, 100), current: (100, 50)))
        XCTAssertEqual(try XCTUnwrap(SystemMonitorDelta.rate(previous: 1_000, current: 3_000, seconds: 2)), 1_000)
        XCTAssertNil(SystemMonitorDelta.rate(previous: 3_000, current: 1_000, seconds: 2))
    }

    func testTickCountersReadAsUnsigned32BitValues() {
        XCTAssertEqual(SystemMonitorDelta.tickCounter(Int32.max), 2_147_483_647)
        XCTAssertEqual(SystemMonitorDelta.tickCounter(Int32.min), 2_147_483_648)
        XCTAssertEqual(SystemMonitorDelta.tickCounter(-1), 4_294_967_295)
        let beforeWrap = SystemMonitorDelta.tickCounter(-1)
        let afterWrap = SystemMonitorDelta.tickCounter(10)
        XCTAssertNil(SystemMonitorDelta.cpuUsage(previous: (beforeWrap, beforeWrap), current: (afterWrap, afterWrap)))
    }

    func testProtectedProcessInfoRefreshesOnAgeOrRestrictedSetChange() {
        let start = Date(timeIntervalSince1970: 1_000)
        let pids: Set<Int32> = [1, 42]
        let maximumAge = SystemMonitorProcessSampler.publicInfoMaximumAge
        XCTAssertTrue(SystemMonitorProcessSampler.needsPublicRefresh(
            cachedAt: nil, cachedPIDs: [], restrictedPIDs: pids, now: start))
        XCTAssertFalse(SystemMonitorProcessSampler.needsPublicRefresh(
            cachedAt: start, cachedPIDs: pids, restrictedPIDs: pids, now: start.addingTimeInterval(maximumAge - 1)))
        XCTAssertTrue(SystemMonitorProcessSampler.needsPublicRefresh(
            cachedAt: start, cachedPIDs: pids, restrictedPIDs: pids, now: start.addingTimeInterval(maximumAge)))
        XCTAssertTrue(SystemMonitorProcessSampler.needsPublicRefresh(
            cachedAt: start, cachedPIDs: pids, restrictedPIDs: [1, 43], now: start.addingTimeInterval(1)))
        XCTAssertFalse(SystemMonitorProcessSampler.needsPublicRefresh(
            cachedAt: start, cachedPIDs: pids, restrictedPIDs: [1], now: start.addingTimeInterval(1)))
    }

    func testDetailedHistoryHasABoundedCeiling() {
        var history = SystemMonitorHistory()
        for index in 0..<150 { history.append(sample(cpuUsage: Double(index)), metrics: [.cpu]) }
        history.append(sample(), metrics: [.gpu])
        XCTAssertEqual(history.samples(for: .cpu).count, 120)
        XCTAssertEqual(history.samples(for: .cpu).first?.cpuUsage, 30)
        XCTAssertEqual(history.samples(for: .cpu).last?.cpuUsage, 149)
        XCTAssertEqual(history.samples(for: .gpu).count, 1)
        XCTAssertTrue(history.samples(for: .battery).isEmpty)
        XCTAssertEqual(SystemMonitorService.maximumHistoryCount, 120)
    }

    @MainActor
    func testSamplingStaysActiveUntilEveryOwnerStops() {
        let service = SystemMonitorService(observesWake: false)

        service.startDetailed(owner: "home")
        service.startDetailed(owner: "other")
        service.stopDetailed(owner: "other")
        XCTAssertEqual(service.timerOwnerCount, 1)

        service.stopDetailed(owner: "home")
        XCTAssertEqual(service.timerOwnerCount, 0)
    }

    func testSnapshotRetainsReadingsDuringAFreshSamplerBaseline() {
        let measured = sample()
        let baseline = sample(cpuUsage: nil, networkDownload: nil, networkUpload: nil)
            .preservingAvailableValues(from: measured)
        XCTAssertEqual(baseline.cpuUsage, measured.cpuUsage)
        XCTAssertEqual(baseline.networkDownload, measured.networkDownload)
        XCTAssertEqual(baseline.networkUpload, measured.networkUpload)

        let unavailable = sample(cpuUsage: nil, unavailableMetrics: [.cpu])
            .preservingAvailableValues(from: measured)
        XCTAssertEqual(unavailable.cpuUsage, measured.cpuUsage)
        XCTAssertEqual(unavailable.lastSuccessfulReads[.cpu], measured.lastSuccessfulReads[.cpu])
    }

    private func sample(
        cpuUsage: Double? = 42.4,
        networkDownload: Double? = 2_000,
        networkUpload: Double? = 1_000,
        unavailableMetrics: Set<SystemMonitorMetric> = []
    ) -> SystemMonitorSample {
        SystemMonitorSample(
            timestamp: Date(timeIntervalSince1970: 1_000),
            cpuUsage: cpuUsage,
            memoryUsed: 6_000_000_000,
            memoryTotal: 10_000_000_000,
            gpuUsage: 22,
            networkDownload: networkDownload,
            networkUpload: networkUpload,
            diskUsed: 25,
            diskTotal: 100,
            batteryPercent: 80,
            batteryCharging: true,
            thermalState: "Nominal",
            loadAverage: (1, 2, 3),
            unavailableMetrics: unavailableMetrics
        )
    }
}
