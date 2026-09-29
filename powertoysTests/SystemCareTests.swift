import XCTest
@testable import powertoys

@MainActor
final class SystemCareTests: XCTestCase {
    func testMetricBytesSeparateValueAndUnit() {
        let zero = SystemCareByteMetric(0)
        XCTAssertEqual(zero.value, "0")
        XCTAssertEqual(zero.unit, "KB")

        let kilobyte = SystemCareByteMetric(1_000)
        XCTAssertEqual(kilobyte.value, "1")
        XCTAssertEqual(kilobyte.unit, "KB")
    }

    func testApplicationMetadataUsesFinalUnavailableLabels() {
        let application = InstalledApplication(
            name: "Missing App",
            url: URL(fileURLWithPath: "/path/that/does/not/exist/Missing.app")
        )

        let metadata = SystemCarePresentationRows.application(application)

        XCTAssertEqual(metadata.id, application.id)
        XCTAssertEqual(metadata.size, "Unavailable")
        XCTAssertEqual(metadata.lastUsed, "Not available")
    }

    func testApplicationMetadataRecursivelyCountsAllocatedBundleFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemCareTests-\(UUID().uuidString).app", isDirectory: true)
        let nested = root.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: 8_192).write(to: nested.appendingPathComponent("payload.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let metadata = SystemCarePresentationRows.application(
            InstalledApplication(name: "Test App", url: root)
        )

        XCTAssertNotEqual(metadata.size, "Unavailable")
        XCTAssertNotEqual(metadata.size, "Zero KB")
    }

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
