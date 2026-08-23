import XCTest
@testable import powertoys

final class SystemLogReaderTests: XCTestCase {
    func testSystemLogReadsStayBoundedAndUseExplicitRanges() {
        XCTAssertEqual(SystemLogReader.maximumEntries, 500)
        XCTAssertEqual(SystemLogRange.oneHour.rawValue, 60 * 60)
        XCTAssertEqual(SystemLogRange.sixHours.rawValue, 6 * 60 * 60)
        XCTAssertEqual(SystemLogRange.oneDay.rawValue, 24 * 60 * 60)
    }
}
