import AppKit
import XCTest
@testable import powertoys

@MainActor
final class UtilityModelTests: XCTestCase {
    func testRulerZeroCornersMapDirectionsAndTitles() {
        XCTAssertEqual(RulerZeroCorner.allCases.map(\.title), ["Top Left", "Top Right", "Bottom Left", "Bottom Right"])
        XCTAssertFalse(RulerZeroCorner.topLeft.reversesHorizontal)
        XCTAssertTrue(RulerZeroCorner.topLeft.reversesVertical)
        XCTAssertTrue(RulerZeroCorner.topRight.reversesHorizontal)
        XCTAssertFalse(RulerZeroCorner.bottomLeft.reversesHorizontal)
        XCTAssertFalse(RulerZeroCorner.bottomLeft.reversesVertical)
        XCTAssertTrue(RulerZeroCorner.bottomRight.reversesHorizontal)
    }

    func testRulerStateFrameReadsAndWritesEveryComponent() {
        var state = RulerState(orientation: .horizontal, frame: CGRect(x: 1, y: 2, width: 3, height: 4), screenID: 7)
        XCTAssertEqual(state.frame, CGRect(x: 1, y: 2, width: 3, height: 4))

        state.frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        XCTAssertEqual(state.x, 10)
        XCTAssertEqual(state.y, 20)
        XCTAssertEqual(state.width, 300)
        XCTAssertEqual(state.height, 400)
    }

    func testRulerMeasurementPreservesFrame() {
        let frame = CGRect(x: -10, y: 12.5, width: 300.25, height: 80)
        XCTAssertEqual(RulerMeasurement(frame: frame).frame, frame)
    }

    func testRulerTicksRejectInvalidGeometryAndProduceMajorLevels() {
        XCTAssertTrue(RulerGeometry.ticks(length: 0, pointsPerUnit: 1, reversed: false).isEmpty)
        XCTAssertTrue(RulerGeometry.ticks(length: 100, pointsPerUnit: 0, reversed: false).isEmpty)

        let ticks = RulerGeometry.ticks(length: 60, pointsPerUnit: 1, reversed: false)
        XCTAssertEqual(ticks.first, RulerTick(position: 0, value: 0, level: 2))
        XCTAssertTrue(ticks.contains { $0.level == 1 })
        XCTAssertTrue(ticks.contains { $0.level == 0 })
    }

    func testRulerPointUnitsUseFrameworkFallbackWithoutScreen() {
        XCTAssertEqual(RulerGeometry.pointsPerUnit(.points, screen: nil, calibration: 3), 1)
        XCTAssertEqual(RulerGeometry.pointsPerUnit(.pixels, screen: nil, calibration: 3), 1)
        XCTAssertEqual(RulerGeometry.pointsPerUnit(.inches, screen: nil, calibration: 3), 72)
        XCTAssertEqual(RulerGeometry.pointsPerUnit(.millimeters, screen: nil, calibration: 3), 72 / 25.4, accuracy: 0.0001)
    }

    func testEveryRulerCopyFormatRendersStableDeveloperOutput() throws {
        let frame = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(RulerCopyFormat.plain.render(frame: frame), "30 × 40 at (10, 20); center (25, 40); diagonal 50")
        XCTAssertEqual(RulerCopyFormat.css.render(frame: frame), "width: 30px; height: 40px;")
        XCTAssertEqual(RulerCopyFormat.swiftUI.render(frame: frame), ".frame(width: 30, height: 40)")
        XCTAssertEqual(RulerCopyFormat.cgRect.render(frame: frame), "CGRect(x: 10, y: 20, width: 30, height: 40)")

        let json = try XCTUnwrap(RulerCopyFormat.json.render(frame: frame).data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Double])
        XCTAssertEqual(object["centerX"], 25)
        XCTAssertEqual(object["centerY"], 40)
    }

    func testColorCopyFormatTitlesAreHumanReadable() {
        XCTAssertEqual(ColorCopyFormat.hex.title, "HEX")
        XCTAssertEqual(ColorCopyFormat.cssVariable.title, "CSS Variable")
        XCTAssertEqual(ColorCopyFormat.swiftUI.title, "SwiftUI")
        XCTAssertEqual(ColorCopyFormat.nsColor.title, "NSColor")
    }

    func testColorFormattingCoversEveryOutputFormat() {
        let sample = ColorSample(red: 1, green: 0.5, blue: 0, alpha: 0.25)
        XCTAssertEqual(sample.string(.hex), "#FF8000")
        XCTAssertEqual(sample.string(.hexa), "#FF800040")
        XCTAssertEqual(sample.string(.rgb), "rgb(255, 128, 0)")
        XCTAssertEqual(sample.string(.rgba), "rgba(255, 128, 0, 0.25)")
        XCTAssertEqual(sample.string(.hsl), "hsl(30, 100%, 50%)")
        XCTAssertEqual(sample.string(.hsla), "hsla(30, 100%, 50%, 0.25)")
        XCTAssertEqual(sample.string(.cssVariable), "--color: #FF800040;")
        XCTAssertEqual(sample.string(.swiftUI), "Color(red: 1, green: 0.5, blue: 0, opacity: 0.25)")
        XCTAssertEqual(sample.string(.nsColor), "NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.25)")
    }

    func testColorHSLConversionCoversGrayRedGreenAndBlueBranches() {
        XCTAssertEqual(ColorSample(red: 0.5, green: 0.5, blue: 0.5, alpha: 1).string(.hsl), "hsl(0, 0%, 50%)")
        XCTAssertEqual(ColorSample(red: 1, green: 0, blue: 0, alpha: 1).string(.hsl), "hsl(0, 100%, 50%)")
        XCTAssertEqual(ColorSample(red: 0, green: 1, blue: 0, alpha: 1).string(.hsl), "hsl(120, 100%, 50%)")
        XCTAssertEqual(ColorSample(red: 0, green: 0, blue: 1, alpha: 1).string(.hsl), "hsl(240, 100%, 50%)")
        XCTAssertEqual(ColorSample(red: 1, green: 0, blue: 0.5, alpha: 1).string(.hsl), "hsl(330, 100%, 50%)")
    }

    func testColorMatchingUsesStrictToleranceAcrossAllChannels() {
        let sample = ColorSample(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        XCTAssertTrue(sample.matches(ColorSample(red: 0.1004, green: 0.2004, blue: 0.3004, alpha: 0.4004)))
        XCTAssertFalse(sample.matches(ColorSample(red: 0.1005, green: 0.2, blue: 0.3, alpha: 0.4)))
        XCTAssertFalse(sample.matches(ColorSample(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.41)))
    }

    func testAwakeModesHaveStableTitlesAndConfigurationDefaults() {
        XCTAssertEqual(AwakeMode.allCases.map(\.title), [
            "Passive", "Keep Awake Indefinitely", "Keep Awake for an Interval", "Keep Awake Until"
        ])
        let configuration = AwakeConfiguration()
        XCTAssertEqual(configuration.mode, .passive)
        XCTAssertFalse(configuration.keepDisplayOn)
        XCTAssertNil(configuration.expiresAt)
        XCTAssertEqual(configuration.intervalSeconds, 1_800)
        XCTAssertEqual(configuration.presets, [900, 1_800, 3_600, 7_200])
    }
}
