import XCTest
@testable import powertoys

final class DevSyncGitMatrixTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-git-matrix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testGitShapesAreDiscoveredWithoutMutatingRepositories() async throws {
        let empty = try await makeRepository("empty")
        let normal = try await makeRepository("normal")
        try write("tracked", to: normal.appendingPathComponent("tracked.txt"))
        try await commitAll(normal)
        try await runGit(["remote", "add", "origin", "https://example.com/one.git"], in: normal)
        try await runGit(["remote", "add", "backup", "https://example.com/two.git"], in: normal)

        let nested = normal.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try await runGit(["init", "-q", "-b", "master"], in: nested)

        let linked = temporaryRoot.appendingPathComponent("linked", isDirectory: true)
        try await runGit(["worktree", "add", "--detach", linked.path], in: normal)
        let bare = temporaryRoot.appendingPathComponent("bare.git", isDirectory: true)
        try await runGit(["init", "--bare", bare.path], in: temporaryRoot)

        let before = try await status(of: [empty, normal, linked])
        let discovery = await DevProjectDiscovery.discover(
            root: temporaryRoot,
            side: .internal,
            configuration: .init(),
            managedLinkPaths: [],
            otherRoot: nil
        )
        let kinds = Dictionary(uniqueKeysWithValues: discovery.projects.map { ($0.relativePath, $0.kind) })
        let emptyIdentity = await DevGit.identity(projectURL: empty)
        let normalIdentity = await DevGit.identity(projectURL: normal)
        let after = try await status(of: [empty, normal, linked])

        XCTAssertEqual(kinds["empty"], .gitRepository)
        XCTAssertEqual(kinds["normal"], .gitRepository)
        XCTAssertTrue(discovery.candidates.contains { $0.relativePath == "normal/nested" && $0.kind == .nestedRepository })
        XCTAssertEqual(kinds["linked"], .gitLinkedWorktree)
        XCTAssertTrue(discovery.candidates.contains { $0.relativePath == "bare.git" })
        XCTAssertEqual(emptyIdentity?.remoteURLHints, [])
        XCTAssertEqual(normalIdentity?.remoteURLHints.count, 2)
        XCTAssertEqual(after, before)
    }

    func testGitFeaturesFlowThroughTopologyPolicyAndPlannerWithoutMutation() async throws {
        let repository = try await makeRepository("feature")
        try write("tracked", to: repository.appendingPathComponent("tracked.txt"))
        try write(".env\n*.pem\nnode_modules/\n", to: repository.appendingPathComponent(".gitignore"))
        try write("*.bin filter=lfs diff=lfs merge=lfs -text\n", to: repository.appendingPathComponent(".gitattributes"))
        try await commitAll(repository)
        try write("secret", to: repository.appendingPathComponent(".env"))
        try write("private", to: repository.appendingPathComponent("id.pem"))
        try write("ignored", to: repository.appendingPathComponent("node_modules/dependency.js"))
        try write("visible", to: repository.appendingPathComponent("visible.txt"))
        let head = String(decoding: try await runGit(["rev-parse", "HEAD"], in: repository), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try write("lock", to: repository.appendingPathComponent(".git/index.lock"))
        try write(head + "\n", to: repository.appendingPathComponent(".git/MERGE_HEAD"))
        try write("rebase", to: repository.appendingPathComponent(".git/rebase-merge/head-name"))
        try write(head + "\n", to: repository.appendingPathComponent(".git/shallow"))
        let alternate = temporaryRoot.appendingPathComponent("alternate/objects", isDirectory: true)
        try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: true)
        try write(alternate.path + "\n", to: repository.appendingPathComponent(".git/objects/info/alternates"))

        let before = try await status(of: [repository])
        let topology = await DevGit.topology(
            projectURL: repository,
            internalRoot: repository,
            externalRoot: repository
        )
        let ignoredCandidates = [".env", "id.pem", "node_modules/dependency.js", "visible.txt"]
        let ignored = try await DevGit.ignoredPaths(projectURL: repository, candidates: ignoredCandidates)
        let tracked = Set(nulStrings(try await runGit(["ls-files", "-z"], in: repository)))
        let policy = DevFilePolicyEngine(
            policy: .init(),
            projectKind: topology.kind,
            gitDirectoryRelativePath: ".git",
            gitTracked: tracked,
            gitIgnored: ignored,
            gitAvailable: true,
            projectIgnoreRules: []
        )
        let snapshot = await DevSnapshotScanner.scan(
            projectURL: repository,
            policy: policy,
            gitDirectoryRelativePath: ".git",
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        let destination = temporaryRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let destinationSnapshot = await DevSnapshotScanner.scan(
            projectURL: destination,
            policy: policy,
            gitDirectoryRelativePath: ".git",
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        let pair = makePair(internalURL: repository, externalURL: destination)
        let project = DevProject(
            pairID: pair.id,
            relativePath: "",
            residency: .mirrored,
            kind: .gitRepository,
            explicitlyIncluded: true
        )
        let plan = DevReconciliationPlanner.plan(DevPlannerInput(
            pair: pair,
            project: project,
            baseline: nil,
            internalSnapshot: snapshot,
            externalSnapshot: destinationSnapshot,
            tombstones: [],
            unresolvedConflicts: [],
            capabilities: DevPairCapabilities(),
            unstablePaths: [],
            now: Date()
        ))
        let after = try await status(of: [repository])

        XCTAssertTrue(topology.isShallow)
        XCTAssertTrue(topology.hasLFS)
        XCTAssertTrue(topology.hasAlternates)
        XCTAssertTrue(topology.alternateOutsidePair)
        XCTAssertEqual(ignored, [".env", "id.pem", "node_modules/dependency.js"])
        XCTAssertNotNil(snapshot.entries[".env"])
        XCTAssertNotNil(snapshot.entries["id.pem"])
        XCTAssertEqual(snapshot.excluded["node_modules"], .commonExclusion)
        XCTAssertEqual(snapshot.excluded[".git/index.lock"], .transientGitLock)
        XCTAssertNotNil(snapshot.entries["tracked.txt"])
        XCTAssertNotNil(snapshot.entries["visible.txt"])
        XCTAssertEqual(plan.plan.manifestToExternal.count, snapshot.entries.values.filter { $0.kind != .directory }.count)
        XCTAssertTrue(plan.warnings.isEmpty)
        XCTAssertEqual(after, before)
    }

    private func makeRepository(_ name: String) async throws -> URL {
        let repository = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try await runGit(["init", "-q", "-b", "master"], in: repository)
        return repository
    }

    private func makePair(internalURL: URL, externalURL: URL) -> DevSyncPair {
        DevSyncPair(
            displayName: "Git matrix",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalURL.path, volumeIdentifier: "test", volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalURL.path, volumeIdentifier: "test", volumeName: "External", fileSystemType: "apfs")
        )
    }

    private func commitAll(_ repository: URL) async throws {
        try await runGit(["add", "--all"], in: repository)
        try await runGit(
            ["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "fixture"],
            in: repository
        )
    }

    private func status(of repositories: [URL]) async throws -> [String: Data] {
        var statuses: [String: Data] = [:]
        for repository in repositories {
            statuses[repository.path] = try await runGit(["status", "--porcelain=v1", "-z"], in: repository)
        }
        return statuses
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    private func nulStrings(_ data: Data) -> [String] {
        data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) async throws -> Data {
        try await DevGit.run(arguments, in: directory)
    }
}
