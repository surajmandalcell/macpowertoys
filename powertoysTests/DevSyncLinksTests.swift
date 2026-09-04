import Darwin
import XCTest
@testable import powertoys

final class DevSyncLinksTests: XCTestCase {
    private var root: URL!
    private var internalRoot: URL!
    private var externalRoot: URL!
    private var stateStore: DevSyncStateStore!
    private var pair: DevSyncPair!
    private var manager: DevManagedLinkManager!
    private let volumeIdentifier = "external-volume"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-links-\(UUID().uuidString)", isDirectory: true)
        internalRoot = root.appendingPathComponent("internal", isDirectory: true)
        externalRoot = root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: internalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
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
            )
        )
        stateStore = DevSyncStateStore(rootURL: root.appendingPathComponent("state", isDirectory: true))
        manager = DevManagedLinkManager(pair: pair, stateStore: stateStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        internalRoot = nil
        externalRoot = nil
        stateStore = nil
        pair = nil
        manager = nil
    }

    func testScenario2CreateBuildsCategoryDirectoriesAndMarksLink() async throws {
        let project = try makeProject("personal/data/big-data")

        let link = try await manager.create(
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: volumeIdentifier,
            knownProjectPaths: []
        )

        let linkURL = internalRoot.appendingPathComponent(project.relativePath)
        XCTAssertTrue(DevManagedLinkManager.isSymlink(linkURL))
        XCTAssertEqual(DevManagedLinkManager.readTarget(of: linkURL), externalRoot.appendingPathComponent(project.relativePath).path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: internalRoot.appendingPathComponent("personal/data").path))
        XCTAssertTrue(hasManagedMarker(linkURL))
        let storedLinks = await manager.links()
        let isManaged = await manager.isManagedLinkPath(project.relativePath)
        XCTAssertEqual(storedLinks, [link])
        XCTAssertTrue(isManaged)
    }

    func testScenario4Scenario67CreateRefusesRealDirectory() async throws {
        let project = try makeProject("personal/big-data")
        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        let sentinel = internalProject.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        do {
            _ = try await manager.create(
                project: project,
                internalRoot: internalRoot,
                externalRoot: externalRoot,
                externalVolumeIdentifier: volumeIdentifier,
                knownProjectPaths: []
            )
            XCTFail("Expected a path collision")
        } catch {
            XCTAssertEqual(error as? DevManagedLinkError, .internalPathExists(kind: .directory))
        }

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        let storedLinks = await manager.links()
        XCTAssertTrue(storedLinks.isEmpty)
    }

    func testCreateRefusesNestedProjectWithoutExplicitFlag() async throws {
        let project = try makeProject("personal/monorepo/tools/external-tool")

        do {
            _ = try await manager.create(
                project: project,
                internalRoot: internalRoot,
                externalRoot: externalRoot,
                externalVolumeIdentifier: volumeIdentifier,
                knownProjectPaths: ["personal/monorepo"]
            )
            XCTFail("Expected nested-project refusal")
        } catch {
            XCTAssertEqual(error as? DevManagedLinkError, .parentInsideProject("personal/monorepo"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: internalRoot.appendingPathComponent("personal").path))
    }

    func testCreateRefusesCaseAndUnicodeCollisions() async throws {
        try FileManager.default.createDirectory(
            at: internalRoot.appendingPathComponent("Personal", isDirectory: true),
            withIntermediateDirectories: true
        )
        let caseProject = try makeProject("personal/case-project")
        do {
            _ = try await manager.create(
                project: caseProject,
                internalRoot: internalRoot,
                externalRoot: externalRoot,
                externalVolumeIdentifier: volumeIdentifier,
                knownProjectPaths: []
            )
            XCTFail("Expected a case collision")
        } catch {
            XCTAssertEqual(error as? DevManagedLinkError, .collision("Personal"))
        }

        let composed = "caf\u{00e9}"
        let decomposed = "cafe\u{0301}"
        try FileManager.default.createDirectory(
            at: internalRoot.appendingPathComponent("unicode/\(decomposed)", isDirectory: true),
            withIntermediateDirectories: true
        )
        let unicodeProject = try makeProject("unicode/\(composed)")
        do {
            _ = try await manager.create(
                project: unicodeProject,
                internalRoot: internalRoot,
                externalRoot: externalRoot,
                externalVolumeIdentifier: volumeIdentifier,
                knownProjectPaths: []
            )
            XCTFail("Expected a Unicode collision")
        } catch {
            let managedError = error as? DevManagedLinkError
            XCTAssertTrue(
                managedError == .collision("unicode/\(decomposed)")
                    || managedError == .internalPathExists(kind: .directory)
            )
        }
    }

    func testScenario66Scenario68ValidateAllFiveStates() async throws {
        let project = try makeProject("personal/big-data")
        let link = try await manager.create(
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: volumeIdentifier,
            knownProjectPaths: []
        )
        let linkURL = internalRoot.appendingPathComponent(project.relativePath)

        let healthy = await manager.validate(link, internalRoot: internalRoot, externalRoot: externalRoot, externalVolumeIdentifier: volumeIdentifier)
        let offline = await manager.validate(link, internalRoot: internalRoot, externalRoot: nil, externalVolumeIdentifier: nil)
        let wrongTarget = await manager.validate(link, internalRoot: internalRoot, externalRoot: externalRoot, externalVolumeIdentifier: "other-volume")
        XCTAssertEqual(healthy, .healthy)
        XCTAssertEqual(offline, .offline)
        XCTAssertEqual(wrongTarget, .wrongTarget)

        try FileManager.default.removeItem(at: linkURL)
        let missing = await manager.validate(link, internalRoot: internalRoot, externalRoot: externalRoot, externalVolumeIdentifier: volumeIdentifier)
        XCTAssertEqual(missing, .missing)

        try FileManager.default.createDirectory(at: linkURL, withIntermediateDirectories: false)
        let replaced = await manager.validate(link, internalRoot: internalRoot, externalRoot: externalRoot, externalVolumeIdentifier: volumeIdentifier)
        XCTAssertEqual(replaced, .replaced)

        let refreshed = try await manager.refreshStates(
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: volumeIdentifier
        )
        XCTAssertEqual(refreshed.first?.state, .replaced)
    }

    func testScenario55RepairRewritesTargetAfterMountPathChanges() async throws {
        let project = try makeProject("personal/big-data")
        let link = try await manager.create(
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: volumeIdentifier,
            knownProjectPaths: []
        )
        let oldTarget = externalRoot.appendingPathComponent(project.relativePath).path
        let movedExternalRoot = root.appendingPathComponent("External-1", isDirectory: true)
        try FileManager.default.moveItem(at: externalRoot, to: movedExternalRoot)

        let repaired = try await manager.repair(
            link,
            internalRoot: internalRoot,
            externalRoot: movedExternalRoot,
            externalVolumeIdentifier: volumeIdentifier,
            recreateMissing: false
        )

        let linkURL = internalRoot.appendingPathComponent(project.relativePath)
        XCTAssertEqual(link.lastWrittenTargetText, oldTarget)
        XCTAssertEqual(DevManagedLinkManager.readTarget(of: linkURL), movedExternalRoot.appendingPathComponent(project.relativePath).path)
        XCTAssertEqual(repaired.state, .healthy)
        XCTAssertTrue(hasManagedMarker(linkURL))
    }

    func testRepairRefusesReplacedPath() async throws {
        let project = try makeProject("personal/big-data")
        let link = try await manager.create(
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: volumeIdentifier,
            knownProjectPaths: []
        )
        let linkURL = internalRoot.appendingPathComponent(project.relativePath)
        try FileManager.default.removeItem(at: linkURL)
        try FileManager.default.createDirectory(at: linkURL, withIntermediateDirectories: false)

        do {
            _ = try await manager.repair(
                link,
                internalRoot: internalRoot,
                externalRoot: externalRoot,
                externalVolumeIdentifier: volumeIdentifier,
                recreateMissing: true
            )
            XCTFail("Expected repair to refuse a real directory")
        } catch {
            XCTAssertEqual(error as? DevManagedLinkError, .collision(project.relativePath))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: linkURL.path))
        XCTAssertFalse(DevManagedLinkManager.isSymlink(linkURL))
    }

    func testScenario6AdoptVerifiesExistingUserLinkWithoutRewriting() async throws {
        let project = try makeProject("personal/big-data")
        let linkURL = internalRoot.appendingPathComponent(project.relativePath)
        try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let targetText = "../../external/personal/big-data"
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: targetText)

        let adopted = try await manager.adopt(
            userLinkRelativePath: project.relativePath,
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: volumeIdentifier
        )

        XCTAssertEqual(DevManagedLinkManager.readTarget(of: linkURL), targetText)
        XCTAssertTrue(adopted.adoptedFromUserLink)
        XCTAssertTrue(hasManagedMarker(linkURL))
    }

    func testRemoveDeletesOnlyLinkAndRecordsOperation() async throws {
        let project = try makeProject("personal/big-data")
        let target = externalRoot.appendingPathComponent(project.relativePath)
        let link = try await manager.create(
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: volumeIdentifier,
            knownProjectPaths: []
        )
        let operationID = UUID()

        try await manager.remove(link, internalRoot: internalRoot, operationID: operationID)

        XCTAssertFalse(DevManagedLinkManager.isSymlink(internalRoot.appendingPathComponent(project.relativePath)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        let storedLinks = await manager.links()
        XCTAssertTrue(storedLinks.isEmpty)
        let operation = await stateStore.loadOperation(id: operationID, pairID: pair.id)
        XCTAssertEqual(operation?.kind, .linkRepair)
        XCTAssertEqual(operation?.state, .committed)
        XCTAssertEqual(operation?.plan.actions.first?.kind, .removeManagedLink)
    }

    private func makeProject(_ relativePath: String) throws -> DevProject {
        let target = externalRoot.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("project".utf8).write(to: target.appendingPathComponent("README.md"))
        return DevProject(
            pairID: pair.id,
            relativePath: relativePath,
            residency: .externalOnlyPendingLink,
            kind: .gitRepository
        )
    }

    private func hasManagedMarker(_ url: URL) -> Bool {
        url.path.withCString { path in
            DevSyncDefaults.managedLinkAttributeName.withCString { name in
                getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
            }
        }
    }
}
