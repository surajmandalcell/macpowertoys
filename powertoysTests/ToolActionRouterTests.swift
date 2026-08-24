import XCTest
@testable import powertoys

final class ToolActionRouterTests: XCTestCase {
    @MainActor
    func testRulerClosesMainWindowBeforePostingOpenAction() {
        var events: [String] = []
        ToolActionRouter.launchRuler(
            dismissMainWindow: { events.append("dismiss") },
            openRuler: { events.append("open") }
        )

        XCTAssertEqual(events, ["dismiss", "open"])
    }

    func testParsesActionAndPercentDecodedParameters() throws {
        let url = try XCTUnwrap(URL(string: "macpowertoys://run/awake.timed?seconds=1800&label=Focus%20time"))

        let request = try XCTUnwrap(ToolActionRouter.request(from: url))

        XCTAssertEqual(request.action, .awakeTimed)
        XCTAssertEqual(request.parameters, ["seconds": "1800", "label": "Focus time"])
    }

    func testLegacySchemeRemainsSupported() throws {
        let url = try XCTUnwrap(URL(string: "powertoys://run/color-picker.copy-last"))
        XCTAssertEqual(ToolActionRouter.request(from: url)?.action, .colorPickerCopyLast)
    }

    func testParsesRulerSettingsWithoutTreatingItAsASwiftUIWindow() throws {
        let url = try XCTUnwrap(URL(string: "macpowertoys://run/ruler.settings?flag&source=test"))
        let request = try XCTUnwrap(ToolActionRouter.request(from: url))

        XCTAssertEqual(request.action, .rulerSettings)
        XCTAssertEqual(request.parameters, ["source": "test"])
        XCTAssertFalse(request.action.opensWindow)
    }

    func testRejectsUnsupportedSchemeHostAndAction() throws {
        XCTAssertNil(ToolActionRouter.request(from: try XCTUnwrap(URL(string: "https://run/ruler.open"))))
        XCTAssertNil(ToolActionRouter.request(from: try XCTUnwrap(URL(string: "macpowertoys://open/ruler.open"))))
        XCTAssertNil(ToolActionRouter.request(from: try XCTUnwrap(URL(string: "macpowertoys://run/unknown.action"))))
        for removedAction in ["ruler.new-horizontal", "ruler.new-vertical", "ruler.new-joined", "ruler.measure"] {
            XCTAssertNil(ToolActionRouter.request(
                from: try XCTUnwrap(URL(string: "macpowertoys://run/\(removedAction)"))
            ))
        }
    }

    func testActionMetadataClassifiesWindowActions() {
        let windowActions: Set<ToolActionID> = [.awakeOpen, .colorPickerHistory, .textExtractorOpen]
        for action in ToolActionID.allCases {
            XCTAssertEqual(action.opensWindow, windowActions.contains(action), "Unexpected window classification for \(action)")
            XCTAssertEqual(action.toolID, action.rawValue.split(separator: ".").first.map(String.init))
        }
    }

    func testWindowIdentifierMatchingNeverRaisesAppKitRulerWindowsThroughSwiftUI() {
        XCTAssertTrue(ToolActionRouter.windowIdentifier("awake", matches: "awake"))
        XCTAssertTrue(ToolActionRouter.windowIdentifier("awake-AppWindow-1", matches: "awake"))
        XCTAssertFalse(ToolActionRouter.windowIdentifier("ruler-window", matches: "ruler"))
        XCTAssertFalse(ToolActionRouter.windowIdentifier("ruler-settings-window", matches: "ruler"))
        XCTAssertFalse(ToolActionRouter.windowIdentifier("ruler.1234", matches: "ruler"))
        XCTAssertFalse(ToolActionRouter.windowIdentifier("awake-extra", matches: "ruler"))
    }
}
