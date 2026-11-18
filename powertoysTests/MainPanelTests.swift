import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

final class MainPanelTests: XCTestCase {
    @MainActor
    func testWarmDiagnosticOpenRetainsWindowAndHost() throws {
        let domain = "MainPanelTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let panels = DiagnosticsMenuPanels(defaults: defaults)
        var builds = 0
        panels.makeCaptureContent = { _, _ in
            builds += 1
            return AnyView(Color.clear.frame(width: 356, height: 120))
        }
        defer { panels.close() }
        panels.open(.main, tab: "home")
        let window = try XCTUnwrap(panels.captureWindow)
        let hosting = try XCTUnwrap(window.contentViewController)
        panels.close()
        XCTAssertFalse(window.isVisible)
        panels.open(.main, tab: "home")
        XCTAssertTrue(panels.captureWindow === window)
        XCTAssertTrue(panels.captureWindow?.contentViewController === hosting)
        XCTAssertEqual(builds, 1)
    }

    @MainActor
    func testHomeSamplesOnlyWhileVisibleAndStopsOnCloseOrTabChange() async throws {
        let service = SystemMonitorService.shared
        let host = NSHostingView(rootView: AnyView(home(visible: false)))
        let window = offscreenWindow(host, height: 700)
        defer { window.close(); window.contentView = nil }
        let steps: [(String, AnyView, Int)] = [
            ("hidden", AnyView(home(visible: false)), 0),
            ("visible", AnyView(home(visible: true)), 1),
            ("panel closed", AnyView(home(visible: false)), 0),
            ("reopened", AnyView(home(visible: true)), 1),
            ("other tab", AnyView(Color.clear.frame(width: 338, height: 100)), 0),
        ]
        for (name, root, timers) in steps {
            host.rootView = root
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(service.timerOwnerCount, timers, name)
        }
        XCTAssertEqual(FanControlService.shared.pollOwnerCount, 0)
    }

    @MainActor
    func testTopProcessesRefreshEveryTwoSecondsAndReleaseAfterClose() async {
        var refreshes = 0
        var delays: [Duration] = []
        await MainPanelProcessCadence.run(refresh: { refreshes += 1 }, sleep: { delay in
            delays.append(delay)
            if delays.count == 4 { throw CancellationError() }
        })
        XCTAssertEqual(delays, [.milliseconds(500), .seconds(2), .seconds(2), .seconds(2)])
        XCTAssertEqual(refreshes, 4, "A cancelled sleep stops the loop before another refresh.")

        let release = MenuPanelRelease.shared
        let before = release.pendingCount
        MenuPanelTopProcesses().scheduleRelease()
        XCTAssertEqual(release.pendingCount, before + 1)
        release.cancel("menu-panel-top-processes")
        XCTAssertEqual(release.pendingCount, before)
    }

    @MainActor
    func testMissingBatteryOrGPUKeepsBothBentoColumnsEven() {
        let style = TrayPopoverLayout.style
        for (battery, gpu, height) in [(true, true, 266.0), (false, true, 266), (true, false, 266), (false, false, 203)] {
            let layout = MainPanelBentoLayout(hasBattery: battery, hasGPU: gpu)
            XCTAssertEqual(layout.height, height, "battery \(battery), gpu \(gpu)")
            XCTAssertEqual(layout.cpuChart - OnePlusLinearMetrics.tallChart, layout.cpu - style.tallTile)
            XCTAssertEqual(layout.networkChart - OnePlusLinearMetrics.chart, layout.network - style.tile)
            var readings = Self.reference
            readings.hasBattery = battery
            readings.hasGPU = gpu
            let bento = NSHostingView(rootView: MainPanelBento(readings: readings).frame(width: TrayPopoverLayout.bodyWidth)
                .environment(\.onePlusLinearPanelStyle, style))
            XCTAssertEqual(bento.fittingSize.height, height, accuracy: 0.5, "battery \(battery), gpu \(gpu)")
        }
        XCTAssertTrue(FanControlPresentation(snapshot: FanSnapshot(fans: [], profile: nil, canControl: false)).hasNoFans)
        XCTAssertFalse(FanControlPresentation().hasNoFans, "An unread fan keeps its row until a read finds no fans.")
    }

    @MainActor
    func testHomeHasItsNaturalHeightAndTheBodyScrollsOnlyAtTheCeiling() {
        let content = NSHostingView(rootView: Self.homeContent().frame(width: TrayPopoverLayout.bodyWidth)
            .environment(\.onePlusLinearPanelStyle, TrayPopoverLayout.style))
        // Bento, Fan and Kwake group, process header and group, actions, 10 pt apart.
        XCTAssertEqual(content.fittingSize.height, 266 + 10 + 72 + 10 + 24 + 158 + 10 + 32, accuracy: 0.5)
        let panel = NSHostingView(rootView: Self.panel(maximumHeight: 2_000))
        XCTAssertEqual(panel.fittingSize.width, OnePlusLinearMetrics.panelWidth, accuracy: 0.5)
        XCTAssertEqual(panel.fittingSize.height, 582 + TrayPopoverLayout.chromeHeight, accuracy: 0.5)
        let capped = NSHostingView(rootView: Self.panel(maximumHeight: 300))
        XCTAssertEqual(capped.fittingSize.height, 300 + TrayPopoverLayout.chromeHeight, accuracy: 0.5)
        XCTAssertEqual(TrayPopoverLayout.maximumBodyHeight(panelCeiling: 810) + TrayPopoverLayout.chromeHeight, 810)
        XCTAssertEqual(TrayPopoverLayout.maximumBodyHeight(panelCeiling: 80), TrayPopoverLayout.minimumBodyHeight)
    }

    func testReadingsFormatTheLiveSampleForTheTiles() {
        let sample = SystemMonitorSample(
            timestamp: Date(), cpuUsage: 23.2, memoryUsed: 18_400_000_000, memoryTotal: 48 * 1_073_741_824,
            gpuUsage: 11.4, networkDownload: 2_400_000, networkUpload: 310_000, diskUsed: 388_000_000_000,
            diskTotal: 1_000_000_000_000, batteryPercent: 86, batteryCharging: false, thermalState: nil,
            loadAverage: nil, unavailableMetrics: [],
            cpuDetails: SystemMonitorCPUDetails(user: 14.2, system: 9, idle: 76.8, cores: []),
            batteryDetails: SystemMonitorBatteryDetails(cycleCount: nil, health: nil, currentCapacity: nil,
                                                        maximumCapacity: nil, voltageMillivolts: nil,
                                                        amperageMilliamps: nil, timeRemaining: 3 * 3_600 + 52 * 60))
        let hardware = MainPanelHardware(hasBattery: true, hasGPU: true, cores: 14, chip: "Apple M4 Pro")
        let readings = MainPanelReadings(sample: sample, history: SystemMonitorHistory(), hardware: hardware)
        XCTAssertEqual([readings.cpu, readings.cpuUser, readings.cpuSystem, readings.gpu, readings.memory], ["23", "14", "9", "11", "36"])
        XCTAssertEqual(readings.cores, "14 cores")
        XCTAssertEqual(readings.diskFree, "612")
        XCTAssertEqual(readings.diskFreeUnit, "GB free")
        XCTAssertEqual(readings.diskUsed, "388 GB used")
        XCTAssertEqual(readings.battery, "86")
        XCTAssertEqual(readings.batteryCaption, "3:52 left")
        XCTAssertEqual(readings.batterySymbol, "battery.75percent")
        XCTAssertEqual(readings.down, "2.4")
        XCTAssertEqual(readings.downUnit, "MB/s")
        XCTAssertEqual(readings.up, "310 KB/s")
        XCTAssertEqual(MainPanelReadings.percentRange([4, 27.7]).upperBound, 50)
        XCTAssertEqual(MainPanelReadings.percentRange([90]).upperBound, 100)
    }

    /// No test may reach the real fan helper: every test service gets a fake writer, and no test selects on the shared one.
    func testNoTestSendsAFanWrite() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where file.pathExtension == "swift" && file.lastPathComponent != "MainPanelTests.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbidden in ["FanCommand.apply(", "FanControlService.shared.select(", "FanControlService.shared.enableControl("] {
                XCTAssertFalse(source.contains(forbidden), "\(file.lastPathComponent) calls \(forbidden)")
            }
            let services = source.components(separatedBy: "FanControlService(readSnapshot:").dropFirst()
            for service in services {
                XCTAssertTrue(service.prefix(600).contains("applyPreset:"), "\(file.lastPathComponent) builds a service with the real writer")
            }
        }
    }

    /// Writes the v15 panel captures beside the reference renders in `docs/design/v15/`.
    @MainActor
    func testCapturesHomeAndOneToolTabInLightAndDark() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/redesign/captures/v15-menu-panel")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let priorTab = defaults.string(forKey: "tray.selectedTab.v2")
        defer {
            if let priorTab { defaults.set(priorTab, forKey: "tray.selectedTab.v2") }
            else { defaults.removeObject(forKey: "tray.selectedTab.v2") }
        }
        defaults.set(TrayTab.inputDevices.rawValue, forKey: "tray.selectedTab.v2")
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try capture(AnyView(Self.panel(maximumHeight: 2_000)), appearance: appearance,
                        to: directory.appendingPathComponent("home-\(name).png"))
            try capture(AnyView(TrayPopoverView().environment(\.onePlusMenuMaximumHeight, 2_000)), appearance: appearance,
                        to: directory.appendingPathComponent("input-devices-\(name).png"))
        }
    }

    // MARK: - Fixtures equal to docs/design/v15/menu-panel-*.png

    private static let cpu: [Double] = [9.6, 8.3, 9.5, 10.3, 9.1, 19.4, 10.5, 11.2, 11.2, 25.5, 24.5, 8.4, 10.0, 10.1, 11.0, 12.5, 11.4, 11.1, 11.3, 27.3, 12.5, 13.2, 24.9, 27.7, 12.3, 12.7, 12.3, 10.9, 12.0, 27.6, 10.7, 12.0, 10.7, 11.9, 12.7, 26.4, 22.4, 10.4, 9.1, 9.2, 8.3, 7.7, 22.8, 23.9, 9.6, 8.2, 8.8, 7.3, 6.9, 21.1, 5.0, 6.5, 7.9, 8.2, 7.9, 7.9, 9.4, 10.0, 11.3, 12.9]
    private static let gpu: [Double] = [2.3, 2.4, 2.7, 2.9, 2.9, 3.1, 2.8, 3.0, 3.2, 2.9, 2.8, 3.0, 3.2, 3.0, 2.7, 3.0, 3.1, 8.0, 3.0, 2.7, 2.8, 2.9, 3.2, 3.2, 3.2, 3.2, 3.4, 3.1, 3.1, 2.9, 2.7, 3.0, 8.3, 6.2, 7.7, 3.0, 3.0, 3.2, 3.0, 6.9, 8.1, 5.6, 2.3, 2.2, 2.2, 2.0, 1.7, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 1.7, 1.7, 6.1, 2.3, 2.6, 2.9, 3.3]
    private static let down: [Double] = [4.2, 4.4, 5.6, 6.0, 5.3, 4.9, 4.0, 2.9, 4.1, 4.4, 4.6, 4.8, 3.5, 3.7, 4.5, 5.0, 4.2, 4.0, 5.0, 5.6, 6.7, 7.6, 7.9, 6.8, 5.6, 6.4, 5.6, 6.3, 5.1, 5.4, 4.7, 5.9, 5.2, 5.0, 5.4, 5.7, 6.0, 4.7, 16.3, 15.1, 17.4, 6.5, 7.2, 7.4, 6.6, 7.8, 7.5, 6.8, 20.3, 7.8, 7.9, 7.9, 7.7, 7.9, 23.7, 7.4, 7.7, 12.1, 17.2, 21.8]
    private static let up: [Double] = [2.2, 2.3, 2.3, 2.5, 2.7, 2.7, 2.6, 2.7, 2.6, 2.3, 2.5, 5.3, 4.9, 4.9, 2.6, 2.5, 2.5, 2.7, 2.7, 2.5, 2.5, 2.5, 2.4, 2.3, 2.3, 2.1, 2.0, 2.1, 2.2, 2.3, 2.2, 4.2, 2.3, 2.2, 2.0, 2.2, 1.9, 2.1, 2.0, 4.0, 4.2, 2.0, 2.0, 2.2, 2.4, 2.5, 2.5, 2.5, 2.5, 2.4, 2.6, 2.7, 2.7, 2.5, 2.4, 4.9, 2.4, 2.9, 3.3, 3.7]

    private static var reference: MainPanelReadings {
        var readings = MainPanelReadings(hardware: MainPanelHardware(hasBattery: true, hasGPU: true, cores: 14, chip: nil))
        readings.cpu = "23"; readings.cpuUser = "14"; readings.cpuSystem = "9"
        readings.cpuHistory = cpu; readings.cpuRange = 0...56
        readings.gpu = "11"; readings.gpuName = "Apple GPU"; readings.gpuHistory = gpu; readings.gpuRange = 0...30
        readings.memory = "38"; readings.memoryUsed = "18.4 GB used"; readings.memoryTotal = "48 GB"; readings.memoryFraction = 0.383
        readings.diskFree = "612"; readings.diskFreeUnit = "GB free"; readings.diskUsed = "388 GB used"; readings.diskFraction = 0.388
        readings.battery = "86"; readings.batteryCaption = "3:52 left"; readings.batteryFraction = 0.86
        readings.batterySymbol = "battery.75percent"
        readings.down = "2.4"; readings.downUnit = "MB/s"; readings.up = "310 KB/s"
        readings.downHistory = down; readings.upHistory = up; readings.networkRange = 0...30
        return readings
    }

    private static func appIcon(_ path: String) -> Image? {
        FileManager.default.fileExists(atPath: path) ? Image(nsImage: NSWorkspace.shared.icon(forFile: path)) : nil
    }

    @MainActor
    private static func homeContent() -> some View {
        MainPanelHomeContent(
            readings: reference,
            processes: [
                MainPanelProcessDisplay(name: "WindowServer", icon: nil, cpu: "6.1", memory: "1.2 GB"),
                MainPanelProcessDisplay(name: "Xcode", icon: appIcon("/Applications/Xcode.app"), cpu: "4.8", memory: "3.9 GB"),
                MainPanelProcessDisplay(name: "Google Chrome", icon: appIcon("/Applications/Google Chrome.app"),
                                        cpu: "3.2", memory: "2.1 GB"),
            ],
            actions: [
                OnePlusLinearAction("Pick Color", systemImage: ToolGlyph.colorPicker.symbol) {},
                OnePlusLinearAction("Extract Text", systemImage: ToolGlyph.textExtractor.symbol) {},
                OnePlusLinearAction("Ruler", systemImage: ToolGlyph.ruler.symbol) {},
            ]
        ) {
            OnePlusLinearList(style: .panel) {
                MainPanelFanRow(status: "3,472 RPM", selection: .constant(.auto), isChoiceEnabled: { _ in true }) { EmptyView() }
                MainPanelKwakeRow(isOn: .constant(true), status: "Indefinite")
            }
        }
    }

    @MainActor
    private static func panel(maximumHeight: CGFloat) -> some View {
        MainPanelFrame(maximumHeight: maximumHeight, tabs: [.home, .inputDevices, .cloudSync],
                       selection: .constant(.home), onMove: { _, _ in }, openSettings: {}, openApp: {}) {
            MainPanelScrollBody { homeContent() }
        }
    }

    @MainActor
    private func home(visible: Bool) -> some View {
        TrayHomeView(toolIDs: ["awake"]).frame(width: TrayPopoverLayout.bodyWidth).environment(\.onePlusIsVisible, visible)
    }

    @MainActor
    private func offscreenWindow(_ view: NSView, height: CGFloat, appearance: NSAppearance.Name? = nil) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: OnePlusLinearMetrics.panelWidth, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let appearance { window.appearance = NSAppearance(named: appearance) }
        window.contentView = view
        window.orderBack(nil)
        return window
    }

    @MainActor
    private func capture(_ root: AnyView, appearance: NSAppearance.Name, to url: URL) throws {
        let priorAppearance = NSApp.appearance
        let priorSetting = UserDefaults.standard.string(forKey: AppAppearance.storageKey)
        // The App scene re-applies this setting whenever its body runs, so the render sets it too.
        UserDefaults.standard.set(appearance == .aqua ? AppAppearance.light.rawValue : AppAppearance.dark.rawValue,
                                  forKey: AppAppearance.storageKey)
        NSApp.appearance = NSAppearance(named: appearance)
        defer {
            if let priorSetting { UserDefaults.standard.set(priorSetting, forKey: AppAppearance.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: AppAppearance.storageKey) }
            NSApp.appearance = priorAppearance
        }
        let deadline = Date().addingTimeInterval(2)
        while NSApp.effectiveAppearance.name != appearance && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(NSApp.effectiveAppearance.name, appearance)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: appearance)
        let window = offscreenWindow(host, height: 900, appearance: appearance)
        defer { window.close(); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let shell = try XCTUnwrap(bitmap.colorAt(x: 4, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        let brightness = (shell.redComponent + shell.greenComponent + shell.blueComponent) / 3
        XCTAssertEqual(brightness > 0.5, appearance == .aqua, "\(url.lastPathComponent) shell brightness \(brightness), host \(host.effectiveAppearance.name.rawValue), window \(window.appearance?.name.rawValue ?? "nil"), app \(NSApp.effectiveAppearance.name.rawValue)")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
