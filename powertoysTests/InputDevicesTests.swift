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

    func testHIDTelemetryUsesReportedResolutionAndPollingRate() {
        XCTAssertEqual(InputDeviceDescriptor.fixedPointResolution(26_214_400), 400)
        XCTAssertEqual(InputDeviceDescriptor.fixedPointResolution(800), 800)
        XCTAssertNil(InputDeviceDescriptor.fixedPointResolution(0))

        XCTAssertEqual(
            InputDeviceDescriptor.pollingRate(pointerRate: 120, reportIntervalMicroseconds: 8_000),
            120
        )
        XCTAssertEqual(
            InputDeviceDescriptor.pollingRate(pointerRate: nil, reportIntervalMicroseconds: 8_000),
            125
        )
        XCTAssertNil(InputDeviceDescriptor.pollingRate(pointerRate: nil, reportIntervalMicroseconds: nil))
    }
}
