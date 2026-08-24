import XCTest
@testable import powertoys

final class IndividualMenuBarControllerTests: XCTestCase {
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
}
