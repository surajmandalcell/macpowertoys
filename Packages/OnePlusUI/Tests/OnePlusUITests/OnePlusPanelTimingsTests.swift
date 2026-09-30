import AppKit
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusPanelTimingsTests: XCTestCase {
    func testTimingsRequireTheDestinationAndKeepOnlyFiftyCompletedFrames() throws {
        let timings = OnePlusPanelTimings()
        timings.begin(panel: "main", tab: "home", input: "mouseDown", started: 10)
        timings.finish(panel: "main", tab: "old", size: NSSize(width: 356, height: 200), at: 10.01)
        timings.finish(panel: "main", tab: "home", size: .zero, at: 10.02)
        XCTAssertTrue(timings.records.isEmpty)
        timings.finish(panel: "main", tab: "home", size: NSSize(width: 356, height: 200), at: 10.05)
        let first = try XCTUnwrap(timings.records.first)
        XCTAssertEqual(first.milliseconds, 50, accuracy: 0.001)
        XCTAssertTrue(first.cold)
        XCTAssertEqual(first.input, "mouseDown")
        timings.finish(panel: "main", tab: "home", size: NSSize(width: 356, height: 200), at: 11)
        XCTAssertEqual(timings.records.count, 1)
        for index in 0..<55 {
            timings.begin(panel: "main", operation: .tabSwitch, tab: String(index), started: 20)
            timings.finish(panel: "main", tab: String(index), size: NSSize(width: 356, height: 300), at: 20.01)
        }
        XCTAssertEqual(timings.records.count, 50)
        XCTAssertEqual(timings.records.first?.tab, "5")
        XCTAssertEqual(timings.records.last?.tab, "54")
        XCTAssertTrue(timings.records.allSatisfy { !$0.cold && $0.operation == "tabSwitch" })
        timings.begin(panel: "main", started: 30)
        timings.cancel(panel: "main")
        timings.finish(panel: "main", tab: "home", size: NSSize(width: 356, height: 200), at: 31)
        XCTAssertEqual(timings.records.count, 50)
        timings.begin(panel: "main", started: 30)
        timings.finish(panel: "main", tab: "home", size: NSSize(width: 356, height: 200), at: 30.02)
        XCTAssertEqual(timings.records.last?.cold, false)
        XCTAssertNoThrow(try JSONEncoder().encode(timings.records))
    }
}
