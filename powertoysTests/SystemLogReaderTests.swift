import XCTest
import SwiftData
@testable import powertoys

final class SystemLogReaderTests: XCTestCase {
    func testSourceSearchAndLevelFiltersCompose() {
        func matches(_ level: LogLevel = .warning, source: String = "Sync", filter: String? = nil,
                     search: String = "", levels: Set<LogLevel> = Set(LogLevel.allCases)) -> Bool {
            LogsPresentation.includes(level: level, source: source, message: "Disk is unavailable",
                                      levels: levels, sourceFilter: filter, search: search)
        }
        XCTAssertTrue(matches(filter: "Sync", search: "DISK", levels: [.warning]))
        XCTAssertTrue(matches(search: "sync"))
        XCTAssertFalse(matches(filter: "Other"))
        XCTAssertFalse(matches(source: "SyncHelper", filter: "Sync"))
        XCTAssertFalse(matches(search: "missing"))
        XCTAssertFalse(matches(levels: []))
        XCTAssertFalse(matches(.info, levels: [.error, .warning]))
    }

    func testStartupMergeKeepsNewEntriesWithoutDuplicatesAndCapsOldest() {
        let loaded = (0..<1_002).map { index in
            LogEntryData(id: UUID(), timestamp: Date(timeIntervalSince1970: Double(index)),
                         level: .info, source: "Fixture", message: String(index))
        }
        let newest = LogEntryData(id: UUID(), timestamp: Date(timeIntervalSince1970: 1_003),
                                  level: .warning, source: "Startup", message: "New during load")
        let merged = LogManager.merging(loaded, with: [loaded.last!, newest])
        XCTAssertEqual(merged.count, 1_000)
        XCTAssertEqual(merged.first?.message, "3")
        XCTAssertEqual(merged.last?.id, newest.id)
        XCTAssertEqual(Set(merged.map(\.id)).count, merged.count)
        XCTAssertTrue(LogManager.merging([], with: []).isEmpty)
    }

    @MainActor func testPersistenceRoundTripAndRetentionBoundary() async throws {
        let container = try ModelContainer(for: LogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LogPersistence(modelContainer: container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 200_000)
        let cutoff = LogManager.retentionCutoff(now: now, calendar: calendar)
        XCTAssertEqual(cutoff, now.addingTimeInterval(-2 * 86_400))
        let entries = [-1.0, 0, 1].map { offset in
            LogEntryData(id: UUID(), timestamp: cutoff.addingTimeInterval(offset),
                         level: .debug, source: "Fixture", message: String(offset))
        }
        try await store.persist(entries)
        try await store.prune(before: cutoff)
        let loaded = try await store.load(since: .distantPast, limit: 1_000)
        XCTAssertEqual(loaded.map(\.id), Array(entries.dropFirst()).map(\.id))
        let limited = try await store.load(since: cutoff, limit: 1)
        XCTAssertEqual(limited.first?.id, entries.last?.id)
    }

    @MainActor func testCancelStopsDetachedSystemReadAndCloseDropsRows() async throws {
        let started = expectation(description: "Read started")
        let cancelled = expectation(description: "Detached read cancelled")
        let reader = SystemLogReader { _ in
            started.fulfill()
            let deadline = Date().addingTimeInterval(2)
            while !Task.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
            guard Task.isCancelled else { return [] }
            cancelled.fulfill()
            throw CancellationError()
        }
        reader.refresh(range: .oneHour)
        await fulfillment(of: [started], timeout: 3)
        reader.cancel()
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertFalse(reader.isLoading)
        XCTAssertNil(reader.errorMessage)

        let row = SystemLogLine(id: UUID(), timestamp: .now, level: .fault, source: "Fixture", message: "Fault")
        let loaded = SystemLogReader { _ in [row] }
        loaded.refresh(range: .oneDay)
        let deadline = Date().addingTimeInterval(3)
        while loaded.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(loaded.isLoading)
        XCTAssertEqual(loaded.entries.first?.id, row.id)
        loaded.close()
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertFalse(loaded.isLoading)
    }

    func testSystemLogReadsStayBoundedAndUseExplicitRanges() {
        XCTAssertEqual(SystemLogReader.maximumEntries, 500)
        XCTAssertEqual(SystemLogRange.oneHour.rawValue, 60 * 60)
        XCTAssertEqual(SystemLogRange.sixHours.rawValue, 6 * 60 * 60)
        XCTAssertEqual(SystemLogRange.oneDay.rawValue, 24 * 60 * 60)
    }

    func testLocalizedTimesSortRestorationAndPageFallback() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let first = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 29, hour: 13, minute: 39, second: 1
        )))
        let last = first.addingTimeInterval(52)
        for (localeID, time) in [("en_US", "1:39:01"), ("en_GB", "13:39:01"), ("de_DE", "13:39:01")] {
            let locale = Locale(identifier: localeID)
            let row = LogsPresentation.rowTimeFormatter(locale: locale, calendar: calendar, timeZone: timeZone).string(from: first)
            let span = LogsPresentation.span(from: first, to: last, locale: locale, calendar: calendar, timeZone: timeZone)
            XCTAssertTrue(row.contains(time), row)
            XCTAssertTrue(span.contains(time), span)
            XCTAssertEqual(span.components(separatedBy: "2026").count, 2, span)
            let crossDay = LogsPresentation.span(from: first, to: first.addingTimeInterval(86_400),
                                                  locale: locale, calendar: calendar, timeZone: timeZone)
            XCTAssertEqual(crossDay.components(separatedBy: "2026").count, 3, crossDay)
        }
        XCTAssertEqual(LogsPresentation.exportTimeFormatter(timeZone: timeZone).string(from: first), "09-29 13:39:01")
        let shifted = LogsPresentation.rowTimeFormatter(locale: Locale(identifier: "en_GB"), calendar: calendar,
                                                        timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 3_600))).string(from: first)
        XCTAssertTrue(shifted.contains("14:39:01"), shifted)

        for column in ["time", "level", "source", "message"] {
            for direction in ["ascending", "descending"] {
                let restored = try XCTUnwrap(LogsPresentation.sortOrder(column: column, direction: direction).first)
                XCTAssertEqual(LogsPresentation.sortColumn(for: restored), column)
                XCTAssertEqual(restored.order, direction == "ascending" ? .forward : .reverse)
            }
        }
        for (column, direction) in [("removed", "ascending"), ("time", "invalid")] {
            let fallback = try XCTUnwrap(LogsPresentation.sortOrder(column: column, direction: direction).first)
            XCTAssertEqual(fallback.keyPath, \LogsRow.timestamp)
            XCTAssertEqual(fallback.order, .reverse)
        }
        let suite = "audit-logs-test-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("source", forKey: "logs.sortColumn")
        preferences.set("ascending", forKey: "logs.sortDirection")
        preferences.set("settings", forKey: "logs.page")
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        let savedSort = try XCTUnwrap(LogsPresentation.sortOrder(
            column: reopened.string(forKey: "logs.sortColumn") ?? "time",
            direction: reopened.string(forKey: "logs.sortDirection") ?? "descending"
        ).first)
        XCTAssertEqual(savedSort.keyPath, \LogsRow.source)
        XCTAssertEqual(savedSort.order, .forward)
        XCTAssertEqual(LogsPage.restored(reopened.string(forKey: "logs.page") ?? "internal"), .settings)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = timeZone
        let buddhistSpan = LogsPresentation.span(from: first, to: last, locale: Locale(identifier: "en_US"),
                                                  calendar: buddhist, timeZone: timeZone)
        XCTAssertTrue(buddhistSpan.contains("2569"), buddhistSpan)

        XCTAssertEqual(LogsPage.restored("system"), .systemIssues)
        XCTAssertEqual(LogsPage.restored("settings"), .settings)
        XCTAssertEqual(LogsPage.restored("removed"), .internalLogs)
    }
}
