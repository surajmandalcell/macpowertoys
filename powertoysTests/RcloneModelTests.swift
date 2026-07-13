import XCTest
@testable import powertoys

@MainActor
final class RcloneModelTests: XCTestCase {
    func testOperationMetadataAndDestructiveClassification() {
        XCTAssertEqual(RcloneOperation.allCases.map(\.displayName), ["Copy", "Sync", "Move"])
        XCTAssertEqual(RcloneOperation.allCases.map(\.rcEndpoint), ["sync/copy", "sync/sync", "sync/move"])
        XCTAssertFalse(RcloneOperation.copy.isDestructive)
        XCTAssertTrue(RcloneOperation.sync.isDestructive)
        XCTAssertTrue(RcloneOperation.move.isDestructive)
    }

    func testTransferStateClassificationsAreExhaustive() {
        let active: [TransferState] = [.queued, .running, .retrying, .paused]
        let terminal: [TransferState] = [.completed, .failed, .cancelled]

        for state in active {
            XCTAssertTrue(state.isActive, "Expected active: \(state)")
            XCTAssertFalse(state.isTerminal, "Expected non-terminal: \(state)")
            XCTAssertFalse(state.displayName.isEmpty)
            XCTAssertFalse(state.icon.isEmpty)
        }
        for state in terminal {
            XCTAssertFalse(state.isActive, "Expected inactive: \(state)")
            XCTAssertTrue(state.isTerminal, "Expected terminal: \(state)")
            XCTAssertFalse(state.displayName.isEmpty)
            XCTAssertFalse(state.icon.isEmpty)
        }
    }

    func testJobFiltersMatchTheirDocumentedStates() {
        let states: [TransferState] = [.queued, .running, .retrying, .paused, .completed, .failed, .cancelled]
        XCTAssertEqual(states.filter(JobFilter.all.matches), states)
        XCTAssertEqual(states.filter(JobFilter.active.matches), [.queued, .running, .retrying, .paused])
        XCTAssertEqual(states.filter(JobFilter.completed.matches), [.completed])
        XCTAssertEqual(states.filter(JobFilter.failed.matches), [.failed, .cancelled])
    }

    func testRemoteMetadataCoversKnownAndFallbackProviders() {
        XCTAssertEqual(RcloneRemote(name: "docs", type: "drive").pathPrefix, "docs:")
        XCTAssertEqual(RcloneRemote(name: "server", type: "sftp").icon, "server.rack")
        XCTAssertEqual(RcloneRemote(name: "vault", type: "crypt").icon, "lock.shield")
        XCTAssertEqual(RcloneRemote(name: "custom", type: "future-provider").icon, "cloud")
        XCTAssertEqual(RcloneRemote(name: "empty", type: "").typeLabel, "remote")
    }

    func testTransferOrderMapsToRcloneValues() {
        XCTAssertNil(TransferOrder.default.orderByValue)
        XCTAssertEqual(TransferOrder.largestFirst.orderByValue, "size,descending")
        XCTAssertEqual(TransferOrder.smallestFirst.orderByValue, "size,ascending")
    }

    func testFileAndAggregateFractionsClampAndHandleEmptyTotals() {
        XCTAssertEqual(fileProgress(size: 0, bytes: 10).fraction, 0)
        XCTAssertEqual(fileProgress(size: 100, bytes: 25).fraction, 0.25)
        XCTAssertEqual(fileProgress(size: 100, bytes: 150).fraction, 1)

        var stats = TransferStats.empty
        XCTAssertEqual(stats.fraction, 0)
        stats.totalBytes = 100
        stats.bytes = 150
        XCTAssertEqual(stats.fraction, 1)
    }

    func testCompletedBytesExcludesInFlightWorkAndNeverBecomesNegative() {
        var stats = TransferStats.empty
        stats.bytes = 500
        stats.transferring = [fileProgress(size: 1_000, bytes: 200), fileProgress(size: 500, bytes: 100)]
        XCTAssertEqual(stats.completedBytes, 200)

        stats.bytes = 50
        XCTAssertEqual(stats.completedBytes, 0)
    }

    func testRetryPolicyUsesExponentialBackoffAndClampsNegativeAttempt() {
        let policy = RetryPolicy(maxRetries: 4, backoffSeconds: 3, backoffMultiplier: 2)
        XCTAssertEqual(policy.delay(forAttempt: -1), 3)
        XCTAssertEqual(policy.delay(forAttempt: 0), 3)
        XCTAssertEqual(policy.delay(forAttempt: 1), 6)
        XCTAssertEqual(policy.delay(forAttempt: 3), 24)
    }

    func testRemoteEntryIconsCoverSupportedMimeFamilies() {
        XCTAssertEqual(entry(name: "folder", isDir: true).icon, "folder.fill")
        XCTAssertEqual(entry(name: "a.png", mime: "image/png").icon, "photo")
        XCTAssertEqual(entry(name: "a.mov", mime: "video/quicktime").icon, "film")
        XCTAssertEqual(entry(name: "a.mp3", mime: "audio/mpeg").icon, "waveform")
        XCTAssertEqual(entry(name: "a.txt", mime: "text/plain").icon, "doc.text")
        XCTAssertEqual(entry(name: "a.pdf", mime: "application/pdf").icon, "doc.richtext")
        XCTAssertEqual(entry(name: "a.zip", mime: "application/zip").icon, "archivebox")
        XCTAssertEqual(entry(name: "a.bin", mime: "application/octet-stream").icon, "doc")
    }

    func testFileStatusAcceptsTimestampToleranceAndDirectories() {
        let base = Date(timeIntervalSince1970: 100)
        let source = entry(name: "file", size: 100, date: base)
        XCTAssertEqual(TransferFileStatus.resolve(source: source, destination: entry(name: "file", size: 100, date: base.addingTimeInterval(2))), .uploaded)
        XCTAssertEqual(TransferFileStatus.resolve(source: source, destination: entry(name: "file", size: 100, date: base.addingTimeInterval(2.01))), .pending)

        let sourceDirectory = entry(name: "folder", size: 0, isDir: true)
        let destinationDirectory = entry(name: "folder", size: 999, isDir: true)
        XCTAssertEqual(TransferFileStatus.resolve(source: sourceDirectory, destination: destinationDirectory), .uploaded)
        XCTAssertEqual(TransferFileStatus.resolve(source: sourceDirectory, destination: entry(name: "folder")), .pending)
    }

    func testTransferJobCapabilitiesFollowState() {
        let job = makeJob()
        job.state = .queued
        XCTAssertTrue(job.canPause)
        XCTAssertTrue(job.canCancel)
        XCTAssertFalse(job.canRetry)

        job.state = .paused
        XCTAssertTrue(job.canResume)
        XCTAssertTrue(job.canCancel)

        job.state = .failed
        XCTAssertTrue(job.canRetry)
        XCTAssertFalse(job.canPause)
        XCTAssertFalse(job.canCancel)

        job.state = .completed
        XCTAssertFalse(job.canRetry)
        XCTAssertFalse(job.canCancel)
    }

    func testTransferJobProgressCombinesResumeBaselineAndLiveStats() {
        let job = makeJob()
        job.resumeBaselineBytes = 400
        job.resumeBaselineFiles = 3
        job.expectedBytes = 1_000
        job.expectedFiles = 10
        job.stats.bytes = 250
        job.stats.transfers = 2
        job.stats.totalBytes = 600
        job.stats.totalTransfers = 5

        XCTAssertEqual(job.effectiveTotalBytes, 1_000)
        XCTAssertEqual(job.effectiveTotalFiles, 10)
        XCTAssertEqual(job.displayBytes, 650)
        XCTAssertEqual(job.displayFiles, 5)
        XCTAssertEqual(job.progressFraction, 0.65)

        job.stats.bytes = 1_500
        XCTAssertEqual(job.displayBytes, 1_000)
        XCTAssertEqual(job.progressFraction, 1)
    }

    func testRetryBytesDoNotInflateLogicalProgressOrTotal() {
        let job = makeJob()
        job.attemptPlannedBytes = 700
        job.attemptPlannedFiles = 7
        job.expectedBytes = 700
        job.expectedFiles = 7
        job.stats.bytes = 900
        job.stats.totalBytes = 950
        job.stats.transfers = 6
        job.stats.totalTransfers = 9

        XCTAssertEqual(job.displayBytes, 650)
        XCTAssertEqual(job.effectiveTotalBytes, 700)
        XCTAssertEqual(job.displayFiles, 6)
        XCTAssertEqual(job.effectiveTotalFiles, 7)
        XCTAssertEqual(job.networkBytes, 900)
    }

    func testReplannedRemainingFilesRestoreLogicalFileProgress() {
        let job = makeJob()
        job.resumeBaselineFiles = 1_979
        job.attemptPlannedFiles = 838
        job.expectedFiles = 2_817
        job.stats.totalTransfers = 3

        XCTAssertEqual(job.displayFiles, 2_814)

        job.stats.transfers = 3
        XCTAssertEqual(job.displayFiles, 2_817)

        job.stats = .empty
        XCTAssertEqual(job.displayFiles, 1_979)

        job.resumeBaselineBytes = 653
        job.attemptPlannedBytes = 62
        job.expectedBytes = 715
        XCTAssertEqual(job.displayBytes, 653)
    }

    func testCommittingReplannedFilesPreservesSkippedProgress() {
        let job = makeJob()
        job.resumeBaselineFiles = 1_979
        job.attemptPlannedFiles = 838
        job.expectedFiles = 2_817
        job.stats.totalTransfers = 3

        job.commitAttemptProgress()

        XCTAssertEqual(job.resumeBaselineFiles, 2_814)
        XCTAssertEqual(job.displayFiles, 2_814)
    }

    func testCommittingAttemptExcludesInFlightBytes() {
        let job = makeJob()
        job.attemptPlannedBytes = 1_000
        job.attemptPlannedFiles = 10
        job.expectedBytes = 1_000
        job.expectedFiles = 10
        job.stats.bytes = 500
        job.stats.totalBytes = 1_000
        job.stats.transfers = 3
        job.stats.transferring = [fileProgress(size: 500, bytes: 200)]

        job.commitAttemptProgress()

        XCTAssertEqual(job.resumeBaselineBytes, 300)
        XCTAssertEqual(job.resumeBaselineFiles, 3)
        XCTAssertEqual(job.networkBytes, 500)
        XCTAssertNil(job.attemptPlannedBytes)
        XCTAssertEqual(job.stats, .empty)
    }

    func testTransferJobSnapshotRoundTripsAllUserControlledOptions() {
        let job = makeJob()
        job.state = .paused
        job.transferOrder = .largestFirst
        job.priority = .urgent
        job.isExpanded = true
        job.updateOlderOnly = true
        job.ignoreExisting = true
        job.compareChecksums = true
        job.transfersOverride = 7
        job.checkersOverride = 11
        job.autoResumeOnLaunch = true
        job.resumeBaselineBytes = 123
        job.resumeBaselineFiles = 4
        job.networkBaselineBytes = 456
        job.continuousSync = true

        let restored = TransferJob(snapshot: job.snapshot)

        XCTAssertEqual(restored.state, .paused)
        XCTAssertEqual(restored.transferOrder, .largestFirst)
        XCTAssertEqual(restored.priority, .urgent)
        XCTAssertTrue(restored.isExpanded)
        XCTAssertTrue(restored.updateOlderOnly)
        XCTAssertTrue(restored.ignoreExisting)
        XCTAssertTrue(restored.compareChecksums)
        XCTAssertEqual(restored.transfersOverride, 7)
        XCTAssertEqual(restored.checkersOverride, 11)
        XCTAssertTrue(restored.autoResumeOnLaunch)
        XCTAssertEqual(restored.resumeBaselineBytes, 123)
        XCTAssertEqual(restored.resumeBaselineFiles, 4)
        XCTAssertEqual(restored.networkBaselineBytes, 456)
        XCTAssertTrue(restored.continuousSync)
    }

    func testTerminalSnapshotRestoresWithoutAutoResume() {
        let job = makeJob()
        job.state = .completed
        job.stats.bytes = 100
        job.stats.transfers = 2

        let restored = TransferJob(snapshot: job.snapshot)

        XCTAssertEqual(restored.state, .completed)
        XCTAssertFalse(restored.autoResumeOnLaunch)
        XCTAssertEqual(restored.stats.bytes, 100)
        XCTAssertEqual(restored.stats.transfers, 2)
    }

    func testVolumeMountPointOnlyAcceptsMountedVolumePaths() {
        XCTAssertEqual(VolumeIdentity.mountPoint(forPath: "/Volumes/Backup/photos/2026"), "/Volumes/Backup")
        XCTAssertEqual(VolumeIdentity.mountPoint(forPath: "/Volumes/Backup"), "/Volumes/Backup")
        XCTAssertNil(VolumeIdentity.mountPoint(forPath: "/Volumes"))
        XCTAssertNil(VolumeIdentity.mountPoint(forPath: "/Users/me/file"))
        XCTAssertNil(VolumeIdentity.mountPoint(forPath: "remote:path"))
    }

    func testIgnoreMatcherHandlesExactSuffixPrefixAndNestedDirectoryRules() {
        XCTAssertTrue(IgnoreMatcher.matches(path: "folder/exact.txt", name: "exact.txt", isDir: false, patterns: ["unrelated", "folder/exact.txt"]))
        XCTAssertTrue(IgnoreMatcher.matches(path: "cache.tmp", name: "cache.tmp", isDir: false, pattern: "*.tmp"))
        XCTAssertTrue(IgnoreMatcher.matches(path: "draft-one", name: "draft-one", isDir: false, pattern: "draft*"))
        XCTAssertTrue(IgnoreMatcher.matches(path: "app/node_modules", name: "node_modules", isDir: true, pattern: "node_modules/**"))
        XCTAssertTrue(IgnoreMatcher.matches(path: "app/node_modules/pkg/index.js", name: "index.js", isDir: false, pattern: "node_modules/**"))
        XCTAssertFalse(IgnoreMatcher.matches(path: "app/modules/index.js", name: "index.js", isDir: false, pattern: "node_modules/**"))
    }

    func testRcloneSettingsBuildsRetryPolicy() {
        let settings = RcloneSettings(
            binaryPath: "/opt/rclone", ignorePatterns: [], transfers: 4, checkers: 8,
            bandwidthLimit: "10M", maxRetries: 6, retryBackoffSeconds: 2.5,
            lowLevelRetries: 10, maxConcurrentJobs: 2, defaultOperation: .copy
        )
        XCTAssertEqual(settings.retryPolicy, RetryPolicy(maxRetries: 6, backoffSeconds: 2.5, backoffMultiplier: 2))
    }

    func testRcloneFormatCoversUnitsSpeedEtaAndDuration() {
        XCTAssertEqual(RcloneFormat.bytes(0), "0 B")
        XCTAssertEqual(RcloneFormat.bytes(1_024), "1.0 KB")
        XCTAssertEqual(RcloneFormat.bytes(1_048_576), "1.0 MB")
        XCTAssertEqual(RcloneFormat.speed(0), "—")
        XCTAssertEqual(RcloneFormat.speed(1_024), "1.0 KB/s")
        XCTAssertEqual(RcloneFormat.eta(nil), "—")
        XCTAssertEqual(RcloneFormat.eta(.infinity), "—")
        XCTAssertEqual(RcloneFormat.eta(9), "9s")
        XCTAssertEqual(RcloneFormat.eta(65), "1m 5s")
        XCTAssertEqual(RcloneFormat.eta(3_661), "1h 1m")
        XCTAssertEqual(RcloneFormat.duration(0), "—")
        XCTAssertEqual(RcloneFormat.duration(65), "1m 5s")
    }

    private func makeJob() -> TransferJob {
        TransferJob(
            operation: .copy,
            sourceFs: "/source",
            destinationFs: "remote:backup",
            sourceDisplay: "source",
            destinationDisplay: "backup",
            excludePatterns: [],
            maxRetries: 3
        )
    }

    private func fileProgress(size: Int64, bytes: Int64) -> FileProgress {
        FileProgress(name: UUID().uuidString, size: size, bytes: bytes, percentage: 0, speed: 0, speedAvg: 0, eta: nil)
    }

    private func entry(
        name: String,
        size: Int64 = 0,
        date: Date? = nil,
        isDir: Bool = false,
        mime: String = "application/octet-stream"
    ) -> RemoteEntry {
        RemoteEntry(path: name, name: name, size: size, modTime: date, isDir: isDir, mimeType: mime)
    }
}
