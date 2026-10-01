import AppKit
import XCTest
@testable import powertoys

final class ToolActionRouterTests: XCTestCase {
    @MainActor
    func testBackgroundWindowsNeverUseActivationOrSceneCreation() {
        final class WindowSpy: NSWindow {
            var keyOrders = 0
            var backgroundOrders = 0
            var deminiaturizations = 0
            var minimized = false
            override var isMiniaturized: Bool { minimized }
            override func makeKeyAndOrderFront(_ sender: Any?) { keyOrders += 1 }
            override func orderFrontRegardless() { backgroundOrders += 1 }
            override func deminiaturize(_ sender: Any?) { deminiaturizations += 1 }
        }
        let tools = ["main", "rclone", "logs", "awake", "color-picker", "text-extractor",
                     "input-devices", "system-care", "disk-explorer", "system-monitor", "nettoys", "switch", "mac-tweaks"]
        for tool in tools {
            for existing in [false, true] {
                let window = WindowSpy(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
                window.identifier = .init(tool)
                window.minimized = existing
                var opened: [String] = []
                var created: [String] = []
                var activations = 0
                ToolActionRouter.presentSingleWindow(id: tool, windows: existing ? [window] : [], activateApp: false,
                    createWindow: { created.append($0); return window }, activate: { activations += 1 }) { opened.append($0) }
                XCTAssertEqual(window.backgroundOrders, 1, tool)
                XCTAssertEqual(window.keyOrders, 0, tool)
                XCTAssertEqual(window.deminiaturizations, 0, tool)
                XCTAssertEqual(window.minimized, existing, "Background opens must not restore a minimized window as key.")
                XCTAssertEqual(activations, 0, tool)
                XCTAssertEqual(created, existing ? [] : [tool])
                XCTAssertTrue(opened.isEmpty, "Background creation must not call SwiftUI openWindow.")
                let pages = ToolPageRouter()
                for page in tool == "main" ? ["all-tools", "favorites"] : ["settings", "settings"] {
                    pages.post(tool: tool, page: page, recordTiming: false)
                    XCTAssertEqual(pages.take(tool: tool)?.page, page)
                    ToolActionRouter.presentSingleWindow(id: tool, windows: [window], activateApp: false,
                        createWindow: { _ in XCTFail("Page reuse must keep the existing window"); return nil },
                        activate: { activations += 1 }) { opened.append($0) }
                    XCTAssertEqual(window.keyOrders, 0, "Background page reuse: \(tool)/\(page)")
                    XCTAssertEqual(window.deminiaturizations, 0)
                    XCTAssertEqual(window.minimized, existing)
                    XCTAssertEqual(activations, 0)
                    XCTAssertTrue(opened.isEmpty)
                }
                XCTAssertEqual(window.backgroundOrders, 3)
                ToolActionRouter.presentSingleWindow(id: tool, windows: [window], activateApp: true,
                    createWindow: { _ in XCTFail("Reuse must not create a window"); return nil },
                    activate: { activations += 1 }) { opened.append($0) }
                XCTAssertEqual(window.keyOrders, 1, "Explicit opens keep key ordering.")
                XCTAssertEqual(window.deminiaturizations, existing ? 1 : 0)
                XCTAssertEqual(activations, 1)
                ToolActionRouter.presentSingleWindow(id: tool, windows: [], activateApp: true,
                    createWindow: { _ in XCTFail("Explicit cold opens use their scene"); return nil },
                    activate: { activations += 1 }) { opened.append($0) }
                XCTAssertEqual(opened, [tool])
                XCTAssertEqual(activations, 2)
            }
        }
    }

    @MainActor
    func testToolOpenClosesMainOnlyWhenEnabled() throws {
        let suite = "ToolActionRouterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var closeCount = 0
        ToolActionRouter.finishToolOpen(defaults: defaults) { closeCount += 1 }
        XCTAssertEqual(closeCount, 0, "Missing preferences keep the main window open.")
        defaults.set(true, forKey: "app.closeMainWindowAfterOpeningTool")
        ToolActionRouter.finishToolOpen(defaults: defaults) { closeCount += 1 }
        XCTAssertEqual(closeCount, 1)
        defaults.set(false, forKey: "app.closeMainWindowAfterOpeningTool")
        ToolActionRouter.finishToolOpen(defaults: defaults) { closeCount += 1 }
        XCTAssertEqual(closeCount, 1)
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

    func testExternalWindowActionsDoNotRequestActivation() throws {
        for scheme in ["macpowertoys", "powertoys"] {
            for action in ToolActionID.allCases where action.opensWindow
                || [.rulerOpen, .rulerSettings, .portmanOpen].contains(action) {
                let url = try XCTUnwrap(URL(string: "\(scheme)://run/\(action.rawValue)"))
                XCTAssertFalse(try XCTUnwrap(ToolActionRouter.request(from: url)).activateApp, action.rawValue)
            }
        }
        XCTAssertTrue(ToolActionRequest(action: .awakeOpen).activateApp,
                      "Explicit launcher and panel actions still activate.")
    }

    @MainActor
    func testLegacyMonitorWindowIDResolvesToCurrentID() {
        XCTAssertEqual(ToolActionRouter.resolvedWindowID("power-stats"), "system-monitor")
        XCTAssertEqual(ToolActionRouter.resolvedWindowID("system-monitor"), "system-monitor")
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
