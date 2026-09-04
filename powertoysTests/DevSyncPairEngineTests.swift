import XCTest
@testable import powertoys

final class DevSyncPairEngineTests: XCTestCase {
    private var temporaryRoot: URL!
    private var engines: [DevSyncPairEngine] = []

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-pair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for engine in engines { await engine.stop() }
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testScenario22EditorSavesFiftyTimesProducesOneBatch() async throws {
        let fixture = try await makeFixture()
        await fixture.engine.start()
        try Data("changed content".utf8).write(to: fixture.internalProject.appendingPathComponent("source.swift"))

        for _ in 0..<50 {
            await fixture.engine.noteEvents(side: .internal, relativePaths: ["app/source.swift"])
        }

        try await waitUntil {
            let operations = await fixture.store.loadOperations(pairID: fixture.pair.id, limit: 20)
            return operations.count == 1 && operations[0].state.isTerminal
        }
        XCTAssertEqual(
            try Data(contentsOf: fixture.externalProject.appendingPathComponent("source.swift")),
            Data("changed content".utf8)
        )
    }

    func testScenario24IgnoredStormCopiesNothing() async throws {
        let fixture = try await makeFixture()
        await fixture.engine.start()
        let ignored = fixture.internalProject.appendingPathComponent("node_modules/cache.bin")
        try FileManager.default.createDirectory(at: ignored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: ignored)

        for _ in 0..<1_100 {
            await fixture.engine.noteEvents(side: .internal, relativePaths: ["app/node_modules/cache.bin"])
        }
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.externalProject.appendingPathComponent("node_modules/cache.bin").path))
        let operations = await fixture.store.loadOperations(pairID: fixture.pair.id, limit: 20)
        XCTAssertEqual(operations.count, 0)
    }

    func testScenario26GitLockDefersBatch() async throws {
        let fixture = try await makeFixture(gitRepository: true)
        await fixture.engine.start()
        let lock = fixture.internalProject.appendingPathComponent(".git/index.lock")
        try Data().write(to: lock)
        let source = fixture.internalProject.appendingPathComponent("source.swift")
        try Data("locked change".utf8).write(to: source)

        await fixture.engine.noteEvents(side: .internal, relativePaths: ["app/source.swift"])
        try await waitUntil { await fixture.engine.projects().first?.state == .waitingForGit }

        XCTAssertEqual(try Data(contentsOf: fixture.externalProject.appendingPathComponent("source.swift")), Data("source".utf8))
        let operations = await fixture.store.loadOperations(pairID: fixture.pair.id, limit: 20)
        XCTAssertEqual(operations.count, 0)
    }

    func testScenario29OneWayDriftNeverOverwritesAutomatically() async throws {
        let fixture = try await makeFixture()
        await fixture.engine.start()
        let destination = fixture.externalProject.appendingPathComponent("source.swift")
        try Data("external drift".utf8).write(to: destination)

        await fixture.engine.syncProject(fixture.project.id)
        try await waitUntil { await fixture.engine.projects().first?.state == .destinationDrift }

        XCTAssertEqual(try Data(contentsOf: destination), Data("external drift".utf8))
        let operations = await fixture.store.loadOperations(pairID: fixture.pair.id, limit: 20)
        XCTAssertEqual(operations.count, 0)
    }

    func testVerifyNowFindsSilentSameSizeSameTimeDifference() async throws {
        let fixture = try await makeFixture()
        await fixture.engine.start()
        let internalFile = fixture.internalProject.appendingPathComponent("source.swift")
        let externalFile = fixture.externalProject.appendingPathComponent("source.swift")
        let modificationDate = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: internalFile.path)[.modificationDate] as? Date
        )
        try Data("change".utf8).write(to: externalFile)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: externalFile.path)

        await fixture.engine.verifyNow()

        let projectState = await fixture.engine.projects().first?.state
        XCTAssertEqual(projectState, .destinationDrift)
    }

    func testScenario30AllDriftResolutionsConverge() async throws {
        let overwrite = try await makeFixture(name: "overwrite")
        await overwrite.engine.start()
        let overwriteDestination = overwrite.externalProject.appendingPathComponent("source.swift")
        try Data("drift".utf8).write(to: overwriteDestination)
        try await overwrite.engine.resolveDrift(projectID: overwrite.project.id, relativePath: "source.swift", resolution: .overwriteExternal)
        XCTAssertEqual(try Data(contentsOf: overwriteDestination), Data("source".utf8))

        let adopt = try await makeFixture(name: "adopt")
        await adopt.engine.start()
        let adoptSource = adopt.externalProject.appendingPathComponent("source.swift")
        try Data("adopted external".utf8).write(to: adoptSource)
        try await adopt.engine.resolveDrift(projectID: adopt.project.id, relativePath: "source.swift", resolution: .adoptExternal)
        XCTAssertEqual(try Data(contentsOf: adopt.internalProject.appendingPathComponent("source.swift")), Data("adopted external".utf8))

        let restore = try await makeFixture(name: "restore")
        await restore.engine.start()
        let restoreDestination = restore.externalProject.appendingPathComponent("source.swift")
        try Data("drift again".utf8).write(to: restoreDestination)
        try await restore.engine.resolveDrift(projectID: restore.project.id, relativePath: "source.swift", resolution: .restoreToExternal)
        XCTAssertEqual(try Data(contentsOf: restoreDestination), Data("source".utf8))
    }

    func testScenario53UnmountDuringTransferRecoversAfterMount() async throws {
        let executable = try makeRsyncWrapper(delay: 1)
        let fixture = try await makeFixture(executable: executable)
        await fixture.engine.start()
        try Data("change before disconnect".utf8).write(to: fixture.internalProject.appendingPathComponent("source.swift"))
        await fixture.engine.syncProject(fixture.project.id)
        try await waitUntil {
            await fixture.store.loadOpenOperations(pairID: fixture.pair.id).contains { $0.state == .transferRunning }
        }

        await fixture.engine.volumeWillUnmount(fixture.externalRoot)
        await fixture.engine.volumeDidUnmount(fixture.externalRoot)

        let offlineStatus = await fixture.engine.status()
        XCTAssertEqual(offlineStatus.state, .volumeOffline)
        let baseline = await fixture.store.loadBaseline(projectID: fixture.project.id, pairID: fixture.pair.id)
        XCTAssertEqual(baseline?.entries["source.swift"]?.signature.size, UInt64(Data("source".utf8).count))
        await fixture.engine.volumeDidMount(fixture.externalRoot)
        try await waitUntil(timeout: 5) {
            (try? Data(contentsOf: fixture.externalProject.appendingPathComponent("source.swift"))) == Data("change before disconnect".utf8)
        }
        let recoveredStatus = await fixture.engine.status()
        let recoveredOperations = await fixture.store.loadOperations(pairID: fixture.pair.id, limit: 20)
        let recoveredProjects = await fixture.engine.projects()
        let recoveredDirty = await fixture.store.loadDirty(pairID: fixture.pair.id)
        let detail = recoveredOperations.map { "\($0.state.rawValue):\($0.errorSummary ?? "none")" }.joined(separator: ", ")
            + "; projects=\(recoveredProjects.map { "\($0.residency.rawValue):\($0.state.rawValue)" })"
            + "; dirty=\(recoveredDirty.map { $0.reason.rawValue })"
        XCTAssertEqual(recoveredStatus.state, .idle, detail)
        XCTAssertEqual(try? Data(contentsOf: fixture.externalProject.appendingPathComponent("source.swift")), Data("change before disconnect".utf8), detail)
    }

    func testScenario54WrongVolumeIdentityBlocksPair() async throws {
        let fixture = try await makeFixture(externalVolumeIdentifier: "wrong-volume")

        await fixture.engine.start()

        let status = await fixture.engine.status()
        XCTAssertEqual(status.state, .blocked)
        XCTAssertEqual(status.phaseDetail, "Wrong drive")
    }

    func testScenario57FreeSpacePreflightBlocksPair() async throws {
        let fixture = try await makeFixture(availableCapacity: 1)
        await fixture.engine.start()
        try Data(repeating: 2, count: 4_096).write(to: fixture.internalProject.appendingPathComponent("source.swift"))

        await fixture.engine.syncProject(fixture.project.id)
        try await waitUntil { await fixture.engine.status().state == .blocked }

        let status = await fixture.engine.status()
        XCTAssertTrue(status.phaseDetail?.contains("Not enough space") == true)
        XCTAssertEqual(try Data(contentsOf: fixture.externalProject.appendingPathComponent("source.swift")), Data("source".utf8))
    }

    func testScenario65RetentionRunsAfterSuccess() async throws {
        let fixture = try await makeFixture()
        await fixture.engine.start()
        let retired = fixture.externalRoot.appendingPathComponent("retired.txt")
        try Data("retired".utf8).write(to: retired)
        let safety = DevSafetyStore(pair: fixture.pair, stateStore: fixture.store)
        let expired = try await safety.retainBeforeDelete(side: .external, fileURL: retired, relativePath: "retired.txt", projectID: nil, operationID: UUID(), retainDays: 0)
        try Data("retention trigger".utf8).write(to: fixture.internalProject.appendingPathComponent("source.swift"))

        await fixture.engine.syncProject(fixture.project.id)
        try await waitUntil {
            let records = await fixture.store.loadSafetyRecords(pairID: fixture.pair.id)
            return !records.contains { $0.id == expired.id }
        }

        let records = await fixture.store.loadSafetyRecords(pairID: fixture.pair.id)
        XCTAssertFalse(records.contains { $0.id == expired.id })
    }

    func testScenario84VolumeGateSerializesSameDriveAndParallelizesDistinctDrives() async {
        let same = ConcurrencyMeter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 { group.addTask { await self.measureGate("same", meter: same) } }
        }
        let sameMaximum = await same.maximum()
        XCTAssertEqual(sameMaximum, 1)

        let distinct = ConcurrencyMeter()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.measureGate("drive-a", meter: distinct) }
            group.addTask { await self.measureGate("drive-b", meter: distinct) }
        }
        let distinctMaximum = await distinct.maximum()
        XCTAssertEqual(distinctMaximum, 2)
    }

    func testScenario85LowPowerModePausesAutomaticWork() async throws {
        let fixture = try await makeFixture(
            lowPowerModeEnabled: { true },
            configure: { $0.power.pauseOnLowPowerMode = true }
        )
        await fixture.engine.start()
        try Data("automatic change".utf8).write(to: fixture.internalProject.appendingPathComponent("source.swift"))

        await fixture.engine.noteEvents(side: .internal, relativePaths: ["app/source.swift"])
        try await waitUntil { await fixture.engine.status().state == .paused }

        let operations = await fixture.store.loadOperations(pairID: fixture.pair.id, limit: 20)
        XCTAssertTrue(operations.isEmpty)
    }

    func testIdleSleepAssertionIsPairedAroundMutation() async throws {
        let meter = ActivityMeter()
        let fixture = try await makeFixture(withMutationActivity: DevMutationActivity { operation in
            await meter.begin()
            let outcome = await operation()
            await meter.end()
            return outcome
        })
        await fixture.engine.start()
        try Data("mutation".utf8).write(to: fixture.internalProject.appendingPathComponent("source.swift"))

        await fixture.engine.syncProject(fixture.project.id)
        try await waitUntil {
            await fixture.store.loadOperations(pairID: fixture.pair.id, limit: 20).first?.state == .committed
        }

        let counts = await meter.counts()
        XCTAssertEqual(counts.begun, 1)
        XCTAssertEqual(counts.ended, 1)
        XCTAssertEqual(counts.active, 0)
    }

    func testScenario86SyncNowDuringRunMergesIntoNextGeneration() async throws {
        let fixture = try await makeFixture(executable: makeRsyncWrapper(delay: 0.4))
        await fixture.engine.start()
        let source = fixture.internalProject.appendingPathComponent("source.swift")
        try Data("first running change".utf8).write(to: source)
        await fixture.engine.syncProject(fixture.project.id)
        try await waitUntil {
            await fixture.store.loadOpenOperations(pairID: fixture.pair.id).contains { $0.state == .transferRunning }
        }

        await fixture.engine.syncNow()
        try Data("second generation change".utf8).write(to: source)

        try await waitUntil(timeout: 5) {
            let copied = (try? Data(contentsOf: fixture.externalProject.appendingPathComponent("source.swift"))) == Data("second generation change".utf8)
            let operations = await fixture.store.loadOperations(pairID: fixture.pair.id, limit: 20)
            return copied && operations.count >= 2
        }
    }

    func testScenario88RcloneTransferJobIsUntouched() async throws {
        let manager = RcloneJobManager()
        let job = TransferJob(operation: .copy, sourceFs: temporaryRoot.path, destinationFs: "remote:", sourceDisplay: "Local", destinationDisplay: "Remote", excludePatterns: [], maxRetries: 1)
        manager.jobs = [job]
        let fixture = try await makeFixture()

        await fixture.engine.start()
        await fixture.engine.syncNow()

        XCTAssertEqual(manager.jobs.map(\.id), [job.id])
        XCTAssertEqual(manager.jobs[0].state, .queued)
    }

    private func makeFixture(
        name: String = UUID().uuidString,
        executable: URL = URL(fileURLWithPath: "/usr/bin/rsync"),
        gitRepository: Bool = false,
        externalVolumeIdentifier: String? = nil,
        availableCapacity: Int64? = nil,
        lowPowerModeEnabled: @escaping @Sendable () -> Bool = { false },
        withMutationActivity: DevMutationActivity = .live,
        configure: (inout DevSyncConfiguration) -> Void = { _ in }
    ) async throws -> PairFixture {
        let root = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        let internalRoot = root.appendingPathComponent("internal", isDirectory: true)
        let externalRoot = root.appendingPathComponent("external", isDirectory: true)
        let internalProject = internalRoot.appendingPathComponent("app", isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
        try Data("// marker".utf8).write(to: internalProject.appendingPathComponent("Package.swift"))
        try Data("source".utf8).write(to: internalProject.appendingPathComponent("source.swift"))
        try FileManager.default.copyItem(at: internalProject.appendingPathComponent("Package.swift"), to: externalProject.appendingPathComponent("Package.swift"))
        try FileManager.default.copyItem(at: internalProject.appendingPathComponent("source.swift"), to: externalProject.appendingPathComponent("source.swift"))
        if gitRepository {
            try runGit(["init", "-q"], at: internalProject)
            try runGit(["init", "-q"], at: externalProject)
        }
        let identifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: internalRoot))
        var configuration = DevSyncConfiguration.default
        configuration.timing = .init(fseventsLatencySeconds: 0.01, quietPeriodSeconds: 0.05, minimumProjectIntervalSeconds: 0, continuousCheckpointSeconds: 0.1, largeFileQuietSeconds: 0, fullReconcileSeconds: 86_400)
        configuration.safety.minimumFreeSpaceReserveBytes = 0
        configure(&configuration)
        let pair = DevSyncPair(
            displayName: name,
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: identifier, volumeName: "Test", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalRoot.path, volumeIdentifier: externalVolumeIdentifier ?? identifier, volumeName: "Test", fileSystemType: "apfs"),
            configuration: configuration,
            state: .idle,
            lastFullReconcileAt: Date(),
            lastSuccessAt: Date(),
            hasCompletedFirstRun: true
        )
        let kind: DevProjectKind = gitRepository ? .gitRepository : .nonGit
        let project = DevProject(pairID: pair.id, relativePath: "app", residency: .mirrored, kind: kind, explicitlyIncluded: true)
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("state", isDirectory: true))
        try await store.savePairs([pair])
        try await store.saveProjects([project], pairID: pair.id)
        let packageSignature = try DevSnapshotScanner.signature(of: internalProject.appendingPathComponent("Package.swift"), includeHash: true)
        let sourceSignature = try DevSnapshotScanner.signature(of: internalProject.appendingPathComponent("source.swift"), includeHash: true)
        let baseline = DevBaseline(projectID: project.id, timestampToleranceNanoseconds: 1_000_000_000, entries: [
            "Package.swift": DevBaselineEntry(signature: packageSignature, lastVerifiedAt: Date()),
            "source.swift": DevBaselineEntry(signature: sourceSignature, lastVerifiedAt: Date())
        ])
        try await store.saveBaseline(baseline, pairID: pair.id)
        let rsyncCapabilities = try await DevRsyncProbe.probe(executable: URL(fileURLWithPath: "/usr/bin/rsync"), selfTestDirectory: root)
        var internalVolume = DevVolumeProbe.probe(rootURL: internalRoot, probeDirectory: internalRoot)
        var externalVolume = DevVolumeProbe.probe(rootURL: externalRoot, probeDirectory: externalRoot)
        if let availableCapacity {
            internalVolume.availableCapacity = availableCapacity
            externalVolume.availableCapacity = availableCapacity
        }
        let capabilities = DevPairCapabilities(internalVolume: internalVolume, externalVolume: externalVolume, rsync: rsyncCapabilities, probedAt: Date())
        try await store.saveCapabilities(capabilities, pairID: pair.id)
        let engine = DevSyncPairEngine(
            pair: pair,
            stateStore: store,
            rsyncExecutable: executable,
            emit: { _ in },
            lowPowerModeEnabled: lowPowerModeEnabled,
            withMutationActivity: withMutationActivity
        )
        engines.append(engine)
        return PairFixture(pair: pair, project: project, internalRoot: internalRoot, externalRoot: externalRoot, internalProject: internalProject, externalProject: externalProject, store: store, engine: engine)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for condition")
    }

    private func makeRsyncWrapper(delay: Double) throws -> URL {
        let url = temporaryRoot.appendingPathComponent("rsync-\(UUID().uuidString)")
        try Data("#!/bin/zsh\nsleep \(delay)\nexec /usr/bin/rsync \"$@\"\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = try XCTUnwrap(DevGit.executable)
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func measureGate(_ key: String, meter: ConcurrencyMeter) async {
        await DevVolumeMutationGate.shared.acquire(key)
        await meter.enter()
        try? await Task.sleep(for: .milliseconds(100))
        await meter.leave()
        await DevVolumeMutationGate.shared.release(key)
    }
}

private struct PairFixture {
    var pair: DevSyncPair
    var project: DevProject
    var internalRoot: URL
    var externalRoot: URL
    var internalProject: URL
    var externalProject: URL
    var store: DevSyncStateStore
    var engine: DevSyncPairEngine
}

private actor ConcurrencyMeter {
    private var current = 0
    private var maximumValue = 0

    func enter() {
        current += 1
        maximumValue = max(maximumValue, current)
    }

    func leave() {
        current -= 1
    }

    func maximum() -> Int { maximumValue }
}

private actor ActivityMeter {
    private var begun = 0
    private var ended = 0
    private var active = 0

    func begin() {
        begun += 1
        active += 1
    }

    func end() {
        ended += 1
        active -= 1
    }

    func counts() -> (begun: Int, ended: Int, active: Int) {
        (begun, ended, active)
    }
}
