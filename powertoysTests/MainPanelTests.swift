import AppKit
import SwiftUI
import XCTest
@testable import powertoys

final class MainPanelTests: XCTestCase {
    @MainActor
    func testWarmDiagnosticOpenRetainsWindowAndHost() throws {
        let domain = "MainPanelTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let panels = DiagnosticsMenuPanels(defaults: defaults)
        var builds = 0
        panels.makeCaptureContent = { _, _, _ in
            builds += 1
            return AnyView(Color.clear.frame(width: 356, height: 120))
        }
        defer { panels.close() }
        panels.open(.main, tab: "home")
        let window = try XCTUnwrap(panels.captureWindow)
        let hosting = try XCTUnwrap(window.contentViewController)
        panels.close()
        XCTAssertFalse(window.isVisible)
        panels.open(.main, tab: "home")
        XCTAssertTrue(panels.captureWindow === window)
        XCTAssertTrue(panels.captureWindow?.contentViewController === hosting)
        XCTAssertEqual(builds, 1)
    }
}
