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
                available: [.cloudSync, .inputDevices, .systemCare],
                savedIDs: ["input-devices", "unknown", "rclone", "input-devices"]
            ),
            [.inputDevices, .cloudSync, .systemCare]
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

    func testTrayUsesMutedTabbedChromeAndFocusedContent() throws {
        let source = try sourceFile("Views/TrayPopoverView.swift")

        XCTAssertTrue(source.contains("TrayTabStrip"))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains("TrayHomeActionButton"))
        XCTAssertTrue(source.contains("TrayToolLink"))
        XCTAssertTrue(source.contains("arrow.up.right"))
        XCTAssertTrue(source.contains(".draggable(tab.rawValue)"))
        XCTAssertTrue(source.contains("Button(\"Move Left\""))
        XCTAssertTrue(source.contains("Button(\"Move Right\""))
        XCTAssertTrue(source.contains("InputDevicesSettingsView(showsHeader: true, showsContainerScroll: false)"))
        XCTAssertFalse(source.contains("LogsTrayView"))
        XCTAssertFalse(source.contains("ToolSettingsContent"))
        XCTAssertFalse(source.contains("ToolIconColor.major"))
        XCTAssertFalse(source.contains("Color.accentColor"))
        XCTAssertFalse(source.contains(".focusEffectDisabled()"))
    }

    func testTrayPopoverHeightStaysWithinSeventyPercentOfTheScreen() {
        let screenHeight: CGFloat = 900
        let body = TrayPopoverLayout.maximumBodyHeight(screenHeight: screenHeight)

        XCTAssertLessThanOrEqual(
            body + TrayPopoverLayout.topChromeHeight,
            screenHeight * TrayPopoverLayout.heightFraction
        )
        XCTAssertEqual(
            TrayPopoverLayout.maximumBodyHeight(screenHeight: 100),
            TrayPopoverLayout.minimumBodyHeight
        )
    }

    func testTrayRendersHomeAndInputDevicesInLightAndDark() throws {
        for (tab, scheme, name) in [
            (TrayTab.home, ColorScheme.light, "Home — Light"),
            (.home, .dark, "Home — Dark"),
            (.inputDevices, .dark, "Input Devices — Dark"),
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

    private func transferJob(state: TransferState, createdAt: Date) -> TransferJob {
        let job = TransferJob(
            operation: .copy,
            sourceFs: "/source",
            destinationFs: "/destination",
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
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func render(tab: TrayTab, colorScheme: ColorScheme) throws -> NSImage {
        UserDefaults.standard.set(tab.rawValue, forKey: "tray.selectedTab.v2")
        let host = NSHostingView(
            rootView: TrayPopoverView()
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, colorScheme)
        )
        host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: TrayPopoverLayout.width, height: 1_100)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let size = host.fittingSize
        XCTAssertEqual(size.width, TrayPopoverLayout.width, accuracy: 1)
        XCTAssertGreaterThan(size.height, 100)
        XCTAssertLessThanOrEqual(
            size.height,
            (NSScreen.main?.visibleFrame.height ?? 900) * TrayPopoverLayout.heightFraction + 1
        )

        host.frame.size = size
        host.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }
}
