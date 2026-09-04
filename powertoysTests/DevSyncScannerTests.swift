import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import powertoys

@MainActor
final class DevSyncScannerTests: XCTestCase {
    func testSignatureCapturesFileDirectorySymlinkExecutableModeAndNanosecondMtime() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
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

    func testHashOfThreeMiBFileMatchesCryptoKit() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data((0..<3 * 1_024 * 1_024).map { UInt8($0 % 251) })
        let file = root.appendingPathComponent("large.bin")
        try data.write(to: file)

        XCTAssertEqual(try DevSnapshotScanner.hash(url: file), Data(SHA256.hash(data: data)))
        XCTAssertEqual(try DevSnapshotScanner.signature(of: file, includeHash: true).contentHash, Data(SHA256.hash(data: data)))
    }

    func testScanSkipsSystemAndSymlinkedDirectoriesAndRecordsExcludedBytes() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
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

    func testExcludedDirectoryIsNotDescendedAndLimitRestrictsPathsToAncestors() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
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

    func testScenario35CaseCollisionAndScenario36UnicodeNormalization() {
        XCTAssertEqual(DevSnapshotScanner.collisions(paths: ["Foo.swift", "foo.swift"], caseInsensitive: true), [["Foo.swift", "foo.swift"]])
        let composed = "caf\u{00E9}.txt"
        let decomposed = "cafe\u{0301}.txt"
        XCTAssertEqual(DevSnapshotScanner.collisions(paths: [composed, decomposed], caseInsensitive: false), [[composed, decomposed].sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }])
    }

    func testManifestAddsAncestorsAndSortsByUTF8Bytes() {
        let manifest = DevSnapshotScanner.manifest(paths: ["a-b/file", "a b/file", "deep/path/name"])
        XCTAssertEqual(manifest, ["a b", "a b/file", "a-b", "a-b/file", "deep", "deep/path", "deep/path/name"])
    }

    func testScenario47VerifyRejectsSizeMtimeAndHashChanges() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
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
        try Data("changed!".utf8).write(to: destination)
        XCTAssertFalse(try DevSnapshotScanner.verify(plannedSource: planned, destinationURL: destination, toleranceNanoseconds: Int64.max, compareMode: false, requireHash: true))
    }

    func testIsStableDetectsAppendAcrossStabilityWindow() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
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
        return url
    }
}

private struct ExcludeNodeModulesPolicy: DevPathPolicy {
    func decide(relativePath: String, kind: DevEntryKind, size: Int64, isInsideGitDirectory: Bool) -> DevFilePolicyDecision {
        relativePath == "node_modules" ? .exclude(.commonExclusion) : .include(.defaultInclusion)
    }
}

private struct ExcludeIgnoredDirectoryPolicy: DevPathPolicy {
    func decide(relativePath: String, kind: DevEntryKind, size: Int64, isInsideGitDirectory: Bool) -> DevFilePolicyDecision {
        relativePath == "ignored" ? .exclude(.commonExclusion) : .include(.defaultInclusion)
    }
}
