import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusSegmentAvailabilityTests: XCTestCase {
    func testKeyboardSelectionSkipsUnavailableChoices() {
        let choices = ["Auto", "Cool", "Max"]
        for current in choices {
            for direction in [-1, 1] {
                XCTAssertEqual(OnePlusSegmented.nextSelection(in: choices, current: current, direction: direction,
                                                              isChoiceEnabled: { $0 == "Auto" }), "Auto")
            }
        }
        XCTAssertEqual(OnePlusSegmented.nextSelection(in: choices, current: "Auto", direction: 1,
                                                      isChoiceEnabled: { $0 != "Cool" }), "Max")
        XCTAssertEqual(OnePlusSegmented.nextSelection(in: choices, current: "Max", direction: -1,
                                                      isChoiceEnabled: { $0 != "Cool" }), "Auto")
        XCTAssertNil(OnePlusSegmented.nextSelection(in: choices, current: "Auto", direction: 1,
                                                    isChoiceEnabled: { _ in false }))
        XCTAssertEqual(OnePlusSegmented.nextSelection(in: choices, current: "Auto", direction: 1), "Cool")
    }
}
