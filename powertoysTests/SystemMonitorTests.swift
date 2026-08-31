import XCTest
@testable import powertoys

final class SystemMonitorTests: XCTestCase {
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
        let baselineHistoryCount = detailService.history.count
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
        XCTAssertEqual(detailService.history.count, baselineHistoryCount)
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
        XCTAssertEqual(SystemMonitorService.maximumHistoryCount, 120)
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

    func testNormalizationAllowsEveryItemToBeDisabledAndValidatesSymbols() {
        var settings = SystemMonitorMenuSettings(
            items: [SystemMonitorMenuItemConfiguration(metric: .cpu, symbol: "not-a-symbol")]
        )
        settings.items[0].enabled = false
        settings.normalize()

        XCTAssertEqual(settings.items.count, SystemMonitorMenuMetric.allCases.count)
        XCTAssertTrue(settings.enabledItems.isEmpty)
        XCTAssertEqual(settings.items[0].symbol, SystemMonitorMenuMetric.cpu.symbol)
        settings.enabled = true
        XCTAssertNil(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: false))
    }

    func testNoOpSettingsMutationProducesNoUpdate() throws {
        let settings = SystemMonitorMenuSettings(enabled: true)

        XCTAssertNil(settings.applying { $0.interval = 2 })
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

        service.updateMenuSettings { $0.mode = .direct }
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
        XCTAssertTrue(service.statusItemIdentities.isEmpty)
        XCTAssertTrue(service.statusItemAutosaveNames.isEmpty)
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
        XCTAssertEqual(SystemMonitorMenuSchedule.timerInterval(settings: settings, detailed: false), 2)
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
            "Waiting"
        )
        XCTAssertTrue(
            SystemMonitorMenuRenderer.render(
                item: SystemMonitorMenuItemConfiguration(metric: .network),
                sample: firstDelta
            ).value.contains("Waiting")
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
            2
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
