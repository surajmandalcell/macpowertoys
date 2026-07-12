import XCTest
@testable import powertoys

final class UtilityToolsTests: XCTestCase {
    func testRulerTicksRespectDirection() {
        let forward = RulerGeometry.ticks(length: 100, pointsPerUnit: 1, reversed: false)
        let reverse = RulerGeometry.ticks(length: 100, pointsPerUnit: 1, reversed: true)
        XCTAssertEqual(forward.first?.position, 0)
        XCTAssertEqual(reverse.first?.position, 100)
        XCTAssertEqual(forward.count, reverse.count)
    }

    func testRulerCopyFormats() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        XCTAssertEqual(RulerCopyFormat.css.render(frame: frame), "width: 300px; height: 200px;")
        XCTAssertEqual(RulerCopyFormat.cgRect.render(frame: frame), "CGRect(x: 10, y: 20, width: 300, height: 200)")
    }

    func testColorFormatting() {
        let sample = ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1)
        XCTAssertEqual(sample.string(.hex), "#FF8000")
        XCTAssertEqual(sample.string(.rgb), "rgb(255, 128, 0)")
        XCTAssertTrue(sample.string(.swiftUI).hasPrefix("Color(red:"))
    }

    func testAwakeDurationFormatting() {
        XCTAssertEqual(AwakeService.duration(65), "01:05")
        XCTAssertEqual(AwakeService.duration(3661), "1:01:01")
    }

    func testActionIDsMapToTools() {
        XCTAssertEqual(ToolActionID.rulerNewJoined.toolID, "ruler")
        XCTAssertEqual(ToolActionID.colorPickerCopyLast.toolID, "color-picker")
        XCTAssertEqual(ToolActionID.textExtractorCapture.toolID, "text-extractor")
    }
}
