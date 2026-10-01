import AIManagerCore
import XCTest
@testable import powertoys

final class MainPanelTests: XCTestCase {
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
