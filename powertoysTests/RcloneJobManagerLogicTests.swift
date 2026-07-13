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
    }

    func testRemoteNameOnlyParsesRcloneFileSystems() {
        XCTAssertEqual(RcloneJobManager.remoteName(fromFs: "archive:folder"), "archive")
        XCTAssertEqual(RcloneJobManager.remoteName(fromFs: "archive:"), "archive")
        XCTAssertNil(RcloneJobManager.remoteName(fromFs: "/Users/me"))
        XCTAssertNil(RcloneJobManager.remoteName(fromFs: "relative/path"))
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
