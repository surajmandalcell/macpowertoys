import OnePlusUI
import XCTest
@testable import powertoys

final class CompactAppletRedesignTests: XCTestCase {
    func testHistoryWindowsStayWithinTheirCanvasForEmptyAndLargeHistories() {
        for count in [0, 1, 2, 5, 1000] {
            XCTAssertTrue(OnePlusWindowCanvas.colorPicker.heightRange!.contains(ColorPickerLayout.historyHeight(count: count)))
            XCTAssertTrue(OnePlusWindowCanvas.textExtractor.heightRange!.contains(TextExtractorLayout.historyHeight(count: count)))
        }
        XCTAssertEqual(ColorPickerLayout.historyHeight(count: 1000), 460)
        XCTAssertEqual(TextExtractorLayout.historyHeight(count: 1000), 462)
        XCTAssertEqual(AwakeLayout.windowWidth, 560)
        XCTAssertEqual(AwakeLayout.windowHeight, 500)
    }
}
