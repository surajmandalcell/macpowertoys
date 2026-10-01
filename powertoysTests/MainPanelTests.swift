import AIManagerCore
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

    func testUsageWarningRemainsUntilAWindowHasLimits() {
        XCTAssertFalse(SwitchTrayView.hasUsageLimits(nil))
        for (primary, secondary, expected) in [(nil, nil, false), (0, nil, true), (nil, 100, true)] as [(Int?, Int?, Bool)] {
            let bucket = CodexRateLimitBucketSnapshot(
                id: nil, name: nil, plan: nil, model: nil,
                primary: .init(usedPercent: primary, windowDurationMinutes: nil, resetsAt: nil),
                secondary: .init(usedPercent: secondary, windowDurationMinutes: nil, resetsAt: nil),
                credits: nil, spendControlReached: nil)
            let snapshot = CodexAccountUsageSnapshot(
                account: nil, requiresOpenAIAuthentication: nil,
                rateLimits: .init(accountID: nil, ordinaryUsageAllowed: nil, defaultBucket: bucket, buckets: [:]),
                usage: nil, dailyUsage: [], fetchedAt: Date(timeIntervalSince1970: 0))
            XCTAssertEqual(SwitchTrayView.hasUsageLimits(snapshot), expected)
        }
    }
}
