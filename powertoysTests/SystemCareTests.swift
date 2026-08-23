import XCTest
@testable import powertoys

final class SystemCareTests: XCTestCase {
    func testCleanupCandidateMustBeAChildOfItsAllowedRoot() {
        let root = URL(fileURLWithPath: "/Users/example/Library/Caches", isDirectory: true)
        let safe = CleanupCandidate(
            url: root.appendingPathComponent("com.example.app"),
            allowedRoot: root,
            category: .caches,
            size: 1
        )
        let rootItself = CleanupCandidate(
            url: root,
            allowedRoot: root,
            category: .caches,
            size: 1
        )
        let siblingPrefix = CleanupCandidate(
            url: URL(fileURLWithPath: "/Users/example/Library/CachesBackup/item"),
            allowedRoot: root,
            category: .caches,
            size: 1
        )

        XCTAssertTrue(SystemCareManager.isSafe(safe))
        XCTAssertFalse(SystemCareManager.isSafe(rootItself))
        XCTAssertFalse(SystemCareManager.isSafe(siblingPrefix))
    }
}
