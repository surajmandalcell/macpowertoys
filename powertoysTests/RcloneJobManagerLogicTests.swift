import XCTest
@testable import powertoys

@MainActor
final class RcloneJobManagerLogicTests: XCTestCase {
    func testPatternParserTrimsBlankLinesButPreservesRules() {
        XCTAssertEqual(
            RcloneDefaults.parsePatterns("  *.tmp  \n\nnode_modules/**\r\n .git/** "),
            ["*.tmp", "node_modules/**", ".git/**"]
        )
    }

    func testRemoteConcurrencyKeysRemainNamespaced() {
        XCTAssertEqual(RcloneDefaults.remoteTransfersKey("archive"), "rclone.remote.archive.transfers")
        XCTAssertEqual(RcloneDefaults.remoteCheckersKey("archive"), "rclone.remote.archive.checkers")
    }

    func testJobUsesVolumeOnlyForLocalDescendants() {
        XCTAssertTrue(RcloneJobManager.jobUsesVolume(makeJob(source: "/Volumes/Drive/photos"), "/Volumes/Drive"))
        XCTAssertTrue(RcloneJobManager.jobUsesVolume(makeJob(destination: "/Volumes/Drive"), "/Volumes/Drive"))
        XCTAssertFalse(RcloneJobManager.jobUsesVolume(makeJob(source: "/Volumes/DriveTwo/photos"), "/Volumes/Drive"))
        XCTAssertFalse(RcloneJobManager.jobUsesVolume(makeJob(source: "remote:Drive/photos"), "/Volumes/Drive"))
    }

    func testReadyQueueExcludesFutureRetriesAndNonReadyStates() {
        let now = Date(timeIntervalSince1970: 1_000)
        let queued = makeJob(createdAt: now.addingTimeInterval(-10))
        let readyRetry = makeJob(createdAt: now.addingTimeInterval(-9))
        readyRetry.state = .retrying
        readyRetry.nextRetryAt = now
        let futureRetry = makeJob(createdAt: now.addingTimeInterval(-8))
        futureRetry.state = .retrying
        futureRetry.nextRetryAt = now.addingTimeInterval(1)
        let paused = makeJob(createdAt: now.addingTimeInterval(-7))
        paused.state = .paused

        XCTAssertEqual(RcloneJobManager.orderedReadyJobs([futureRetry, paused, readyRetry, queued], at: now).map(\.id), [queued.id, readyRetry.id])
    }

    func testFileEndpointComponentsSplitLocalAndRemoteFiles() {
        let local = RcloneJobManager.fileEndpointComponents("/Users/me/photo.jpg")
        XCTAssertEqual(local.fs, "/Users/me")
        XCTAssertEqual(local.remote, "photo.jpg")

        let remote = RcloneJobManager.fileEndpointComponents("archive:folder/photo.jpg")
        XCTAssertEqual(remote.fs, "archive:")
        XCTAssertEqual(remote.remote, "folder/photo.jpg")

        XCTAssertEqual(RcloneJobManager.remoteFolderPath(fromFs: "archive:folder", transferKind: .directory), "folder")
        XCTAssertEqual(RcloneJobManager.remoteFolderPath(fromFs: "archive:folder/photo.jpg", transferKind: .file), "folder")
        XCTAssertNil(RcloneJobManager.remoteFolderPath(fromFs: "/Users/me/photo.jpg", transferKind: .file))
    }

    func testRemoteNameOnlyParsesRcloneFileSystems() {
        XCTAssertEqual(RcloneJobManager.remoteName(fromFs: "archive:folder"), "archive")
        XCTAssertEqual(RcloneJobManager.remoteName(fromFs: "archive:"), "archive")
        XCTAssertNil(RcloneJobManager.remoteName(fromFs: "/Users/me"))
        XCTAssertNil(RcloneJobManager.remoteName(fromFs: "relative/path"))
    }

    func testContinuousSyncRequiresALocalSourceFolder() {
        XCTAssertTrue(RcloneJobManager.supportsContinuousSync(makeJob(source: "/Volumes/NVMe")))
        XCTAssertFalse(RcloneJobManager.supportsContinuousSync(makeJob(source: "drive:folder")))

        let file = TransferJob(
            operation: .copy,
            kind: .file,
            sourceFs: "/source/file.txt",
            destinationFs: "remote:file.txt",
            sourceDisplay: "file.txt",
            destinationDisplay: "file.txt",
            excludePatterns: [],
            maxRetries: 3
        )
        XCTAssertFalse(RcloneJobManager.supportsContinuousSync(file))
    }

    func testDerivedJobCollectionsAndAggregateSpeed() {
        let manager = RcloneJobManager()
        let running = makeJob()
        running.state = .running
        running.stats.speed = 100
        let second = makeJob()
        second.state = .running
        second.stats.speed = 50
        let completed = makeJob()
        completed.state = .completed
        completed.stats.speed = 999
        manager.jobs = [running, second, completed]

        XCTAssertEqual(manager.activeJobs.map(\.id), [running.id, second.id])
        XCTAssertEqual(manager.aggregateSpeed, 150)
        XCTAssertEqual(manager.count(for: .completed), 1)
        manager.filter = .active
        XCTAssertEqual(manager.filteredJobs.map(\.id), [running.id, second.id])
    }

    func testRuntimeNeedFollowsWindowTransferContinuousAndBackgroundOwners() {
        let completed = makeJob()
        completed.state = .completed

        XCTAssertFalse(RcloneJobManager.needsRuntime(
            windowVisible: false,
            jobs: [completed],
            backgroundEnabled: false
        ))
        XCTAssertTrue(RcloneJobManager.needsRuntime(
            windowVisible: true,
            jobs: [completed],
            backgroundEnabled: false
        ))

        completed.state = .running
        XCTAssertTrue(RcloneJobManager.needsRuntime(
            windowVisible: false,
            jobs: [completed],
            backgroundEnabled: false
        ))

        completed.state = .completed
        completed.continuousSync = true
        XCTAssertTrue(RcloneJobManager.needsRuntime(
            windowVisible: false,
            jobs: [completed],
            backgroundEnabled: false
        ))
        XCTAssertTrue(RcloneJobManager.needsRuntime(
            windowVisible: false,
            jobs: [],
            backgroundEnabled: true
        ))
    }

    private func makeJob(
        source: String = "/source",
        destination: String = "remote:backup",
        createdAt: Date = Date()
    ) -> TransferJob {
        TransferJob(
            operation: .copy,
            sourceFs: source,
            destinationFs: destination,
            sourceDisplay: "source",
            destinationDisplay: "backup",
            excludePatterns: [],
            maxRetries: 3,
            createdAt: createdAt
        )
    }
}
