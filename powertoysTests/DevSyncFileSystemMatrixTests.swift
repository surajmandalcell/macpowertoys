import Foundation
import XCTest
@testable import powertoys

final class DevSyncFileSystemMatrixTests: XCTestCase {
    private static let caseInsensitiveImage = "/private/tmp/claude-501/-Users-surajmandal-dev-personal-powertoys/a1b9e7ea-13e7-4d6b-970c-4b5256bfe703/scratchpad/images/apfs-ci.sparseimage"
    private static let caseSensitiveImage = "/private/tmp/claude-501/-Users-surajmandal-dev-personal-powertoys/a1b9e7ea-13e7-4d6b-970c-4b5256bfe703/scratchpad/images/apfs-cs.sparseimage"
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-filesystem-matrix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testAPFSImagesRunFirstPassWithExpectedFidelity() async throws {
        for (image, caseSensitive) in [(Self.caseInsensitiveImage, false), (Self.caseSensitiveImage, true)] {
            let mount = try await attach(image)
            let volume = try XCTUnwrap(DevVolumeProbe.probe(rootURL: mount, probeDirectory: mount))
            XCTAssertEqual(volume.isCaseSensitive, caseSensitive)
            XCTAssertEqual(volume.fidelity, .full)

            let fixture = try await makeFixture(externalRoot: mount)
            addTeardownBlock {
                try? FileManager.default.removeItem(at: fixture.externalProject)
                try? FileManager.default.removeItem(
                    at: mount.appendingPathComponent(DevSyncDefaults.systemDirectoryName).appendingPathComponent(fixture.pair.id.uuidString)
                )
            }
            try Data("volume transfer".utf8).write(to: fixture.internalProject.appendingPathComponent("file.txt"))
            let output = await plan(fixture)
            XCTAssertEqual(output.plan.manifestToExternal, ["file.txt"])
            let outcome = await DevOperationRunner(context: fixture.context).run(
                plan: output.plan,
                kind: .firstRun,
                baseline: nil,
                plannerOutput: output,
                progress: { _, _ in }
            )

            XCTAssertNil(outcome.error)
            XCTAssertEqual(outcome.operation.state, .committed)
            XCTAssertEqual(
                try Data(contentsOf: fixture.externalProject.appendingPathComponent("file.txt")),
                Data("volume transfer".utf8)
            )
        }
    }

    func testScenario35CaseCollisionBlocksCaseInsensitiveDestinationButNotCaseSensitiveDestination() async throws {
        let caseSensitiveMount = try await attach(Self.caseSensitiveImage)
        let caseInsensitiveMount = try await attach(Self.caseInsensitiveImage)
        let relativePath = "collision-\(UUID().uuidString)"
        let source = caseSensitiveMount.appendingPathComponent(relativePath, isDirectory: true)
        let insensitiveDestination = caseInsensitiveMount.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: insensitiveDestination, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: insensitiveDestination)
        }
        try Data("upper".utf8).write(to: source.appendingPathComponent("Foo.swift"))
        try Data("lower".utf8).write(to: source.appendingPathComponent("foo.swift"))
        let policy = nonGitPolicy()
        let sourceSnapshot = await DevSnapshotScanner.scan(
            projectURL: source,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: true,
            hashPaths: []
        )
        let destinationSnapshot = await DevSnapshotScanner.scan(
            projectURL: insensitiveDestination,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        let blocked = plannerOutput(
            source: source,
            destination: insensitiveDestination,
            sourceSnapshot: sourceSnapshot,
            destinationSnapshot: destinationSnapshot,
            externalCaseSensitive: false
        )
        let permitted = plannerOutput(
            source: source,
            destination: caseSensitiveMount,
            sourceSnapshot: sourceSnapshot,
            destinationSnapshot: destinationSnapshot,
            externalCaseSensitive: true
        )

        XCTAssertEqual(blocked.projectState, .blockedByFileSystem)
        XCTAssertEqual(blocked.newConflicts.map(\.type), [.caseCollision])
        XCTAssertTrue(blocked.plan.manifestToExternal.isEmpty)
        XCTAssertNotEqual(permitted.projectState, .blockedByFileSystem)
        XCTAssertEqual(Set(permitted.plan.manifestToExternal), ["Foo.swift", "foo.swift"])
    }

    func testScenarios56And57ReadOnlyAndReservePreflightBlockBeforeMutation() async throws {
        let readOnlyMount = try await attach(Self.caseInsensitiveImage, readOnly: true)
        let readOnlyFixture = try await makeFixture(
            externalRoot: readOnlyMount,
            relativePath: "",
            createExternalProject: false
        )
        try Data("blocked".utf8).write(to: readOnlyFixture.internalProject.appendingPathComponent("file.txt"))
        let readOnlyPlan = try copyOutput(readOnlyFixture)
        let readOnlyOutcome = await DevOperationRunner(context: readOnlyFixture.context).run(
            plan: readOnlyPlan.plan,
            kind: .firstRun,
            baseline: nil,
            plannerOutput: readOnlyPlan,
            progress: { _, _ in }
        )
        XCTAssertEqual(readOnlyFixture.capabilities.externalVolume?.isReadOnly, true)
        XCTAssertEqual(readOnlyOutcome.operation.state, .failed)
        XCTAssertTrue(readOnlyOutcome.error?.contains("read-only") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: readOnlyFixture.externalProject.appendingPathComponent("file.txt").path))

        let writableMount = try await attach(Self.caseSensitiveImage)
        var lowSpaceFixture = try await makeFixture(externalRoot: writableMount)
        try Data("blocked".utf8).write(to: lowSpaceFixture.internalProject.appendingPathComponent("file.txt"))
        let available = lowSpaceFixture.capabilities.externalVolume?.availableCapacity ?? 0
        lowSpaceFixture.pair.configuration.safety.minimumFreeSpaceReserveBytes = max(0, available) + 1
        lowSpaceFixture.context.pair = lowSpaceFixture.pair
        let lowSpacePlan = try copyOutput(lowSpaceFixture)
        let lowSpaceOutcome = await DevOperationRunner(context: lowSpaceFixture.context).run(
            plan: lowSpacePlan.plan,
            kind: .firstRun,
            baseline: nil,
            plannerOutput: lowSpacePlan,
            progress: { _, _ in }
        )
        XCTAssertEqual(lowSpaceOutcome.operation.state, .failed)
        XCTAssertTrue(lowSpaceOutcome.error?.contains("Not enough space") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lowSpaceFixture.externalProject.appendingPathComponent("file.txt").path))
    }

    func testScenario55ChangedMountPathRepairsManagedLink() async throws {
        let firstMount = try await attach(Self.caseSensitiveImage)
        let volumeIdentifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: firstMount))
        let relativePath = "link-\(UUID().uuidString)"
        let externalProject = firstMount.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
        let internalRoot = temporaryRoot.appendingPathComponent("link-internal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalRoot, withIntermediateDirectories: true)
        let pair = DevSyncPair(
            displayName: "Changed mount",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: "internal", volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: firstMount.path, volumeIdentifier: volumeIdentifier, volumeName: "External", fileSystemType: "apfs")
        )
        let project = DevProject(pairID: pair.id, relativePath: relativePath, residency: .externalResident, kind: .nonGit)
        let store = DevSyncStateStore(rootURL: temporaryRoot.appendingPathComponent("link-state", isDirectory: true))
        let manager = DevManagedLinkManager(pair: pair, stateStore: store)
        let link = try await manager.create(
            project: project,
            internalRoot: internalRoot,
            externalRoot: firstMount,
            externalVolumeIdentifier: volumeIdentifier,
            knownProjectPaths: []
        )
        _ = try await MatrixProcess.run("/usr/bin/hdiutil", ["detach", firstMount.path])

        let changedMount = temporaryRoot.appendingPathComponent("changed-mount", isDirectory: true)
        try FileManager.default.createDirectory(at: changedMount, withIntermediateDirectories: true)
        let remounted = try await attach(Self.caseSensitiveImage, mountPoint: changedMount)
        addTeardownBlock { try? FileManager.default.removeItem(at: remounted.appendingPathComponent(relativePath)) }
        let repaired = try await manager.repair(
            link,
            internalRoot: internalRoot,
            externalRoot: remounted,
            externalVolumeIdentifier: try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: remounted)),
            recreateMissing: false
        )

        XCTAssertEqual(
            URL(fileURLWithPath: repaired.lastWrittenTargetText).resolvingSymlinksInPath().path,
            remounted.appendingPathComponent(relativePath).resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            DevManagedLinkManager.readTarget(of: internalRoot.appendingPathComponent(relativePath)).map {
                URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
            },
            URL(fileURLWithPath: repaired.lastWrittenTargetText).resolvingSymlinksInPath().path
        )
    }

    func testSyntheticExFATDisablesMetadataAndUsesTwoSecondTolerance() async throws {
        let rsync = try await DevRsyncProbe.probe(
            executable: URL(fileURLWithPath: "/usr/bin/rsync"),
            selfTestDirectory: temporaryRoot
        )
        let full = syntheticVolume(fileSystem: "apfs", fidelity: .full, timestampResolution: 1)
        let exFAT = syntheticVolume(fileSystem: "exfat", fidelity: .portable, timestampResolution: 2_000_000_000)
        let pairCapabilities = DevPairCapabilities(internalVolume: full, externalVolume: exFAT, rsync: rsync)
        let options = DevRsyncOptions.resolve(
            capabilities: rsync,
            pairCapabilities: pairCapabilities,
            metadata: .init(),
            partialDirectory: temporaryRoot,
            backupDirectory: nil
        )

        XCTAssertFalse(options.preservePermissions)
        XCTAssertFalse(options.preserveXattrs)
        XCTAssertFalse(options.preserveHardLinks)
        XCTAssertEqual(options.modifyWindowSeconds, rsync.supportsModifyWindow ? 2 : nil)
        XCTAssertEqual(pairCapabilities.fidelity, .portable)
        XCTAssertEqual(
            DevReconciliationPlanner.entryState(
                baseline: signature(time: 1_000_000_000),
                current: signature(time: 2_999_999_999),
                isUnreadable: false,
                isUnstable: false,
                toleranceNanoseconds: pairCapabilities.timestampToleranceNanoseconds,
                compareMode: false
            ),
            .unchanged
        )
    }

    private func attach(_ imagePath: String, readOnly: Bool = false, mountPoint: URL? = nil) async throws -> URL {
        guard FileManager.default.fileExists(atPath: imagePath) else { throw XCTSkip("Disk image is unavailable") }
        var arguments = ["attach", "-nobrowse", "-noautoopen"]
        if readOnly { arguments.append("-readonly") }
        if let mountPoint { arguments += ["-mountpoint", mountPoint.path] }
        arguments += ["-plist", imagePath]
        let result = try await MatrixProcess.run("/usr/bin/hdiutil", arguments)
        guard result.status == 0 else {
            throw XCTSkip("Could not attach \(URL(fileURLWithPath: imagePath).lastPathComponent): \(result.stderr)")
        }
        let propertyList = try PropertyListSerialization.propertyList(from: result.stdout, format: nil)
        let dictionary = try XCTUnwrap(propertyList as? [String: Any])
        let entities = try XCTUnwrap(dictionary["system-entities"] as? [[String: Any]])
        let path = try XCTUnwrap(entities.compactMap { $0["mount-point"] as? String }.last)
        let mount = URL(fileURLWithPath: path, isDirectory: true)
        addTeardownBlock { _ = try? await MatrixProcess.run("/usr/bin/hdiutil", ["detach", mount.path]) }
        return mount
    }

    private func makeFixture(
        externalRoot: URL,
        relativePath suppliedRelativePath: String? = nil,
        createExternalProject: Bool = true
    ) async throws -> FileSystemFixture {
        let internalRoot = temporaryRoot.appendingPathComponent("internal-\(UUID().uuidString)", isDirectory: true)
        let relativePath = suppliedRelativePath ?? "pipeline-\(UUID().uuidString)"
        let internalProject = internalRoot.appendingPathComponent(relativePath, isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        if createExternalProject {
            try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
        }
        let internalIdentifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: internalRoot))
        let externalIdentifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: externalRoot))
        var configuration = DevSyncConfiguration.default
        configuration.safety.minimumFreeSpaceReserveBytes = 0
        let pair = DevSyncPair(
            displayName: "File-system matrix",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: internalIdentifier, volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalRoot.path, volumeIdentifier: externalIdentifier, volumeName: "External", fileSystemType: "apfs"),
            configuration: configuration
        )
        let project = DevProject(pairID: pair.id, relativePath: relativePath, residency: .mirrored, kind: .nonGit, explicitlyIncluded: true)
        let store = DevSyncStateStore(rootURL: temporaryRoot.appendingPathComponent("state-\(UUID().uuidString)", isDirectory: true))
        var externalVolume = DevVolumeProbe.probe(rootURL: externalRoot, probeDirectory: externalRoot)
        if !externalVolume.isReadOnly, externalVolume.availableCapacity <= 0 {
            externalVolume.availableCapacity = Int64.max / 4
        }
        let capabilities = DevPairCapabilities(
            internalVolume: DevVolumeProbe.probe(rootURL: internalRoot, probeDirectory: internalRoot),
            externalVolume: externalVolume,
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
        return FileSystemFixture(
            pair: pair,
            project: project,
            internalProject: internalProject,
            externalProject: externalProject,
            capabilities: capabilities,
            context: context
        )
    }

    private func copyOutput(_ fixture: FileSystemFixture) throws -> DevPlannerOutput {
        let signature = try DevSnapshotScanner.signature(
            of: fixture.internalProject.appendingPathComponent("file.txt"),
            includeHash: false
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
            reason: "File-system preflight"
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

    private func plan(_ fixture: FileSystemFixture) async -> DevPlannerOutput {
        let policy = nonGitPolicy()
        let internalSnapshot = await DevSnapshotScanner.scan(
            projectURL: fixture.internalProject,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: fixture.capabilities.externalVolume?.isCaseSensitive == false,
            hashPaths: []
        )
        let externalSnapshot = await DevSnapshotScanner.scan(
            projectURL: fixture.externalProject,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: fixture.capabilities.internalVolume?.isCaseSensitive == false,
            hashPaths: []
        )
        return DevReconciliationPlanner.plan(DevPlannerInput(
            pair: fixture.pair,
            project: fixture.project,
            baseline: nil,
            internalSnapshot: internalSnapshot,
            externalSnapshot: externalSnapshot,
            tombstones: [],
            unresolvedConflicts: [],
            capabilities: fixture.capabilities,
            unstablePaths: [],
            now: Date()
        ))
    }

    private func plannerOutput(
        source: URL,
        destination: URL,
        sourceSnapshot: DevSnapshot,
        destinationSnapshot: DevSnapshot,
        externalCaseSensitive: Bool
    ) -> DevPlannerOutput {
        let pair = DevSyncPair(
            displayName: "Collision",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: source.path, volumeIdentifier: "internal", volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: destination.path, volumeIdentifier: "external", volumeName: "External", fileSystemType: "apfs")
        )
        let project = DevProject(pairID: pair.id, relativePath: "", residency: .mirrored, kind: .nonGit)
        var externalVolume = syntheticVolume(fileSystem: "apfs", fidelity: .full, timestampResolution: 1)
        externalVolume.isCaseSensitive = externalCaseSensitive
        return DevReconciliationPlanner.plan(DevPlannerInput(
            pair: pair,
            project: project,
            baseline: nil,
            internalSnapshot: sourceSnapshot,
            externalSnapshot: destinationSnapshot,
            tombstones: [],
            unresolvedConflicts: [],
            capabilities: DevPairCapabilities(
                internalVolume: syntheticVolume(fileSystem: "apfs", fidelity: .full, timestampResolution: 1),
                externalVolume: externalVolume
            ),
            unstablePaths: [],
            now: Date()
        ))
    }

    private func nonGitPolicy() -> DevFilePolicyEngine {
        DevFilePolicyEngine(
            policy: .init(),
            projectKind: .nonGit,
            gitDirectoryRelativePath: nil,
            gitTracked: nil,
            gitIgnored: nil,
            gitAvailable: false,
            projectIgnoreRules: []
        )
    }

    private func syntheticVolume(fileSystem: String, fidelity: DevFileSystemFidelity, timestampResolution: Int64) -> DevVolumeCapabilities {
        DevVolumeCapabilities(
            volumeIdentifier: fileSystem,
            volumeName: fileSystem,
            mountPath: "/Volumes/\(fileSystem)",
            fileSystemType: fileSystem,
            isReadOnly: false,
            isRemovable: true,
            isLocal: true,
            isEncrypted: false,
            availableCapacity: 1_000_000,
            totalCapacity: 2_000_000,
            isCaseSensitive: fileSystem != "exfat",
            isCasePreserving: true,
            supportsSymbolicLinks: fileSystem != "exfat",
            supportsHardLinks: fileSystem != "exfat",
            supportsUnixPermissions: fileSystem != "exfat",
            supportsExtendedAttributes: fileSystem != "exfat",
            supportsCreationTimes: true,
            supportsPersistentIdentifiers: true,
            timestampResolutionNanoseconds: timestampResolution,
            maximumPathComponentLength: 255,
            probedAt: Date(),
            fidelity: fidelity,
            fidelityNotes: []
        )
    }

    private func signature(time: Int64) -> DevFileSignature {
        DevFileSignature(kind: .file, size: 1, modificationTimeNanoseconds: time, mode: 0o644)
    }
}

private struct FileSystemFixture {
    var pair: DevSyncPair
    var project: DevProject
    var internalProject: URL
    var externalProject: URL
    var capabilities: DevPairCapabilities
    var context: DevOperationContext
}

private nonisolated struct MatrixProcessResult: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: String
}

private nonisolated enum MatrixProcess {
    static func run(_ executable: String, _ arguments: [String]) async throws -> MatrixProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            try process.run()
            async let stdout = Task.detached { (try? output.fileHandleForReading.readToEnd()) ?? Data() }.value
            async let stderr = Task.detached { (try? error.fileHandleForReading.readToEnd()) ?? Data() }.value
            process.waitUntilExit()
            return await MatrixProcessResult(
                status: process.terminationStatus,
                stdout: stdout,
                stderr: String(decoding: stderr, as: UTF8.self)
            )
        }.value
    }
}
