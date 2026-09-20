import XCTest
@testable import powertoys

@MainActor
final class TrayPopoverLayoutTests: XCTestCase {
    private var restoredModes: [IndividualMenuBarTool: String?] = [:]

    override func setUpWithError() throws {
        let defaults = UserDefaults.standard
        for tool in IndividualMenuBarTool.allCases {
            restoredModes[tool] = defaults.string(forKey: tool.preferenceKey)
            defaults.set(MenuBarDisplayMode.combined.rawValue, forKey: tool.preferenceKey)
        }
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        for (tool, value) in restoredModes {
            if let value {
                defaults.set(value, forKey: tool.preferenceKey)
            } else {
                defaults.removeObject(forKey: tool.preferenceKey)
            }
        }
    }

    func testDashboardSectionsFollowScanAndActOrder() {
        XCTAssertEqual(
            TrayPopoverLayout.dashboardSections(for: [
                "rclone", "awake", "color-picker", "text-extractor", "input-devices"
            ]),
            [.quickActions, .awake, .cloudSync, .inputDevices]
        )
        XCTAssertEqual(
            TrayPopoverLayout.dashboardSections(for: ["input-devices", "rclone"]),
            [.cloudSync, .inputDevices]
        )
        XCTAssertEqual(
            TrayPopoverLayout.dashboardSections(for: ["text-extractor"]),
            [.quickActions]
        )
        XCTAssertTrue(TrayPopoverLayout.dashboardSections(for: []).isEmpty)
    }

    func testDashboardUsesQuickControlsInsteadOfToolSettingsOrTabs() throws {
        let source = try sourceFile("Views/TrayPopoverView.swift")

        XCTAssertFalse(source.contains("ToolSettingsContent"))
        XCTAssertFalse(source.contains("TrayTabStrip"))
        XCTAssertTrue(source.contains("Picker(\"Awake duration\""))
        XCTAssertTrue(source.contains("activeJobs.prefix(3)"))
    }

    func testTrayPopoverHeightStaysWithinSeventyPercentOfTheScreen() {
        let screenHeight: CGFloat = 900
        let body = TrayPopoverLayout.maximumBodyHeight(screenHeight: screenHeight)

        XCTAssertLessThanOrEqual(
            body + TrayPopoverLayout.chromeHeight,
            screenHeight * TrayPopoverLayout.heightFraction
        )
        XCTAssertEqual(
            TrayPopoverLayout.maximumBodyHeight(screenHeight: 100),
            TrayPopoverLayout.minimumBodyHeight
        )
    }

    private func sourceFile(_ path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys")
            .appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
