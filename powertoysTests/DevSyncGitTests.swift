import Foundation
import XCTest
@testable import powertoys

final class DevSyncGitTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
        try super.tearDownWithError()
    }

    func testScenario24WorkingTreeManifestIncludesTrackedAndUntrackedFilesButNotNodeModules() async throws {
        let repository = try makeRepository(named: "manifest")
        try write("tracked\n", to: repository.appendingPathComponent("README.md"))
        try runGit(["add", "README.md"], in: repository)
        try runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "initial"], in: repository)
        try write("untracked\n", to: repository.appendingPathComponent("notes.txt"))
        try write("node_modules/\n", to: repository.appendingPathComponent(".gitignore"))
        try runGit(["add", ".gitignore"], in: repository)
        try runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "ignore"], in: repository)
        for index in 0..<200 {
            try write("ignored", to: repository.appendingPathComponent("node_modules/file-\(index).js"))
        }

        let manifest = try await DevGit.workingTreeManifest(projectURL: repository)
        XCTAssertTrue(manifest.contains("README.md"))
        XCTAssertTrue(manifest.contains("notes.txt"))
        XCTAssertFalse(manifest.contains { $0.hasPrefix("node_modules/") })
    }

    func testScenario25GitIgnoreReportsIgnoredCandidates() async throws {
        let repository = try makeRepository(named: "ignore")
        try write(".env.local\nnode_modules/\n", to: repository.appendingPathComponent(".gitignore"))
        try write("secret", to: repository.appendingPathComponent(".env.local"))
        try write("module", to: repository.appendingPathComponent("node_modules/index.js"))

        let ignored = try await DevGit.ignoredPaths(
            projectURL: repository,
            candidates: [".env.local", "node_modules/index.js", "visible.txt"]
        )
        XCTAssertEqual(ignored, [".env.local", "node_modules/index.js"])
    }

    func testScenario14WorkingTreeManifestIncludesInitializedSubmoduleFiles() async throws {
        let source = try makeRepository(named: "submodule-source")
        try write("submodule", to: source.appendingPathComponent("file.txt"))
        try runGit(["add", "file.txt"], in: source)
        try runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "submodule"], in: source)

        let repository = try makeRepository(named: "superproject")
        try runGit(["-c", "protocol.file.allow=always", "submodule", "add", source.path, "modules/lib"], in: repository)
        try runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-am", "submodule"], in: repository)

        let manifest = try await DevGit.workingTreeManifest(projectURL: repository)
        XCTAssertTrue(manifest.contains("modules/lib/file.txt"))
    }

    func testScenario15TopologyDetectsLinkedWorktree() async throws {
        let repository = try makeRepository(named: "worktree-main")
        try write("content", to: repository.appendingPathComponent("file.txt"))
        try runGit(["add", "file.txt"], in: repository)
        try runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "initial"], in: repository)
        let linked = temporaryRoot.appendingPathComponent("worktree", isDirectory: true)
        try runGit(["worktree", "add", "--detach", linked.path], in: repository)

        let topology = await DevGit.topology(projectURL: linked, internalRoot: temporaryRoot, externalRoot: temporaryRoot)
        XCTAssertEqual(topology.kind, .gitLinkedWorktree)
        XCTAssertTrue(topology.commonDirectory?.hasSuffix("/worktree-main/.git") == true)
    }

    func testScenario16TopologyDetectsBareRepository() async throws {
        let bare = temporaryRoot.appendingPathComponent("bare.git", isDirectory: true)
        try runGit(["init", "--bare", bare.path], in: temporaryRoot)

        let topology = await DevGit.topology(projectURL: bare, internalRoot: temporaryRoot, externalRoot: temporaryRoot)
        XCTAssertEqual(topology.kind, .gitBareRepository)
    }

    func testScenario26ActiveLocksListsGitLocksAndTransientPaths() throws {
        let repository = try makeRepository(named: "locks")
        let refs = repository.appendingPathComponent(".git/refs/heads", isDirectory: true)
        let pack = repository.appendingPathComponent(".git/objects/pack", isDirectory: true)
        try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try write("lock", to: repository.appendingPathComponent(".git/index.lock"))
        try write("lock", to: refs.appendingPathComponent("feature.lock"))
        try write("temporary", to: pack.appendingPathComponent("tmp_pack"))

        let locks = DevGit.activeLocks(projectURL: repository, gitDirectory: repository.appendingPathComponent(".git"))
        XCTAssertEqual(locks, [".git/index.lock", ".git/objects/pack/tmp_pack", ".git/refs/heads/feature.lock"])
        XCTAssertTrue(DevGit.isTransientGitPath("index.lock"))
        XCTAssertTrue(DevGit.isTransientGitPath("objects/pack/tmp_pack"))
        XCTAssertFalse(DevGit.isTransientGitPath("objects/pack/pack-123.pack"))
    }

    func testScenario17IdentityStripsRemoteCredentialsAndKeepsFirstCommit() async throws {
        let repository = try makeRepository(named: "identity")
        try write("content", to: repository.appendingPathComponent("file.txt"))
        try runGit(["add", "file.txt"], in: repository)
        try runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "initial"], in: repository)
        try runGit(["remote", "add", "origin", "https://user:password@example.com/team/project.git"], in: repository)
        try runGit(["remote", "add", "backup", "git@example.com:team/project.git"], in: repository)

        let identityResult = await DevGit.identity(projectURL: repository)
        let identity = try XCTUnwrap(identityResult)
        XCTAssertEqual(identity.topologyKind, .gitRepository)
        XCTAssertEqual(identity.headReference, "master")
        XCTAssertEqual(identity.firstCommit?.count, 40)
        XCTAssertTrue(identity.remoteURLHints.contains("https://example.com/team/project.git"))
        XCTAssertTrue(identity.remoteURLHints.contains("git@example.com:team/project.git"))
        XCTAssertFalse(identity.remoteURLHints.contains { $0.contains("password") })
    }

    func testScenario74EmptyRepositoryIdentityHasNoFirstCommit() async throws {
        let repository = try makeRepository(named: "empty")
        let identityResult = await DevGit.identity(projectURL: repository)
        let identity = try XCTUnwrap(identityResult)
        XCTAssertNil(identity.firstCommit)
    }

    private func makeRepository(named name: String) throws -> URL {
        let repository = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-q", "-b", "master"], in: repository)
        return repository
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let stdout = try output.fileHandleForReading.readToEnd() ?? Data()
        let stderr = try error.fileHandleForReading.readToEnd() ?? Data()
        guard process.terminationStatus == 0 else {
            XCTFail(String(decoding: stderr, as: UTF8.self))
            return stdout
        }
        return stdout
    }
}
