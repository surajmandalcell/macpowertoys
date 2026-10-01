import AppKit
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusWindowTimingsTests: XCTestCase {
    func testWindowAndPageIntervalsKeepTheirStartsAndShareThePanelLedger() throws {
        let timings = OnePlusPanelTimings()
        timings.begin(panel: "window.main", operation: .windowOpen, input: "native-url", started: 10)
        timings.begin(panel: "page.main", operation: .pageSwitch, tab: "settings", input: "sidebar", started: 10.02)
        timings.begin(panel: "main", tab: "home", started: 10.03)
        timings.finish(panel: "page.main", tab: nil, size: .zero, at: 10.04)
        XCTAssertTrue(timings.hasPending("page.main"))
        timings.finish(panel: "window.main", tab: nil, size: NSSize(width: 1240, height: 840), at: 10.08)
        timings.finish(panel: "page.main", tab: nil, size: NSSize(width: 1240, height: 840), at: 10.08)
        timings.finish(panel: "main", tab: "home", size: NSSize(width: 356, height: 200), at: 10.08)
        XCTAssertEqual(timings.records.map(\.operation), ["windowOpen", "pageSwitch", "open"])
        XCTAssertEqual(timings.records[0].milliseconds, 80, accuracy: 0.001)
        XCTAssertEqual(timings.records[1].milliseconds, 60, accuracy: 0.001)
        XCTAssertEqual(timings.records[1].tab, "settings")
        XCTAssertEqual(timings.records.map(\.cold), [true, false, true])
        timings.begin(panel: "window.main", operation: .windowOpen, started: 20)
        timings.finish(panel: "window.main", tab: nil, size: NSSize(width: 1240, height: 840), at: 20.01)
        XCTAssertEqual(timings.records.last?.cold, false)
        XCTAssertNoThrow(try JSONEncoder().encode(timings.records))
    }
}
