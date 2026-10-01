import AIManagerCore
import XCTest
@testable import powertoys

final class MainPanelTests: XCTestCase {
    func testUsageWarningRemainsUntilAWindowHasLimits() {
        XCTAssertFalse(SwitchTrayView.hasUsageLimits(nil))
        for values in [(nil, nil), (0, nil), (nil, 100)] as [(Int?, Int?)] {
            let bucket = CodexRateLimitBucketSnapshot(
                id: nil, name: nil, plan: nil, model: nil,
                primary: .init(usedPercent: values.0, windowDurationMinutes: nil, resetsAt: nil),
                secondary: .init(usedPercent: values.1, windowDurationMinutes: nil, resetsAt: nil),
                credits: nil, spendControlReached: nil)
            let snapshot = CodexAccountUsageSnapshot(
                account: nil, requiresOpenAIAuthentication: nil,
                rateLimits: .init(accountID: nil, ordinaryUsageAllowed: nil, defaultBucket: bucket, buckets: [:]),
                usage: nil, dailyUsage: [], fetchedAt: Date(timeIntervalSince1970: 0))
            XCTAssertEqual(SwitchTrayView.hasUsageLimits(snapshot), values.0 != nil || values.1 != nil)
        }
    }
}
