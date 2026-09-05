import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import powertoys

@MainActor
final class DevSyncScannerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        try super.tearDownWithError()
    }

    func testSignatureCapturesFileDirectorySymlinkExecutableModeAndNanosecondMtime() throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("script.sh")
        try Data("echo ok".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let directory = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "script.sh")

        let fileSignature = try DevSnapshotScanner.signature(of: file, includeHash: false)
        let directorySignature = try DevSnapshotScanner.signature(of: directory, includeHash: false)
        let linkSignature = try DevSnapshotScanner.signature(of: link, includeHash: false)
        var status = Darwin.stat()
        XCTAssertEqual(lstat(file.path, &status), 0)

        XCTAssertEqual(fileSignature.kind, .file)
        XCTAssertEqual(fileSignature.size, UInt64(Data("echo ok".utf8).count))
        XCTAssertEqual(fileSignature.mode, 0o755)
        XCTAssertEqual(fileSignature.modificationTimeNanoseconds, Int64(status.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(status.st_mtimespec.tv_nsec))
        XCTAssertEqual(directorySignature.kind, .directory)
        XCTAssertEqual(linkSignature.kind, .symlink)
        XCTAssertEqual(linkSignature.symlinkTarget, "script.sh")
    }

    func testSignatureUsesFileResourceIdentifier() throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("resource-id.txt")
        try Data("id".utf8).write(to: file)

        let signature = try DevSnapshotScanner.signature(of: file, includeHash: false)
        XCTAssertEqual(signature.resourceIdentifier, try expectedResourceIdentifier(of: file))
    }

    func testXattrDigestSeparatesNamesFromValues() throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("file")
        try Data().write(to: file)
        try setExtendedAttribute(name: "a", value: Data("bc".utf8), at: file)
        let firstDigest = try XCTUnwrap(DevSnapshotScanner.signature(of: file, includeHash: false).xattrDigest)
        try removeExtendedAttribute(name: "a", at: file)
        try setExtendedAttribute(name: "ab", value: Data("c".utf8), at: file)
        let secondDigest = try XCTUnwrap(DevSnapshotScanner.signature(of: file, includeHash: false).xattrDigest)

        XCTAssertNotEqual(firstDigest, secondDigest)
    }

    func testHashOfThreeMiBFileMatchesCryptoKit() throws {
        let root = try makeTemporaryDirectory()
        let data = Data((0..<3 * 1_024 * 1_024).map { UInt8($0 % 251) })
        let file = root.appendingPathComponent("large.bin")
        try data.write(to: file)

        XCTAssertEqual(try DevSnapshotScanner.hash(url: file), Data(SHA256.hash(data: data)))
        XCTAssertEqual(try DevSnapshotScanner.signature(of: file, includeHash: true).contentHash, Data(SHA256.hash(data: data)))
    }

    func testScenario33SameBytesProduceSameHashDespiteDifferentMetadata() throws {
        let root = try makeTemporaryDirectory()
        let internalFile = root.appendingPathComponent("internal")
        let externalFile = root.appendingPathComponent("external")
        try Data("same".utf8).write(to: internalFile)
        try Data("same".utf8).write(to: externalFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: internalFile.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: externalFile.path)

        let internalSignature = try DevSnapshotScanner.signature(of: internalFile, includeHash: true)
        let externalSignature = try DevSnapshotScanner.signature(of: externalFile, includeHash: true)
        XCTAssertNotEqual(internalSignature.mode, externalSignature.mode)
        XCTAssertEqual(internalSignature.contentHash, externalSignature.contentHash)
    }

    func testScenario34MtimeOnlyChangeKeepsContentHash() throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("checkout.txt")
        try Data("unchanged".utf8).write(to: file)
        let before = try DevSnapshotScanner.signature(of: file, includeHash: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: file.path
        )
        let after = try DevSnapshotScanner.signature(of: file, includeHash: true)

        XCTAssertNotEqual(before.modificationTimeNanoseconds, after.modificationTimeNanoseconds)
        XCTAssertEqual(before.contentHash, after.contentHash)
    }

    func testScanSkipsSystemAndSymlinkedDirectoriesAndRecordsExcludedBytes() async throws {
        let root = try makeTemporaryDirectory()
        try Data("kept".utf8).write(to: root.appendingPathComponent("kept.txt"))
        let excluded = root.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: false)
        try Data(repeating: 1, count: 128).write(to: excluded.appendingPathComponent("ignored.js"))
        let system = root.appendingPathComponent(DevSyncDefaults.systemDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: false)
        try Data("private".utf8).write(to: system.appendingPathComponent("state"))
        let realDirectory = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        try Data("hidden".utf8).write(to: realDirectory.appendingPathComponent("hidden.txt"))
        let linkDirectory = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: linkDirectory.path, withDestinationPath: "real")

        let snapshot = await DevSnapshotScanner.scan(
            projectURL: root,
            policy: ExcludeNodeModulesPolicy(),
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )

        XCTAssertTrue(snapshot.complete)
        XCTAssertTrue(snapshot.entries.keys.contains("kept.txt"))
        XCTAssertFalse(snapshot.entries.keys.contains("node_modules/ignored.js"))
        XCTAssertFalse(snapshot.entries.keys.contains("linked/hidden.txt"))
        XCTAssertEqual(snapshot.excluded[DevSyncDefaults.systemDirectoryName], .cloudSyncInternalPath)
        XCTAssertEqual(snapshot.excluded["node_modules"], .commonExclusion)
        XCTAssertGreaterThan(snapshot.excludedBytes, 0)
    }

    func testScanHashesOnlyRequestedPaths() async throws {
        let root = try makeTemporaryDirectory()
        try Data("hashed".utf8).write(to: root.appendingPathComponent("hashed.txt"))
        try Data("quick".utf8).write(to: root.appendingPathComponent("quick.txt"))

        let snapshot = await DevSnapshotScanner.scan(
            projectURL: root,
            policy: IncludeAllPolicy(),
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: ["hashed.txt"]
        )

        XCTAssertNotNil(snapshot.entries["hashed.txt"]?.contentHash)
        XCTAssertNil(snapshot.entries["quick.txt"]?.contentHash)
    }

    func testScanMarksUnreadableDirectoryIncomplete() async throws {
        let root = try makeTemporaryDirectory()
        let unreadable = root.appendingPathComponent("unreadable", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: false)
        try Data("hidden".utf8).write(to: unreadable.appendingPathComponent("hidden.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path) }

        let snapshot = await DevSnapshotScanner.scan(
            projectURL: root,
            policy: IncludeAllPolicy(),
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )

        XCTAssertFalse(snapshot.complete)
        XCTAssertTrue(snapshot.unreadablePaths.contains("unreadable"))
        XCTAssertFalse(snapshot.entries.keys.contains("unreadable/hidden.txt"))
    }

    func testScanDetectsHashedFileChangingDuringScan() async throws {
        let root = try makeTemporaryDirectory()
        let changingFile = root.appendingPathComponent("changing.txt")
        try Data("before".utf8).write(to: changingFile)

        let snapshot = await DevSnapshotScanner.scan(
            projectURL: root,
            policy: AppendOnDecisionPolicy(file: changingFile),
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: ["changing.txt"]
        )

        XCTAssertFalse(snapshot.complete)
        XCTAssertNil(snapshot.entries["changing.txt"])
        XCTAssertTrue(snapshot.unreadablePaths.contains("changing.txt"))
    }

    func testExcludedDirectoryIsNotDescendedAndLimitRestrictsPathsToAncestors() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("a".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("b".utf8).write(to: source.appendingPathComponent("b.txt"))
        let ignored = root.appendingPathComponent("ignored", isDirectory: true)
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: false)
        try Data("no".utf8).write(to: ignored.appendingPathComponent("nested.txt"))

        let snapshot = await DevSnapshotScanner.scan(
            projectURL: root,
            policy: ExcludeIgnoredDirectoryPolicy(),
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: [],
            limitToPaths: ["src/a.txt"]
        )

        XCTAssertTrue(snapshot.entries.keys.contains("src"))
        XCTAssertTrue(snapshot.entries.keys.contains("src/a.txt"))
        XCTAssertFalse(snapshot.entries.keys.contains("src/b.txt"))
        XCTAssertFalse(snapshot.entries.keys.contains("ignored"))
    }

    func testScenario35CaseCollision() {
        XCTAssertEqual(DevSnapshotScanner.collisions(paths: ["Foo.swift", "foo.swift"], caseInsensitive: true), [["Foo.swift", "foo.swift"]])
        XCTAssertTrue(DevSnapshotScanner.collisions(paths: ["Foo.swift", "foo.swift"], caseInsensitive: false).isEmpty)
    }

    func testScenario36UnicodeNormalizationCollision() {
        let composed = "caf\u{00E9}.txt"
        let decomposed = "cafe\u{0301}.txt"
        XCTAssertEqual(DevSnapshotScanner.collisions(paths: [composed, decomposed], caseInsensitive: false), [[composed, decomposed].sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }])
    }

    func testDuplicatePathIsNotACollision() {
        XCTAssertTrue(DevSnapshotScanner.collisions(paths: ["same", "same"], caseInsensitive: true).isEmpty)
    }

    func testManifestAddsAncestorsAndSortsByUTF8Bytes() {
        let manifest = DevSnapshotScanner.manifest(paths: ["a-b/file", "a b/file", "deep/path/name"])
        XCTAssertEqual(manifest, ["a b", "a b/file", "a-b", "a-b/file", "deep", "deep/path", "deep/path/name"])
    }

    func testScenario47VerifyRejectsSizeMtimeAndHashChanges() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("source.txt")
        let destination = root.appendingPathComponent("destination.txt")
        try Data("same bytes".utf8).write(to: source)
        try FileManager.default.copyItem(at: source, to: destination)
        let planned = try DevSnapshotScanner.signature(of: source, includeHash: true)

        XCTAssertTrue(try DevSnapshotScanner.verify(plannedSource: planned, destinationURL: destination, toleranceNanoseconds: 1_000_000_000, compareMode: true, requireHash: true))
        try Data("changed size".utf8).write(to: destination)
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: planned, destinationURL: destination, toleranceNanoseconds: 1_000_000_000, compareMode: false, requireHash: true))
        try Data("same bytes".utf8).write(to: destination)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: destination.path)
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: planned, destinationURL: destination, toleranceNanoseconds: 0, compareMode: false, requireHash: false))
        try Data("diff bytes".utf8).write(to: destination)
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: planned, destinationURL: destination, toleranceNanoseconds: Int64.max, compareMode: false, requireHash: true))
    }

    func testVerifyChecksExistenceKindSymlinkTargetAndMode() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try Data("same".utf8).write(to: source)
        try Data("same".utf8).write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
        let plannedFile = try DevSnapshotScanner.signature(of: source, includeHash: false)

        XCTAssertTrue(try DevSnapshotScanner.verify(plannedSource: plannedFile, destinationURL: destination, toleranceNanoseconds: Int64.max, compareMode: false, requireHash: false))
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: plannedFile, destinationURL: destination, toleranceNanoseconds: Int64.max, compareMode: true, requireHash: false))
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: plannedFile, destinationURL: root.appendingPathComponent("missing"), toleranceNanoseconds: 0, compareMode: false, requireHash: false))
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: DevFileSignature(kind: .directory), destinationURL: destination, toleranceNanoseconds: 0, compareMode: false, requireHash: false))

        let sourceDirectory = root.appendingPathComponent("source-directory", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("destination-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: false)
        let directoryDate = Date(timeIntervalSince1970: 100)
        try FileManager.default.setAttributes([.modificationDate: directoryDate], ofItemAtPath: sourceDirectory.path)
        try FileManager.default.setAttributes([.modificationDate: directoryDate], ofItemAtPath: destinationDirectory.path)
        let plannedDirectory = try DevSnapshotScanner.signature(of: sourceDirectory, includeHash: false)
        XCTAssertTrue(try DevSnapshotScanner.verify(plannedSource: plannedDirectory, destinationURL: destinationDirectory, toleranceNanoseconds: 0, compareMode: false, requireHash: false))
        try FileManager.default.setAttributes([.modificationDate: directoryDate.addingTimeInterval(1)], ofItemAtPath: destinationDirectory.path)
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: plannedDirectory, destinationURL: destinationDirectory, toleranceNanoseconds: 0, compareMode: false, requireHash: false))

        let sourceLink = root.appendingPathComponent("source-link")
        let destinationLink = root.appendingPathComponent("destination-link")
        try FileManager.default.createSymbolicLink(atPath: sourceLink.path, withDestinationPath: "source")
        try FileManager.default.createSymbolicLink(atPath: destinationLink.path, withDestinationPath: "source")
        let plannedLink = try DevSnapshotScanner.signature(of: sourceLink, includeHash: false)
        XCTAssertTrue(try DevSnapshotScanner.verify(plannedSource: plannedLink, destinationURL: destinationLink, toleranceNanoseconds: Int64.max, compareMode: false, requireHash: false))
        try FileManager.default.removeItem(at: destinationLink)
        try FileManager.default.createSymbolicLink(atPath: destinationLink.path, withDestinationPath: "target")
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: plannedLink, destinationURL: destinationLink, toleranceNanoseconds: Int64.max, compareMode: false, requireHash: false))
    }

    func testIsStableDetectsAppendAcrossStabilityWindow() async throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("growing.log")
        try Data("before".utf8).write(to: file)
        let previous = try DevSnapshotScanner.signature(of: file, includeHash: false)
        let append = Task {
            try await Task.sleep(nanoseconds: 50_000_000)
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("after".utf8))
            try handle.close()
        }

        let stable = await DevSnapshotScanner.isStable(url: file, previous: previous, windowSeconds: 0.2)
        _ = try? await append.value
        XCTAssertFalse(stable)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func expectedResourceIdentifier(of url: URL) throws -> Data {
        let identifier = try XCTUnwrap(url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier)
        if let data = identifier as? Data { return data }
        if let number = identifier as? NSNumber {
            var value = number.uint64Value.bigEndian
            return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
        }
        return Data(String(describing: identifier).utf8)
    }

    private func setExtendedAttribute(name: String, value: Data, at url: URL) throws {
        let result = value.withUnsafeBytes { bytes in
            url.path.withCString { path in
                name.withCString { attributeName in
                    setxattr(path, attributeName, bytes.baseAddress, value.count, 0, XATTR_NOFOLLOW)
                }
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func removeExtendedAttribute(name: String, at url: URL) throws {
        let result = url.path.withCString { path in
            name.withCString { attributeName in
                removexattr(path, attributeName, XATTR_NOFOLLOW)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

nonisolated private struct IncludeAllPolicy: DevPathPolicy {
    func decide(relativePath: String, kind: DevEntryKind, size: Int64, isInsideGitDirectory: Bool) -> DevFilePolicyDecision {
        .include(.defaultInclusion)
    }
}

extension DevSyncScannerTests {
    func testNestedProjectPathsAreCarvedOutOfTheRootUnit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("devsync-nested-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("repo/src"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appendingPathComponent("repo/src/a.swift"))
        try Data("b".utf8).write(to: root.appendingPathComponent("loose.txt"))

        let snapshot = await DevSnapshotScanner.scan(
            projectURL: root,
            policy: ExcludeNodeModulesPolicy(),
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            nestedProjectPaths: ["repo"],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )

        XCTAssertNotNil(snapshot.entries["loose.txt"])
        XCTAssertNil(snapshot.entries["repo"])
        XCTAssertNil(snapshot.entries["repo/src/a.swift"])
        XCTAssertEqual(snapshot.excluded["repo"], .separateProject)
    }
}

nonisolated private struct ExcludeNodeModulesPolicy: DevPathPolicy {
    func decide(relativePath: String, kind: DevEntryKind, size: Int64, isInsideGitDirectory: Bool) -> DevFilePolicyDecision {
        relativePath == "node_modules" ? .exclude(.commonExclusion) : .include(.defaultInclusion)
    }
}

nonisolated private struct ExcludeIgnoredDirectoryPolicy: DevPathPolicy {
    func decide(relativePath: String, kind: DevEntryKind, size: Int64, isInsideGitDirectory: Bool) -> DevFilePolicyDecision {
        relativePath == "ignored" ? .exclude(.commonExclusion) : .include(.defaultInclusion)
    }
}

nonisolated private final class AppendOnDecisionPolicy: @unchecked Sendable, DevPathPolicy {
    private let file: URL
    private let lock = NSLock()
    private var appended = false

    init(file: URL) {
        self.file = file
    }

    func decide(relativePath: String, kind: DevEntryKind, size: Int64, isInsideGitDirectory: Bool) -> DevFilePolicyDecision {
        lock.lock()
        let shouldAppend = relativePath == "changing.txt" && !appended
        appended = appended || shouldAppend
        lock.unlock()
        if shouldAppend, let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("after".utf8))
            try? handle.close()
        }
        return .include(.defaultInclusion)
    }
}
