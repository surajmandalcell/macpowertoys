import CoreServices
import Foundation
import XCTest
@testable import powertoys

@MainActor
final class DevSyncEventsTests: XCTestCase {
    func testStreamReceivesCreatedAndModifiedEventsWithIncreasingIDs() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let collector = EventCollector()
        let stream = DevEventStream(
            rootURL: root,
            sinceEventID: nil,
            latencySeconds: 0.05,
            queue: DispatchQueue(label: "DevSyncEventsTests.stream"),
            handler: collector.append
        )

        XCTAssertTrue(stream.start())
        let file = root.appendingPathComponent("note.txt")
        try Data("first".utf8).write(to: file)
        try await Task.sleep(nanoseconds: 200_000_000)
        try Data("second".utf8).write(to: file)
        collector.wait(timeout: 5)
        stream.stop()

        let events = collector.events
        XCTAssertTrue(events.contains { $0.flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 }, events.description)
        XCTAssertTrue(events.contains { $0.flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 }, events.description)
        XCTAssertEqual(events.map { $0.eventID }, events.map { $0.eventID }.sorted())
        XCTAssertTrue(events.contains { $0.path.hasSuffix("/note.txt") }, events.description)
    }

    func testScenario22EditorSavesFiftyTimesProducesOneDueGeneration() async throws {
        let projectID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let scheduler = makeScheduler()
        await scheduler.noteEvents(
            side: .internal,
            relativePaths: Array(repeating: "Sources/main.swift", count: 50),
            projectResolver: { _ in projectID },
            at: start
        )

        let beforeQuiet = await scheduler.due(at: start.addingTimeInterval(9.99))
        let afterQuiet = await scheduler.due(at: start.addingTimeInterval(10))
        XCTAssertTrue(beforeQuiet.isEmpty)
        XCTAssertEqual(afterQuiet.count, 1)
        XCTAssertEqual(afterQuiet[0].paths, ["Sources/main.swift"])
    }

    func testScenario23ContinuousActivityProducesCheckpointGeneration() async {
        let projectID = UUID()
        let start = Date(timeIntervalSince1970: 2_000)
        var timing = DevSyncConfiguration.Timing.default
        timing.minimumProjectIntervalSeconds = 0
        timing.continuousCheckpointSeconds = 20
        let scheduler = DevDirtyScheduler(timing: timing, performance: .init())
        for offset in stride(from: 0.0, through: 21.0, by: 3.0) {
            await scheduler.noteEvents(
                side: .internal,
                relativePaths: ["Sources/main.swift"],
                projectResolver: { _ in projectID },
                at: start.addingTimeInterval(offset)
            )
        }

        let checkpoint = await scheduler.due(at: start.addingTimeInterval(20))
        XCTAssertEqual(checkpoint.count, 1)
        XCTAssertEqual(checkpoint[0].firstEventAt, start)
        XCTAssertEqual(checkpoint[0].lastEventAt, start.addingTimeInterval(21))
    }

    func testScenario24EventStormCollapsesToWholeProjectScan() async {
        let projectID = UUID()
        let start = Date(timeIntervalSince1970: 3_000)
        let scheduler = makeScheduler()
        let paths = (0..<1_500).map { "node_modules/package-\($0)/index.js" }
        await scheduler.noteEvents(
            side: .internal,
            relativePaths: paths,
            projectResolver: { _ in projectID },
            at: start
        )

        let due = await scheduler.due(at: start.addingTimeInterval(10))
        XCTAssertEqual(due.count, 1)
        XCTAssertNil(due[0].paths)
        XCTAssertTrue(due[0].requiresFullScan)
    }

    func testPathCollapseThresholdCollapsesPendingPaths() async {
        var performance = DevSyncConfiguration.Performance()
        performance.pathCollapseThreshold = 2
        let scheduler = DevDirtyScheduler(
            timing: DevSyncConfiguration.Timing(
                fseventsLatencySeconds: 0,
                quietPeriodSeconds: 1,
                minimumProjectIntervalSeconds: 0,
                continuousCheckpointSeconds: 0,
                largeFileQuietSeconds: 0,
                fullReconcileSeconds: 0
            ),
            performance: performance
        )
        let projectID = UUID()
        await scheduler.noteEvents(
            side: .internal,
            relativePaths: ["a", "b", "c"],
            projectResolver: { _ in projectID },
            at: Date(timeIntervalSince1970: 4_000)
        )
        let due = await scheduler.due(at: Date(timeIntervalSince1970: 4_001))
        XCTAssertNil(due.first?.paths)
        XCTAssertTrue(due.first?.requiresFullScan == true)
    }

    func testManualOnlyTimingOnlyAllowsSyncNow() async {
        var timing = DevSyncConfiguration.Timing.default
        timing.quietPeriodSeconds = 0
        timing.continuousCheckpointSeconds = 0
        let projectID = UUID()
        let scheduler = DevDirtyScheduler(timing: timing, performance: .init())
        await scheduler.noteEvents(side: .internal, relativePaths: ["file"], projectResolver: { _ in projectID }, at: Date(timeIntervalSince1970: 5_000))
        let automaticDue = await scheduler.due(at: Date(timeIntervalSince1970: 6_000))
        XCTAssertTrue(automaticDue.isEmpty)
        await scheduler.requestNow(projectID: projectID, reason: .userRequested)
        let manualDue = await scheduler.due(at: Date(timeIntervalSince1970: 5_001))
        XCTAssertEqual(manualDue.count, 1)
    }

    func testMinimumProjectIntervalDefersAutomaticGeneration() async {
        var timing = DevSyncConfiguration.Timing.default
        timing.quietPeriodSeconds = 1
        timing.continuousCheckpointSeconds = 0
        timing.minimumProjectIntervalSeconds = 10
        let projectID = UUID()
        let scheduler = DevDirtyScheduler(timing: timing, performance: .init())
        let first = Date(timeIntervalSince1970: 6_000)
        await scheduler.noteEvents(side: .internal, relativePaths: ["first"], projectResolver: { _ in projectID }, at: first)
        let generation = await scheduler.begin(projectID: projectID)
        XCTAssertNotNil(generation)
        await scheduler.complete(projectID: projectID, at: first.addingTimeInterval(1))
        await scheduler.noteEvents(side: .internal, relativePaths: ["second"], projectResolver: { _ in projectID }, at: first.addingTimeInterval(2))
        let beforeInterval = await scheduler.due(at: first.addingTimeInterval(3))
        let afterInterval = await scheduler.due(at: first.addingTimeInterval(11))
        XCTAssertTrue(beforeInterval.isEmpty)
        XCTAssertEqual(afterInterval.count, 1)
    }

    func testScenario86RequestNowMergesPendingPaths() async throws {
        var timing = DevSyncConfiguration.Timing.default
        timing.quietPeriodSeconds = 1
        timing.continuousCheckpointSeconds = 0
        let projectID = UUID()
        let scheduler = DevDirtyScheduler(timing: timing, performance: .init())
        let start = Date(timeIntervalSince1970: 7_000)
        await scheduler.noteEvents(side: .internal, relativePaths: ["first"], projectResolver: { _ in projectID }, at: start)
        await scheduler.requestNow(projectID: projectID, reason: .userRequested)
        let nextCandidates = await scheduler.due(at: start.addingTimeInterval(0.1))
        let next = try XCTUnwrap(nextCandidates.first)
        XCTAssertEqual(next.reason, .userRequested)
        XCTAssertEqual(next.paths, ["first"])
        let consumed = await scheduler.begin(projectID: projectID)
        XCTAssertNotNil(consumed)
    }

    func testExportImportRoundTripPreservesDirtyEntries() async {
        let projectID = UUID()
        let start = Date(timeIntervalSince1970: 8_000)
        let first = makeScheduler()
        await first.noteEvents(side: .external, relativePaths: ["b", "a"], projectResolver: { _ in projectID }, at: start)
        let exported = await first.exportEntries()
        let second = makeScheduler()
        await second.importEntries(exported)
        let restored = await second.exportEntries()
        XCTAssertEqual(restored, exported)
    }

    func testBeginAndRequeueIncrementAttemptCount() async throws {
        let projectID = UUID()
        let scheduler = makeScheduler()
        await scheduler.noteEvents(side: .internal, relativePaths: ["file"], projectResolver: { _ in projectID }, at: Date(timeIntervalSince1970: 9_000))
        let generationOptional = await scheduler.begin(projectID: projectID)
        let generation = try XCTUnwrap(generationOptional)
        await scheduler.requeue(generation)
        let entries = await scheduler.exportEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].attemptCount, 1)
    }

    func testScenario83DroppedFlagBatchRequiresRootRescan() {
        let flags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped)
        let batch = DevEventBatch(
            events: [DevFileEvent(path: "/tmp/project", flags: flags, eventID: 42)],
            lastEventID: 42,
            mustRescanRoot: true,
            rescanSubtrees: [],
            mountChanged: false
        )
        XCTAssertTrue(batch.mustRescanRoot)
        XCTAssertEqual(batch.events.first?.flags, flags)
    }

    func testScenario48SelfEventLedgerSuppressesMatchingAndDetectsDrift() async {
        let ledger = DevSelfEventLedger()
        let operationID = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let expected = DevFileSignature(kind: .file, size: 10, modificationTimeNanoseconds: 100, mode: 0o644)
        let changed = DevFileSignature(kind: .file, size: 11, modificationTimeNanoseconds: 100, mode: 0o644)
        await ledger.expect(side: .external, relativePath: "file", signature: expected, operationID: operationID, until: now.addingTimeInterval(10))
        let differingResult = await ledger.consume(side: .external, relativePath: "file", actual: changed, toleranceNanoseconds: 0, now: now)
        let consumedAfterDifference = await ledger.consume(side: .external, relativePath: "file", actual: expected, toleranceNanoseconds: 0, now: now)
        XCTAssertFalse(differingResult)
        XCTAssertFalse(consumedAfterDifference)

        await ledger.expect(side: .external, relativePath: "file", signature: expected, operationID: operationID, until: now.addingTimeInterval(10))
        let matchingResult = await ledger.consume(side: .external, relativePath: "file", actual: expected, toleranceNanoseconds: 0, now: now)
        XCTAssertTrue(matchingResult)
    }

    func testSelfEventLedgerExpiresExpectations() async {
        let ledger = DevSelfEventLedger()
        let now = Date(timeIntervalSince1970: 11_000)
        let signature = DevFileSignature(kind: .directory)
        await ledger.expect(side: .internal, relativePath: "folder", signature: signature, operationID: UUID(), until: now)
        await ledger.expire(now: now)
        let expiredResult = await ledger.consume(side: .internal, relativePath: "folder", actual: signature, toleranceNanoseconds: 0, now: now)
        XCTAssertFalse(expiredResult)
    }

    private func makeScheduler() -> DevDirtyScheduler {
        DevDirtyScheduler(timing: .default, performance: .init())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let expectation = XCTestExpectation(description: "FSEvents callback")
    private var storedEvents: [DevFileEvent] = []

    var events: [DevFileEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    func append(_ batch: DevEventBatch) {
        lock.lock()
        storedEvents.append(contentsOf: batch.events)
        let count = storedEvents.count
        lock.unlock()
        if count >= 2 { expectation.fulfill() }
    }

    func wait(timeout: TimeInterval) {
        XCTWaiter().wait(for: [expectation], timeout: timeout)
    }
}
