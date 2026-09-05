import SwiftData
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class TrayPopoverLayoutTests: XCTestCase {
    private var container: ModelContainer!
    private var restoredModes: [IndividualMenuBarTool: String?] = [:]
    private var restoredSelection: String?

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: TransferRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = UserDefaults.standard
        restoredSelection = defaults.string(forKey: "tray.selectedTab")
        for tool in IndividualMenuBarTool.allCases {
            restoredModes[tool] = defaults.string(forKey: tool.preferenceKey)
            defaults.set(MenuBarDisplayMode.combined.rawValue, forKey: tool.preferenceKey)
        }
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        for (tool, value) in restoredModes {
            if let value {
                defaults.set(value, forKey: tool.preferenceKey)
            } else {
                defaults.removeObject(forKey: tool.preferenceKey)
            }
        }
        if let restoredSelection {
            defaults.set(restoredSelection, forKey: "tray.selectedTab")
        } else {
            defaults.removeObject(forKey: "tray.selectedTab")
        }
    }

    func testTrayBodyStartsOneOuterInsetBelowTheTabRow() throws {
        UserDefaults.standard.set("color-picker", forKey: "tray.selectedTab")
        let bands = try inkBands(of: TrayPopoverView().modelContainer(container))

        XCTAssertGreaterThanOrEqual(bands.count, 3, "expected outer inset, tab group, body gap")
        XCTAssertEqual(
            bands[0],
            Band(isInk: false, length: Int(TrayPopoverLayout.tabGroupOuterInset)),
            "the tab row must sit one outer inset below the popover top"
        )
        XCTAssertEqual(
            bands[1],
            Band(
                isInk: true,
                length: Int(TrayPopoverLayout.tabGroupInset * 2 + TrayPopoverLayout.tabHeight)
            ),
            "the tab group must keep an equal inner inset around a 28pt tab row"
        )

        XCTAssertFalse(bands[2].isInk)
        let bodyGap = bands[2].length
        XCTAssertGreaterThanOrEqual(bodyGap, Int(TrayPopoverLayout.tabGroupOuterInset))
        XCTAssertLessThanOrEqual(
            bodyGap,
            Int(TrayPopoverLayout.tabGroupOuterInset) + 3,
            "the body must not stack a second top gap under the tab row"
        )
        XCTAssertEqual(TrayPopoverLayout.bodyTopInset, 0)
    }

    func testEveryTrayTabbedToolRendersItsSharedSettingsView() throws {
        let fallbackHeight = settingsHeight(for: "no-such-tool")
        let trayTools = ToolRegistry.allTools.filter(\.hasTrayTab)

        XCTAssertEqual(trayTools.count, 5)
        for tool in trayTools {
            let height = settingsHeight(for: tool.id)
            XCTAssertNotEqual(
                height,
                fallbackHeight,
                "\(tool.id) falls back to the no-settings placeholder in the tray"
            )
            XCTAssertGreaterThan(height, 60, "\(tool.id) renders no usable tray settings")
        }
    }

    func testTrayPopoverHeightStaysWithinSeventyPercentOfTheScreen() {
        let screenHeight: CGFloat = 900
        let body = TrayPopoverLayout.maximumBodyHeight(screenHeight: screenHeight)

        XCTAssertLessThanOrEqual(
            body + TrayPopoverLayout.chromeHeight,
            screenHeight * TrayPopoverLayout.heightFraction
        )
        XCTAssertEqual(
            TrayPopoverLayout.maximumBodyHeight(screenHeight: 100),
            TrayPopoverLayout.minimumBodyHeight
        )
    }

    // MARK: - Helpers

    private struct Band: Equatable {
        let isInk: Bool
        let length: Int
    }

    private func settingsHeight(for toolID: String) -> CGFloat {
        let host = NSHostingView(
            rootView: ToolSettingsContent(toolID: toolID)
                .environment(\.compactSettingsLayout, true)
                .frame(width: TrayPopoverLayout.width)
        )
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    /// Vertical runs of drawn and undrawn pixels, so the measured gaps come from
    /// the rendered popover rather than from the layout constants alone.
    private func inkBands(of view: some View) throws -> [Band] {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: TrayPopoverLayout.width, height: 400)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.frame = NSRect(
            x: 0,
            y: 0,
            width: TrayPopoverLayout.width,
            height: host.fittingSize.height
        )
        host.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)

        let backgroundAlpha = try XCTUnwrap(representation.colorAt(x: 2, y: 2)).alphaComponent
        var bands: [Band] = []
        for y in 0..<representation.pixelsHigh {
            var isInk = false
            for x in stride(from: 0, to: representation.pixelsWide, by: 2) {
                guard let color = representation.colorAt(x: x, y: y) else { continue }
                if abs(color.alphaComponent - backgroundAlpha) > 0.01 {
                    isInk = true
                    break
                }
            }
            if let last = bands.last, last.isInk == isInk {
                bands[bands.count - 1] = Band(isInk: isInk, length: last.length + 1)
            } else {
                bands.append(Band(isInk: isInk, length: 1))
            }
        }
        return bands
    }
}
