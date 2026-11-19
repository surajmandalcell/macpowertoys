import AppKit
import OnePlusUI
import OSLog
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum LogsPage: String, CaseIterable, Identifiable, Sendable {
    case internalLogs = "internal"
    case systemIssues = "system"
    case settings

    static func restored(_ id: String) -> Self { Self(rawValue: id) ?? .internalLogs }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .internalLogs: "Internal Logs"
        case .systemIssues: "System Issues"
        case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .internalLogs: "app.badge.checkmark"
        case .systemIssues: "desktopcomputer.trianglebadge.exclamationmark"
        case .settings: "gearshape"
        }
    }
}

enum SystemLogRange: TimeInterval, CaseIterable, Identifiable, Sendable {
    case oneHour = 3_600
    case sixHours = 21_600
    case oneDay = 86_400

    var id: TimeInterval { rawValue }
    var title: String {
        switch self {
        case .oneHour: "Last Hour"
        case .sixHours: "Last 6 Hours"
        case .oneDay: "Last 24 Hours"
        }
    }
}

struct SystemLogLine: Identifiable, Sendable {
    enum Level: String, Sendable { case error = "Error", fault = "Fault" }
    let id: UUID
    let timestamp: Date
    let level: Level
    let source: String
    let message: String
}

@Observable
@MainActor
final class SystemLogReader {
    nonisolated static let maximumEntries = 500
    private(set) var entries: [SystemLogLine] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var loadTask: Task<Void, Never>?
    private let read: @Sendable (SystemLogRange) throws -> [SystemLogLine]

    init(read: @escaping @Sendable (SystemLogRange) throws -> [SystemLogLine] = { try SystemLogReader.readEntries(range: $0) }) {
        self.read = read
    }

    func refresh(range: SystemLogRange) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        entries = []
        let read = read
        loadTask = Task { [weak self] in
            do {
                let work = Task.detached(priority: .utility) { try read(range) }
                let entries = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                guard !Task.isCancelled else { return }
                self?.entries = entries
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
            }
            self?.isLoading = false
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func close() {
        cancel()
        entries = []
        errorMessage = nil
    }

    nonisolated static func readEntries(range: SystemLogRange) throws -> [SystemLogLine] {
        try Task.checkCancellation()
        let store = try OSLogStore(scope: .system)
        let now = Date()
        let cutoff = now.addingTimeInterval(-range.rawValue)
        let sequence = try store.getEntries(
            with: [.reverse],
            at: store.position(date: now),
            matching: NSPredicate(format: "messageType == error OR messageType == fault")
        )
        var result: [SystemLogLine] = []
        result.reserveCapacity(maximumEntries)
        for case let entry as OSLogEntryLog in sequence {
            try Task.checkCancellation()
            guard entry.date >= cutoff else { break }
            let source = [entry.subsystem, entry.category].filter { !$0.isEmpty }.joined(separator: "/")
            result.append(SystemLogLine(
                id: UUID(),
                timestamp: entry.date,
                level: entry.level == .fault ? .fault : .error,
                source: source.isEmpty ? entry.process : "\(entry.process) · \(source)",
                message: entry.composedMessage
            ))
            if result.count == maximumEntries { break }
        }
        return result
    }
}

nonisolated struct LogsRow: Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let time: String
    let detailTime: String
    let exportTime: String
    let level: String
    let levelFilter: LogLevel
    let symbol: String
    let source: String
    let message: String

    init(_ entry: LogEntryData, time: String, detailTime: String, exportTime: String) {
        id = entry.id.uuidString
        timestamp = entry.timestamp
        self.time = time
        self.detailTime = detailTime
        self.exportTime = exportTime
        levelFilter = entry.level
        switch entry.level {
        case .error: (level, symbol) = ("Error", "xmark.circle.fill")
        case .warning: (level, symbol) = ("Warning", "exclamationmark.triangle.fill")
        case .info: (level, symbol) = ("Info", "info.circle.fill")
        case .debug: (level, symbol) = ("Debug", "ant.fill")
        }
        source = entry.source
        message = entry.message
    }

    init(_ entry: SystemLogLine, time: String, detailTime: String, exportTime: String) {
        id = entry.id.uuidString
        timestamp = entry.timestamp
        self.time = time
        self.detailTime = detailTime
        self.exportTime = exportTime
        level = entry.level.rawValue
        levelFilter = .error
        symbol = entry.level == .fault ? "bolt.trianglebadge.exclamationmark.fill" : "xmark.circle.fill"
        source = entry.source
        message = entry.message
    }

    var fileURL: URL? {
        let expanded = NSString(string: source).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
    }
}

nonisolated private struct PreparedLogs: Sendable {
    let rows: [LogsRow]
    let span: String?
    let sources: [String]
}

nonisolated private struct LogsVersion: Equatable, Sendable {
    let count: Int
    let lastID: UUID?
}

nonisolated enum LogsPresentation {
    static func includes(level: LogLevel, source: String, message: String,
                         levels: Set<LogLevel>, sourceFilter: String?, search: String) -> Bool {
        levels.contains(level) && (sourceFilter == nil || source == sourceFilter)
            && (search.isEmpty || source.localizedCaseInsensitiveContains(search)
                || message.localizedCaseInsensitiveContains(search))
    }

    static func rowTimeFormatter(locale: Locale = .current, calendar: Calendar = .current,
                                 timeZone: TimeZone = .current) -> DateFormatter {
        formatter("Mdjmmss", locale: locale, calendar: calendar, timeZone: timeZone)
    }

    static func formatter(_ template: String, locale: Locale = .current, calendar: Calendar = .current,
                          timeZone: TimeZone = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    static func span(from first: Date, to last: Date, locale: Locale = .current,
                     calendar: Calendar = .current, timeZone: TimeZone = .current) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        if calendar.isDate(first, inSameDayAs: last) {
            let date = formatter("yMMMd", locale: locale, calendar: calendar, timeZone: timeZone).string(from: first)
            let time = formatter("jmmss", locale: locale, calendar: calendar, timeZone: timeZone)
            return "\(date), \(time.string(from: first)) – \(time.string(from: last))"
        }
        let dateTime = formatter("yMMMdjmmss", locale: locale, calendar: calendar, timeZone: timeZone)
        return "\(dateTime.string(from: first)) – \(dateTime.string(from: last))"
    }

    static func exportTimeFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }

    static func sortOrder(column: String, direction: String) -> [KeyPathComparator<LogsRow>] {
        guard direction == "ascending" || direction == "descending" else {
            return [KeyPathComparator(\LogsRow.timestamp, order: .reverse)]
        }
        let order: SortOrder = direction == "ascending" ? .forward : .reverse
        switch column {
        case "time": return [KeyPathComparator(\LogsRow.timestamp, order: order)]
        case "level": return [KeyPathComparator(\LogsRow.level, order: order)]
        case "source": return [KeyPathComparator(\LogsRow.source, order: order)]
        case "message": return [KeyPathComparator(\LogsRow.message, order: order)]
        default: return [KeyPathComparator(\LogsRow.timestamp, order: .reverse)]
        }
    }

    static func sortColumn(for comparator: KeyPathComparator<LogsRow>) -> String? {
        switch comparator.keyPath {
        case \LogsRow.timestamp: "time"
        case \LogsRow.level: "level"
        case \LogsRow.source: "source"
        case \LogsRow.message: "message"
        default: nil
        }
    }
}

struct LogsWindowView: View {
    @AppStorage("logs.page") private var storedPage = LogsPage.internalLogs.rawValue
    private var page: LogsPage {
        get { LogsPage.restored(storedPage) }
        nonmutating set { storedPage = newValue.rawValue }
    }
    @State private var selectedLevels = Set(LogLevel.allCases)
    @State private var systemRange = SystemLogRange.oneHour
    @State private var systemLogs = SystemLogReader()
    @State private var search = ""
    @State private var searchFocus = 0

    var body: some View {
        LinearToolWindow(canvas: .logs, editorial: true) {
            LogsSidebar(
                page: Binding(get: { page }, set: { page = $0 }),
                selectedLevels: $selectedLevels,
                systemLogs: systemLogs,
                search: $search,
                searchFocus: searchFocus
            )
        } content: {
            LinearToolPane(page: Binding(get: { page }, set: { page = $0 }), title: page.title) {
                EmptyView()
            } content: {
                content
            }
        }
            .background(WindowAccessor(identifier: "logs"))
            .onAppear {
                storedPage = page.rawValue
                if page == .systemIssues && systemLogs.entries.isEmpty && !systemLogs.isLoading {
                    systemLogs.refresh(range: systemRange)
                }
            }
            .onChange(of: page) { _, newPage in
                if newPage == .systemIssues && systemLogs.entries.isEmpty { systemLogs.refresh(range: systemRange) }
                else if newPage != .systemIssues { systemLogs.cancel() }
            }
            .onChange(of: systemRange) { _, _ in
                if page == .systemIssues { systemLogs.refresh(range: systemRange) }
            }
            .onDisappear { systemLogs.close() }
            .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
                guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("logs") == true else { return }
                page = .settings
            }
            .onOpenToolPage("logs") { open(page: $0) }
            .overlay(alignment: .topLeading) {
                Button("") { searchFocus &+= 1 }
                    .keyboardShortcut("f")
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .internalLogs, .systemIssues:
            LogsPageView(
                page: page,
                selectedLevels: selectedLevels,
                systemRange: $systemRange,
                systemLogs: systemLogs,
                search: search
            )
        case .settings: LogsSettingsPage()
        }
    }

    private func open(page pageID: String) {
        guard let requested = LogsPage(rawValue: pageID) else { return }
        page = requested
    }
}

private struct LogsSidebar: View {
    @Binding var page: LogsPage
    @Binding var selectedLevels: Set<LogLevel>
    let systemLogs: SystemLogReader
    @Binding var search: String
    let searchFocus: Int

    @State private var logManager = LogManager.shared
    @State private var counts: [LogLevel: Int] = [:]
    @State private var countTask: Task<Void, Never>?

    private var version: LogsVersion {
        LogsVersion(count: logManager.logs.count, lastID: logManager.logs.last?.id)
    }

    var body: some View {
        OnePlusLinearSidebar {
            OnePlusLinearSearchField("Search logs", text: $search, accessibilityIdentifier: "logs.search",
                                     focusTrigger: searchFocus)
        } navigation: {
            OnePlusLinearNavCaption("Sources")
            OnePlusLinearNavRow(
                "Internal",
                systemImage: LogsPage.internalLogs.icon,
                selected: page == .internalLogs,
                count: logManager.logs.count
            ) { page = .internalLogs }
                .keyboardShortcut("1")
            OnePlusLinearNavRow(
                "System issues",
                systemImage: LogsPage.systemIssues.icon,
                selected: page == .systemIssues,
                count: systemLogs.entries.count
            ) { page = .systemIssues }
                .keyboardShortcut("2")

            OnePlusLinearNavCaption("Levels")
            ForEach(LogLevel.allCases, id: \.self) { level in
                OnePlusLinearNavRow(
                    level.name,
                    systemImage: selectedLevels.contains(level) ? level.icon : "circle",
                    count: count(for: level)
                ) { toggle(level) }
                    .accessibilityValue(selectedLevels.contains(level) ? "Included" : "Excluded")
            }
        } bottom: {
            OnePlusLinearNavRow("Settings", systemImage: "gearshape", selected: page == .settings, shortcut: "⌘,") {
                page = .settings
            }
                .keyboardShortcut(",")
        }
        .linearSidebarTitle("Event Viewer")
        .task { rebuildCounts() }
        .onChange(of: version) { rebuildCounts() }
        .onDisappear {
            countTask?.cancel()
            countTask = nil
        }
    }

    private func toggle(_ level: LogLevel) {
        if selectedLevels.contains(level) { selectedLevels.remove(level) }
        else { selectedLevels.insert(level) }
    }

    private func count(for level: LogLevel) -> Int {
        if page == .systemIssues {
            return level == .error ? systemLogs.entries.count : 0
        }
        return counts[level, default: 0]
    }

    private func rebuildCounts() {
        countTask?.cancel()
        let logs = logManager.logs
        countTask = Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                Dictionary(grouping: logs, by: \.level).mapValues(\.count)
            }.value
            guard !Task.isCancelled else { return }
            counts = prepared
        }
    }
}

private struct LogsPageView: View {
    private static let columns: [OnePlusGridColumn] = [
        OnePlusGridColumn("Time", width: 168, textRole: .mono),
        OnePlusGridColumn("Level", width: 96, textColor: OnePlusLinearColor.secondary,
                          headerLabelInset: OnePlusLinearMetrics.navIcon + OnePlusLinearSpace.tight),
        OnePlusGridColumn("Source", width: 215),
        OnePlusGridColumn("Message", width: 500)
    ]

    let page: LogsPage
    let selectedLevels: Set<LogLevel>
    @Binding var systemRange: SystemLogRange
    let systemLogs: SystemLogReader
    let search: String

    @State private var logManager = LogManager.shared
    @State private var selection: Set<String> = []
    @AppStorage("logs.sortColumn") private var sortColumn = "time"
    @AppStorage("logs.sortDirection") private var sortDirection = "descending"
    @State private var sortOrder = [KeyPathComparator(\LogsRow.timestamp, order: .reverse)]
    @State private var visibleRows: [LogsRow] = []
    @State private var visibleSpan: String?
    @State private var rowLoadTask: Task<Void, Never>?
    @State private var detailID: String?
    @State private var confirmClear = false
    @State private var sourceFilter: String?
    @State private var sources: [String] = []
    @State private var isExporting = false
    @State private var exportError: String?
    @AppStorage("logs.fontSize") private var logsFontSize = 11

    private var internalVersion: LogsVersion {
        page == .internalLogs
            ? LogsVersion(count: logManager.logs.count, lastID: logManager.logs.last?.id)
            : LogsVersion(count: 0, lastID: nil)
    }

    private var systemVersion: LogsVersion {
        page == .systemIssues
            ? LogsVersion(count: systemLogs.entries.count, lastID: systemLogs.entries.last?.id)
            : LogsVersion(count: 0, lastID: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.sectionGap) {
            HStack(spacing: OnePlusLinearMetrics.appletActionGap) {
                if page == .systemIssues {
                    OnePlusLinearSelect(
                        choices: SystemLogRange.allCases.map { ($0, $0.title) },
                        selection: $systemRange,
                        accessibilityLabel: "System log time range",
                        width: OnePlusLinearControlWidth.regular
                    )
                    OnePlusLinearIconButton(systemImage: "arrow.clockwise", help: "Refresh system issues",
                                            size: OnePlusLinearMetrics.toolbarButton) { systemLogs.refresh(range: systemRange) }
                        .disabled(systemLogs.isLoading)
                }
                OnePlusLinearSelect(
                    choices: [(String?.none, "All sources")] + sources.map { (Optional($0), $0) },
                    selection: $sourceFilter,
                    accessibilityLabel: "Log source",
                    width: OnePlusLinearControlWidth.regular
                )
                Spacer(minLength: 0)
                LinearCaption(summary)
                if page == .systemIssues {
                    Image(systemName: "info.circle")
                        .foregroundStyle(OnePlusLinearColor.muted)
                        .help("Reads macOS errors and faults on demand, up to \(SystemLogReader.maximumEntries) entries. System issues are not stored.")
                        .accessibilityLabel("System issues are read on demand, limited to \(SystemLogReader.maximumEntries) entries, and not stored.")
                }
                Button("Copy") { copyRows() }.buttonStyle(OnePlusLinearButtonStyle(.soft)).disabled(visibleRows.isEmpty)
                Button("Export") { exportRows() }.buttonStyle(OnePlusLinearButtonStyle(.soft)).disabled(visibleRows.isEmpty || isExporting)
            }
            if let error = logManager.persistenceError, page == .internalLogs {
                OnePlusLinearBanner(.error, title: "Internal log storage is unavailable: \(error)") { EmptyView() }
            }
            if let error = systemLogs.errorMessage, page == .systemIssues {
                OnePlusLinearBanner(.error, title: error) {
                    Button("Try Again") { systemLogs.refresh(range: systemRange) }
                }
            }
            if systemLogs.isLoading && page == .systemIssues && systemLogs.entries.isEmpty {
                ProgressView("Reading system issues…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleRows.isEmpty {
                OnePlusLinearEmptyState(
                    page == .internalLogs ? "No internal logs" : "No system issues",
                    systemImage: page == .internalLogs ? "doc.text" : "checkmark.circle"
                )
                    .frame(maxHeight: .infinity)
            } else {
                OnePlusLinearAppletGroup {
                    Table(visibleRows, selection: $selection, sortOrder: sortBinding) {
                        TableColumn("Time", value: \LogsRow.timestamp) { row in
                            Text(row.time)
                                .textSelection(.enabled)
                                .onePlusTableCell(Self.columns[0], position: .first)
                        }
                        .width(Self.columns[0].width)
                        TableColumn("Level", value: \LogsRow.level) { row in
                            HStack(spacing: OnePlusLinearSpace.tight) {
                                Image(systemName: row.symbol)
                                    .foregroundStyle(levelGlyphColor(row))
                                    .accessibilityHidden(true)
                                    .frame(width: OnePlusLinearMetrics.navIcon)
                                Text(row.level)
                                    .lineLimit(1)
                            }
                                .textSelection(.enabled)
                                .onePlusTableCell(Self.columns[1])
                        }
                        .width(Self.columns[1].width)
                        TableColumn("Source", value: \LogsRow.source) { row in
                            Text(row.source)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .onePlusTableCell(Self.columns[2])
                        }
                        .width(Self.columns[2].width)
                        TableColumn("Message", value: \LogsRow.message) { row in
                            Text(row.message)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                                .onePlusTableCell(Self.columns[3], position: .last)
                        }
                        .width(min: 300, ideal: Self.columns[3].width)
                    }
                    .contextMenu(forSelectionType: String.self) { selected in
                        logContextMenu(selected)
                    } primaryAction: { selected in
                        detailID = selected.first
                    }
                    .onePlusNativeTable(columns: Self.columns)
                }
                .frame(maxHeight: .infinity)
            }
            if page == .internalLogs {
                Button("Clear Logs", role: .destructive) { confirmClear = true }
                    .buttonStyle(OnePlusLinearButtonStyle(.destructive))
                    .disabled(logManager.logs.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, OnePlusLinearEditorialMetrics.bodyTop)
        .padding(.horizontal, OnePlusLinearEditorialMetrics.gutter)
        .padding(.bottom, OnePlusLinearEditorialMetrics.bottom)
        .accessibilityIdentifier("logs.\(page.rawValue)")
        .task {
            sortOrder = LogsPresentation.sortOrder(column: sortColumn, direction: sortDirection)
            rebuildRows()
        }
        .onChange(of: page) {
            selection.removeAll()
            sourceFilter = nil
            rebuildRows()
        }
        .onChange(of: search) { rebuildRows() }
        .onChange(of: sourceFilter) { rebuildRows() }
        .onChange(of: selectedLevels) { rebuildRows() }
        .onChange(of: internalVersion) { rebuildRows() }
        .onChange(of: systemVersion) { rebuildRows() }
        .onChange(of: AppInitializer.shared.formattingRevision) { rebuildRows() }
        .onDisappear {
            rowLoadTask?.cancel()
            rowLoadTask = nil
        }
        .sheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } })) {
            if let detailID, let row = row(for: detailID) {
                LogDetailSheet(row: row, fontSize: logsFontSize) { self.detailID = nil }
            }
        }
        .confirmationDialog("Clear all internal logs?", isPresented: $confirmClear) {
            Button("Clear Logs", role: .destructive) { logManager.clearMemoryLogs() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the in-memory internal log list.")
        }
        .alert("Could not export logs", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "The file could not be written.") }
    }

    private var summary: String {
        guard let visibleSpan else { return "0 entries" }
        return "\(visibleRows.count) entries · \(visibleSpan)"
    }

    private var sortBinding: Binding<[KeyPathComparator<LogsRow>]> {
        Binding(
            get: { sortOrder },
            set: {
                guard let comparator = $0.first,
                      let column = LogsPresentation.sortColumn(for: comparator) else { return }
                sortOrder = $0
                sortColumn = column
                sortDirection = comparator.order == .forward ? "ascending" : "descending"
                rebuildRows()
            }
        )
    }

    private func rebuildRows() {
        rowLoadTask?.cancel()
        let internalEntries = page == .internalLogs ? logManager.logs : []
        let systemEntries = page == .systemIssues ? systemLogs.entries : []
        let page = page
        let selectedLevels = selectedLevels
        let sourceFilter = sourceFilter
        let search = search
        let sortOrder = sortOrder
        let formattingRevision = AppInitializer.shared.formattingRevision

        rowLoadTask = Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                // Snapshot formatting context once per revision, away from rendering.
                let locale = Locale.current
                let calendar = Calendar.current
                let timeZone = TimeZone.current
                let rowTimeFormatter = LogsPresentation.rowTimeFormatter(locale: locale, calendar: calendar, timeZone: timeZone)
                let detailFormatter = LogsPresentation.formatter("yMMMdjmmss", locale: locale, calendar: calendar, timeZone: timeZone)
                let exportFormatter = LogsPresentation.exportTimeFormatter(timeZone: timeZone)
                let source = page == .internalLogs
                    ? internalEntries.map { LogsRow($0, time: rowTimeFormatter.string(from: $0.timestamp),
                                               detailTime: detailFormatter.string(from: $0.timestamp),
                                               exportTime: exportFormatter.string(from: $0.timestamp)) }
                    : systemEntries.map { LogsRow($0, time: rowTimeFormatter.string(from: $0.timestamp),
                                               detailTime: detailFormatter.string(from: $0.timestamp),
                                               exportTime: exportFormatter.string(from: $0.timestamp)) }
                let rows = source
                    .filter {
                        LogsPresentation.includes(level: $0.levelFilter, source: $0.source, message: $0.message,
                                                  levels: selectedLevels, sourceFilter: sourceFilter, search: search)
                    }
                    .sorted(using: sortOrder)
                let firstTimestamp = rows.map(\.timestamp).min()
                let lastTimestamp = rows.map(\.timestamp).max()
                let span: String?
                if let firstTimestamp, let lastTimestamp {
                    span = LogsPresentation.span(from: firstTimestamp, to: lastTimestamp,
                                                 locale: locale, calendar: calendar, timeZone: timeZone)
                } else {
                    span = nil
                }
                return PreparedLogs(rows: rows, span: span, sources: Set(source.map(\.source)).sorted())
            }.value
            guard !Task.isCancelled else { return }
            guard formattingRevision == AppInitializer.shared.formattingRevision else { return }
            visibleRows = prepared.rows
            visibleSpan = prepared.span
            sources = prepared.sources
        }
    }

    private func row(for id: String) -> LogsRow? { visibleRows.first { $0.id == id } }

    @ViewBuilder private func logContextMenu(_ ids: Set<String>) -> some View {
        if let id = ids.first, let row = row(for: id) {
            Button("Copy Row") { copy(rowText(row)) }
            Button("Copy Message") { copy(row.message) }
            Button("Show Details…") { detailID = row.id }
            if let url = row.fileURL {
                Button("Reveal Source") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    private func levelGlyphColor(_ row: LogsRow) -> Color {
        if row.level == SystemLogLine.Level.fault.rawValue { return OnePlusLinearColor.destructiveText }
        switch row.levelFilter {
        case .error: return OnePlusLinearColor.destructiveText
        case .warning: return OnePlusLinearColor.warning
        case .info: return OnePlusLinearColor.secondary
        case .debug: return OnePlusLinearColor.muted
        }
    }

    private func selectedOrVisibleRows() -> [LogsRow] {
        let chosen = visibleRows.filter { selection.contains($0.id) }
        return chosen.isEmpty ? visibleRows : chosen
    }

    private func rowText(_ row: LogsRow) -> String {
        "[\(row.exportTime)] [\(row.level)] \(row.source): \(row.message)"
    }

    private func copyRows() { copy(selectedOrVisibleRows().map(rowText).joined(separator: "\n")) }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func exportRows() {
        guard !isExporting,
              let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "logs" && $0.isVisible }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = page == .internalLogs ? "MacPowerToys-Internal-Logs.txt" : "MacPowerToys-System-Issues.txt"
        panel.allowedContentTypes = [.plainText]
        let text = selectedOrVisibleRows().map(rowText).joined(separator: "\n")
        isExporting = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { isExporting = false; return }
            Task { @MainActor in
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try text.write(to: url, atomically: true, encoding: .utf8)
                    }.value
                } catch { exportError = error.localizedDescription }
                isExporting = false
            }
        }
    }
}

struct LogDetailSheet: View {
    let row: LogsRow
    let fontSize: Int
    let close: () -> Void

    var body: some View {
        OnePlusLinearSheet("Log Entry", width: .large, close: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: OnePlusLinearSpace.section) {
                    OnePlusLinearAppletGroup {
                        detailRow("Time", row.detailTime)
                        detailRow("Level", row.level)
                        detailRow("Source", row.source)
                    }
                    Text(row.message)
                        .font(.system(size: CGFloat(fontSize), design: .monospaced))
                        .foregroundStyle(OnePlusLinearColor.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: OnePlusLinearSpace.page * 4, alignment: .topLeading)
                        .padding(OnePlusLinearMetrics.appletRowPadding)
                        .background(OnePlusLinearColor.fillGroup,
                                    in: RoundedRectangle(cornerRadius: OnePlusLinearMetrics.appletGroupRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: OnePlusLinearMetrics.appletGroupRadius, style: .continuous)
                            .strokeBorder(OnePlusLinearColor.line, lineWidth: 1))
                }
            }
            .onePlusScrollIndicators()
            .frame(maxHeight: OnePlusWindowCanvas.logs.size.height / 2)
        } footer: {
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.message, forType: .string)
            }
            .buttonStyle(OnePlusLinearButtonStyle(.soft))
            Button("Done", action: close)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnePlusLinearButtonStyle(.soft))
        }
    }

    /// A label and a selectable value, so time, level, and source copy like the message.
    private func detailRow(_ label: String, _ value: String) -> some View {
        OnePlusLinearAppletRow(label) {
            Text(value).linearText(color: OnePlusLinearColor.secondary).textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle).help(value)
        }
    }
}

struct LogsSettingsPage: View {
    var body: some View {
        OnePlusLinearEditorialBody {
            LogsSettingsView()
        }
        .accessibilityIdentifier("logs.settings")
    }
}

struct LogsSettingsView: View {
    @AppStorage("logs.fontSize") private var fontSize = 11

    var body: some View {
        OnePlusLinearAppletSection("Event Viewer") {
            OnePlusLinearAppletRow("Font size", systemImage: "textformat.size") {
                OnePlusLinearSelect(
                    choices: [(10, "Small"), (11, "Medium"), (12, "Default"), (14, "Large")],
                    selection: $fontSize,
                    accessibilityLabel: "Log font size",
                    width: OnePlusLinearControlWidth.regular
                )
            }
            .help("Used for selectable log detail text.")
            OnePlusLinearAppletRow("Retention", value: "\(LogManager.retentionDays) days", systemImage: "calendar")
                .help("Fixed policy for internal logs.")
            OnePlusLinearAppletRow("System issues", value: "Not stored", systemImage: "exclamationmark.triangle")
                .help("Read from macOS only when requested.")
        }
    }
}

#Preview { LogsWindowView() }
