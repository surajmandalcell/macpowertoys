import Darwin
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
        let repository = try await makeRepository(named: "manifest")
        try write("tracked\n", to: repository.appendingPathComponent("README.md"))
        try await runGit(["add", "README.md"], in: repository)
        try await runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "initial"], in: repository)
        try write("untracked\n", to: repository.appendingPathComponent("notes.txt"))
        try write("node_modules/\n", to: repository.appendingPathComponent(".gitignore"))
        try await runGit(["add", ".gitignore"], in: repository)
        try await runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "ignore"], in: repository)
        for index in 0..<200 {
            try write("ignored", to: repository.appendingPathComponent("node_modules/file-\(index).js"))
        }

        let manifest = try await DevGit.workingTreeManifest(projectURL: repository)
        XCTAssertTrue(manifest.contains("README.md"))
        XCTAssertTrue(manifest.contains("notes.txt"))
        XCTAssertFalse(manifest.contains { $0.hasPrefix("node_modules/") })
    }

    func testScenario25GitIgnoreReportsIgnoredCandidates() async throws {
        let repository = try await makeRepository(named: "ignore")
        try write("secret", to: repository.appendingPathComponent(".env.local"))
        try write("module", to: repository.appendingPathComponent("node_modules/index.js"))

        let beforeChange = try await DevGit.ignoredPaths(projectURL: repository, candidates: [".env.local"])
        XCTAssertTrue(beforeChange.isEmpty)

        try write(".env.local\nnode_modules/\n", to: repository.appendingPathComponent(".gitignore"))

        let ignored = try await DevGit.ignoredPaths(
            projectURL: repository,
            candidates: [".env.local", "node_modules/index.js", "visible.txt"]
        )
        XCTAssertEqual(ignored, [".env.local", "node_modules/index.js"])
    }

    func testScenario24WorkingTreeManifestHonorsIsolatedGlobalIgnore() async throws {
        let repository = try await makeRepository(named: "global-ignore")
        let globalExcludes = temporaryRoot.appendingPathComponent("global-excludes")
        let globalConfiguration = temporaryRoot.appendingPathComponent("global-gitconfig")
        try write("*.tmp\n", to: globalExcludes)
        try write("[core]\n\texcludesFile = \(globalExcludes.path)\n", to: globalConfiguration)
        try write("ignored", to: repository.appendingPathComponent("cache.tmp"))
        try write("visible", to: repository.appendingPathComponent("visible.txt"))
        let previousConfiguration = ProcessInfo.processInfo.environment["GIT_CONFIG_GLOBAL"]
        setenv("GIT_CONFIG_GLOBAL", globalConfiguration.path, 1)
        defer {
            if let previousConfiguration {
                setenv("GIT_CONFIG_GLOBAL", previousConfiguration, 1)
            } else {
                unsetenv("GIT_CONFIG_GLOBAL")
            }
        }

        let manifest = try await DevGit.workingTreeManifest(projectURL: repository)

        XCTAssertFalse(manifest.contains("cache.tmp"))
        XCTAssertTrue(manifest.contains("visible.txt"))
    }

    func testScenario14WorkingTreeManifestIncludesInitializedSubmoduleFiles() async throws {
        let source = try await makeRepository(named: "submodule-source")
        try write("submodule", to: source.appendingPathComponent("file.txt"))
        try await runGit(["add", "file.txt"], in: source)
        try await runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "submodule"], in: source)

        let repository = try await makeRepository(named: "superproject")
        try await runGit(["-c", "protocol.file.allow=always", "submodule", "add", source.path, "modules/lib with space"], in: repository)
        try await runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-am", "submodule"], in: repository)

        let manifest = try await DevGit.workingTreeManifest(projectURL: repository)
        XCTAssertTrue(manifest.contains("modules/lib with space/file.txt"))
        let topology = await DevGit.topology(projectURL: repository, internalRoot: temporaryRoot, externalRoot: temporaryRoot)
        XCTAssertEqual(topology.submodulePaths, ["modules/lib with space"])
    }

    func testScenario15TopologyDetectsLinkedWorktree() async throws {
        let repository = try await makeRepository(named: "worktree-main")
        try write("content", to: repository.appendingPathComponent("file.txt"))
        try await runGit(["add", "file.txt"], in: repository)
        try await runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "initial"], in: repository)
        let linked = temporaryRoot.appendingPathComponent("worktree", isDirectory: true)
        try await runGit(["worktree", "add", "--detach", linked.path], in: repository)
        let externalRoot = temporaryRoot.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)

        let topology = await DevGit.topology(projectURL: linked, internalRoot: linked, externalRoot: externalRoot)
        XCTAssertEqual(topology.kind, .gitLinkedWorktree)
        XCTAssertTrue(topology.commonDirectory?.hasSuffix("/worktree-main/.git") == true)
        XCTAssertTrue(topology.commonDirectoryOutsidePair)
    }

    func testScenario16TopologyDetectsBareRepository() async throws {
        let bare = temporaryRoot.appendingPathComponent("bare.git", isDirectory: true)
        try await runGit(["init", "--bare", bare.path], in: temporaryRoot)

        let topology = await DevGit.topology(projectURL: bare, internalRoot: temporaryRoot, externalRoot: temporaryRoot)
        XCTAssertEqual(topology.kind, .gitBareRepository)
    }

    func testTopologyDetectsAlternatesShallowStateAndLFS() async throws {
        let pairRoot = temporaryRoot.appendingPathComponent("pair", isDirectory: true)
        try FileManager.default.createDirectory(at: pairRoot, withIntermediateDirectories: true)
        let repository = try await makeRepository(named: "pair/project")
        let alternateObjects = temporaryRoot.appendingPathComponent("outside/objects", isDirectory: true)
        try FileManager.default.createDirectory(at: alternateObjects, withIntermediateDirectories: true)
        try write(
            alternateObjects.path + "\n",
            to: repository.appendingPathComponent(".git/objects/info/alternates")
        )
        try write("shallow\n", to: repository.appendingPathComponent(".git/shallow"))
        try write("*.bin filter=lfs diff=lfs merge=lfs -text\n", to: repository.appendingPathComponent(".gitattributes"))

        let topology = await DevGit.topology(projectURL: repository, internalRoot: pairRoot, externalRoot: pairRoot)
        XCTAssertTrue(topology.hasAlternates)
        XCTAssertTrue(topology.alternateOutsidePair)
        XCTAssertTrue(topology.isShallow)
        XCTAssertTrue(topology.hasLFS)
    }

    func testScenario26ActiveLocksListsGitLocksAndTransientPaths() async throws {
        let repository = try await makeRepository(named: "locks")
        let refs = repository.appendingPathComponent(".git/refs/heads", isDirectory: true)
        let pack = repository.appendingPathComponent(".git/objects/pack", isDirectory: true)
        try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try write("lock", to: repository.appendingPathComponent(".git/index.lock"))
        try write("lock", to: refs.appendingPathComponent("feature.lock"))
        try write("temporary", to: pack.appendingPathComponent("tmp_pack"))
        let linkedRefs = temporaryRoot.appendingPathComponent("linked-refs", isDirectory: true)
        try write("lock", to: linkedRefs.appendingPathComponent("outside.lock"))
        try FileManager.default.createSymbolicLink(at: refs.appendingPathComponent("linked"), withDestinationURL: linkedRefs)

        let locks = DevGit.activeLocks(projectURL: repository, gitDirectory: repository.appendingPathComponent(".git"))
        XCTAssertEqual(locks, [".git/index.lock", ".git/objects/pack/tmp_pack", ".git/refs/heads/feature.lock"])
        XCTAssertTrue(DevGit.isTransientGitPath("index.lock"))
        XCTAssertTrue(DevGit.isTransientGitPath("objects/pack/tmp_pack"))
        XCTAssertFalse(DevGit.isTransientGitPath("objects/pack/pack-123.pack"))
    }

    func testScenario17IdentityStripsRemoteCredentialsAndKeepsFirstCommit() async throws {
        let repository = try await makeRepository(named: "identity")
        try write("content", to: repository.appendingPathComponent("file.txt"))
        try await runGit(["add", "file.txt"], in: repository)
        try await runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", "initial"], in: repository)
        try await runGit(["remote", "add", "origin", "https://user:password@example.com/team/project.git"], in: repository)
        try await runGit(["remote", "add", "backup", "git@example.com:team/project.git"], in: repository)

        let identityResult = await DevGit.identity(projectURL: repository)
        let identity = try XCTUnwrap(identityResult)
        XCTAssertEqual(identity.topologyKind, .gitRepository)
        XCTAssertEqual(identity.headReference, "master")
        XCTAssertEqual(identity.firstCommit?.count, 40)
        XCTAssertTrue(identity.remoteURLHints.contains("https://example.com/team/project.git"))
        XCTAssertTrue(identity.remoteURLHints.contains("git@example.com:team/project.git"))
        XCTAssertFalse(identity.remoteURLHints.contains { $0.contains("password") })
    }

    func testEmptyRepositoryIdentityHasNoFirstCommit() async throws {
        let repository = try await makeRepository(named: "empty")
        let identityResult = await DevGit.identity(projectURL: repository)
        let identity = try XCTUnwrap(identityResult)
        XCTAssertNil(identity.firstCommit)
    }

    func testGitUsesSelectedDeveloperDirectory() throws {
        let developerDirectory = try XCTUnwrap(DevGit.developerDirectory())
        let executable = try XCTUnwrap(DevGit.executable)
        XCTAssertEqual(executable, developerDirectory.appendingPathComponent("usr/bin/git"))
        XCTAssertTrue(DevGit.isAvailable)
    }

    func testIgnoreCandidatesRejectPathEscapes() async throws {
        let repository = try await makeRepository(named: "unsafe-ignore")

        do {
            _ = try await DevGit.ignoredPaths(projectURL: repository, candidates: ["../outside"])
            XCTFail("Expected an invalid candidate error")
        } catch let error as DevGitError {
            XCTAssertEqual(error, .failed(exitCode: -1, stderr: "Invalid Git ignore candidate"))
        }
    }

    func testGitRunRejectsSymbolicLinkWorkingDirectory() async throws {
        let repository = try await makeRepository(named: "real-repository")
        let link = temporaryRoot.appendingPathComponent("repository-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repository)

        do {
            _ = try await DevGit.run(["status", "--short"], in: link)
            XCTFail("Expected a symbolic-link directory error")
        } catch let error as DevGitError {
            XCTAssertEqual(error, .failed(exitCode: -1, stderr: "Invalid Git working directory"))
        }
    }

    private func makeRepository(named name: String) async throws -> URL {
        let repository = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try await runGit(["init", "-q", "-b", "master"], in: repository)
        return repository
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) async throws -> Data {
        try await DevGit.run(arguments, in: directory)
    }
}
