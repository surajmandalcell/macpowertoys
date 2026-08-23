import XCTest
@testable import powertoys

final class InputDevicesTests: XCTestCase {
    func testScrollProfilesStayIndependent() {
        var settings = InputDevicesSettings()
        settings.mouse.reverseVertical = true
        settings.mouse.reverseHorizontal = true
        settings.mouse.speed = 2
        settings.trackpad.speed = 0.5

        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: 3, horizontal: -2, isContinuous: false, settings: settings),
            InputScrollResult(vertical: -6, horizontal: 4, shouldSmooth: true)
        )
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: 3, horizontal: -2, isContinuous: true, settings: settings),
            InputScrollResult(vertical: 1.5, horizontal: -1, shouldSmooth: false)
        )
    }
}
