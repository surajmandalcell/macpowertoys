import XCTest
@testable import powertoys

/// Pins every Open entry point to the surface it shows. Explicit reuse, minimized, and closed-window cases live in
/// `ToolActionRouterTests` (`presentSingleWindow`).
@MainActor
final class ToolOpenRoutingTests: XCTestCase {
    private let enabled: (String) -> Bool = { _ in true }
    private let expected: [String: ToolActionRouter.OpenTarget] = [
        "main": .window("main"),
        "rclone": .window("rclone"),
        "logs": .window("logs"),
        "color-picker": .window("color-picker"),
        "text-extractor": .window("text-extractor"),
        "input-devices": .window("input-devices"),
        "mac-tweaks": .window("mac-tweaks"),
        "ruler": .ruler,
        "portman": .portmanPanel,
        // Awake has no window: its main-window page is the explicit fallback.
        "awake": .mainPage("tool/awake")
    ]

    func testEveryBuiltInToolOpensItsOwnSurface() {
        for tool in ToolRegistry.builtInTools {
            XCTAssertNotNil(expected[tool.id], "Pin the open target of \(tool.id)")
        }
        for (id, target) in expected {
            XCTAssertEqual(ToolActionRouter.openTarget(for: id, isEnabled: enabled), target, id)
        }
        for (alias, id) in ["cloud-sync": "rclone", "cloudsync": "rclone", "rsync": "rclone",
                            "settings": "main", "home": "main"] {
            XCTAssertEqual(ToolActionRouter.openTarget(for: alias, isEnabled: enabled), .window(id), alias)
        }
        XCTAssertEqual(Set(expected.values.compactMap { target -> String? in
                           if case .window(let id) = target { return id }
                           return nil
                       }),
                       ToolActionRouter.windowIDs, "Every window scene has a tool that opens it")
        XCTAssertEqual(ToolActionRouter.openTarget(for: AppsBySamView.pageID, isEnabled: enabled),
                       .mainPage(AppsBySamView.pageID))
        XCTAssertEqual(ToolActionRouter.openTarget(for: FanPageView.pageID, isEnabled: enabled),
                       .mainPage(FanPageView.pageID))
        XCTAssertEqual(ToolActionRouter.openTarget(for: "some-plugin", isEnabled: enabled), .marketplace("some-plugin"))
    }

    func testDisabledToolsOpenNothingButMainStillOpens() {
        for tool in ToolRegistry.builtInTools {
            XCTAssertEqual(ToolActionRouter.openTarget(for: tool.id, isEnabled: { _ in false }), .ignored, tool.id)
            XCTAssertEqual(ToolActionRouter.panelOpenTarget(for: tool.id, isEnabled: { _ in false }), .ignored, tool.id)
        }
        XCTAssertEqual(ToolActionRouter.openTarget(for: "main", isEnabled: { _ in false }), .window("main"))
    }

    /// The main window tool page's Open tile and Command-O open the tool, never a settings page.
    func testMainWindowOpenButtonsOpenTheToolNotAPage() {
        for tool in ToolRegistry.builtInTools where tool.id != "awake" {
            let target = ToolActionRouter.openTarget(for: tool.id, isEnabled: enabled)
            if case .mainPage = target { XCTFail("\(tool.id) Open must not show a main-window page") }
        }
    }

    func testPanelArrowOpensTheSelectedTool() {
        let tabs: [TrayTab: ToolActionRouter.OpenTarget] = [
            .home: .window("main"), .cloudSync: .window("rclone"), .inputDevices: .window("input-devices")
        ]
        for tab in TrayTab.allCases {
            XCTAssertEqual(ToolActionRouter.panelOpenTarget(for: tab.openToolID, isEnabled: enabled), tabs[tab], tab.id)
        }
        let separate: [IndividualMenuBarTool: ToolActionRouter.OpenTarget] = [
            .cloudSync: .window("rclone"), .colorPicker: .window("color-picker"),
            .textExtractor: .window("text-extractor"), .inputDevices: .window("input-devices"),
            .awake: .mainPage("tool/awake")
        ]
        for tool in IndividualMenuBarTool.allCases {
            XCTAssertEqual(ToolActionRouter.panelOpenTarget(for: tool.id, isEnabled: enabled), separate[tool], tool.id)
        }
        // Portman's panel is Portman itself; reopening it from inside would do nothing.
        XCTAssertEqual(ToolActionRouter.panelOpenTarget(for: "portman", isEnabled: enabled), .mainPage("tool/portman"))
    }

    func testOpenLinksUseTheSameTargetsInBothSchemes() throws {
        for scheme in ["macpowertoys", "powertoys"] {
            for (id, target) in expected {
                let route = try XCTUnwrap(OpenToolRoute.parse(XCTUnwrap(URL(string: "\(scheme)://open/\(id)"))))
                XCTAssertNil(route.page)
                XCTAssertEqual(ToolActionRouter.openTarget(for: route.tool, isEnabled: enabled), target, "\(scheme) \(id)")
            }
            let action = try XCTUnwrap(ToolActionRouter.request(from: XCTUnwrap(URL(string: "\(scheme)://run/portman.open"))))
            XCTAssertEqual(action.action, .portmanOpen)
        }
    }
}
