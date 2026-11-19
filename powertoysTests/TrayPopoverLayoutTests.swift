import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class TrayPopoverLayoutTests: XCTestCase {
    private var restoredModes: [IndividualMenuBarTool: String?] = [:]
    private var restoredSelection: String?
    private var restoredOrder: String?

    override func setUpWithError() throws {
        let defaults = UserDefaults.standard
        for tool in IndividualMenuBarTool.allCases {
            restoredModes[tool] = defaults.string(forKey: tool.preferenceKey)
            defaults.set(MenuBarDisplayMode.combined.rawValue, forKey: tool.preferenceKey)
        }
        restoredSelection = defaults.string(forKey: "tray.selectedTab.v2")
        restoredOrder = defaults.string(forKey: "tray.tabOrder.v2")
        defaults.set(TrayTab.home.rawValue, forKey: "tray.selectedTab.v2")
        defaults.removeObject(forKey: "tray.tabOrder.v2")
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        for (tool, value) in restoredModes {
            if let value { defaults.set(value, forKey: tool.preferenceKey) }
            else { defaults.removeObject(forKey: tool.preferenceKey) }
        }
        restore(restoredSelection, key: "tray.selectedTab.v2")
        restore(restoredOrder, key: "tray.tabOrder.v2")
    }

    func testComplexTabOrderUsesSavedUniqueAvailableTabsThenDefaults() {
        XCTAssertEqual(
            TrayPopoverLayout.orderedComplexTabs(
                available: [.cloudSync, .inputDevices],
                savedIDs: ["input-devices", "unknown", "nettoys", "rclone", "input-devices"]
            ),
            [.inputDevices, .cloudSync]
        )
    }

    func testDiagnosticsTabIDsMapToStoredTabs() {
        XCTAssertEqual(
            ["home", "cloud-sync", "input-devices", "system-care", "nettoys"]
                .compactMap(TrayTab.init(panelID:)),
            [.home, .cloudSync, .inputDevices]
        )
    }

    func testEveryTrayCapableBuiltInHasAHomeActionOrComplexTab() {
        let trayToolIDs = Set(
            TrayPopoverLayout.homeToolIDs
                + TrayPopoverLayout.defaultComplexTabs.compactMap(\.toolID)
        )
        let expected = Set(ToolRegistry.builtInTools.filter(\.hasTrayTab).map(\.id) + ["ruler"])
        XCTAssertEqual(trayToolIDs, expected)
        XCTAssertFalse(LogsTool.shared.hasTrayTab)
    }

    func testTransferConsoleBoundsActiveAndRecentJobs() {
        let active = (0..<7).map { index in
            transferJob(state: index == 0 ? .paused : .running, createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        let recent = (0..<5).map { index in
            transferJob(state: index == 0 ? .failed : .completed, createdAt: Date(timeIntervalSince1970: Double(100 + index)))
        }

        let visible = TrayPopoverLayout.visibleTransferJobs(active + recent)

        XCTAssertEqual(visible.count, 8)
        XCTAssertEqual(visible.filter { $0.state.isActive }.count, 5)
        XCTAssertEqual(visible.filter { $0.state.isTerminal }.count, 3)
        XCTAssertEqual(visible.first?.createdAt, Date(timeIntervalSince1970: 6))
        XCTAssertEqual(visible.last?.createdAt, Date(timeIntervalSince1970: 102))
    }

    func testRemoteActivityUsesBothEndpointsAndLatestFinishTime() {
        let latest = transferJob(state: .completed, createdAt: Date(timeIntervalSince1970: 1),
                                 sourceFs: "foo:source", destinationFs: "bar:destination")
        latest.finishedAt = Date(timeIntervalSince1970: 20)
        let older = transferJob(state: .completed, createdAt: Date(timeIntervalSince1970: 5),
                                destinationFs: "foo:older")
        let other = transferJob(state: .running, createdAt: Date(timeIntervalSince1970: 30),
                                destinationFs: "foobar:destination")
        let activity = TrayPopoverLayout.latestTransfersByRemote([latest, older, other])
        XCTAssertEqual(activity["foo"]?.id, latest.id)
        XCTAssertEqual(activity["bar"]?.id, latest.id)
        XCTAssertEqual(activity["foobar"]?.id, other.id)
        XCTAssertNil(activity["/source"])
    }

    func testTrayUsesSharedMenuPanelWithReorderableTabs() throws {
        let source = try sourceFile("Views/MenuPanels")

        XCTAssertEqual(TrayPopoverLayout.width, OnePlusLinearMetrics.panelWidth)
        XCTAssertTrue(source.contains("OnePlusLinearPanel {"))
        XCTAssertTrue(source.contains("OnePlusLinearPanelFooter"))
        XCTAssertTrue(source.contains("OnePlusLinearIconTabs(tabs: menuTabs"))
        XCTAssertTrue(source.contains("OnePlusLinearIconButton(systemImage: \"gearshape\""))
        XCTAssertTrue(source.contains("\"tray.open-app\""))
        XCTAssertEqual(TrayTab.home.symbol, "square.grid.2x2")
        XCTAssertEqual(TrayTab.cloudSync.symbol, ToolGlyph.cloudSync.symbol)
        XCTAssertTrue(source.contains("OnePlusLinearDisclosureRow"))
        XCTAssertFalse(source.contains("TrayToolHeader"))
        XCTAssertTrue(source.contains("OnePlusLinearActionBar"))
        XCTAssertTrue(source.contains("OnePlusLinearControlRow(\"Awake\""))
        XCTAssertFalse(source.contains("TrayTabStrip"))
        XCTAssertFalse(source.contains("LogsTrayView"))
        XCTAssertFalse(source.contains("ToolSettingsContent"))
        XCTAssertFalse(source.contains("ToolIconColor.major"))
        XCTAssertFalse(source.contains("accessibilityReduceTransparency"))
        XCTAssertFalse(source.contains("withAnimation"))
    }

    func testTrayCorrectionPassKeepsGroupsAlignedAndErrorsOnDemand() throws {
        let source = try sourceFile("Views/MenuPanels")

        XCTAssertTrue(source.contains("@State private var showsError = false"))
        XCTAssertTrue(source.contains("if showsError, let error = job.errorMessage"))
        XCTAssertTrue(source.contains("symbol: ToolGlyph.textExtractor.symbol"))
    }

    func testCorrectedSharedSurfacesHaveOneTrailingAndHoverGeometry() throws {
        let input = try sourceFile("Views/InputDevices/InputDevicesSettingsView.swift")
        let launcher = try sourceFile("Views/AllToolsGridView.swift")

        XCTAssertTrue(input.contains("OnePlusSettingRow"))
        XCTAssertFalse(input.contains(".frame(width: 160, alignment: .trailing)"))
        XCTAssertFalse(input.contains(".frame(maxWidth: .infinity, alignment: .trailing)"))
        XCTAssertFalse(launcher.contains(".buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 8))"))
    }

    func testTrayPopoverHeightStaysWithinSeventyPercentOfTheScreen() {
        let ceiling: CGFloat = 900 * TrayPopoverLayout.heightFraction
        let body = TrayPopoverLayout.maximumBodyHeight(panelCeiling: ceiling)

        XCTAssertEqual(body + TrayPopoverLayout.chromeHeight, ceiling)
        XCTAssertEqual(TrayPopoverLayout.maximumBodyHeight(panelCeiling: 100), TrayPopoverLayout.minimumBodyHeight)
    }

    func testTrayRendersEveryPrimarySurfaceInLightAndDark() throws {
        for (tab, scheme, name) in [
            (TrayTab.home, ColorScheme.light, "Home — Light"),
            (.home, .dark, "Home — Dark"),
            (.cloudSync, .dark, "RSync UI — Dark"),
            (.cloudSync, .light, "RSync UI — Light"),
            (.inputDevices, .dark, "Input Devices — Dark"),
            (.inputDevices, .light, "Input Devices — Light"),
        ] {
            let attachment = XCTAttachment(image: try render(tab: tab, colorScheme: scheme))
            attachment.name = "Menu Bar — \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func restore(_ value: String?, key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func transferJob(state: TransferState, createdAt: Date,
                             sourceFs: String = "/source", destinationFs: String = "/destination") -> TransferJob {
        let job = TransferJob(
            operation: .copy,
            sourceFs: sourceFs,
            destinationFs: destinationFs,
            sourceDisplay: "Source",
            destinationDisplay: "Destination",
            excludePatterns: [],
            maxRetries: 1,
            createdAt: createdAt
        )
        job.state = state
        job.finishedAt = state.isTerminal ? createdAt : nil
        return job
    }

    private func sourceFile(_ path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys")
            .appendingPathComponent(path)
        if path.hasSuffix(".swift") {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
        let files = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    private func render(tab: TrayTab, colorScheme: ColorScheme) throws -> NSImage {
        let priorAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        defer { NSApp.appearance = priorAppearance }
        UserDefaults.standard.set(tab.rawValue, forKey: "tray.selectedTab.v2")
        let host = NSHostingView(
            rootView: TrayPopoverView()
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, colorScheme)
        )
        host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        host.frame = NSRect(origin: NSPoint(x: -10000, y: -10000), size: NSSize(width: TrayPopoverLayout.width,
                                                              height: screen.height * TrayPopoverLayout.heightFraction))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close(); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while host.fittingSize.height <= 100 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }

        let size = host.fittingSize
        XCTAssertEqual(size.width, TrayPopoverLayout.width, accuracy: 1)
        XCTAssertGreaterThan(size.height, 100, "\(tab.rawValue): visible=\(window.isVisible), occlusion=\(window.occlusionState.rawValue)")
        XCTAssertLessThanOrEqual(
            size.height,
            (NSScreen.main?.visibleFrame.height ?? 900) * TrayPopoverLayout.heightFraction + 1
        )

        host.frame.size = size
        host.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let surface = try XCTUnwrap(representation.colorAt(x: representation.pixelsWide - 5,
                                                          y: representation.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        let brightness = (surface.redComponent + surface.greenComponent + surface.blueComponent) / 3
        if colorScheme == .dark { XCTAssertLessThan(brightness, 0.5) }
        else { XCTAssertGreaterThan(brightness, 0.5) }
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }
}
