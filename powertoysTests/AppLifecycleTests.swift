import XCTest
import SwiftData
@testable import powertoys

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testShutdownDeadlineKeepsOneOperationAndAllowsRetryAfterFailure() async throws {
        let stage = AppShutdownStage()
        var release: CheckedContinuation<Void, Never>?
        var attempts = 0
        var finished = false
        var wasCancelled = false
        var heartbeat = false
        let tick = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(2))
            heartbeat = true
        }
        let started = ContinuousClock.now
        do {
            try await stage.run(name: "Fan Auto", timeout: .milliseconds(20)) {
                attempts += 1
                defer { finished = true }
                await withCheckedContinuation { release = $0 }
                wasCancelled = Task.isCancelled
                try Task.checkCancellation()
            }
            XCTFail("An unfinished operation must cancel quit")
        } catch {
            XCTAssertEqual((error as NSError).code, 2)
            XCTAssertTrue(error.localizedDescription.contains("Fan Auto"))
        }
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        try await tick.value
        XCTAssertTrue(heartbeat)
        do {
            try await stage.run(name: "Fan Auto", timeout: .milliseconds(20)) { attempts += 1 }
            XCTFail("Retry must wait for the unfinished operation")
        } catch {
            XCTAssertEqual((error as NSError).code, 2)
        }
        XCTAssertEqual(attempts, 1)
        release?.resume()
        while !finished { await Task.yield() }
        XCTAssertTrue(wasCancelled)
        do {
            try await stage.run(name: "Saving", timeout: .seconds(1)) {
                attempts += 1
                throw NSError(domain: "SaveFailure", code: 7,
                              userInfo: [NSLocalizedDescriptionKey: "Disk is full"])
            }
            XCTFail("A save failure must cancel quit")
        } catch {
            XCTAssertEqual((error as NSError).code, 1)
            XCTAssertTrue(error.localizedDescription.contains("Disk is full"))
        }
        try await stage.run(name: "Saving", timeout: .seconds(1)) { attempts += 1 }
        XCTAssertEqual(attempts, 3)
    }

    func testFailedStoreOpenPreservesFilesAndRetryUsesExistingData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let original = try AppModelStore.createContainer(at: url)
        original.mainContext.insert(LogEntry(level: 0, source: "test", message: "Keep this record"))
        try original.mainContext.save()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let before = try files.map { try Data(contentsOf: $0) }
        let store = AppModelStore()

        await store.open {
            throw NSError(domain: "InjectedStoreFailure", code: 17,
                          userInfo: [NSLocalizedDescriptionKey: "The store could not be opened."])
        }

        XCTAssertNil(store.container)
        XCTAssertTrue(store.showsRecovery)
        XCTAssertFalse(store.isOpening)
        XCTAssertTrue(store.errorMessage?.contains("InjectedStoreFailure (17)") == true)
        XCTAssertEqual(try files.map { try Data(contentsOf: $0) }, before)
        await store.open { try AppModelStore.createContainer(at: url) }
        let reopened = try XCTUnwrap(store.container)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.showsRecovery)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<LogEntry>()).map(\.message), ["Keep this record"])
    }
}
