import Foundation
import XCTest
@testable import powertoys

@MainActor
final class ToolSettingsPreferenceObserverTests: XCTestCase {
    func testOnlyWatchedPreferenceChangesNotifyAndStopRemovesObservers() async throws {
        let suite = "ToolSettingsPreferenceObserverTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var changes = 0
        var signal: XCTestExpectation?
        var observer: ToolSettingsPreferenceObserver? = ToolSettingsPreferenceObserver(
            keys: ["awake.configuration.v1", "plainKey"], defaults: defaults
        ) { changes += 1; signal?.fulfill() }
        weak let weakObserver = observer

        defaults.set(true, forKey: "unrelated")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(changes, 0)
        signal = expectation(description: "Watched data preference changed")
        defaults.set(Data([1]), forKey: "awake.configuration.v1")
        await fulfillment(of: [signal!], timeout: 1)
        signal = nil
        XCTAssertEqual(changes, 1)
        defaults.set(Data([1]), forKey: "awake.configuration.v1")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(changes, 1, "Writing the same value must not refresh the main window.")
        signal = expectation(description: "Watched plain preference changed")
        defaults.set("new", forKey: "plainKey")
        await fulfillment(of: [signal!], timeout: 1)
        signal = nil
        XCTAssertEqual(changes, 2)
        observer?.stop()
        defaults.set(Data([2]), forKey: "awake.configuration.v1")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(changes, 2)
        observer = nil
        XCTAssertNil(weakObserver)
    }
}
