import XCTest
import SwiftData
@testable import powertoys

@MainActor
final class AppLifecycleTests: XCTestCase {
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
