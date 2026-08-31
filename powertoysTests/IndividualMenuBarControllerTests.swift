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

        for tool in IndividualMenuBarTool.allCases {
            for mode in MenuBarDisplayMode.allCases {
                defaults.set(mode.rawValue, forKey: tool.preferenceKey)
                XCTAssertEqual(tool.displayMode(in: defaults), mode, "\(tool.id): \(mode.id)")
            }
        }
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
        XCTAssertEqual(Set(tools.map(\.autosaveName)).count, tools.count)
        XCTAssertEqual(tools.map(\.autosaveName), [
            "MacPowerToys.rclone",
            "MacPowerToys.awake",
            "MacPowerToys.color-picker",
            "MacPowerToys.text-extractor",
            "MacPowerToys.input-devices"
        ])
        XCTAssertEqual(tools.map(\.activation), [
            .openTool("rclone"),
            .openTool("awake"),
            .execute(.colorPickerPick),
            .execute(.textExtractorCapture),
            .openTool("input-devices")
        ])
    }

    func testEveryMenuBarToolSupportsACombinedTab() {
        XCTAssertTrue(IndividualMenuBarTool.allCases.allSatisfy { tool in
            ToolRegistry.tool(for: tool.id)?.hasTrayTab == true
        })
    }

    func testEveryModeUsesOnePlacementAndDisabledToolsUseNone() {
        let suiteName = "IndividualMenuBarPlacementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for tool in IndividualMenuBarTool.allCases {
            for mode in MenuBarDisplayMode.allCases {
                defaults.set(mode.rawValue, forKey: tool.preferenceKey)
                for placement in MenuBarDisplayMode.allCases {
                    XCTAssertEqual(
                        tool.usesMenuBarMode(placement, enabled: true, in: defaults),
                        placement == mode,
                        "\(tool.id): \(mode.id) -> \(placement.id)"
                    )
                    XCTAssertFalse(tool.usesMenuBarMode(placement, enabled: false, in: defaults))
                }
            }
        }
    }

    func testRefreshPlanKeepsExistingItemsAndChangesOnlyPlacementDelta() {
        let current: Set<IndividualMenuBarTool> = [.cloudSync, .colorPicker]

        let unchanged = IndividualMenuBarRefreshPlan(
            current: current,
            desired: [.cloudSync, .colorPicker]
        )
        XCTAssertTrue(unchanged.insertions.isEmpty)
        XCTAssertTrue(unchanged.removals.isEmpty)

        let changed = IndividualMenuBarRefreshPlan(
            current: current,
            desired: [.awake, .colorPicker]
        )
        XCTAssertEqual(changed.insertions, [.awake])
        XCTAssertEqual(changed.removals, [.cloudSync])
    }
}
