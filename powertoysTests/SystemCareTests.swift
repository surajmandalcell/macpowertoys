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
        XCTAssertNotNil(metadata.sizeError)
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
        XCTAssertNil(metadata.sizeError)

        let link = root.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let linkedMetadata = SystemCarePresentationRows.application(
            InstalledApplication(name: "Linked App", url: link)
        )
        XCTAssertEqual(linkedMetadata.size, "Unavailable")
        XCTAssertEqual(linkedMetadata.sizeError, "Bundle is a symbolic link. Size scanning does not follow links.")
    }

    func testCleanupRejectsUntrustedRootsLinksAndChangedIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let candidate = try fixture.candidate("marker")
        XCTAssertTrue(SystemCareManager.isSafe(candidate, homeDirectory: fixture.home))

        let rootItself = CleanupCandidate(url: fixture.root, allowedRoot: fixture.root, category: .caches, size: 1)
        XCTAssertFalse(SystemCareManager.isSafe(rootItself, homeDirectory: fixture.home))
        let outside = CleanupCandidate(url: fixture.home.appendingPathComponent("marker"),
                                       allowedRoot: fixture.home, category: .caches, size: 1,
                                       fileIdentity: candidate.fileIdentity, rootIdentity: candidate.rootIdentity)
        XCTAssertFalse(SystemCareManager.isSafe(outside, homeDirectory: fixture.home))
        let wrongCategory = CleanupCandidate(url: candidate.url, allowedRoot: fixture.root, category: .logs,
                                            size: 1, fileIdentity: candidate.fileIdentity, rootIdentity: candidate.rootIdentity)
        XCTAssertFalse(SystemCareManager.isSafe(wrongCategory, homeDirectory: fixture.home))

        try FileManager.default.moveItem(at: candidate.url, to: fixture.root.appendingPathComponent("original"))
        try Data("replacement".utf8).write(to: candidate.url)
        XCTAssertFalse(SystemCareManager.isSafe(candidate, homeDirectory: fixture.home))
        try FileManager.default.removeItem(at: candidate.url)
        try FileManager.default.createSymbolicLink(at: candidate.url, withDestinationURL: fixture.root.appendingPathComponent("original"))
        XCTAssertFalse(SystemCareManager.isSafe(candidate, homeDirectory: fixture.home))

        let library = fixture.home.appendingPathComponent("Library")
        let movedLibrary = fixture.home.appendingPathComponent("MovedLibrary")
        let fresh = try fixture.candidate("fresh")
        try FileManager.default.moveItem(at: library, to: movedLibrary)
        try FileManager.default.createSymbolicLink(at: library, withDestinationURL: movedLibrary)
        XCTAssertFalse(SystemCareManager.isSafe(fresh, homeDirectory: fixture.home))
    }

    func testSavedCleanupScanRestoresUntilExplicitClear() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let candidate = try fixture.candidate("marker")
        let unverified = CleanupCandidate(url: fixture.root.appendingPathComponent("legacy"),
                                          allowedRoot: fixture.root, category: .caches, size: 512)
        let snapshot = CleanupScanSnapshot(scannedAt: Date(timeIntervalSince1970: 123),
                                           candidates: [candidate, unverified], selectedCandidateIDs: [])
        fixture.defaults.set(try JSONEncoder().encode(snapshot), forKey: SystemCareManager.cleanupScanKey)
        let manager = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home)
        try await waitUntilIdle(manager)

        XCTAssertTrue(manager.hasCleanupScan)
        XCTAssertEqual(manager.cleanupCandidates, [candidate])
        XCTAssertTrue(manager.selectedCandidateIDs.isEmpty)
        manager.setCandidate(candidate.id, selected: true)
        let restored = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home)
        try await waitUntilIdle(restored)
        XCTAssertEqual(restored.selectedCandidateIDs, [candidate.id])
        manager.clearCleanupScan()
        XCTAssertFalse(manager.hasCleanupScan)
        XCTAssertTrue(manager.cleanupCandidates.isEmpty)
        XCTAssertNil(fixture.defaults.data(forKey: SystemCareManager.cleanupScanKey))
    }

    func testTrashFreezesSelectionAndRetainsPartialFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let moved = try fixture.candidate("moved")
        let failed = try fixture.candidate("failed")
        let untouched = try fixture.candidate("untouched")
        let snapshot = CleanupScanSnapshot(scannedAt: Date(), candidates: [moved, failed, untouched],
                                           selectedCandidateIDs: [moved.id, failed.id])
        fixture.defaults.set(try JSONEncoder().encode(snapshot), forKey: SystemCareManager.cleanupScanKey)
        let started = expectation(description: "Trash worker started")
        let release = DispatchSemaphore(value: 0)
        let manager = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home) { url in
            if url == moved.url {
                started.fulfill()
                guard release.wait(timeout: .now() + 3) == .success else { throw CancellationError() }
                try FileManager.default.removeItem(at: url)
            } else {
                throw NSError(domain: "SystemCareTests", code: 1)
            }
        }
        try await waitUntilIdle(manager)
        manager.moveSelectedToTrash()
        await fulfillment(of: [started], timeout: 2)
        manager.setCandidate(moved.id, selected: false)
        manager.setCandidate(untouched.id, selected: true)
        manager.setCandidates([moved.id, failed.id], selected: false)
        manager.clearCleanupScan()
        manager.moveSelectedToTrash()
        manager.cancel()
        manager.refresh()
        manager.scanCleanup(categories: [.caches])
        manager.analyze(fixture.home)
        manager.loadHistory()
        manager.installOrUpdateMole()
        XCTAssertTrue(manager.isWorking)
        XCTAssertFalse(manager.canCancel)
        XCTAssertEqual(manager.selectedCandidateIDs, [moved.id, failed.id])
        release.signal()
        try await waitUntilIdle(manager)

        XCTAssertEqual(manager.cleanupCandidates.map(\.id), [failed.id, untouched.id])
        XCTAssertEqual(manager.selectedCandidateIDs, [failed.id])
        XCTAssertEqual(manager.lastTrashResult?.movedCount, 1)
        XCTAssertEqual(manager.lastTrashResult?.movedBytes, moved.size)
        XCTAssertEqual(manager.lastTrashResult?.failures.map(\.id), [failed.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: untouched.url.path))
        let restored = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home)
        try await waitUntilIdle(restored)
        XCTAssertEqual(restored.cleanupCandidates.map(\.id), [failed.id, untouched.id])
    }

    func testCancellationWaitsForDetachedWorkerExit() async throws {
        let started = expectation(description: "Worker started")
        let canceled = expectation(description: "Worker received cancellation")
        let finished = expectation(description: "Outer task finished")
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            defer { finished.fulfill() }
            do {
                _ = try await SystemCareManager.runWorker {
                    started.fulfill()
                    while !Task.isCancelled { usleep(1_000) }
                    canceled.fulfill()
                    _ = release.wait(timeout: .now() + 3)
                    try Task.checkCancellation()
                    return true
                }
                XCTFail("Canceled worker returned a result")
            } catch is CancellationError {
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [canceled], timeout: 2)
        finished.isInverted = true
        await fulfillment(of: [finished], timeout: 0.05)
        finished.isInverted = false
        release.signal()
        await task.value
        await fulfillment(of: [finished], timeout: 2)
    }

    private func waitUntilIdle(_ manager: SystemCareManager) async throws {
        let deadline = Date().addingTimeInterval(4)
        while manager.isWorking, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(manager.isWorking)
    }

    private struct Fixture {
        let home: URL
        let suite = "SystemCareTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var root: URL { SystemCareManager.cleanupRoot(for: .caches, homeDirectory: home) }

        init() throws {
            home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("SystemCareTests-\(UUID().uuidString)", isDirectory: true)
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func candidate(_ name: String) throws -> CleanupCandidate {
            let url = root.appendingPathComponent(name)
            try Data(repeating: 0xA5, count: 8_192).write(to: url)
            return CleanupCandidate(url: url, allowedRoot: root, category: .caches, size: 8_192,
                                    fileIdentity: try SystemCareManager.fileIdentity(at: url),
                                    rootIdentity: try SystemCareManager.fileIdentity(at: root))
        }

        func remove() {
            try? FileManager.default.removeItem(at: home)
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
