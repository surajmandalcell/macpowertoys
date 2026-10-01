import Darwin
import AppKit
import XCTest
import SwiftUI
import OnePlusUI
@testable import powertoys

@MainActor
final class SystemCareTests: XCTestCase {
    func testMetricBytesSeparateValueAndUnit() {
        let zero = SystemCareByteMetric(0)
        XCTAssertEqual(zero.value, "0")
        XCTAssertEqual(zero.unit, "KB")

        let kilobyte = SystemCareByteMetric(1_000)
        XCTAssertEqual(kilobyte.value, "1")
        XCTAssertEqual(kilobyte.unit, "KB")
        for (bytes, expected) in [(Int64(366_849_000_000), "366.8"), (113_649_000_000, "113.6"),
                                   (999_940_000_000, "999.9")] {
            let metric = SystemCareByteMetric(bytes)
            XCTAssertEqual(metric.value, expected)
            XCTAssertEqual(metric.unit, "GB")
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let host = NSHostingView(rootView: HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.navRowGap) {
                    Text(metric.value).onePlusText(.metric).fixedSize()
                    Text(metric.unit).onePlusText(.unit).fixedSize()
                }.onePlusDensity(.compact))
                host.appearance = NSAppearance(named: appearance)
                XCTAssertLessThanOrEqual(host.fittingSize.width, (338 - 16 - 2 * 16) / 3)
            }
        }
        XCTAssertEqual(SystemCareByteMetric(999_950_000_000).unit, "TB")
        XCTAssertEqual(SystemCareByteMetric(Int64.max).unit, "EB")
    }

    func testApplicationMetadataUsesFinalUnavailableLabels() {
        let application = InstalledApplication(
            name: "Missing App",
            url: URL(fileURLWithPath: "/path/that/does/not/exist/Missing.app")
        )

        let metadata = SystemCarePresentationRows.application(application)

        XCTAssertEqual(metadata.id, application.id)
        XCTAssertEqual(metadata.size, "Unavailable")
        XCTAssertNotNil(metadata.sizeError)
        XCTAssertEqual(metadata.lastUsed, "Not available")
    }

    func testApplicationIconsKeepOnlyDisplaySizedPixels() throws {
        let icon = try XCTUnwrap(SystemCarePresentationRows.applicationIcon(
            at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        ))
        XCTAssertEqual(icon.width, 80)
        XCTAssertEqual(icon.height, 80)
        XCTAssertLessThanOrEqual(icon.bytesPerRow * icon.height, 80 * 80 * 4)
        let bytes = try XCTUnwrap(icon.dataProvider?.data) as Data
        XCTAssertTrue(bytes.contains { $0 != 0 })
    }

    func testApplicationMetadataRecursivelyCountsAllocatedBundleFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemCareTests-\(UUID().uuidString).app", isDirectory: true)
        let nested = root.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: 8_192).write(to: nested.appendingPathComponent("payload.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let metadata = SystemCarePresentationRows.application(
            InstalledApplication(name: "Test App", url: root)
        )

        XCTAssertNotEqual(metadata.size, "Unavailable")
        XCTAssertNotEqual(metadata.size, "Zero KB")
        XCTAssertNil(metadata.sizeError)

        let link = root.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let linkedMetadata = SystemCarePresentationRows.application(
            InstalledApplication(name: "Linked App", url: link)
        )
        XCTAssertEqual(linkedMetadata.size, "Unavailable")
        XCTAssertEqual(linkedMetadata.sizeError, "Bundle is a symbolic link. Size scanning does not follow links.")
    }

    func testCleanupRejectsUntrustedRootsLinksAndChangedIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let candidate = try fixture.candidate("marker")
        XCTAssertTrue(SystemCareManager.isSafe(candidate, homeDirectory: fixture.home))

        let rootItself = CleanupCandidate(url: fixture.root, allowedRoot: fixture.root, category: .caches, size: 1,
                                         fileIdentity: candidate.rootIdentity, rootIdentity: candidate.rootIdentity)
        XCTAssertFalse(SystemCareManager.isSafe(rootItself, homeDirectory: fixture.home))
        let outsideURL = fixture.home.appendingPathComponent("marker")
        try Data("outside".utf8).write(to: outsideURL)
        let outside = CleanupCandidate(url: outsideURL, allowedRoot: fixture.home, category: .caches, size: 1,
                                       fileIdentity: try SystemCareManager.fileIdentity(at: outsideURL),
                                       rootIdentity: try SystemCareManager.fileIdentity(at: fixture.home))
        XCTAssertFalse(SystemCareManager.isSafe(outside, homeDirectory: fixture.home))
        let wrongCategory = CleanupCandidate(url: candidate.url, allowedRoot: fixture.root, category: .logs,
                                            size: 1, fileIdentity: candidate.fileIdentity, rootIdentity: candidate.rootIdentity)
        XCTAssertFalse(SystemCareManager.isSafe(wrongCategory, homeDirectory: fixture.home))
        let escapeURL = URL(fileURLWithPath: fixture.root.path + "/../Caches/marker")
        let escape = CleanupCandidate(url: escapeURL, allowedRoot: fixture.root, category: .caches, size: 1,
                                      fileIdentity: candidate.fileIdentity, rootIdentity: candidate.rootIdentity)
        XCTAssertFalse(SystemCareManager.isSafe(escape, homeDirectory: fixture.home))
        XCTAssertThrowsError(try SystemCareManager.fileIdentity(at: escapeURL))

        try FileManager.default.moveItem(at: candidate.url, to: fixture.root.appendingPathComponent("original"))
        try Data("replacement".utf8).write(to: candidate.url)
        XCTAssertFalse(SystemCareManager.isSafe(candidate, homeDirectory: fixture.home))
        try FileManager.default.removeItem(at: candidate.url)
        try FileManager.default.createSymbolicLink(at: candidate.url, withDestinationURL: fixture.root.appendingPathComponent("original"))
        XCTAssertFalse(SystemCareManager.isSafe(candidate, homeDirectory: fixture.home))

        let library = fixture.home.appendingPathComponent("Library")
        let movedLibrary = fixture.home.appendingPathComponent("MovedLibrary")
        let fresh = try fixture.candidate("fresh")
        try FileManager.default.moveItem(at: library, to: movedLibrary)
        try FileManager.default.createSymbolicLink(at: library, withDestinationURL: movedLibrary)
        XCTAssertFalse(SystemCareManager.isSafe(fresh, homeDirectory: fixture.home))
    }

    func testSavedCleanupScanRestoresUntilExplicitClear() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let candidate = try fixture.candidate("marker")
        let unverified = CleanupCandidate(url: fixture.root.appendingPathComponent("legacy"),
                                          allowedRoot: fixture.root, category: .caches, size: 512)
        let snapshot = CleanupScanSnapshot(scannedAt: Date(timeIntervalSince1970: 123),
                                           candidates: [candidate, unverified], selectedCandidateIDs: [])
        fixture.defaults.set(try JSONEncoder().encode(snapshot), forKey: SystemCareManager.cleanupScanKey)
        let manager = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home)
        try await waitUntilIdle(manager)

        XCTAssertTrue(manager.hasCleanupScan)
        XCTAssertEqual(manager.cleanupCandidates, [candidate])
        XCTAssertTrue(manager.selectedCandidateIDs.isEmpty)
        manager.setCandidate(candidate.id, selected: true)
        let restored = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home)
        try await waitUntilIdle(restored)
        XCTAssertEqual(restored.selectedCandidateIDs, [candidate.id])
        manager.clearCleanupScan()
        XCTAssertFalse(manager.hasCleanupScan)
        XCTAssertTrue(manager.cleanupCandidates.isEmpty)
        XCTAssertNil(fixture.defaults.data(forKey: SystemCareManager.cleanupScanKey))
    }

    func testTrashFreezesSelectionAndRetainsPartialFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let moved = try fixture.candidate("moved")
        let failed = try fixture.candidate("failed")
        let untouched = try fixture.candidate("untouched")
        let snapshot = CleanupScanSnapshot(scannedAt: Date(), candidates: [moved, failed, untouched],
                                           selectedCandidateIDs: [moved.id, failed.id])
        fixture.defaults.set(try JSONEncoder().encode(snapshot), forKey: SystemCareManager.cleanupScanKey)
        let started = expectation(description: "Trash worker started")
        let release = DispatchSemaphore(value: 0)
        let manager = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home) { url in
            if url == moved.url {
                started.fulfill()
                guard release.wait(timeout: .now() + 3) == .success else { throw CancellationError() }
                try FileManager.default.removeItem(at: url)
            } else {
                throw NSError(domain: "SystemCareTests", code: 1)
            }
        }
        try await waitUntilIdle(manager)
        manager.moveSelectedToTrash()
        await fulfillment(of: [started], timeout: 2)
        manager.setCandidate(moved.id, selected: false)
        manager.setCandidate(untouched.id, selected: true)
        manager.setCandidates([moved.id, failed.id], selected: false)
        manager.clearCleanupScan()
        manager.moveSelectedToTrash()
        manager.cancel()
        manager.refresh()
        manager.scanCleanup(categories: [.caches])
        manager.analyze(fixture.home)
        manager.loadHistory()
        manager.installOrUpdateMole()
        XCTAssertTrue(manager.isWorking)
        XCTAssertFalse(manager.canCancel)
        XCTAssertEqual(manager.selectedCandidateIDs, [moved.id, failed.id])
        release.signal()
        try await waitUntilIdle(manager)

        XCTAssertEqual(manager.cleanupCandidates.map(\.id), [failed.id, untouched.id])
        XCTAssertEqual(manager.selectedCandidateIDs, [failed.id])
        XCTAssertEqual(manager.lastTrashResult?.movedCount, 1)
        XCTAssertEqual(manager.lastTrashResult?.movedBytes, moved.size)
        XCTAssertEqual(manager.lastTrashResult?.failures.map(\.id), [failed.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: untouched.url.path))
        let restored = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home)
        try await waitUntilIdle(restored)
        XCTAssertEqual(restored.cleanupCandidates.map(\.id), [failed.id, untouched.id])
    }

    func testCancellationWaitsForDetachedWorkerExit() async throws {
        let started = expectation(description: "Worker started")
        let canceled = expectation(description: "Worker received cancellation")
        var finished = false
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            defer { finished = true }
            do {
                _ = try await SystemCareManager.runWorker {
                    started.fulfill()
                    while !Task.isCancelled { usleep(1_000) }
                    canceled.fulfill()
                    _ = { release.wait(timeout: .now() + 3) }()
                    try Task.checkCancellation()
                    return true
                }
                XCTFail("Canceled worker returned a result")
            } catch is CancellationError {
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [canceled], timeout: 2)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(finished, "Cancellation must wait for the worker to exit")
        release.signal()
        await task.value
        XCTAssertTrue(finished)
    }

    func testCleanupCoverageReportsLimitsMissingRootsAndPackages() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.candidate("a")
        _ = try fixture.candidate("b")
        let package = fixture.root.appendingPathComponent("z.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let payload = package.appendingPathComponent("payload")
        try Data(repeating: 0xA5, count: 16_384).write(to: payload)
        let values = try payload.resourceValues(forKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey])
        let expected = try XCTUnwrap(values.totalFileAllocatedSize ?? values.fileAllocatedSize)
        XCTAssertEqual(try SystemCareManager.allocatedSize(of: fixture.root.appendingPathComponent("z.app")), Int64(expected))

        let bounded = try SystemCareManager.cleanupReport(for: [.caches], homeDirectory: fixture.home, childLimit: 2)
        XCTAssertEqual(bounded.candidates.count, 2)
        XCTAssertEqual(bounded.coverage.first?.examinedCount, 2)
        XCTAssertEqual(bounded.coverage.first?.isTruncated, true)
        XCTAssertEqual(bounded.outcome, .partial)
        let complete = try SystemCareManager.cleanupReport(for: [.caches], homeDirectory: fixture.home)
        XCTAssertEqual(complete.outcome, .completed)
        XCTAssertEqual(complete.candidates.count, 3)
        let partial = try SystemCareManager.cleanupReport(for: [.caches, .logs], homeDirectory: fixture.home)
        XCTAssertEqual(partial.outcome, .partial)
        XCTAssertEqual(partial.coverage.last?.issues.first?.kind, .missing)
        XCTAssertEqual(partial.candidates.count, 3)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("link"), withDestinationURL: payload)
        let linked = try SystemCareManager.cleanupReport(for: [.caches], homeDirectory: fixture.home)
        XCTAssertEqual(linked.coverage.first?.issues.first?.kind, .unsafePath)
        XCTAssertEqual(linked.candidates.count, 3)
        XCTAssertEqual(SystemCareFileIssue(url: fixture.root, error: NSError(domain: NSPOSIXErrorDomain, code: 13)).kind, .accessDenied)
        XCTAssertEqual(SystemCareFileIssue(url: fixture.root, error: NSError(domain: NSPOSIXErrorDomain, code: 5)).kind, .io)
    }

    func testRetryScansOnlyAffectedRootsAndKeepsSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let candidate = try fixture.candidate("marker")
        let manager = SystemCareManager(defaults: fixture.defaults, homeDirectory: fixture.home)
        manager.scanCleanup(categories: [.caches, .logs])
        try await waitUntilIdle(manager)
        XCTAssertEqual(manager.cleanupScanOutcome, .partial)
        manager.setCandidate(candidate.id, selected: false)
        let logs = SystemCareManager.cleanupRoot(for: .logs, homeDirectory: fixture.home)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("marker.log")
        try Data("log".utf8).write(to: log)
        manager.retryCleanupScan()
        try await waitUntilIdle(manager)
        XCTAssertEqual(manager.cleanupScanOutcome, .completed)
        XCTAssertEqual(Set(manager.cleanupCandidates.map(\.id)), [candidate.id, log.path])
        XCTAssertEqual(manager.selectedCandidateIDs, [log.path])

        manager.analyze(logs, resetBreadcrumbs: true)
        try await waitUntilIdle(manager)
        XCTAssertFalse(manager.storageCountIsFiles)
        manager.analyze(fixture.home.appendingPathComponent("missing"))
        try await waitUntilIdle(manager)
        XCTAssertEqual(manager.storageURL, logs)
        XCTAssertEqual(manager.storageBreadcrumbs, [logs])
        XCTAssertEqual(manager.storageIssue?.kind, .missing)
    }

    private func waitUntilIdle(_ manager: SystemCareManager) async throws {
        let deadline = Date().addingTimeInterval(4)
        while manager.isWorking, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(manager.isWorking)
    }

    func testMoleReadsBoundOutputTimeoutAndCancellation() async throws {
        do {
            _ = try await SystemCareManager.runWorker {
                try SystemCareManager.run(executable: URL(fileURLWithPath: "/usr/bin/yes"),
                                          arguments: [], timeout: 2, maximumOutputBytes: 8_192)
            }
            XCTFail("Oversized output was accepted")
        } catch { XCTAssertEqual(error as? SystemCareCommandError, .outputLimit) }
        let startedAt = Date()
        do {
            _ = try await SystemCareManager.runWorker {
                try SystemCareManager.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                          arguments: ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.1)
            }
            XCTFail("Stalled command was accepted")
        } catch { XCTAssertEqual(error as? SystemCareCommandError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)

        let fixture = try Fixture()
        defer { fixture.remove() }
        let pidFile = fixture.home.appendingPathComponent("child.pid")
        let task = Task {
            try await SystemCareManager.runWorker {
                try SystemCareManager.run(executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "echo $$ > \"$1\"; trap '' TERM; while :; do :; done", "fixture", pidFile.path], timeout: 3)
            }
        }
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: pidFile.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pidText = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(Int32(pidText))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Canceled command was accepted")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testUninstallRequiresOneExactNativeAndMoleBundle() throws {
        let selected = InstalledApplication(name: "Same", url: URL(fileURLWithPath: "/Applications/Same.app"))
        let duplicate = InstalledApplication(name: "same", url: URL(fileURLWithPath: "/Users/fixture/Applications/same.app"))
        XCTAssertNil(SystemCareManager.uninstallRefusal(for: selected, applications: [selected]))
        XCTAssertNotNil(SystemCareManager.uninstallRefusal(for: selected, applications: [selected, duplicate]))
        XCTAssertNotNil(SystemCareManager.uninstallRefusal(for: selected, applications: [duplicate]))
        for name in ["Glob*App", "Glob?App", "Glob[App", "Glob\\App", "-Option"] {
            let unsafe = InstalledApplication(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
            XCTAssertNotNil(SystemCareManager.uninstallRefusal(for: unsafe, applications: [unsafe]))
        }
        let exact = Data(#"[{"name":"Same","path":"/Applications/Same.app"}]"#.utf8)
        XCTAssertEqual(try SystemCareManager.validatedUninstallName(for: selected, inventory: exact), "Same")
        let ambiguous = Data(#"[{"name":"Same","path":"/Applications/Same.app"},{"name":"Same","path":"/Volumes/Fixture/Applications/Same.app"}]"#.utf8)
        XCTAssertThrowsError(try SystemCareManager.validatedUninstallName(for: selected, inventory: ambiguous))
        let wrongBundle = Data(#"[{"name":"Same","path":"/Volumes/Fixture/Applications/Same.app"}]"#.utf8)
        XCTAssertThrowsError(try SystemCareManager.validatedUninstallName(for: selected, inventory: wrongBundle))
        XCTAssertThrowsError(try SystemCareManager.validatedUninstallName(for: selected, inventory: Data("[]".utf8)))
    }

    func testMoleHistoryParsesNestedCountsTargetsAndOptionalMetadata() throws {
        let data = Data(#"""
        {
          "sessions": [
            {
              "command": "uninstall", "started_at": "2026-10-01 07:00:00", "ended_at": "",
              "items": 3, "size": "92 MB", "operation_count": 5, "failed_tasks": 1,
              "actions": {"removed": 2, "trashed": 0, "skipped": 0, "failed": 1, "rebuilt": 0, "other": 0}
            },
            {"command": "optimize", "actions": {"removed": true, "failed": -1, "other": 2.5}},
            {"command": "clean", "operation_count": 1, "started_at": "", "ended_at": "2026-10-01 08:00:00"}
          ],
          "deletions": [
            {"timestamp": "2026-10-01 07:00:01", "mode": "trash", "status": "TRASHED", "size_kb": 1024, "path": "/Applications/Fixture.app"},
            {"mode": "delete", "status": null, "size_kb": null, "path": "/tmp/Fixture\nSecond.dmg"}
          ]
        }
        """#.utf8)
        let rows = try SystemCareManager.parseMoleHistory(data)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].title, "uninstall")
        XCTAssertEqual(rows[0].detail, "3 items · 92 MB")
        XCTAssertEqual(rows[0].timestamp, "2026-10-01 07:00:00")
        XCTAssertEqual(rows[0].result, "2 removed, 1 failed, 1 task failed")
        XCTAssertFalse(rows[0].detail.contains("actions:"))
        XCTAssertTrue(rows.allSatisfy { !$0.detail.contains("\n") })
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rows[0].rawPayload.utf8)) as? [String: Any])
        XCTAssertEqual((raw["actions"] as? [String: Any])?["removed"] as? Int, 2)
        XCTAssertEqual(rows[1].detail, "")
        XCTAssertNil(rows[1].timestamp)
        XCTAssertNil(rows[1].result)
        XCTAssertEqual(rows[2].detail, "1 operation")
        XCTAssertEqual(rows[2].timestamp, "2026-10-01 08:00:00")
        XCTAssertNil(rows[2].result)
        XCTAssertEqual(rows[3].title, "trash")
        XCTAssertEqual(rows[3].detail, "/Applications/Fixture.app")
        XCTAssertEqual(rows[3].timestamp, "2026-10-01 07:00:01")
        XCTAssertEqual(rows[3].result, "TRASHED")
        XCTAssertEqual(rows[4].title, "delete")
        XCTAssertEqual(rows[4].detail, "/tmp/Fixture Second.dmg")
        XCTAssertNil(rows[4].timestamp)
        XCTAssertNil(rows[4].result)
        XCTAssertTrue(try SystemCareManager.parseMoleHistory(Data("{}".utf8)).isEmpty)
        XCTAssertThrowsError(try SystemCareManager.parseMoleHistory(Data("[]".utf8)))
        XCTAssertThrowsError(try SystemCareManager.parseMoleHistory(Data(#"{"sessions":false}"#.utf8)))
    }

    private struct Fixture {
        let home: URL
        let suite = "SystemCareTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var root: URL { SystemCareManager.cleanupRoot(for: .caches, homeDirectory: home) }

        init() throws {
            guard let physicalPath = realpath(FileManager.default.temporaryDirectory.path, nil) else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            let temporaryDirectory = URL(fileURLWithPath: String(cString: physicalPath), isDirectory: true)
            free(physicalPath)
            home = temporaryDirectory.appendingPathComponent("SystemCareTests-\(UUID().uuidString)", isDirectory: true)
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func candidate(_ name: String) throws -> CleanupCandidate {
            let url = root.appendingPathComponent(name)
            try Data(repeating: 0xA5, count: 8_192).write(to: url)
            return CleanupCandidate(url: url, allowedRoot: root, category: .caches, size: 8_192,
                                    fileIdentity: try SystemCareManager.fileIdentity(at: url),
                                    rootIdentity: try SystemCareManager.fileIdentity(at: root))
        }

        func remove() {
            try? FileManager.default.removeItem(at: home)
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
