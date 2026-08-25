import XCTest
@testable import powertoys

final class IndividualMenuBarControllerTests: XCTestCase {
    func testMenuBarModesPreserveLegacyPreferences() {
        let suiteName = "IndividualMenuBarControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(IndividualMenuBarTool.cloudSync.displayMode(in: defaults), .combined)
        XCTAssertEqual(IndividualMenuBarTool.colorPicker.displayMode(in: defaults), .none)

        defaults.set(true, forKey: IndividualMenuBarTool.colorPicker.legacyPreferenceKey)
        XCTAssertEqual(IndividualMenuBarTool.colorPicker.displayMode(in: defaults), .separate)

        defaults.set(
            MenuBarDisplayMode.combined.rawValue,
            forKey: IndividualMenuBarTool.colorPicker.preferenceKey
        )
        XCTAssertEqual(IndividualMenuBarTool.colorPicker.displayMode(in: defaults), .combined)
    }

    func testSupportedToolsHaveStableUniquePreferencesAndActions() {
        let tools = IndividualMenuBarTool.allCases

        XCTAssertEqual(tools.map(\.id), [
            "rclone",
            "awake",
            "color-picker",
            "text-extractor",
            "input-devices"
        ])
        XCTAssertEqual(Set(tools.map(\.preferenceKey)).count, tools.count)
        XCTAssertEqual(IndividualMenuBarTool.colorPicker.quickAction, .colorPickerPick)
        XCTAssertEqual(IndividualMenuBarTool.textExtractor.quickAction, .textExtractorCapture)
        XCTAssertNil(IndividualMenuBarTool.cloudSync.quickAction)
        XCTAssertNil(IndividualMenuBarTool.awake.quickAction)
        XCTAssertNil(IndividualMenuBarTool.inputDevices.quickAction)
    }

    func testEveryMenuBarToolSupportsACombinedTab() {
        XCTAssertTrue(IndividualMenuBarTool.allCases.allSatisfy { tool in
            ToolRegistry.tool(for: tool.id)?.hasTrayTab == true
        })
    }
}
