//
//  RcloneEngineTests.swift
//  powertoysTests
//

import XCTest
@testable import powertoys

@MainActor
final class RcloneEngineTests: XCTestCase {
    private let managedKeys = [
        RcloneDefaults.ignorePatternsKey,
        RcloneDefaults.binaryPathKey,
        RcloneDefaults.maxRetriesKey,
        RcloneDefaults.retryBackoffKey,
        RcloneDefaults.transfersKey,
        RcloneDefaults.bandwidthLimitKey,
        RcloneDefaults.maxConcurrentJobsKey
    ]
    private var savedDefaults: [String: Any?] = [:]

    override func setUp() {
        for key in managedKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        try? FileManager.default.removeItem(at: AppDataLocation.transfersURL)
    }

    override func tearDown() {
        for key in managedKeys {
            if let value = savedDefaults[key] ?? nil {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return condition()
    }

    func testCopyAppliesIgnorePatternsAndCompletes() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rclone-test-\(UUID().uuidString)")
        let src = root.appendingPathComponent("src")
        let dst = root.appendingPathComponent("dst")
        try fm.createDirectory(at: src.appendingPathComponent("keep"), withIntermediateDirectories: true)
        try fm.createDirectory(at: src.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: src.appendingPathComponent("keep/a.txt"))
        try Data("junk".utf8).write(to: src.appendingPathComponent("node_modules/b.txt"))
        try Data("ds".utf8).write(to: src.appendingPathComponent(".DS_Store"))
        defer { try? fm.removeItem(at: root) }

        UserDefaults.standard.set("node_modules/**\n.DS_Store", forKey: RcloneDefaults.ignorePatternsKey)
        UserDefaults.standard.set(2, forKey: RcloneDefaults.maxRetriesKey)

        let manager = RcloneJobManager()
        await manager.start()
        addTeardownBlock { await manager.shutdown() }

        let healthy = await waitFor(15) { manager.daemonIsHealthy }
        XCTAssertTrue(healthy, "daemon should become healthy — status: \(manager.daemonStatusText)")

        manager.createTransfer(
            operation: .copy,
            sourceFs: src.path,
            destinationFs: dst.path,
            sourceDisplay: "src",
            destinationDisplay: "dst",
            extraExcludes: []
        )

        let completed = await waitFor(30) { manager.jobs.first?.state == .completed }
        XCTAssertTrue(completed, "copy should complete — state: \(String(describing: manager.jobs.first?.state)), error: \(manager.jobs.first?.errorMessage ?? "nil")")

        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("keep/a.txt").path), "kept file should be copied")
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("node_modules/b.txt").path), "node_modules/** should be excluded")
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent(".DS_Store").path), ".DS_Store should be excluded")
    }

    func testListDirectoryAndSingleFileTransfer() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rclone-browse-\(UUID().uuidString)")
        let src = root.appendingPathComponent("src")
        let dst = root.appendingPathComponent("dst")
        try fm.createDirectory(at: src.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("solo file".utf8).write(to: src.appendingPathComponent("solo.txt"))
        defer { try? fm.removeItem(at: root) }

        let manager = RcloneJobManager()
        await manager.start()
        addTeardownBlock { await manager.shutdown() }

        let healthy = await waitFor(15) { manager.daemonIsHealthy }
        XCTAssertTrue(healthy, "daemon should become healthy")

        let entries = try await manager.listDirectory(fs: src.path, path: "")

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.first?.isDir == true, "directories sort first")
        XCTAssertEqual(entries.first?.name, "folder")
        XCTAssertEqual(entries.last?.name, "solo.txt")
        XCTAssertNotNil(entries.last?.modTime, "mod time should parse")

        manager.createTransfer(
            operation: .copy,
            kind: .file,
            sourceFs: src.appendingPathComponent("solo.txt").path,
            destinationFs: dst.appendingPathComponent("solo.txt").path,
            sourceDisplay: "solo.txt",
            destinationDisplay: "dst/solo.txt",
            extraExcludes: []
        )

        let completed = await waitFor(20) { manager.jobs.first?.state == .completed }
        XCTAssertTrue(completed, "file transfer should complete — \(manager.jobs.first?.errorMessage ?? "")")
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("solo.txt").path))
    }

    func testUnknownRemoteFailsFastWithoutBurningRetries() async throws {
        UserDefaults.standard.set(3, forKey: RcloneDefaults.maxRetriesKey)
        UserDefaults.standard.set(2.0, forKey: RcloneDefaults.retryBackoffKey)

        let manager = RcloneJobManager()
        await manager.start()
        addTeardownBlock { await manager.shutdown() }

        let healthy = await waitFor(15) { manager.daemonIsHealthy }
        XCTAssertTrue(healthy, "daemon should become healthy — status: \(manager.daemonStatusText)")

        manager.createTransfer(
            operation: .copy,
            sourceFs: "nonexistent-remote-xyz:",
            destinationFs: FileManager.default.temporaryDirectory.path,
            sourceDisplay: "bad",
            destinationDisplay: "tmp",
            extraExcludes: []
        )

        let failed = await waitFor(15) { manager.jobs.first?.state == .failed }
        XCTAssertTrue(failed, "unknown remote should fail — state: \(String(describing: manager.jobs.first?.state))")
        XCTAssertEqual(manager.jobs.first?.attempt, 0, "a permanent config error must not consume the retry budget")
    }
}
