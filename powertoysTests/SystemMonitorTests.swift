import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

final class SystemMonitorTests: XCTestCase {
    private static let renderRemoteProfiles = [
        SystemMonitorRemoteProfile(id: "build-mac", name: "Build Mac", host: "builder@build-mac", platform: .macOS),
        SystemMonitorRemoteProfile(id: "windows-ci", name: "Windows CI", host: "builder@windows-ci", platform: .windows),
    ]

    func testWindowPageIDsMatchDeepLinks() {
        XCTAssertEqual(SystemMonitorPage.allCases.map(\.rawValue), [
            "overview", "processes", "cpu", "gpu", "memory", "network", "disk",
            "battery", "sensors", "remote", "report", "about", "settings",
        ])
    }

    func testMetricTextSeparatesCompactValuesFromUnits() {
        XCTAssertEqual(TaskManagerMetricText.parts("42%").value, "42")
        XCTAssertEqual(TaskManagerMetricText.parts("42%").unit, "%")
        XCTAssertEqual(TaskManagerMetricText.parts("1.2 GB/s").value, "1.2")
        XCTAssertEqual(TaskManagerMetricText.parts("1.2 GB/s").unit, "GB/s")
        XCTAssertEqual(TaskManagerMetricText.parts("Nominal").unit, "")
        XCTAssertEqual(TaskManagerMetricText.parts("—").value, "—")
    }

    func testDiskByteFormatterUsesDecimalUnits() {
        for (bytes, expected) in [(Int64(1_000), "1KB"), (1_000_000, "1MB"),
                                  (1_000_000_000, "1GB"), (1_000_000_000_000, "1TB")] {
            XCTAssertEqual(TrayPopoverLayout.diskBytes(bytes).replacingOccurrences(of: " ", with: ""), expected)
        }
    }

    func testTrayPagesSampleOnlyTheirMetricFamilies() {
        XCTAssertEqual(SystemMonitorTrayPage.allCases.count, 9)
        XCTAssertEqual(SystemMonitorTrayPage.home.metrics, Set(SystemMonitorMenuMetric.allCases))
        XCTAssertEqual(SystemMonitorTrayPage.cpu.metrics, [.cpu, .thermal])
        XCTAssertEqual(SystemMonitorTrayPage.gpu.metrics, [.gpu, .thermal])
        XCTAssertEqual(SystemMonitorTrayPage.memory.metrics, [.memory])
        XCTAssertEqual(SystemMonitorTrayPage.network.metrics, [.network])
        XCTAssertEqual(SystemMonitorTrayPage.disk.metrics, [.disk])
        XCTAssertEqual(SystemMonitorTrayPage.battery.metrics, [.battery])
        XCTAssertEqual(SystemMonitorTrayPage.sensors.metrics, [.thermal])
        XCTAssertEqual(SystemMonitorTrayPage.processes.metrics, [])
        XCTAssertEqual(SystemMonitorTrayPage.cpu.symbol, "cpu")
        XCTAssertEqual(SystemMonitorTrayPage.gpu.symbol, "rectangle.3.group")
    }

    @MainActor
    func testMonitorHomeFitsShortMenuBody() throws {
        let suiteName = "SystemMonitorHomeHeight.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(SystemMonitorTrayPage.home.rawValue, forKey: "systemMonitor.trayPage")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defer { SystemMonitorService.shared.stopDetailed(owner: "tray") }

        var preferredHeight: CGFloat = 0
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let screenCap = screen.height * OnePlusMenuMetrics.heightFraction
        let host = NSHostingView(rootView: SystemMonitorTrayView(remoteProfiles: Self.renderRemoteProfiles) {
            preferredHeight = $0
        }
            .defaultAppStorage(defaults)
            .frame(width: OnePlusMenuMetrics.width, height: screenCap))
        host.frame = NSRect(x: screen.minX + 32, y: screen.minY + 32,
                            width: OnePlusMenuMetrics.width, height: screenCap)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close(); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while preferredHeight <= 300 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(preferredHeight, 300)
        XCTAssertLessThanOrEqual(
            preferredHeight,
            screenCap,
            "Home must stay inside the shared visible-screen cap"
        )
    }

    @MainActor
    func testTaskManagerMenuMeasuresTabsAndAsyncProfiles() async throws {
        let suiteName = "TaskManagerMenuHeight.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defer { SystemMonitorService.shared.stopDetailed(owner: "tray") }
        defaults.set(true, forKey: "systemMonitor.rememberTrayPage")
        defaults.set(SystemMonitorTrayPage.home.rawValue, forKey: "systemMonitor.trayPage")
        SystemMonitorRemoteProfiles.save(Self.renderRemoteProfiles, defaults: defaults)

        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let proposal = NSSize(width: OnePlusMenuMetrics.width, height: screen.height * OnePlusMenuMetrics.heightFraction)
        let emptyHost = NSHostingController(rootView: SystemMonitorMenuPopoverView(remoteProfiles: [], defaults: defaults))
        let emptyHeight = emptyHost.sizeThatFits(in: proposal).height
        let popover = NSPopover()
        popover.animates = false
        let host = NSHostingController(rootView: SystemMonitorMenuPopoverView(defaults: defaults) { [weak popover] height in
            popover?.contentSize = NSSize(width: OnePlusMenuMetrics.width, height: height)
        })
        let initial = host.sizeThatFits(in: proposal)
        XCTAssertGreaterThan(initial.height, 100, "The layout tree must exist before presentation")
        host.view.setFrameSize(initial)
        popover.contentViewController = host

        let window = NSWindow(contentRect: NSRect(x: screen.minX + 32, y: screen.minY + 32, width: 400, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        window.contentView = anchor
        window.makeKeyAndOrderFront(nil)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        defer { popover.close(); popover.contentViewController = nil; window.close(); window.contentView = nil }
        func settle() async throws {
            for _ in 0..<10 {
                host.view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            host.view.layoutSubtreeIfNeeded()
        }
        try await settle()
        let homeHeight = popover.contentSize.height
        XCTAssertEqual(homeHeight, host.sizeThatFits(in: proposal).height, accuracy: 1)
        XCTAssertGreaterThan(homeHeight, emptyHeight, "The asynchronous profiles must increase Home height")
        for page in [SystemMonitorTrayPage.cpu, .processes, .sensors, .home] {
            defaults.set(page.rawValue, forKey: "systemMonitor.trayPage")
            try await settle()
            let measured = host.sizeThatFits(in: proposal)
            XCTAssertEqual(popover.contentSize.width, OnePlusMenuMetrics.width, accuracy: 1)
            XCTAssertEqual(popover.contentSize.height, measured.height, accuracy: 1, page.rawValue)
            XCTAssertGreaterThan(measured.height, 100, page.rawValue)
            XCTAssertLessThanOrEqual(measured.height, proposal.height + 1, page.rawValue)
            if page == .cpu { XCTAssertLessThanOrEqual(measured.height, 422, "CPU must keep its compact plot") }
            if page == .sensors { XCTAssertLessThanOrEqual(measured.height, 330, "Sensors must keep its compact plot") }
            if page == .cpu { XCTAssertLessThan(measured.height, homeHeight) }
            if page == .home { XCTAssertEqual(measured.height, homeHeight, accuracy: 1) }
        }
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

    func testRemoteLinuxParserAndSSHHostBoundary() throws {
        let output = """
        MPT1
        cpu 100 0 50 850 0 0 0 0 0 0
        MemTotal: 1000 kB
        MemAvailable: 250 kB
        0.25 0.50 1.00 1/100 123
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
            lo: 10 0 0 0 0 0 0 0 20 0 0 0 0 0 0 0
          eth0: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0
        /dev/vda1 4000 1000 3000 25% /
        """
        let sample = try SystemMonitorRemoteProtocol.parse(output)
        XCTAssertEqual(sample.cpuTotal, 1_000)
        XCTAssertEqual(sample.cpuIdle, 850)
        XCTAssertEqual(sample.memoryTotal, 1_024_000)
        XCTAssertEqual(sample.memoryAvailable, 256_000)
        XCTAssertEqual(sample.received, 100)
        XCTAssertEqual(sample.sent, 200)
        XCTAssertEqual(sample.diskTotal, 4_096_000)
        XCTAssertEqual(sample.diskUsed, 1_024_000)
        XCTAssertEqual(sample.load, [0.25, 0.5, 1])
        XCTAssertTrue(SystemMonitorRemoteProtocol.validHost("admin@server-1"))
        XCTAssertFalse(SystemMonitorRemoteProtocol.validHost("-oProxyCommand=sh"))
        XCTAssertFalse(SystemMonitorRemoteProtocol.validHost("server;reboot"))
        XCTAssertThrowsError(try SystemMonitorRemoteProtocol.parse(
            output.replacingOccurrences(of: "MemTotal: 1000", with: "MemTotal: 18446744073709551615")
        ))
    }

    func testRemoteMacAndWindowsReadings() throws {
        for (platform, marker) in [(SystemMonitorRemotePlatform.macOS, "MPTMAC1"),
                                   (.windows, "MPTWIN1")] {
            let output = "\(marker)\nCPU=25.5\nMEM=8000000\nAVAILABLE=2000000\nDISK=10000000,4000000\nNET=100,200\n"
            let sample = try SystemMonitorRemoteProtocol.parseKeyed(output, platform: platform)
            XCTAssertEqual(sample.cpuPercent, 25.5)
            XCTAssertEqual(sample.memoryAvailable, 2_000_000)
            XCTAssertEqual(sample.diskUsed, 4_000_000)
            XCTAssertThrowsError(try SystemMonitorRemoteProtocol.parseKeyed(
                output.replacingOccurrences(of: "AVAILABLE=2000000", with: "AVAILABLE=9000000"),
                platform: platform
            ))
        }
        XCTAssertTrue(try SystemMonitorRemoteProtocol.arguments(host: "server", platform: .windows).last?
            .contains("-EncodedCommand") == true)
    }

    func testRemoteProfilesMigrateLegacyHostAndRoundTrip() throws {
        let suiteName = "SystemMonitorRemoteProfiles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("builder@ci1", forKey: "systemMonitor.remoteHost")
        defaults.set(SystemMonitorRemotePlatform.macOS.rawValue, forKey: "systemMonitor.remotePlatform")
        defaults.set(5, forKey: "systemMonitor.remoteInterval")
        defaults.set(Data("[]".utf8), forKey: SystemMonitorRemoteProfiles.key)

        let migrated = try XCTUnwrap(SystemMonitorRemoteProfiles.load(defaults: defaults).first)
        XCTAssertEqual(migrated.host, "builder@ci1")
        XCTAssertEqual(migrated.name, "ci1")
        XCTAssertEqual(migrated.platform, .macOS)
        XCTAssertEqual(migrated.interval, 5)

        let second = SystemMonitorRemoteProfile(name: "Windows lab", host: "win1", platform: .windows, interval: 10)
        SystemMonitorRemoteProfiles.save([migrated, second], defaults: defaults)
        XCTAssertEqual(SystemMonitorRemoteProfiles.load(defaults: defaults), [migrated, second])
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

    func testShortHistoryStaysAtChartRightEdge() {
        XCTAssertEqual(
            TaskManagerChartGeometry.xPositions(count: 3, capacity: 11, width: 100),
            [80, 90, 100]
        )
        XCTAssertEqual(
            TaskManagerChartGeometry.sampleIndex(at: 91, count: 3, capacity: 11, width: 100),
            1
        )
    }

    func testVersionOnlyProcessNamesUseTheirBundleOrParent() {
        let process = SystemMonitorProcess(
            pid: 42, started: 1, name: "2.1.284", cpuPercent: 0,
            residentBytes: 1, virtualBytes: 1, threads: 1, parentPID: 1, userID: 501,
            executablePath: "/Applications/Orca.app/Contents/MacOS/2.1.284"
        )
        let row = SystemMonitorProcessHierarchy.Row(process: process, depth: 0, parentName: "Parent")
        XCTAssertEqual(row.displayName, "Orca (2.1.284)")
        XCTAssertEqual(row.symbol, "app")
        let protected = SystemMonitorProcess(
            pid: 43, started: 0, name: "2.1.282", cpuPercent: nil,
            residentBytes: 0, virtualBytes: 0, threads: 0, parentPID: 42, userID: 501,
            executablePath: "Protected process"
        )
        let child = SystemMonitorProcessHierarchy.Row(process: protected, depth: 1, parentName: "Orca")
        XCTAssertEqual(child.displayName, "Orca (2.1.282)")
        XCTAssertEqual(child.symbol, "lock")
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

    func testSystemReportFlattensInventoryAndOmitsIdentifiers() throws {
        let json = """
        {
          "SPHardwareDataType": [{
            "_name": "Hardware",
            "machine_name": "Mac",
            "serial_number": "SECRET",
            "details": { "core_count": 14 },
            "families": ["Performance", "Efficiency"]
          }]
        }
        """
        let source = TaskManagerSystemReportParser.Source(
            id: "hardware", title: "Hardware overview", symbol: "desktopcomputer",
            group: "Hardware", dataType: "SPHardwareDataType"
        )
        let category = try XCTUnwrap(TaskManagerSystemReportParser.parse(
            data: Data(json.utf8), sources: [source]
        ).first)
        let rows = category.sections.flatMap(\.rows)

        XCTAssertTrue(rows.contains { $0.field == "Model name" && $0.value == "Mac" })
        XCTAssertTrue(rows.contains { $0.field == "Details · Core count" && $0.value == "14" })
        XCTAssertTrue(rows.contains { $0.field == "Families" && $0.value == "Performance, Efficiency" })
        XCTAssertFalse(rows.contains { $0.field.localizedCaseInsensitiveContains("serial") || $0.value == "SECRET" })
    }

    func testSystemReportNormalizesHardwareAndKeepsRawExportValues() throws {
        let json = """
        {"SPHardwareDataType":[{"_name":"hardware_overview",
        "number_processors":"proc 14:0:10:4","chip_type":"Apple M4 Pro"}]}
        """
        let category = try XCTUnwrap(TaskManagerSystemReportParser.parse(data: Data(json.utf8)).first)
        let section = try XCTUnwrap(category.sections.first)
        XCTAssertEqual(section.title, "Hardware overview")
        XCTAssertEqual(section.rawTitle, "hardware_overview")
        let processor = try XCTUnwrap(section.rows.first { $0.field == "CPU cores" })
        XCTAssertEqual(processor.value, "14 cores, 10 performance, 4 efficiency")
        XCTAssertEqual(processor.rawField, "number_processors")
        XCTAssertEqual(processor.rawValue, "proc 14:0:10:4")
        XCTAssertTrue(section.rows.contains { $0.field == "Chip" && $0.value == "Apple M4 Pro" })
        for invalid in ["proc 14:0:10:5", "proc -14:0:10:4", "proc 14::10:4", "proc 14:0:10:4:0"] {
            let data = Data(json.replacingOccurrences(of: "proc 14:0:10:4", with: invalid).utf8)
            let rows = try TaskManagerSystemReportParser.parse(data: data)[0].sections[0].rows
            XCTAssertEqual(rows.first { $0.field == "CPU cores" }?.value, invalid)
        }
    }

    func testSystemReportSearchBuildsStableMatches() throws {
        let category = TaskManagerReportCategory(
            id: "hardware",
            title: "Hardware",
            symbol: "desktopcomputer",
            group: "Hardware",
            sections: [TaskManagerReportSection(
                title: "Memory",
                rows: [
                    TaskManagerReportRow(field: "Type", value: "Unified"),
                    TaskManagerReportRow(field: "Capacity", value: "32 GB"),
                ]
            )]
        )

        let matches = TaskManagerReportSearch.matches(query: "32 gb", categories: [category])

        XCTAssertEqual(matches.map(\.id), ["hardware:0:1"])
        XCTAssertEqual(matches.first?.row.field, "Capacity")
        XCTAssertTrue(TaskManagerReportSearch.matches(query: " ", categories: [category]).isEmpty)
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

    func testPreparedProcessRowsFilterSortLimitAndFormatBeforeRendering() {
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

        let result = SystemMonitorProcessRows.prepare(
            processes,
            search: "worker",
            hierarchy: false,
            column: .cpu,
            descending: true,
            limit: 5
        )

        XCTAssertEqual(result.matchingCount, 12)
        XCTAssertEqual(result.rows.map(\.process.pid), [12, 11, 10, 9, 8])
        XCTAssertEqual(result.rows.first?.cpuText, "12.0%")
        XCTAssertNotEqual(result.rows.first?.memoryText, "—")
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

    func testProcessHierarchyKeepsEveryPIDAndSortsSiblings() {
        let rows = [
            SystemMonitorProcess(pid: 1, started: 1, name: "Parent", cpuPercent: 1,
                                 residentBytes: 1, virtualBytes: 1, threads: 1, parentPID: 0,
                                 userID: 501, executablePath: "/bin/parent"),
            SystemMonitorProcess(pid: 2, started: 2, name: "Busy", cpuPercent: 30,
                                 residentBytes: 1, virtualBytes: 1, threads: 1, parentPID: 1,
                                 userID: 501, executablePath: "/bin/busy"),
            SystemMonitorProcess(pid: 3, started: 3, name: "Quiet", cpuPercent: 2,
                                 residentBytes: 1, virtualBytes: 1, threads: 1, parentPID: 1,
                                 userID: 501, executablePath: "/bin/quiet"),
        ]
        let grouped = SystemMonitorProcessHierarchy.rows(Array(rows.reversed()), by: .cpu, descending: true)
        XCTAssertEqual(grouped.map(\.process.pid), [1, 2, 3])
        XCTAssertEqual(grouped.map(\.depth), [0, 1, 1])
        XCTAssertEqual(SystemMonitorProcessPorts.parse("p42\nnTCP 127.0.0.1:9000\nnTCP 127.0.0.1:9000\nnUDP *:53\n"),
                       ["TCP 127.0.0.1:9000", "UDP *:53"])
    }

    @MainActor
    func testProcessDetailRendersAtReferenceSize() throws {
        let process = SystemMonitorProcess(
            pid: 4_281, started: UInt64(Date().addingTimeInterval(-3_600).timeIntervalSince1970 * 1_000_000),
            name: "Xcode", cpuPercent: 18.4, residentBytes: 1_842_000_000,
            virtualBytes: 428_000_000_000, threads: 34, parentPID: 1,
            userID: 501, executablePath: "/Applications/Xcode.app/Contents/MacOS/Xcode"
        )
        let host = NSHostingView(rootView: ProcessDetailSheet(
            process: process, parentName: "launchd", childCount: 3,
            endpoints: ["TCP 127.0.0.1:62541 → 127.0.0.1:62542"], endpointsLoaded: true,
            lastUpdated: Date(), onQuit: {}, onForceQuit: {}, onDone: {}
        ))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: 450, height: 520)
        host.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(representation)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Task Manager — Process Detail"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testNonMetricPagesReleaseDetailedSampling() {
        let service = SystemMonitorService(
            menuSettings: SystemMonitorMenuSettings(), toolEnabled: true, observesWake: false
        )
        service.startDetailed(metrics: [])
        XCTAssertEqual(service.timerOwnerCount, 0)
        service.updateDetailed(metrics: [.memory])
        XCTAssertEqual(service.timerOwnerCount, 1)
        service.updateDetailed(metrics: [])
        XCTAssertEqual(service.timerOwnerCount, 0)
        service.startDetailed(owner: "tray")
        XCTAssertEqual(service.timerOwnerCount, 1)
        service.stopDetailed(owner: "tray")
        service.stopDetailed()
        XCTAssertEqual(service.timerOwnerCount, 0)
    }

    @MainActor
    func testHistoryChartsStayInsideTheirRequestedPlotHeight() throws {
        let margin: CGFloat = 24
        for scheme in [ColorScheme.dark, .light] {
            for (height, compact) in [(CGFloat(72), false), (138, false), (19, true)] {
                let host = NSHostingView(rootView: TaskManagerHistoryChart(
                    values: [0, 0], range: 0...1, unit: "W", compact: compact, sampleCapacity: 2,
                    upperScaleLabel: "1 W", middleScaleLabel: "0.5 W", lowerScaleLabel: "0 W"
                ).frame(width: 320, height: height)
                    .padding(.vertical, margin)
                    .background(OnePlusColor.window)
                    .environment(\.colorScheme, scheme))
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame.size = NSSize(width: 320, height: height + 2 * margin)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let background = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
                let scale = CGFloat(bitmap.pixelsHigh) / host.bounds.height
                let x = bitmap.pixelsWide * 3 / 4
                let plotRows = Int(margin * scale)..<Int((margin + height) * scale)
                var paintedPlot = false
                for y in 0..<bitmap.pixelsHigh {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let difference = max(abs(color.redComponent - background.redComponent),
                                         abs(color.greenComponent - background.greenComponent),
                                         abs(color.blueComponent - background.blueComponent))
                    if plotRows.contains(y) {
                        paintedPlot = paintedPlot || difference > 0.01
                    } else {
                        XCTAssertLessThanOrEqual(difference, 0.01, "\(scheme), \(height)pt, row \(y)")
                    }
                }
                XCTAssertTrue(paintedPlot, "The chart must still render inside its \(height)pt plot")
            }
        }
    }

    @MainActor
    func testDitherSparklineDrawsSamples() throws {
        func render(_ values: [Double]) throws -> (NSBitmapImageRep, NSImage) {
            let host = NSHostingView(rootView: SystemMonitorDitherSparkline(
                values: values, color: SystemMonitorPalette.cyan, showsGuide: true
            ).frame(width: 320, height: 80))
            host.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
            host.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(representation)
            return (representation, image)
        }

        let empty = try render([])
        let populated = try render([12, 18, 9, 24, 17, 28])
        XCTAssertNotEqual(empty.0.representation(using: .png, properties: [:]),
                          populated.0.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(image: populated.1)
        attachment.name = "Task Manager — Dithered Chart"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTaskManagerPagesRenderAtProductionSize() throws {
        let suiteName = "TaskManagerWindowRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reportSnapshot = TaskManagerSystemReportParser.sources.map { source in
            TaskManagerReportCategory(
                id: source.id,
                title: source.title,
                symbol: source.symbol,
                group: source.group,
                sections: [TaskManagerReportSection(
                    title: source.id == "hardware" ? "Hosted Mac" : source.title,
                    rows: source.id == "hardware" ? [
                        TaskManagerReportRow(field: "Model name", value: "Mac"),
                        TaskManagerReportRow(field: "Model identifier", value: "VirtualMac"),
                        TaskManagerReportRow(field: "Chip", value: "Apple Silicon"),
                        TaskManagerReportRow(field: "CPU cores", value: "3"),
                        TaskManagerReportRow(field: "Memory", value: "7 GB"),
                        TaskManagerReportRow(field: "Architecture", value: "arm64"),
                    ] : [TaskManagerReportRow(field: "Status", value: "Available")]
                )]
            )
        }
        SystemMonitorService.shared.startDetailed(owner: "render")
        defer { SystemMonitorService.shared.stopDetailed(owner: "render") }
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        let pages = [
            "overview", "processes", "cpu", "gpu", "memory", "network", "disk",
            "battery", "sensors", "remote", "report", "about", "settings",
        ]
        for page in pages {
            defaults.set(page, forKey: "systemMonitor.windowPage")
            let host = NSHostingView(rootView: SystemMonitorWindowView(
                reportSnapshot: reportSnapshot,
                remoteProfiles: Self.renderRemoteProfiles
            )
                .defaultAppStorage(defaults))
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(origin: .zero, size: TaskManagerTheme.windowContentSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(1.2))

            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(representation)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Task Manager — \(page)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testSystemMonitorTrayRendersAtProductionWidth() throws {
        let suiteName = "SystemMonitorTrayRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defer { SystemMonitorService.shared.stopDetailed(owner: "tray") }
        for scheme in [ColorScheme.dark, .light] {
            for page in ["home", "cpu", "gpu", "memory", "network", "disk", "battery", "sensors", "processes"] {
                defaults.set(page, forKey: "systemMonitor.trayPage")
                var measuredHeight: CGFloat = 0
                let host = NSHostingView(rootView: SystemMonitorMenuPopoverView(
                    remoteProfiles: Self.renderRemoteProfiles,
                    defaults: defaults,
                    onPreferredHeight: { measuredHeight = $0 }
                ).environment(\.colorScheme, scheme))
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                let screen = try XCTUnwrap(NSScreen.main).visibleFrame
                host.frame = NSRect(
                    x: screen.minX + 32, y: screen.minY + 32,
                    width: OnePlusMenuMetrics.width,
                    height: screen.height * OnePlusMenuMetrics.heightFraction
                )
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                defer { window.close(); window.contentView = nil }
                host.layoutSubtreeIfNeeded()
                let deadline = Date().addingTimeInterval(2)
                while host.fittingSize.height <= 100 && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                    host.layoutSubtreeIfNeeded()
                }
                let size = host.fittingSize
                XCTAssertEqual(size.width, OnePlusMenuMetrics.width, accuracy: 1)
                XCTAssertGreaterThan(size.height, 100, "\(page): \(scheme)")
                XCTAssertLessThanOrEqual(size.height, (NSScreen.main?.visibleFrame.height ?? 800) * OnePlusMenuMetrics.heightFraction + 1)
                XCTAssertEqual(measuredHeight, size.height, accuracy: 1)
                host.frame.size = size
                host.layoutSubtreeIfNeeded()

                let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: representation)
                let image = NSImage(size: host.bounds.size)
                image.addRepresentation(representation)
                let attachment = XCTAttachment(image: image)
                attachment.name = "Task Manager Menu — \(page.capitalized) — \(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testTwentyFiveLifecycleCyclesReturnEveryOwnerToBaseline() async throws {
        let menuSettings = SystemMonitorMenuSettings(
            enabled: true,
            items: [SystemMonitorMenuItemConfiguration(metric: .cpu, enabled: true)]
        )
        let menuService = SystemMonitorService(
            menuSettings: menuSettings,
            toolEnabled: false,
            observesWake: true
        )

        XCTAssertEqual(menuService.timerOwnerCount, 0)
        XCTAssertEqual(menuService.statusItemOwnerCount, 0)
        XCTAssertEqual(menuService.wakeObserverOwnerCount, 1)
        for _ in 0..<25 {
            menuService.setToolEnabled(true)
            XCTAssertEqual(menuService.timerOwnerCount, 1)
            XCTAssertEqual(menuService.statusItemOwnerCount, 1)
            XCTAssertEqual(menuService.wakeObserverOwnerCount, 1)
            menuService.setToolEnabled(true)
            XCTAssertEqual(menuService.timerOwnerCount, 1)

            menuService.setToolEnabled(false)
            XCTAssertEqual(menuService.timerOwnerCount, 0)
            XCTAssertEqual(menuService.statusItemOwnerCount, 0)
            XCTAssertEqual(menuService.wakeObserverOwnerCount, 1)
            menuService.setToolEnabled(false)
            XCTAssertEqual(menuService.timerOwnerCount, 0)
        }

        let detailService = SystemMonitorService(
            menuSettings: SystemMonitorMenuSettings(),
            toolEnabled: true,
            observesWake: true
        )
        let baselineHistoryCount = detailService.history.samples(for: .cpu).count
        for _ in 0..<25 {
            detailService.startDetailed()
            XCTAssertEqual(detailService.timerOwnerCount, 1)
            detailService.startDetailed()
            XCTAssertEqual(detailService.timerOwnerCount, 1)

            detailService.stopDetailed()
            XCTAssertEqual(detailService.timerOwnerCount, 0)
            detailService.stopDetailed()
            XCTAssertEqual(detailService.timerOwnerCount, 0)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(menuService.history.isEmpty)
        XCTAssertNil(menuService.snapshot)
        XCTAssertEqual(detailService.history.samples(for: .cpu).count, baselineHistoryCount)
        XCTAssertNil(detailService.snapshot)
        XCTAssertEqual(detailService.statusItemOwnerCount, 0)
        XCTAssertEqual(detailService.wakeObserverOwnerCount, 1)
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
    func testDetailedSamplingStaysActiveUntilEverySurfaceCloses() {
        let service = SystemMonitorService(
            menuSettings: SystemMonitorMenuSettings(),
            toolEnabled: true,
            observesWake: false
        )

        service.startDetailed(owner: "window")
        service.startDetailed(owner: "tray")
        service.stopDetailed(owner: "tray")
        XCTAssertTrue(service.detailedActive)
        XCTAssertEqual(service.timerOwnerCount, 1)

        service.stopDetailed(owner: "window")
        XCTAssertFalse(service.detailedActive)
        XCTAssertEqual(service.timerOwnerCount, 0)
    }

    @MainActor
    func testLegacyMenuSettingsLoadWhenCurrentSettingsAreAbsent() throws {
        let suite = "SystemMonitorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = SystemMonitorMenuSettings(
            enabled: true,
            mode: .direct,
            interval: 3,
            metrics: [.network]
        )
        defaults.set(try JSONEncoder().encode(expected), forKey: SystemMonitorService.legacySettingsKey)

        XCTAssertEqual(SystemMonitorService.storedMenuSettings(in: defaults), expected)
    }

    func testLegacyMetricsMigrateToOrderedConfigurations() throws {
        let legacy = """
        {"enabled":true,"mode":"direct","interval":3,"metrics":["network","cpu"]}
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(SystemMonitorMenuSettings.self, from: legacy)

        XCTAssertEqual(settings.items.map(\.metric), SystemMonitorMenuMetric.allCases)
        XCTAssertEqual(settings.enabledItems.map(\.metric), [.cpu, .network])
        XCTAssertTrue(settings.enabledItems.allSatisfy { $0.interval == .global })
        XCTAssertEqual(settings.schemaVersion, SystemMonitorMenuSettings.currentSchemaVersion)
        XCTAssertEqual(settings.items.first(where: { $0.metric == .gpu })?.interval, .seconds5)
    }

    func testConfigurationsRoundTripWithoutLosingOrderOrCustomization() throws {
        let expected = SystemMonitorMenuSettings(
            enabled: true,
            mode: .direct,
            interval: 10,
            items: [
                SystemMonitorMenuItemConfiguration(
                    metric: .network,
                    enabled: true,
                    style: .valueOnly,
                    interval: .seconds3,
                    networkDirection: .upload,
                    networkUnit: .bits
                ),
                SystemMonitorMenuItemConfiguration(
                    metric: .memory,
                    enabled: true,
                    style: .iconOnly,
                    symbol: "chart.bar.fill",
                    memoryUnit: .available
                ),
                SystemMonitorMenuItemConfiguration(
                    metric: .disk,
                    enabled: false,
                    diskUnit: .available,
                    batteryDisplay: .both,
                    thermalDisplay: .full
                )
            ]
        )

        let decoded = try JSONDecoder().decode(
            SystemMonitorMenuSettings.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded, expected)
        XCTAssertEqual(decoded.items.prefix(3).map(\.metric), [.network, .memory, .disk])
        XCTAssertEqual(decoded.schemaVersion, SystemMonitorMenuSettings.currentSchemaVersion)
    }

    @MainActor
    func testMixedMenuPlacementsCreateCombinedAndSeparateItems() throws {
        let suiteName = "SystemMonitorPlacements.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SystemMonitorMenuController(defaults: defaults)
        var settings = SystemMonitorMenuSettings(enabled: true, items: [
            SystemMonitorMenuItemConfiguration(metric: .cpu, enabled: true, placement: .separate),
            SystemMonitorMenuItemConfiguration(metric: .memory, enabled: true, placement: .combined),
        ])
        settings = try JSONDecoder().decode(SystemMonitorMenuSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(settings.separateItems.map(\.metric), [.cpu])
        XCTAssertEqual(settings.combinedItems.map(\.metric), [.memory])
        controller.configure(settings: settings)
        XCTAssertEqual(controller.statusItemCount, 2)
        settings.enabled = false
        controller.configure(settings: settings)
    }

    func testVersionOneItemsDecodeWithNewFormatDefaultsAndEncodeCurrentSchema() throws {
        let versionOne = """
        {"enabled":true,"mode":"grouped","interval":2,"items":[{"metric":"battery","enabled":true,"style":"valueOnly","symbol":"battery.75percent","interval":"seconds1","memoryUnit":"percentage","networkDirection":"both"}]}
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(SystemMonitorMenuSettings.self, from: versionOne)
        let battery = try XCTUnwrap(settings.items.first(where: { $0.metric == .battery }))
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )

        XCTAssertEqual(settings.schemaVersion, SystemMonitorMenuSettings.currentSchemaVersion)
        XCTAssertEqual(battery.batteryDisplay, .percentage)
        XCTAssertEqual(battery.networkUnit, .bytes)
        XCTAssertEqual(battery.diskUnit, .percentage)
        XCTAssertEqual(battery.thermalDisplay, .compact)
        XCTAssertEqual(encoded["schemaVersion"] as? Int, SystemMonitorMenuSettings.currentSchemaVersion)
    }

    func testEnabledMenuRestoresRAMAndValidatesSymbols() {
        var settings = SystemMonitorMenuSettings(
            items: [SystemMonitorMenuItemConfiguration(metric: .cpu, symbol: "not-a-symbol")]
        )
        settings.items[0].enabled = false
        settings.normalize()

        XCTAssertEqual(settings.items.count, SystemMonitorMenuMetric.allCases.count)
        XCTAssertTrue(settings.enabledItems.isEmpty)
        XCTAssertEqual(settings.items[0].symbol, SystemMonitorMenuMetric.cpu.symbol)
        settings.enabled = true
        settings.normalize()
        XCTAssertEqual(settings.enabledItems.map(\.metric), [.memory])
        XCTAssertEqual(settings.combinedItems.map(\.metric), [.memory])
        XCTAssertEqual(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: false), 10)
    }

    func testFirstMenuPlacementDoesNotEnableOtherLegacyDefaults() {
        var settings = SystemMonitorMenuSettings()
        XCTAssertFalse(settings.enabled)
        settings.setPlacement(.separate, for: .cpu)
        XCTAssertEqual(settings.enabledItems.map(\.metric), [.cpu])
        XCTAssertEqual(settings.separateItems.map(\.metric), [.cpu])
        settings.setPlacement(.off, for: .cpu)
        XCTAssertFalse(settings.enabled)
        XCTAssertTrue(settings.enabledItems.isEmpty)
        settings.enabled = true
        settings.normalize()
        XCTAssertEqual(settings.enabledItems.map(\.metric), [.memory])
    }

    func testNoOpSettingsMutationProducesNoUpdate() throws {
        let settings = SystemMonitorMenuSettings(enabled: true)

        XCTAssertNil(settings.applying { $0.interval = 10 })
        let changed = try XCTUnwrap(settings.applying { $0.interval = 5 })
        XCTAssertEqual(changed.interval, 5)
    }

    func testDirectOrderChangeReturnsOnlyMetricPositionKeys() {
        let previous = SystemMonitorMenuMetric.allCases
        let current: [SystemMonitorMenuMetric] = [.memory, .cpu, .gpu, .disk, .network, .battery, .thermal]

        XCTAssertEqual(
            SystemMonitorStatusItemOrder.preferredPositionKeys(
                previous: previous,
                current: current,
                mode: .direct
            ),
            current.map { "NSStatusItem Preferred Position system-monitor.\($0.rawValue)" }
        )
        XCTAssertTrue(
            SystemMonitorStatusItemOrder.preferredPositionKeys(
                previous: current,
                current: current,
                mode: .direct
            ).isEmpty
        )
        XCTAssertTrue(
            SystemMonitorStatusItemOrder.preferredPositionKeys(
                previous: previous,
                current: current,
                mode: .grouped
            ).isEmpty
        )
        XCTAssertTrue(SystemMonitorStatusItemOrder.preferredPositionKeys(
            previous: [.cpu], current: [.cpu, .memory], mode: .direct
        ).isEmpty)
    }

    @MainActor
    func testMenuModesKeepStableAutosaveNamesAndDoNotRecreateForStyleChanges() throws {
        let suiteName = "SystemMonitorMenuIdentityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = SystemMonitorService(
            menuSettings: SystemMonitorMenuSettings(
                enabled: true,
                mode: .grouped,
                items: SystemMonitorMenuMetric.allCases.map {
                    SystemMonitorMenuItemConfiguration(metric: $0, enabled: true)
                }
            ),
            toolEnabled: false,
            observesWake: false,
            defaults: defaults
        )

        service.setToolEnabled(true)
        let groupedIdentities = service.statusItemIdentities
        XCTAssertEqual(service.statusItemAutosaveNames, ["system-monitor.grouped"])

        service.updateMenuSettings { $0.items[0].style = .iconOnly }
        XCTAssertEqual(service.statusItemIdentities, groupedIdentities)

        service.updateMenuSettings {
            for index in $0.items.indices { $0.items[index].placement = .separate }
        }
        XCTAssertEqual(
            service.statusItemAutosaveNames,
            Set(SystemMonitorMenuMetric.allCases.map {
                "system-monitor.\($0.rawValue)"
            })
        )
        let directIdentities = service.statusItemIdentities

        service.updateMenuSettings { $0.items[1].interval = .seconds5 }
        XCTAssertEqual(service.statusItemIdentities, directIdentities)

        service.updateMenuSettings {
            for index in $0.items.indices { $0.items[index].enabled = false }
        }
        XCTAssertEqual(service.statusItemAutosaveNames, ["system-monitor.grouped"])
        XCTAssertEqual(service.menuSettings.enabledItems.map(\.metric), [.memory])
    }

    func testLifecycleReconfiguresOnlyForStateChanges() {
        XCTAssertFalse(SystemMonitorLifecycle.changesState(from: false, to: false))
        XCTAssertFalse(SystemMonitorLifecycle.changesState(from: true, to: true))
        XCTAssertTrue(SystemMonitorLifecycle.changesState(from: false, to: true))
        XCTAssertTrue(SystemMonitorLifecycle.changesState(from: true, to: false))
    }

    func testScheduleUsesOneFastestCadenceAndOnlyReturnsDueMetrics() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let settings = SystemMonitorMenuSettings(
            enabled: true,
            interval: 5,
            items: [
                SystemMonitorMenuItemConfiguration(metric: .cpu, enabled: true),
                SystemMonitorMenuItemConfiguration(metric: .gpu, enabled: true),
                SystemMonitorMenuItemConfiguration(metric: .network, enabled: true, interval: .seconds2)
            ]
        )

        XCTAssertEqual(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: false), 2)
        XCTAssertEqual(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: true), 1)
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(settings: settings, lastSampled: [:], now: start),
            [.cpu, .gpu, .network]
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(
                settings: settings,
                lastSampled: [.cpu: start, .gpu: start, .network: start],
                now: start.addingTimeInterval(1.999)
            ),
            []
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(
                settings: settings,
                lastSampled: [.cpu: start, .gpu: start, .network: start],
                now: start.addingTimeInterval(2)
            ),
            [.network]
        )
    }

    func testNextDeadlineKeepsNonDivisibleMetricCadencesExact() {
        let start = Date(timeIntervalSince1970: 1_000)
        let settings = SystemMonitorMenuSettings(
            enabled: true,
            items: [
                SystemMonitorMenuItemConfiguration(metric: .cpu, enabled: true, interval: .seconds2),
                SystemMonitorMenuItemConfiguration(metric: .gpu, enabled: true, interval: .seconds5)
            ]
        )

        XCTAssertEqual(
            SystemMonitorMenuSchedule.nextInterval(
                settings: settings,
                lastSampled: [.cpu: start, .gpu: start],
                detailed: false,
                now: start
            ),
            2
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.nextInterval(
                settings: settings,
                lastSampled: [.cpu: start.addingTimeInterval(2), .gpu: start],
                detailed: false,
                now: start.addingTimeInterval(2)
            ),
            2
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.nextInterval(
                settings: settings,
                lastSampled: [.cpu: start.addingTimeInterval(4), .gpu: start],
                detailed: false,
                now: start.addingTimeInterval(4)
            ),
            1
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(
                settings: settings,
                lastSampled: [.cpu: start.addingTimeInterval(4), .gpu: start],
                now: start.addingTimeInterval(5)
            ),
            [.gpu]
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.nextInterval(
                settings: settings,
                lastSampled: [.cpu: start.addingTimeInterval(4), .gpu: start.addingTimeInterval(5)],
                detailed: false,
                now: start.addingTimeInterval(5)
            ),
            1
        )
    }

    func testDisabledScheduleTearsDownAndMetricDefaultsUseSupportedCadences() {
        var settings = SystemMonitorMenuSettings()
        XCTAssertNil(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: false))
        XCTAssertEqual(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: true), 1)
        XCTAssertEqual(settings.items.first(where: { $0.metric == .gpu })?.interval, .seconds5)
        XCTAssertTrue(
            settings.items
                .filter { [.disk, .battery, .thermal].contains($0.metric) }
                .allSatisfy { $0.interval == .seconds30 }
        )
        XCTAssertTrue(
            settings.items
                .filter { [.cpu, .memory, .network].contains($0.metric) }
                .allSatisfy { $0.interval == .global }
        )
        settings.enabled = true
        XCTAssertEqual(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: false), 10)
    }

    func testEffectiveCadenceFloorsProtectDiskBatteryAndThermal() {
        let start = Date(timeIntervalSince1970: 1_000)
        let settings = SystemMonitorMenuSettings(
            enabled: true,
            interval: 1,
            items: [
                SystemMonitorMenuItemConfiguration(metric: .disk, enabled: true, interval: .global),
                SystemMonitorMenuItemConfiguration(metric: .battery, enabled: true, interval: .seconds1),
                SystemMonitorMenuItemConfiguration(metric: .thermal, enabled: true, interval: .seconds3)
            ]
        )
        let sampled: [SystemMonitorMenuMetric: Date] = [.disk: start, .battery: start, .thermal: start]

        XCTAssertEqual(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: false), 10)
        XCTAssertEqual(
            SystemMonitorMenuItemConfiguration(metric: .disk, interval: .global).effectiveInterval(global: 1),
            15
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(settings: settings, lastSampled: sampled, now: start.addingTimeInterval(9.999)),
            []
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(settings: settings, lastSampled: sampled, now: start.addingTimeInterval(10)),
            [.battery, .thermal]
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(settings: settings, lastSampled: sampled, now: start.addingTimeInterval(15)),
            [.battery, .thermal]
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(settings: settings, lastSampled: sampled, now: start.addingTimeInterval(30)),
            [.disk, .battery, .thermal]
        )
    }

    func testSupportedIntervalsNormalizeLegacySelectionsAndPreserveValidOnes() {
        XCTAssertEqual(SystemMonitorMenuMetric.cpu.supportedIntervals(global: 1), SystemMonitorMenuInterval.allCases)
        XCTAssertEqual(SystemMonitorMenuMetric.disk.supportedIntervals(global: 2), [.seconds30, .seconds60])
        XCTAssertEqual(SystemMonitorMenuMetric.disk.supportedIntervals(global: 30), [.global, .seconds30, .seconds60])
        XCTAssertEqual(
            SystemMonitorMenuMetric.battery.supportedIntervals(global: 10),
            [.global, .seconds10, .seconds30, .seconds60]
        )

        let settings = SystemMonitorMenuSettings(
            interval: 2,
            items: [
                SystemMonitorMenuItemConfiguration(metric: .disk, interval: .seconds10),
                SystemMonitorMenuItemConfiguration(metric: .battery, interval: .global),
                SystemMonitorMenuItemConfiguration(metric: .thermal, interval: .seconds5),
                SystemMonitorMenuItemConfiguration(metric: .network, interval: .seconds3),
                SystemMonitorMenuItemConfiguration(metric: .gpu, interval: .seconds5),
                SystemMonitorMenuItemConfiguration(metric: .memory, interval: .seconds60)
            ]
        )

        XCTAssertEqual(settings.items.first(where: { $0.metric == .disk })?.interval, .seconds30)
        XCTAssertEqual(settings.items.first(where: { $0.metric == .battery })?.interval, .seconds10)
        XCTAssertEqual(settings.items.first(where: { $0.metric == .thermal })?.interval, .seconds10)
        XCTAssertEqual(settings.items.first(where: { $0.metric == .network })?.interval, .seconds3)
        XCTAssertEqual(settings.items.first(where: { $0.metric == .gpu })?.interval, .seconds5)
        XCTAssertEqual(settings.items.first(where: { $0.metric == .memory })?.interval, .seconds60)
        XCTAssertTrue(settings.items.allSatisfy {
            $0.metric.supportedIntervals(global: settings.interval).contains($0.interval)
        })
    }

    func testUnavailableMetricsStayRenderedButRetireFromMenuScheduling() {
        let start = Date(timeIntervalSince1970: 1_000)
        let settings = SystemMonitorMenuSettings(
            enabled: true,
            items: [
                SystemMonitorMenuItemConfiguration(metric: .gpu, enabled: true),
                SystemMonitorMenuItemConfiguration(metric: .battery, enabled: true),
                SystemMonitorMenuItemConfiguration(metric: .cpu, enabled: true),
                SystemMonitorMenuItemConfiguration(metric: .network, enabled: true)
            ]
        )
        let unavailable: Set<SystemMonitorMenuMetric> = [.gpu, .battery]
        let firstDelta = sample(
            cpuUsage: nil,
            networkDownload: nil,
            networkUpload: nil,
            unavailableMetrics: unavailable
        )

        XCTAssertEqual(
            SystemMonitorMenuRenderer.render(
                item: SystemMonitorMenuItemConfiguration(metric: .gpu),
                sample: firstDelta
            ).value,
            "Unavailable"
        )
        XCTAssertEqual(
            SystemMonitorMenuRenderer.render(
                item: SystemMonitorMenuItemConfiguration(metric: .cpu),
                sample: firstDelta
            ).value,
            "—"
        )
        XCTAssertTrue(
            SystemMonitorMenuRenderer.render(
                item: SystemMonitorMenuItemConfiguration(metric: .network),
                sample: firstDelta
            ).value.contains("—")
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(
                settings: settings,
                lastSampled: [:],
                unavailableMetrics: unavailable,
                now: start
            ),
            [.cpu, .network]
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.timerInterval(
                settings: settings,
                detailed: false,
                unavailableMetrics: unavailable
            ),
            10
        )

        var onlyUnavailable = settings
        onlyUnavailable.items.indices.forEach {
            onlyUnavailable.items[$0].enabled = unavailable.contains(onlyUnavailable.items[$0].metric)
        }
        XCTAssertNil(
            SystemMonitorMenuSchedule.timerInterval(
                settings: onlyUnavailable,
                detailed: false,
                unavailableMetrics: unavailable
            )
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.timerInterval(
                settings: onlyUnavailable,
                detailed: true,
                unavailableMetrics: unavailable
            ),
            1
        )
    }

    func testRendererAppliesMemoryUnitsNetworkDirectionAndStyles() {
        let sample = sample()
        let memory = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(
                metric: .memory,
                enabled: true,
                style: .iconOnly,
                memoryUnit: .available
            ),
            sample: sample
        )
        let network = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(
                metric: .network,
                enabled: true,
                style: .valueOnly,
                networkDirection: .upload
            ),
            sample: sample
        )

        XCTAssertEqual(memory.style, .iconOnly)
        XCTAssertFalse(memory.value.contains("%"))
        XCTAssertEqual(network.style, .valueOnly)
        XCTAssertTrue(network.value.hasPrefix("↑"))
        XCTAssertFalse(network.value.contains("↓"))
    }

    func testRendererAppliesDiskNetworkBatteryAndThermalFormats() {
        let sample = sample()
        let diskUsed = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(metric: .disk, diskUnit: .used),
            sample: sample
        )
        let diskAvailable = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(metric: .disk, diskUnit: .available),
            sample: sample
        )
        let networkBits = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(
                metric: .network,
                networkDirection: .download,
                networkUnit: .bits
            ),
            sample: sample
        )
        let batteryStatus = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(metric: .battery, batteryDisplay: .status),
            sample: sample
        )
        let batteryBoth = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(metric: .battery, batteryDisplay: .both),
            sample: sample
        )
        let thermalCompact = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(metric: .thermal, thermalDisplay: .compact),
            sample: sample
        )
        let thermalFull = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(metric: .thermal, thermalDisplay: .full),
            sample: sample
        )

        XCTAssertNotEqual(diskUsed.value, diskAvailable.value)
        XCTAssertEqual(networkBits.value, "↓16 kb/s")
        XCTAssertEqual(batteryStatus.value, "Charging")
        XCTAssertEqual(batteryBoth.value, "80% · Charging")
        XCTAssertEqual(thermalCompact.value, "OK")
        XCTAssertEqual(thermalFull.value, "Nominal")
    }

    func testRendererFormatsIdleNetworkRateAsANumber() {
        let network = SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(metric: .network, networkDirection: .download),
            sample: sample(networkDownload: 0, networkUpload: 0)
        )

        XCTAssertEqual(network.value, "↓0 KB/s")
    }

    func testRenderedStateCacheRejectsRedundantWrites() {
        let state = [SystemMonitorMenuRenderer.render(
            item: SystemMonitorMenuItemConfiguration(metric: .cpu, enabled: true),
            sample: sample()
        )]
        var cache = SystemMonitorRenderedStateCache()

        XCTAssertTrue(cache.shouldApply(state, for: "cpu"))
        XCTAssertFalse(cache.shouldApply(state, for: "cpu"))
        cache.removeAll()
        XCTAssertTrue(cache.shouldApply(state, for: "cpu"))
    }

    @MainActor
    func testEqualRenderedContentSkipsActualStatusButtonWrites() throws {
        for mode in SystemMonitorMenuMode.allCases {
            let suiteName = "SystemMonitorRenderedWrites.\(mode.rawValue).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let controller = SystemMonitorMenuController(defaults: defaults)
            var settings = SystemMonitorMenuSettings(
                enabled: true,
                mode: mode,
                items: [SystemMonitorMenuItemConfiguration(metric: .cpu, enabled: true)]
            )

            controller.configure(settings: settings)
            let writesBeforeSample = controller.renderedWriteCount
            controller.update(sample: sample(), dueMetrics: [.cpu])
            XCTAssertEqual(controller.renderedWriteCount, writesBeforeSample + 1)

            controller.update(sample: sample(), dueMetrics: [.cpu])
            XCTAssertEqual(controller.renderedWriteCount, writesBeforeSample + 1)

            settings.enabled = false
            controller.configure(settings: settings)
        }
    }

    @MainActor
    func testMenuRetainsMeasuredValuesThroughTenSecondRescheduleAndPlacementChanges() throws {
        let suiteName = "SystemMonitorValueRetention.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SystemMonitorMenuController(defaults: defaults)
        var settings = SystemMonitorMenuSettings(
            enabled: true,
            items: [
                SystemMonitorMenuItemConfiguration(metric: .cpu, enabled: true),
                SystemMonitorMenuItemConfiguration(metric: .network, enabled: true)
            ]
        )
        controller.configure(settings: settings)
        controller.update(sample: sample(), dueMetrics: [.cpu, .network])
        XCTAssertEqual(controller.displayedValue(for: .cpu), "42%")
        XCTAssertFalse(try XCTUnwrap(controller.displayedValue(for: .network)).contains("—"))
        let groupedIdentities = controller.statusItemIdentities
        let writesBeforeReschedule = controller.renderedWriteCount

        settings.items[0].interval = .seconds10
        settings.items[1].interval = .seconds10
        controller.configure(settings: settings)
        XCTAssertEqual(controller.displayedValue(for: .cpu), "42%")
        XCTAssertEqual(controller.renderedWriteCount, writesBeforeReschedule)
        controller.update(sample: sample(cpuUsage: nil, networkDownload: nil, networkUpload: nil),
                          dueMetrics: [.cpu, .network])
        XCTAssertEqual(controller.displayedValue(for: .cpu), "42%")
        XCTAssertFalse(try XCTUnwrap(controller.displayedValue(for: .network)).contains("—"))

        settings.setPlacement(.separate, for: .cpu)
        controller.configure(settings: settings)
        XCTAssertEqual(controller.displayedValue(for: .cpu), "42%")
        XCTAssertTrue(groupedIdentities.isSubset(of: controller.statusItemIdentities))
        settings.enabled = false
        controller.configure(settings: settings)
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
        XCTAssertNil(unavailable.cpuUsage)
    }

    private func sample(
        cpuUsage: Double? = 42.4,
        networkDownload: Double? = 2_000,
        networkUpload: Double? = 1_000,
        unavailableMetrics: Set<SystemMonitorMenuMetric> = []
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
