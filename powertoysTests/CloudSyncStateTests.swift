import XCTest
@testable import powertoys

@MainActor
final class CloudSyncStateTests: XCTestCase {
    func testPriorityHasFiveOrderedStages() {
        XCTAssertEqual(TransferPriority.allCases.map(\.rawValue), [1, 2, 3, 4, 5])
        XCTAssertEqual(TransferPriority.normal.displayName, "Normal")
        XCTAssertEqual(TransferPriority.urgent.displayName, "Urgent")
    }

    func testRemoteNamesAcceptSafeRcloneCharactersOnly() {
        for name in ["archive", "Drive-2", "backup_home", "s3.eu"] {
            XCTAssertTrue(RcloneJobManager.isValidRemoteName(name), "Expected a valid remote name: \(name)")
        }
        for name in ["", "-archive", ".hidden", "two words", "remote:", "folder/name"] {
            XCTAssertFalse(RcloneJobManager.isValidRemoteName(name), "Expected an invalid remote name: \(name)")
        }
    }

    func testSnapshotPersistsIndividualFilePriorityAndExpandedState() {
        let job = makeJob(kind: .file, createdAt: Date(timeIntervalSince1970: 10))
        job.priority = .high
        job.isExpanded = true

        let restored = TransferJob(snapshot: job.snapshot)

        XCTAssertEqual(restored.priority, .high)
        XCTAssertTrue(restored.isExpanded)
    }

    func testLegacySnapshotDefaultsToNormalAndCollapsed() throws {
        let job = makeJob(createdAt: Date(timeIntervalSince1970: 10))
        let data = try JSONEncoder().encode(job.snapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "priority")
        json.removeValue(forKey: "isExpanded")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let snapshot = try JSONDecoder().decode(TransferJobSnapshot.self, from: legacyData)
        let restored = TransferJob(snapshot: snapshot)

        XCTAssertEqual(restored.priority, .normal)
        XCTAssertFalse(restored.isExpanded)
    }

    func testQueuedIndividualFilesSortByPriorityThenCreationTime() {
        let oldNormal = makeJob(kind: .file, createdAt: Date(timeIntervalSince1970: 1))
        let newerUrgent = makeJob(kind: .file, createdAt: Date(timeIntervalSince1970: 3))
        newerUrgent.priority = .urgent
        let olderUrgent = makeJob(kind: .file, createdAt: Date(timeIntervalSince1970: 2))
        olderUrgent.priority = .urgent
        let directory = makeJob(createdAt: Date(timeIntervalSince1970: 4))
        directory.priority = .urgent

        let ordered = RcloneJobManager.orderedReadyJobs([directory, newerUrgent, oldNormal, olderUrgent])

        XCTAssertEqual(ordered.map(\.id), [olderUrgent.id, newerUrgent.id, oldNormal.id, directory.id])
        XCTAssertNil(directory.snapshot.priority)
        XCTAssertEqual(TransferJob(snapshot: directory.snapshot).priority, .normal)
    }

    func testManagerRejectsPriorityForDirectoryJobs() {
        let manager = RcloneJobManager()
        let directory = makeJob(createdAt: Date(timeIntervalSince1970: 1))
        let file = makeJob(kind: .file, createdAt: Date(timeIntervalSince1970: 2))

        manager.setPriority(.urgent, for: directory)
        manager.setPriority(.high, for: file)

        XCTAssertEqual(directory.priority, .normal)
        XCTAssertEqual(file.priority, .high)
    }

    func testInterruptedSnapshotPreservesCompletedProgressForResume() {
        let job = makeJob(createdAt: Date(timeIntervalSince1970: 1))
        job.state = .running
        job.stats.bytes = 400
        job.stats.transfers = 3
        job.stats.totalBytes = 1_000
        job.stats.totalTransfers = 10

        let restored = TransferJob(snapshot: job.snapshot)

        XCTAssertEqual(restored.state, .paused)
        XCTAssertTrue(restored.autoResumeOnLaunch)
        XCTAssertEqual(restored.resumeBaselineBytes, 400)
        XCTAssertEqual(restored.resumeBaselineFiles, 3)
        XCTAssertEqual(restored.displayBytes, 400)
        XCTAssertEqual(restored.displayFiles, 3)
    }

    func testInterruptedSnapshotDoesNotCountAnUncommittedActiveFile() {
        let job = makeJob(createdAt: Date(timeIntervalSince1970: 1))
        job.state = .running
        job.stats.bytes = 400
        job.stats.totalBytes = 1_000
        job.stats.transferring = [
            FileProgress(
                name: "large.mov",
                size: 500,
                bytes: 250,
                percentage: 50,
                speed: 100,
                speedAvg: 100,
                eta: 2.5
            )
        ]

        let restored = TransferJob(snapshot: job.snapshot)

        XCTAssertEqual(restored.resumeBaselineBytes, 150)
        XCTAssertEqual(restored.displayBytes, 150)
    }

    func testFileStatusRequiresMatchingDestinationFile() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let source = entry(path: "folder/file.mov", size: 100, modTime: timestamp)
        let matching = entry(path: "folder/file.mov", size: 100, modTime: timestamp)
        let partial = entry(path: "folder/file.mov", size: 60, modTime: timestamp)
        let stale = entry(path: "folder/file.mov", size: 100, modTime: timestamp.addingTimeInterval(-10))

        XCTAssertEqual(TransferFileStatus.resolve(source: source, destination: matching), .uploaded)
        XCTAssertEqual(TransferFileStatus.resolve(source: source, destination: partial), .pending)
        XCTAssertEqual(TransferFileStatus.resolve(source: source, destination: stale), .pending)
        XCTAssertEqual(TransferFileStatus.resolve(source: source, destination: nil), .pending)
    }

    func testIgnoreMatcherCoversFileAndDirectoryPatterns() {
        XCTAssertTrue(IgnoreMatcher.matches(path: "build/cache.tmp", name: "cache.tmp", isDir: false, pattern: "*.tmp"))
        XCTAssertTrue(IgnoreMatcher.matches(path: "app/node_modules/pkg.js", name: "pkg.js", isDir: false, pattern: "node_modules/**"))
        XCTAssertTrue(IgnoreMatcher.matches(path: "draft.partial", name: "draft.partial", isDir: false, pattern: "draft*"))
        XCTAssertFalse(IgnoreMatcher.matches(path: "Sources/main.swift", name: "main.swift", isDir: false, pattern: "*.tmp"))
    }

    private func makeJob(kind: TransferKind = .directory, createdAt: Date) -> TransferJob {
        TransferJob(
            operation: .copy,
            kind: kind,
            sourceFs: "/source",
            destinationFs: "remote:backup",
            sourceDisplay: "source",
            destinationDisplay: "backup",
            excludePatterns: [],
            maxRetries: 3,
            createdAt: createdAt
        )
    }

    private func entry(path: String, size: Int64, modTime: Date? = nil) -> RemoteEntry {
        RemoteEntry(
            path: path,
            name: (path as NSString).lastPathComponent,
            size: size,
            modTime: modTime,
            isDir: false,
            mimeType: "application/octet-stream"
        )
    }
}
