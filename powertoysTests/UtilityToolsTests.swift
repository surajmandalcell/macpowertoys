import XCTest
@testable import powertoys

@MainActor
final class UtilityToolsTests: XCTestCase {
    func testDockIconMatchesActiveToolWindow() {
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "ruler"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "awake-AppWindow-1"), "AwakeLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "color-picker"), "ColorPickerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "text-extractor"), "TextExtractorLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "main"), "AppIcon")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: nil), "AppIcon")
    }

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
        XCTAssertTrue(sample.matches(ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1)))
        XCTAssertFalse(sample.matches(ColorSample(red: 0, green: 0.5, blue: 0, alpha: 1)))
    }

    func testJoinedRulerStartsWithBothArms() {
        let ruler = RulerState(orientation: .joined, frame: CGRect(x: 0, y: 0, width: 400, height: 300), screenID: nil)
        XCTAssertTrue(ruler.showsHorizontalArm)
        XCTAssertTrue(ruler.showsVerticalArm)
    }

    func testOlderRulerPayloadsReceiveNewDefaults() throws {
        let stateData = Data(#"{"id":"00000000-0000-0000-0000-000000000001","orientation":"joined","x":1,"y":2,"width":300,"height":200,"isVisible":true}"#.utf8)
        let state = try JSONDecoder().decode(RulerState.self, from: stateData)
        XCTAssertTrue(state.showsHorizontalArm)
        XCTAssertTrue(state.showsVerticalArm)

        let styleData = Data(#"{"unit":"px","zeroCorner":"topLeft","opacity":1,"red":1,"green":1,"blue":1,"floats":true,"hasShadow":true,"calibration":1}"#.utf8)
        let style = try JSONDecoder().decode(RulerStyle.self, from: styleData)
        XCTAssertTrue(style.displayCalibrations.isEmpty)
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

    func testGlobalShortcutKeysCoverAlphabetWithoutDuplicateCodes() {
        XCTAssertEqual(GlobalShortcutKey.allCases.map(\.title), Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init))
        XCTAssertEqual(Set(GlobalShortcutKey.allCases.map(\.keyCode)).count, 26)
    }
}
