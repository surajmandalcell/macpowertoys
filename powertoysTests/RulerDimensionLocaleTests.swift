import AppKit
import XCTest
@testable import powertoys

@MainActor
final class RulerDimensionLocaleTests: XCTestCase {
    func testDisplayedDimensionsRoundTripThroughEachFieldsLocale() throws {
        let controls = RulerSettingsControlsView(frame: NSRect(x: 0, y: 0, width: 380, height: 491))
        controls.configureForRulerSettings()
        let widthFormatter = try XCTUnwrap(controls.dimensionWidthField.formatter as? NumberFormatter)
        let heightFormatter = try XCTUnwrap(controls.dimensionHeightField.formatter as? NumberFormatter)
        widthFormatter.locale = Locale(identifier: "de_DE")
        heightFormatter.locale = Locale(identifier: "en_US")

        for (unit, scale, width, height) in [
            (Unit.millimeters, NSScreen.defaultDpmm, CGFloat(25.5), CGFloat(12.5)),
            (Unit.inches, NSScreen.defaultDpi, 3.125, 2.75)
        ] {
            controls.updateDimensions(unit: unit, horizontalLength: width * scale, verticalLength: height * scale)
            XCTAssertTrue(controls.dimensionWidthField.stringValue.contains(","))
            XCTAssertTrue(controls.dimensionHeightField.stringValue.contains("."))
            XCTAssertEqual(controls.dimensionWidthField.doubleValue, Double(width), accuracy: 0.0001)
            XCTAssertEqual(controls.dimensionHeightField.doubleValue, Double(height), accuracy: 0.0001)
            XCTAssertEqual(controls.selectedHorizontalLength, (width * scale).rounded(), accuracy: 0.0001)
            XCTAssertEqual(controls.selectedVerticalLength, (height * scale).rounded(), accuracy: 0.0001)
        }
    }
}
