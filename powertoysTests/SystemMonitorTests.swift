import XCTest
@testable import powertoys

final class SystemMonitorTests: XCTestCase {
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
            SystemMonitorMenuSchedule.dueMetrics(settings: settings, lastSampled: sampled, now: start.addingTimeInterval(9.999)),
            []
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(settings: settings, lastSampled: sampled, now: start.addingTimeInterval(10)),
            [.battery, .thermal]
        )
        XCTAssertEqual(
            SystemMonitorMenuSchedule.dueMetrics(settings: settings, lastSampled: sampled, now: start.addingTimeInterval(15)),
            [.disk, .battery, .thermal]
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

    private func sample() -> SystemMonitorSample {
        SystemMonitorSample(
            timestamp: Date(timeIntervalSince1970: 1_000),
            cpuUsage: 42.4,
            memoryUsed: 6_000_000_000,
            memoryTotal: 10_000_000_000,
            gpuUsage: 22,
            networkDownload: 2_000,
            networkUpload: 1_000,
            diskUsed: 25,
            diskTotal: 100,
            batteryPercent: 80,
            batteryCharging: true,
            thermalState: "Nominal",
            loadAverage: (1, 2, 3)
        )
    }
}
