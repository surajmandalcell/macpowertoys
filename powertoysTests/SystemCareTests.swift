import XCTest
@testable import powertoys

@MainActor
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

    func testSavedCleanupScanRestoresUntilExplicitClear() throws {
        let suiteName = "SystemCareTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = URL(fileURLWithPath: "/Users/example/Library/Caches", isDirectory: true)
        let candidate = CleanupCandidate(
            url: root.appendingPathComponent("com.example.app"),
            allowedRoot: root,
            category: .caches,
            size: 512
        )
        let snapshot = CleanupScanSnapshot(
            scannedAt: Date(timeIntervalSince1970: 123),
            candidates: [candidate],
            selectedCandidateIDs: []
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: SystemCareManager.cleanupScanKey)

        let manager = SystemCareManager(defaults: defaults)

        XCTAssertTrue(manager.hasCleanupScan)
        XCTAssertEqual(manager.cleanupCandidates, [candidate])
        XCTAssertTrue(manager.selectedCandidateIDs.isEmpty)
        manager.setCandidate(candidate.id, selected: true)
        XCTAssertEqual(SystemCareManager(defaults: defaults).selectedCandidateIDs, [candidate.id])
        manager.clearCleanupScan()
        XCTAssertFalse(manager.hasCleanupScan)
        XCTAssertTrue(manager.cleanupCandidates.isEmpty)
        XCTAssertNil(defaults.data(forKey: SystemCareManager.cleanupScanKey))
    }
}
