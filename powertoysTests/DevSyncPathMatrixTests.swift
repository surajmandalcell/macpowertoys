import Darwin
import XCTest
@testable import powertoys

final class DevSyncPathMatrixTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-path-matrix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testScenarios37To43PathMatrixTransfersAndCommitsEverySupportedPath() async throws {
        let fixture = try await makeFixture()
        let names = [
            "normal.txt",
            "space name.txt",
            "tab\tname.txt",
            "newline\nname.txt",
            "emoji-😀.txt",
            "e\u{301}.txt",
            "-leading.txt",
            String(repeating: "l", count: 250),
            ".hidden"
        ]
        for name in names {
            try Data(name.utf8).write(to: fixture.internalProject.appendingPathComponent(name))
        }
        let deepFile = fixture.internalProject.appendingPathComponent("deep/a/b/c/file.txt")
        try FileManager.default.createDirectory(at: deepFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("deep".utf8).write(to: deepFile)
        let emptyDirectory = fixture.internalProject.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)
        let script = fixture.internalProject.appendingPathComponent("script")
        try Data("#!/bin/false\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let absoluteTarget = temporaryRoot.appendingPathComponent("outside-target")
        try Data("outside".utf8).write(to: absoluteTarget)
        try Data("outside".utf8).write(to: fixture.internalProject.deletingLastPathComponent().appendingPathComponent("outside"))
        try createSymlink("normal.txt", at: fixture.internalProject.appendingPathComponent("normal-link"))
        try createSymlink(absoluteTarget.path, at: fixture.internalProject.appendingPathComponent("absolute-link"))
        try createSymlink("../outside", at: fixture.internalProject.appendingPathComponent("relative-link"))
        let hardSource = fixture.internalProject.appendingPathComponent("hard-source")
        let hardLink = fixture.internalProject.appendingPathComponent("hard-link")
        try Data("hard".utf8).write(to: hardSource)
        XCTAssertEqual(Darwin.link(hardSource.path, hardLink.path), 0)
        let xattrFile = fixture.internalProject.appendingPathComponent("xattr.txt")
        try Data("attributes".utf8).write(to: xattrFile)
        let xattrValue = Data("metadata".utf8)
        try setExtendedAttribute(xattrValue, at: xattrFile)
        let fifo = fixture.internalProject.appendingPathComponent("unsupported.fifo")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o600), 0)

        let policy = DevFilePolicyEngine(
            policy: fixture.pair.configuration.policy,
            projectKind: .nonGit,
            gitDirectoryRelativePath: nil,
            gitTracked: nil,
            gitIgnored: nil,
            gitAvailable: false,
            projectIgnoreRules: []
        )
        let internalSnapshot = await DevSnapshotScanner.scan(
            projectURL: fixture.internalProject,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        let externalSnapshot = await DevSnapshotScanner.scan(
            projectURL: fixture.externalProject,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        XCTAssertEqual(internalSnapshot.excluded["unsupported.fifo"], .unsupportedObjectType)
        let output = DevReconciliationPlanner.plan(DevPlannerInput(
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
        let outcome = await DevOperationRunner(context: fixture.context).run(
            plan: output.plan,
            kind: .firstRun,
            baseline: nil,
            plannerOutput: output,
            progress: { _, _ in }
        )

        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.operation.state, .committed)
        for path in internalSnapshot.entries.keys {
            XCTAssertNotNil(try? DevSnapshotScanner.signature(of: fixture.externalProject.appendingPathComponent(path), includeHash: false), path)
        }
        for linkName in ["normal-link", "absolute-link", "relative-link"] {
            let source = try DevSnapshotScanner.signature(of: fixture.internalProject.appendingPathComponent(linkName), includeHash: false)
            let destination = try DevSnapshotScanner.signature(of: fixture.externalProject.appendingPathComponent(linkName), includeHash: false)
            XCTAssertEqual(destination.kind, .symlink)
            XCTAssertEqual(destination.symlinkTarget, source.symlinkTarget)
        }
        let destinationMode = try DevSnapshotScanner.signature(of: fixture.externalProject.appendingPathComponent("script"), includeHash: false).mode
        XCTAssertEqual(destinationMode.map { $0 & 0o111 }, 0o111)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.externalProject.appendingPathComponent("empty").path), [])
        if fixture.capabilities.rsync?.supportsXattrs == true,
           fixture.capabilities.externalVolume?.supportsExtendedAttributes == true {
            XCTAssertEqual(try extendedAttribute(at: fixture.externalProject.appendingPathComponent("xattr.txt")), xattrValue)
        }
        let storedBaseline = await fixture.store.loadBaseline(projectID: fixture.project.id, pairID: fixture.pair.id)
        let baseline = try XCTUnwrap(storedBaseline)
        XCTAssertEqual(Set(baseline.entries.keys), Set(internalSnapshot.entries.keys))
    }

    func testDanglingSymlinkIsPlannedButAppleRsyncCannotTransferIt() async throws {
        let fixture = try await makeFixture()
        try createSymlink("missing.txt", at: fixture.internalProject.appendingPathComponent("dangling-link"))
        let policy = DevFilePolicyEngine(
            policy: fixture.pair.configuration.policy,
            projectKind: .nonGit,
            gitDirectoryRelativePath: nil,
            gitTracked: nil,
            gitIgnored: nil,
            gitAvailable: false,
            projectIgnoreRules: []
        )
        let internalSnapshot = await DevSnapshotScanner.scan(
            projectURL: fixture.internalProject,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        let externalSnapshot = await DevSnapshotScanner.scan(
            projectURL: fixture.externalProject,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        let output = DevReconciliationPlanner.plan(DevPlannerInput(
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

        XCTAssertTrue(output.plan.manifestToExternal.contains("dangling-link"))
        throw XCTSkip("Apple openrsync 2.6.9 exits 23 for dangling links supplied through --files-from")
    }

    private func makeFixture() async throws -> PathFixture {
        let internalRoot = temporaryRoot.appendingPathComponent("internal", isDirectory: true)
        let externalRoot = temporaryRoot.appendingPathComponent("external", isDirectory: true)
        let internalProject = internalRoot.appendingPathComponent("app", isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
        let identifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: internalRoot))
        var configuration = DevSyncConfiguration.default
        configuration.safety.minimumFreeSpaceReserveBytes = 0
        let pair = DevSyncPair(
            displayName: "Path matrix",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: identifier, volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalRoot.path, volumeIdentifier: identifier, volumeName: "External", fileSystemType: "apfs"),
            configuration: configuration
        )
        let project = DevProject(pairID: pair.id, relativePath: "app", residency: .mirrored, kind: .nonGit, explicitlyIncluded: true)
        let store = DevSyncStateStore(rootURL: temporaryRoot.appendingPathComponent("state", isDirectory: true))
        let safety = DevSafetyStore(pair: pair, stateStore: store)
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
            safetyStore: safety,
            linkManager: DevManagedLinkManager(pair: pair, stateStore: store),
            ledger: DevSelfEventLedger(),
            policy: nil,
            gitDirectoryRelativePath: nil
        )
        return PathFixture(pair: pair, project: project, internalProject: internalProject, externalProject: externalProject, capabilities: capabilities, store: store, context: context)
    }

    private func createSymlink(_ target: String, at url: URL) throws {
        guard Darwin.symlink(target, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func setExtendedAttribute(_ data: Data, at url: URL) throws {
        let result = data.withUnsafeBytes { buffer in
            setxattr(url.path, "com.macpowertoys.devsync-test", buffer.baseAddress, buffer.count, 0, 0)
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private func extendedAttribute(at url: URL) throws -> Data {
        let size = getxattr(url.path, "com.macpowertoys.devsync-test", nil, 0, 0, 0)
        guard size >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var data = Data(count: size)
        let count = data.withUnsafeMutableBytes { buffer in
            getxattr(url.path, "com.macpowertoys.devsync-test", buffer.baseAddress, size, 0, 0)
        }
        guard count >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        data.count = count
        return data
    }
}

private struct PathFixture {
    var pair: DevSyncPair
    var project: DevProject
    var internalProject: URL
    var externalProject: URL
    var capabilities: DevPairCapabilities
    var store: DevSyncStateStore
    var context: DevOperationContext
}
