import Darwin
import CoreServices
import XCTest
@testable import powertoys

final class DevSyncFailureMatrixTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-failure-matrix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testDeepVerificationFindsSilentContentAndMetadataDifferences() async throws {
        let fixture = try makeVerificationFixture()
        let internalFile = fixture.internalProject.appendingPathComponent("silent.txt")
        let externalFile = fixture.externalProject.appendingPathComponent("silent.txt")
        try Data("internal".utf8).write(to: internalFile)
        try Data("external".utf8).write(to: externalFile)
        let sharedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: sharedDate, .posixPermissions: 0o700], ofItemAtPath: internalFile.path)
        try FileManager.default.setAttributes([.modificationDate: sharedDate, .posixPermissions: 0o600], ofItemAtPath: externalFile.path)

        let report = try await fixture.verifier.verify(pairID: fixture.pair.id, projectID: fixture.project.id)

        XCTAssertTrue(report.complete)
        XCTAssertEqual(report.verifiedFileCount, 1)
        XCTAssertTrue(report.differences.contains { $0.relativePath == "silent.txt" && $0.kind == .content })
        XCTAssertTrue(report.differences.contains { $0.relativePath == "silent.txt" && $0.kind == .permissions })
    }

    func testDeepVerificationCancellationStopsWithinFile() async throws {
        let fixture = try makeVerificationFixture()
        let internalFile = fixture.internalProject.appendingPathComponent("large.bin")
        let externalFile = fixture.externalProject.appendingPathComponent("large.bin")
        for file in [internalFile, externalFile] {
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: 512 * 1_024 * 1_024)
            try handle.close()
        }
        let task = Task {
            try await fixture.verifier.verify(pairID: fixture.pair.id, projectID: fixture.project.id)
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected deep verification to cancel")
        } catch is CancellationError {
        }
    }

    func testScenarios74To80FailureAfterEveryOperationStepLeavesRecoverableJournal() async throws {
        for step in DevOperationRunnerStep.allCases {
            let fixture = try await makeOperationFixture(step: step)
            try Data("recoverable".utf8).write(to: fixture.internalProject.appendingPathComponent("file.txt"))
            let output = try copyOutput(fixture)
            let runner = DevOperationRunner(context: fixture.context) { completed in
                if completed == step { throw InjectedOperationFailure.step(step) }
            }
            let outcome = await runner.run(
                plan: output.plan,
                kind: .reconcile,
                baseline: nil,
                plannerOutput: output,
                progress: { _, _ in }
            )
            let stored = await fixture.store.loadOperation(id: outcome.operation.id, pairID: fixture.pair.id)
            let operation = try XCTUnwrap(stored, "step \(step.rawValue)")
            let decision = await DevRecovery.recover(operation: operation, context: fixture.context)

            XCTAssertNotNil(outcome.error, "step \(step.rawValue)")
            XCTAssertEqual(operation.state, step.rawValue < 4 ? .failed : .recoveryRequired, "step \(step.rawValue)")
            if step.rawValue < DevOperationRunnerStep.readTransferResult.rawValue {
                XCTAssertEqual(decision, .replan, "step \(step.rawValue)")
            } else {
                XCTAssertEqual(decision, .commitVerified(["file.txt"]), "step \(step.rawValue)")
            }
        }
    }

    func testFailureSignalsForceFullReconciliationAndUnavailableStoreFailsClosed() async throws {
        let rootPath = temporaryRoot.path
        let dropped = DevEventBatch.classify(
            events: [
                DevFileEvent(
                    path: rootPath,
                    flags: UInt32(kFSEventStreamEventFlagKernelDropped),
                    eventID: 7
                )
            ],
            rootPath: rootPath,
            isReplay: false
        )
        XCTAssertTrue(dropped.mustRescanRoot)

        let fixture = try await makeOperationFixture(step: .preflight)
        try Data("store failure".utf8).write(to: fixture.internalProject.appendingPathComponent("file.txt"))
        let output = try copyOutput(fixture)
        try FileManager.default.createDirectory(at: fixture.store.rootURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: fixture.store.rootURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.store.rootURL.path) }
        let outcome = await DevOperationRunner(context: fixture.context).run(
            plan: output.plan,
            kind: .reconcile,
            baseline: nil,
            plannerOutput: output,
            progress: { _, _ in }
        )

        XCTAssertEqual(outcome.operation.state, .failed)
        XCTAssertNotNil(outcome.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.externalProject.appendingPathComponent("file.txt").path))
    }

    private func makeVerificationFixture() throws -> VerificationFixture {
        let internalRoot = temporaryRoot.appendingPathComponent("internal", isDirectory: true)
        let externalRoot = temporaryRoot.appendingPathComponent("external", isDirectory: true)
        let internalProject = internalRoot.appendingPathComponent("app", isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
        let identifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: internalRoot))
        let pair = DevSyncPair(
            displayName: "Verification",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: identifier, volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalRoot.path, volumeIdentifier: identifier, volumeName: "External", fileSystemType: "apfs")
        )
        let project = DevProject(pairID: pair.id, relativePath: "app", residency: .mirrored, kind: .nonGit, explicitlyIncluded: true)
        let capabilities = DevPairCapabilities(
            internalVolume: DevVolumeProbe.probe(rootURL: internalRoot, probeDirectory: internalRoot),
            externalVolume: DevVolumeProbe.probe(rootURL: externalRoot, probeDirectory: externalRoot),
            probedAt: Date()
        )
        let verifier = DevDeepVerifier(pair: pair, projects: [project], internalRoot: internalRoot, externalRoot: externalRoot, capabilities: capabilities)
        return VerificationFixture(pair: pair, project: project, internalProject: internalProject, externalProject: externalProject, verifier: verifier)
    }

    private func makeOperationFixture(step: DevOperationRunnerStep) async throws -> FailureOperationFixture {
        let suffix = String(step.rawValue)
        let internalRoot = temporaryRoot.appendingPathComponent("operation-internal-\(suffix)", isDirectory: true)
        let externalRoot = temporaryRoot.appendingPathComponent("operation-external-\(suffix)", isDirectory: true)
        let internalProject = internalRoot.appendingPathComponent("app", isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
        let volumeIdentifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: internalRoot))
        var configuration = DevSyncConfiguration.default
        configuration.safety.minimumFreeSpaceReserveBytes = 0
        let pair = DevSyncPair(
            displayName: "Failure \(suffix)",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: volumeIdentifier, volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalRoot.path, volumeIdentifier: volumeIdentifier, volumeName: "External", fileSystemType: "apfs"),
            configuration: configuration
        )
        let project = DevProject(pairID: pair.id, relativePath: "app", residency: .mirrored, kind: .nonGit)
        let store = DevSyncStateStore(rootURL: temporaryRoot.appendingPathComponent("operation-state-\(suffix)", isDirectory: true))
        let capabilities = DevPairCapabilities(
            internalVolume: DevVolumeProbe.probe(rootURL: internalRoot, probeDirectory: internalRoot),
            externalVolume: DevVolumeProbe.probe(rootURL: externalRoot, probeDirectory: externalRoot),
            rsync: try await DevRsyncProbe.probe(executable: URL(fileURLWithPath: "/usr/bin/rsync"), selfTestDirectory: temporaryRoot),
            probedAt: Date()
        )
        let context = DevOperationContext(
            pair: pair,
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            capabilities: capabilities,
            rsyncExecutable: URL(fileURLWithPath: "/usr/bin/rsync"),
            stateStore: store,
            safetyStore: DevSafetyStore(pair: pair, stateStore: store),
            linkManager: DevManagedLinkManager(pair: pair, stateStore: store),
            ledger: DevSelfEventLedger(),
            policy: nil,
            gitDirectoryRelativePath: nil
        )
        return FailureOperationFixture(
            pair: pair,
            project: project,
            internalProject: internalProject,
            externalProject: externalProject,
            store: store,
            context: context
        )
    }

    private func copyOutput(_ fixture: FailureOperationFixture) throws -> DevPlannerOutput {
        let signature = try DevSnapshotScanner.signature(
            of: fixture.internalProject.appendingPathComponent("file.txt"),
            includeHash: true
        )
        let action = DevSyncAction(
            kind: .copyPath,
            destinationSide: .external,
            relativePath: "file.txt",
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
            reason: "Failure injection"
        )
        let plan = DevSyncPlan(
            pairID: fixture.pair.id,
            projectID: fixture.project.id,
            actions: [action],
            manifestToExternal: ["file.txt"]
        )
        return DevPlannerOutput(
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

private struct VerificationFixture {
    var pair: DevSyncPair
    var project: DevProject
    var internalProject: URL
    var externalProject: URL
    var verifier: DevDeepVerifier
}

private struct FailureOperationFixture {
    var pair: DevSyncPair
    var project: DevProject
    var internalProject: URL
    var externalProject: URL
    var store: DevSyncStateStore
    var context: DevOperationContext
}

private nonisolated enum InjectedOperationFailure: Error, Sendable {
    case step(DevOperationRunnerStep)
}
