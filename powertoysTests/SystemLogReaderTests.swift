import XCTest
@testable import powertoys

final class SystemLogReaderTests: XCTestCase {
    func testSystemLogReadsStayBoundedAndUseExplicitRanges() {
        XCTAssertEqual(SystemLogReader.maximumEntries, 500)
        XCTAssertEqual(SystemLogRange.oneHour.rawValue, 60 * 60)
        XCTAssertEqual(SystemLogRange.sixHours.rawValue, 6 * 60 * 60)
        XCTAssertEqual(SystemLogRange.oneDay.rawValue, 24 * 60 * 60)
    }

    func testLogPresentationShowsRowDatesAndCollapsesSameDayRanges() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let first = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 29,
            hour: 10,
            minute: 39,
            second: 1
        )))
        let last = first.addingTimeInterval(52)

        XCTAssertEqual(LogsPresentation.rowTime(first, timeZone: timeZone), "09-29 10:39:01")
        XCTAssertEqual(
            LogsPresentation.span(from: first, to: last, timeZone: timeZone),
            "2026-09-29, 10:39:01 AM – 10:39:53 AM"
        )
    }
}
