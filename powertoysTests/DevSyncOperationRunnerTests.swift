import XCTest
@testable import powertoys

final class DevSyncOperationRunnerTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-operation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testScenario47SourceChangeAfterPlanningRequeuesWithoutBaselineCommit() async throws {
        let fixture = try await makeFixture()
        let relativePath = "source.swift"
        let stablePath = "stable.swift"
        let sourceURL = fixture.internalProject.appendingPathComponent(relativePath)
        let stableURL = fixture.internalProject.appendingPathComponent(stablePath)
        try Data("before".utf8).write(to: sourceURL)
        try Data("stable".utf8).write(to: stableURL)
        let plannedSignature = try DevSnapshotScanner.signature(of: sourceURL, includeHash: true)
        let stableSignature = try DevSnapshotScanner.signature(of: stableURL, includeHash: true)
        let plan = DevSyncPlan(
            pairID: fixture.pair.id,
            projectID: fixture.project.id,
            actions: [
                copyAction(fixture: fixture, relativePath: relativePath, signature: plannedSignature),
                copyAction(fixture: fixture, relativePath: stablePath, signature: stableSignature)
            ],
            manifestToExternal: [relativePath, stablePath]
        )
        let runner = DevOperationRunner(context: fixture.context)
        let changed = LockedFlag()

        let outcome = await runner.run(
            plan: plan,
            kind: .reconcile,
            baseline: nil,
            plannerOutput: plannerOutput(plan: plan)
        ) { _, _ in
            guard changed.take() else { return }
            try? Data("after-transfer".utf8).write(to: sourceURL)
        }

        XCTAssertEqual(outcome.committedPaths, [stablePath])
        XCTAssertEqual(outcome.requeuedPaths, [relativePath])
        let baseline = await fixture.stateStore.loadBaseline(projectID: fixture.project.id, pairID: fixture.pair.id)
        XCTAssertNil(baseline?.entries[relativePath])
        XCTAssertEqual(baseline?.entries[stablePath]?.signature.contentHash, stableSignature.contentHash)
    }

    func testScenario31DeletionStagesDeletesAndRecordsTombstone() async throws {
        let fixture = try await makeFixture()
        let relativePath = "old.swift"
        let externalURL = fixture.externalProject.appendingPathComponent(relativePath)
        try Data("old".utf8).write(to: externalURL)
        let signature = try DevSnapshotScanner.signature(of: externalURL, includeHash: true)
        let baseline = DevBaseline(
            projectID: fixture.project.id,
            entries: [relativePath: DevBaselineEntry(signature: signature, lastVerifiedAt: Date())]
        )
        try await fixture.stateStore.saveBaseline(baseline, pairID: fixture.pair.id)
        let preconditions = DevActionPreconditions(
            expectedSourceSignature: signature,
            expectedDestinationSignature: signature,
            expectDestinationAbsent: false,
            expectedVolumeIdentifier: fixture.pair.externalRoot.volumeIdentifier,
            expectedProjectFingerprint: nil,
            expectedParentKind: .directory,
            requiredFreeBytes: 0,
            policySchemaVersion: fixture.pair.configuration.policySchemaVersion
        )
        let plan = DevSyncPlan(
            pairID: fixture.pair.id,
            projectID: fixture.project.id,
            actions: [
                DevSyncAction(kind: .stageExistingVersion, destinationSide: .external, relativePath: relativePath, preconditions: preconditions, reason: "Retain"),
                DevSyncAction(kind: .deletePath, destinationSide: .external, relativePath: relativePath, preconditions: preconditions, reason: "Delete")
            ]
        )
        let tombstone = DevTombstone(
            projectID: fixture.project.id,
            relativePath: relativePath,
            deletedFromSide: .internal,
            baselineSignature: signature,
            createdAt: Date(),
            observedInternal: true,
            observedExternal: false,
            expiresAt: Date().addingTimeInterval(86_400)
        )
        var output = plannerOutput(plan: plan)
        output.newTombstones = [tombstone]

        let outcome = await DevOperationRunner(context: fixture.context).run(
            plan: plan,
            kind: .reconcile,
            baseline: baseline,
            plannerOutput: output,
            progress: { _, _ in }
        )

        XCTAssertEqual(outcome.committedPaths, [relativePath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: externalURL.path))
        XCTAssertNil(outcome.baseline?.entries[relativePath])
        let storedTombstones = await fixture.stateStore.loadTombstones(pairID: fixture.pair.id)
        XCTAssertEqual(storedTombstones, [tombstone])
        let records = await fixture.stateStore.loadSafetyRecords(pairID: fixture.pair.id)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: records[0].safetyPath))
    }

    func testScenario77Exit23CommitsNothingUnverified() async throws {
        var fixture = try await makeFixture()
        let relativePath = "partial.swift"
        let sourceURL = fixture.internalProject.appendingPathComponent(relativePath)
        try Data("partial".utf8).write(to: sourceURL)
        let signature = try DevSnapshotScanner.signature(of: sourceURL, includeHash: true)
        let executable = try makeScript("exit 23")
        fixture.context.rsyncExecutable = executable
        let plan = copyPlan(fixture: fixture, relativePath: relativePath, signature: signature)

        let outcome = await DevOperationRunner(context: fixture.context).run(
            plan: plan,
            kind: .reconcile,
            baseline: nil,
            plannerOutput: plannerOutput(plan: plan),
            progress: { _, _ in }
        )

        XCTAssertEqual(outcome.operation.state, .failed)
        XCTAssertEqual(outcome.committedPaths, [])
        XCTAssertEqual(outcome.requeuedPaths, [relativePath])
        let baseline = await awaitBaseline(fixture)
        XCTAssertNil(baseline)
    }

    func testScenario87CancelMidTransferKeepsDirtyState() async throws {
        var fixture = try await makeFixture()
        let relativePath = "slow.swift"
        let sourceURL = fixture.internalProject.appendingPathComponent(relativePath)
        try Data("slow".utf8).write(to: sourceURL)
        let signature = try DevSnapshotScanner.signature(of: sourceURL, includeHash: true)
        fixture.context.rsyncExecutable = try makeScript("sleep 10\nexit 0")
        let plan = copyPlan(fixture: fixture, relativePath: relativePath, signature: signature)
        let runner = DevOperationRunner(context: fixture.context)
        let task = Task {
            await runner.run(
                plan: plan,
                kind: .reconcile,
                baseline: nil,
                plannerOutput: plannerOutput(plan: plan),
                progress: { _, _ in }
            )
        }
        try await Task.sleep(for: .milliseconds(150))
        await runner.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome.operation.state, .cancelled)
        XCTAssertEqual(outcome.requeuedPaths, [relativePath])
        let baseline = await awaitBaseline(fixture)
        XCTAssertNil(baseline)
    }

    func testScenario79RecoveryReturnsCommitForVerifiedDestination() async throws {
        let fixture = try await makeFixture()
        let relativePath = "verified.swift"
        let sourceURL = fixture.internalProject.appendingPathComponent(relativePath)
        let destinationURL = fixture.externalProject.appendingPathComponent(relativePath)
        try Data("verified".utf8).write(to: sourceURL)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        let signature = try DevSnapshotScanner.signature(of: sourceURL, includeHash: true)
        let plan = copyPlan(fixture: fixture, relativePath: relativePath, signature: signature)
        let operation = DevOperation(
            pairID: fixture.pair.id,
            projectID: fixture.project.id,
            kind: .reconcile,
            state: .transferComplete,
            plan: plan
        )

        let decision = await DevRecovery.recover(operation: operation, context: fixture.context)

        XCTAssertEqual(decision, .commitVerified([relativePath]))
    }

    func testScenario80RecoveryRollsSafetyMoveBackWhenDestinationIsMissing() async throws {
        let fixture = try await makeFixture()
        let relativePath = "restore.swift"
        let destinationURL = fixture.externalProject.appendingPathComponent(relativePath)
        try Data("restore".utf8).write(to: destinationURL)
        let operationID = UUID()
        let record = try await fixture.context.safetyStore.retainBeforeDelete(
            side: .external,
            fileURL: destinationURL,
            relativePath: "app/\(relativePath)",
            projectID: fixture.project.id,
            operationID: operationID,
            retainDays: 30
        )
        let operation = DevOperation(
            id: operationID,
            pairID: fixture.pair.id,
            projectID: fixture.project.id,
            kind: .reconcile,
            state: .safetyPrepared,
            plan: DevSyncPlan(pairID: fixture.pair.id, projectID: fixture.project.id),
            safetyRecords: [record]
        )

        let decision = await DevRecovery.recover(operation: operation, context: fixture.context)

        XCTAssertEqual(decision, .rollbackSafety)
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("restore".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.safetyPath))
    }

    private func makeFixture() async throws -> Fixture {
        let internalRoot = temporaryRoot.appendingPathComponent("internal", isDirectory: true)
        let externalRoot = temporaryRoot.appendingPathComponent("external", isDirectory: true)
        let stateRoot = temporaryRoot.appendingPathComponent("state", isDirectory: true)
        let internalProject = internalRoot.appendingPathComponent("app", isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
        let volumeIdentifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: internalRoot))
        let pair = DevSyncPair(
            displayName: "Test",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: volumeIdentifier, volumeName: "Test", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalRoot.path, volumeIdentifier: volumeIdentifier, volumeName: "Test", fileSystemType: "apfs"),
            state: .idle
        )
        let project = DevProject(pairID: pair.id, relativePath: "app", residency: .mirrored, kind: .nonGit)
        let stateStore = DevSyncStateStore(rootURL: stateRoot)
        let safetyStore = DevSafetyStore(pair: pair, stateStore: stateStore)
        let linkManager = DevManagedLinkManager(pair: pair, stateStore: stateStore)
        let rsync = URL(fileURLWithPath: "/usr/bin/rsync")
        let rsyncCapabilities = try await DevRsyncProbe.probe(executable: rsync, selfTestDirectory: temporaryRoot)
        let volume = DevVolumeCapabilities(
            volumeIdentifier: volumeIdentifier,
            volumeName: "Test",
            mountPath: temporaryRoot.path,
            fileSystemType: "apfs",
            isReadOnly: false,
            isRemovable: false,
            isLocal: true,
            isEncrypted: true,
            availableCapacity: Int64.max / 4,
            totalCapacity: Int64.max / 2,
            isCaseSensitive: false,
            isCasePreserving: true,
            supportsSymbolicLinks: true,
            supportsHardLinks: true,
            supportsUnixPermissions: true,
            supportsExtendedAttributes: true,
            supportsCreationTimes: true,
            supportsPersistentIdentifiers: true,
            timestampResolutionNanoseconds: 1_000_000_000,
            maximumPathComponentLength: 255,
            probedAt: Date(),
            fidelity: .full,
            fidelityNotes: []
        )
        let capabilities = DevPairCapabilities(internalVolume: volume, externalVolume: volume, rsync: rsyncCapabilities, probedAt: Date())
        let context = DevOperationContext(
            pair: pair,
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            capabilities: capabilities,
            rsyncExecutable: rsync,
            stateStore: stateStore,
            safetyStore: safetyStore,
            linkManager: linkManager,
            ledger: DevSelfEventLedger(),
            policy: nil,
            gitDirectoryRelativePath: nil
        )
        return Fixture(
            pair: pair,
            project: project,
            internalProject: internalProject,
            externalProject: externalProject,
            stateStore: stateStore,
            context: context
        )
    }

    private func copyPlan(fixture: Fixture, relativePath: String, signature: DevFileSignature) -> DevSyncPlan {
        let action = copyAction(fixture: fixture, relativePath: relativePath, signature: signature)
        return DevSyncPlan(
            pairID: fixture.pair.id,
            projectID: fixture.project.id,
            actions: [action],
            manifestToExternal: [relativePath]
        )
    }

    private func copyAction(fixture: Fixture, relativePath: String, signature: DevFileSignature) -> DevSyncAction {
        DevSyncAction(
            kind: .copyPath,
            destinationSide: .external,
            relativePath: relativePath,
            bytes: Int64(signature.size ?? 0),
            preconditions: DevActionPreconditions(
                expectedSourceSignature: signature,
                expectedDestinationSignature: nil,
                expectDestinationAbsent: true,
                expectedVolumeIdentifier: fixture.pair.externalRoot.volumeIdentifier,
                expectedProjectFingerprint: nil,
                expectedParentKind: .directory,
                requiredFreeBytes: Int64(signature.size ?? 0),
                policySchemaVersion: fixture.pair.configuration.policySchemaVersion
            ),
            reason: "Copy test file"
        )
    }

    private func awaitBaseline(_ fixture: Fixture) async -> DevBaseline? {
        await fixture.stateStore.loadBaseline(projectID: fixture.project.id, pairID: fixture.pair.id)
    }

    private func makeScript(_ body: String) throws -> URL {
        let url = temporaryRoot.appendingPathComponent("rsync-\(UUID().uuidString)")
        try Data("#!/bin/zsh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func plannerOutput(plan: DevSyncPlan) -> DevPlannerOutput {
        DevPlannerOutput(
            plan: plan,
            newConflicts: [],
            newTombstones: [],
            driftPaths: [],
            externalOnlyPaths: [],
            needsHashes: [],
            projectState: .clean,
            warnings: []
        )
    }
}

private struct Fixture {
    var pair: DevSyncPair
    var project: DevProject
    var internalProject: URL
    var externalProject: URL
    var stateStore: DevSyncStateStore
    var context: DevOperationContext
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true

    func take() -> Bool {
        lock.withLock {
            defer { value = false }
            return value
        }
    }
}
