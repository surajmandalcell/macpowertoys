import Foundation
import XCTest
@testable import powertoys

final class DevSyncResidencyTests: XCTestCase {
    private var root: URL!
    private var internalRoot: URL!
    private var externalRoot: URL!
    private var stateStore: DevSyncStateStore!
    private var pair: DevSyncPair!
    private var safetyStore: DevSafetyStore!
    private var linkManager: DevManagedLinkManager!
    private let volumeIdentifier = "external-volume"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-residency-\(UUID().uuidString)", isDirectory: true)
        internalRoot = root.appendingPathComponent("internal", isDirectory: true)
        externalRoot = root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: internalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)

        var configuration = DevSyncConfiguration.default
        configuration.safety.minimumFreeSpaceReserveBytes = 0
        pair = DevSyncPair(
            displayName: "External",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(
                bookmark: nil,
                path: internalRoot.path,
                volumeIdentifier: "internal-volume",
                volumeName: "Internal",
                fileSystemType: "apfs"
            ),
            externalRoot: DevSyncRoot(
                bookmark: nil,
                path: externalRoot.path,
                volumeIdentifier: volumeIdentifier,
                volumeName: "External",
                fileSystemType: "apfs"
            ),
            configuration: configuration
        )
        stateStore = DevSyncStateStore(rootURL: root.appendingPathComponent("state", isDirectory: true))
        safetyStore = DevSafetyStore(pair: pair, stateStore: stateStore)
        linkManager = DevManagedLinkManager(pair: pair, stateStore: stateStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        internalRoot = nil
        externalRoot = nil
        stateStore = nil
        pair = nil
        safetyStore = nil
        linkManager = nil
    }

    func testScenario70MoveToExternalCommitsCompleteProjectAndRetainsInternalCopy() async throws {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        let project = try await makeInternalGitProject()
        try await stateStore.saveProjects([project], pairID: pair.id)

        let result = try await DevResidencyConversion.moveToExternal(makeContext(project: project)) { _ in }

        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        let externalProject = externalRoot.appendingPathComponent(project.relativePath)
        XCTAssertEqual(try Data(contentsOf: externalProject.appendingPathComponent("README.md")), Data("readme".utf8))
        XCTAssertEqual(try Data(contentsOf: externalProject.appendingPathComponent("Sources/main.swift")), Data("print(\"hello\")\n".utf8))
        XCTAssertTrue(DevManagedLinkManager.isSymlink(internalProject))
        XCTAssertEqual(DevManagedLinkManager.readTarget(of: internalProject), externalProject.path)
        XCTAssertEqual(result.project.residency, .externalResident)
        XCTAssertEqual(result.operation.state, .committed)

        let safetyRecords = await stateStore.loadSafetyRecords(pairID: pair.id)
        let retained = try XCTUnwrap(safetyRecords.first(where: { $0.kind == .projectRetired }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: retained.safetyPath).appendingPathComponent("README.md").path))
        let savedOperation = await stateStore.loadOperation(id: result.operation.id, pairID: pair.id)
        XCTAssertEqual(savedOperation?.state, .committed)
    }

    func testScenario71StagingVerificationFailureLeavesInternalProjectUntouched() async throws {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        let project = try await makeInternalGitProject()
        try await stateStore.saveProjects([project], pairID: pair.id)
        let stagingFile = externalRoot
            .appendingPathComponent(DevSyncDefaults.systemDirectoryName)
            .appendingPathComponent(pair.id.uuidString)
            .appendingPathComponent("staging")
            .appendingPathComponent(project.id.uuidString)
            .appendingPathComponent("README.md")
        let corruptor = StagingCorruptor(file: stagingFile, threshold: 4.0 / 11.0)

        do {
            _ = try await DevResidencyConversion.moveToExternal(makeContext(project: project)) { value in
                corruptor.corruptIfReady(value)
            }
            XCTFail("Expected staging verification to fail")
        } catch let error as DevResidencyError {
            guard case .stagingVerificationFailed(let paths) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(paths.contains("README.md"))
        }

        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        XCTAssertFalse(DevManagedLinkManager.isSymlink(internalProject))
        XCTAssertEqual(try Data(contentsOf: internalProject.appendingPathComponent("README.md")), Data("readme".utf8))
        let savedProject = await stateStore.loadProjects(pairID: pair.id).first(where: { $0.id == project.id })
        XCTAssertEqual(savedProject?.residency, .mirrored)
        XCTAssertEqual(savedProject?.state, .error)
        XCTAssertNotNil(savedProject?.lastError)
        let storedLinks = await linkManager.links()
        XCTAssertTrue(storedLinks.isEmpty)
    }

    func testMoveToExternalMergesExistingMirrorWithBackup() async throws {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        let project = try await makeInternalGitProject()
        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        let externalProject = externalRoot.appendingPathComponent(project.relativePath)
        try FileManager.default.createDirectory(at: externalProject.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: internalProject, to: externalProject)
        try Data("external old".utf8).write(to: externalProject.appendingPathComponent("README.md"), options: .atomic)
        try await stateStore.saveProjects([project], pairID: pair.id)

        let result = try await DevResidencyConversion.moveToExternal(makeContext(project: project)) { _ in }

        XCTAssertEqual(try Data(contentsOf: externalProject.appendingPathComponent("README.md")), Data("readme".utf8))
        let backup = externalRoot
            .appendingPathComponent(DevSyncDefaults.systemDirectoryName)
            .appendingPathComponent(pair.id.uuidString)
            .appendingPathComponent("history")
            .appendingPathComponent(result.operation.id.uuidString)
            .appendingPathComponent("README.md")
        XCTAssertEqual(try Data(contentsOf: backup), Data("external old".utf8))
        XCTAssertEqual(result.operation.state, .committed)
    }

    func testScenario72BringInternalRoundTripKeepsExternalMirror() async throws {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        let project = try await makeInternalGitProject()
        try await stateStore.saveProjects([project], pairID: pair.id)
        let moved = try await DevResidencyConversion.moveToExternal(makeContext(project: project)) { _ in }

        let result = try await DevResidencyConversion.bringInternal(makeContext(project: moved.project)) { _ in }

        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        let externalProject = externalRoot.appendingPathComponent(project.relativePath)
        XCTAssertFalse(DevManagedLinkManager.isSymlink(internalProject))
        XCTAssertEqual(try Data(contentsOf: internalProject.appendingPathComponent("README.md")), Data("readme".utf8))
        XCTAssertEqual(try Data(contentsOf: externalProject.appendingPathComponent("README.md")), Data("readme".utf8))
        XCTAssertEqual(result.project.residency, .mirrored)
        XCTAssertEqual(result.operation.kind, .bringInternal)
        XCTAssertEqual(result.operation.state, .committed)
        let storedLinks = await linkManager.links()
        XCTAssertTrue(storedLinks.isEmpty)
    }

    func testScenario73BringInternalRefusesRealDirectoryAtManagedLinkPath() async throws {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        let project = try await makeInternalGitProject()
        try await stateStore.saveProjects([project], pairID: pair.id)
        let moved = try await DevResidencyConversion.moveToExternal(makeContext(project: project)) { _ in }
        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        try FileManager.default.removeItem(at: internalProject)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: false)
        let sentinel = internalProject.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        do {
            _ = try await DevResidencyConversion.bringInternal(makeContext(project: moved.project)) { _ in }
            XCTFail("Expected an unexpected internal path error")
        } catch {
            XCTAssertEqual(error as? DevResidencyError, .unexpectedInternalPath(internalProject.path))
        }

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        XCTAssertFalse(DevManagedLinkManager.isSymlink(internalProject))
    }

    func testScenario7MissingInternalConvertsOnlyAfterBaselineVerification() async throws {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        var project = try await makeExternalGitProject()
        project.state = .missing
        try await stateStore.saveProjects([project], pairID: pair.id)
        try await saveBaseline(project: project)

        let result = try await DevResidencyConversion.convertMissingInternalToExternalResident(makeContext(project: project))

        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        XCTAssertTrue(DevManagedLinkManager.isSymlink(internalProject))
        XCTAssertEqual(result.project.residency, .externalResident)
        XCTAssertEqual(result.project.state, .clean)
        XCTAssertEqual(result.operation.state, .committed)
    }

    func testScenario9MissingExternalBaselinePathLeavesProjectMissingWithoutLink() async throws {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        var project = try await makeExternalGitProject()
        project.state = .missing
        try await stateStore.saveProjects([project], pairID: pair.id)
        try await saveBaseline(project: project)
        try FileManager.default.removeItem(
            at: externalRoot.appendingPathComponent(project.relativePath).appendingPathComponent("Sources/main.swift")
        )

        do {
            _ = try await DevResidencyConversion.convertMissingInternalToExternalResident(makeContext(project: project))
            XCTFail("Expected baseline verification to fail")
        } catch let error as DevResidencyError {
            guard case .stagingVerificationFailed(let paths) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(paths.contains("Sources/main.swift"))
        }

        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        XCTAssertFalse(DevManagedLinkManager.isSymlink(internalProject))
        XCTAssertNil(DevManagedLinkManager.readTarget(of: internalProject))
        let savedProject = await stateStore.loadProjects(pairID: pair.id).first(where: { $0.id == project.id })
        XCTAssertEqual(savedProject?.state, .missing)
        XCTAssertNotNil(savedProject?.lastError)
        let storedLinks = await linkManager.links()
        XCTAssertTrue(storedLinks.isEmpty)
    }

    private func makeInternalGitProject() async throws -> DevProject {
        try await makeGitProject(at: internalRoot)
    }

    private func makeExternalGitProject() async throws -> DevProject {
        try await makeGitProject(at: externalRoot)
    }

    private func makeGitProject(at projectRoot: URL) async throws -> DevProject {
        let relativePath = "personal/app-a"
        let projectURL = projectRoot.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try Data("readme".utf8).write(to: projectURL.appendingPathComponent("README.md"))
        try Data("print(\"hello\")\n".utf8).write(to: projectURL.appendingPathComponent("Sources/main.swift"))
        _ = try await DevGit.run(["init"], in: projectURL)
        _ = try await DevGit.run(["add", "--all"], in: projectURL)
        return DevProject(
            pairID: pair.id,
            relativePath: relativePath,
            residency: .mirrored,
            kind: .gitRepository,
            state: .clean
        )
    }

    private func saveBaseline(project: DevProject) async throws {
        let context = makeContext(project: project)
        let projectURL = externalRoot.appendingPathComponent(project.relativePath)
        let snapshot = await DevSnapshotScanner.scan(
            projectURL: projectURL,
            policy: context.policy,
            gitDirectoryRelativePath: context.gitDirectoryRelativePath,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        XCTAssertTrue(snapshot.complete)
        let now = Date()
        let entries = snapshot.entries.mapValues { DevBaselineEntry(signature: $0, lastVerifiedAt: now) }
        try await stateStore.saveBaseline(
            DevBaseline(
                projectID: project.id,
                timestampToleranceNanoseconds: 1_000_000_000,
                entries: entries,
                updatedAt: now
            ),
            pairID: pair.id
        )
    }

    private func makeContext(project: DevProject) -> DevResidencyContext {
        let rsync = makeRsyncCapabilities()
        let internalVolume = makeVolume(path: internalRoot, identifier: pair.internalRoot.volumeIdentifier)
        let externalVolume = makeVolume(path: externalRoot, identifier: pair.externalRoot.volumeIdentifier)
        return DevResidencyContext(
            pair: pair,
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            capabilities: DevPairCapabilities(
                internalVolume: internalVolume,
                externalVolume: externalVolume,
                rsync: rsync,
                probedAt: Date()
            ),
            policy: DevFilePolicyEngine(
                policy: pair.configuration.policy,
                projectKind: .gitRepository,
                gitDirectoryRelativePath: ".git",
                gitTracked: nil,
                gitIgnored: nil,
                gitAvailable: false,
                projectIgnoreRules: []
            ),
            gitDirectoryRelativePath: ".git",
            stateStore: stateStore,
            safetyStore: safetyStore,
            linkManager: linkManager,
            rsyncExecutable: URL(fileURLWithPath: "/usr/bin/rsync")
        )
    }

    private func makeRsyncCapabilities() -> DevRsyncCapabilities {
        DevRsyncCapabilities(
            executablePath: "/usr/bin/rsync",
            versionText: "test rsync",
            protocolVersion: 29,
            isOpenrsync: true,
            supportedLongOptions: ["--from0"],
            supportsFilesFrom: true,
            supportsFrom0: true,
            supportsPartialDir: true,
            supportsBackupDir: true,
            supportsItemizeChanges: true,
            supportsExecutability: true,
            supportsPerms: true,
            supportsXattrs: false,
            supportsACLs: false,
            supportsHardLinks: false,
            supportsCrtimes: false,
            supportsOmitDirTimes: true,
            supportsModifyWindow: true,
            supportsDoubleDash: true,
            selfTestPassed: true,
            selfTestNotes: [],
            fingerprint: "test",
            probedAt: Date()
        )
    }

    private func makeVolume(path: URL, identifier: String) -> DevVolumeCapabilities {
        DevVolumeCapabilities(
            volumeIdentifier: identifier,
            volumeName: path.lastPathComponent,
            mountPath: path.path,
            fileSystemType: "apfs",
            isReadOnly: false,
            isRemovable: false,
            isLocal: true,
            isEncrypted: true,
            availableCapacity: 100_000_000_000,
            totalCapacity: 200_000_000_000,
            isCaseSensitive: true,
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
    }
}

private nonisolated final class StagingCorruptor: @unchecked Sendable {
    private let file: URL
    private let threshold: Double
    private let lock = NSLock()
    private var didCorrupt = false

    init(file: URL, threshold: Double) {
        self.file = file
        self.threshold = threshold
    }

    func corruptIfReady(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard !didCorrupt, value >= threshold else { return }
        didCorrupt = true
        try? Data("corrupt".utf8).write(to: file, options: .atomic)
    }
}
