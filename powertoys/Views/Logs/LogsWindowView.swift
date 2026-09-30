import AppKit
import OnePlusUI
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private enum LogsPage: String, CaseIterable, Identifiable, Sendable {
    case internalLogs = "internal"
    case systemIssues = "system"
    case settings

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

    func refresh(range: SystemLogRange) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        loadTask = Task { [weak self] in
            do {
                let entries = try await Task.detached(priority: .utility) { try Self.readEntries(range: range) }.value
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

    nonisolated private static func readEntries(range: SystemLogRange) throws -> [SystemLogLine] {
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

nonisolated private struct LogsRow: Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let time: String
    let level: String
    let levelFilter: LogLevel
    let symbol: String
    let source: String
    let message: String

    init(_ entry: LogEntryData, time: String) {
        id = entry.id.uuidString
        timestamp = entry.timestamp
        self.time = time
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

    init(_ entry: SystemLogLine, time: String) {
        id = entry.id.uuidString
        timestamp = entry.timestamp
        self.time = time
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
}

nonisolated private struct LogsVersion: Equatable, Sendable {
    let count: Int
    let lastID: UUID?
}

nonisolated enum LogsPresentation {
    static func rowTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        rowTimeFormatter(timeZone: timeZone).string(from: date)
    }

    static func rowTimeFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        formatter("MM-dd HH:mm:ss", timeZone: timeZone)
    }

    static func span(from first: Date, to last: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(first, inSameDayAs: last) {
            let date = formatter("yyyy-MM-dd", timeZone: timeZone).string(from: first)
            let time = formatter("h:mm:ss a", timeZone: timeZone)
            return "\(date), \(time.string(from: first)) – \(time.string(from: last))"
        }
        let dateTime = formatter("yyyy-MM-dd, h:mm a", timeZone: timeZone)
        return "\(dateTime.string(from: first)) – \(dateTime.string(from: last))"
    }

    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}

struct LogsWindowView: View {
    @State private var page = LogsPage.internalLogs
    @State private var selectedLevels = Set(LogLevel.allCases)
    @State private var systemRange = SystemLogRange.oneHour
    @State private var systemLogs = SystemLogReader()
    @State private var search = ""
    @State private var searchFocus = 0

    var body: some View {
        OnePlusWindowRoot(canvas: .logs) {
            LogsSidebar(
                page: $page,
                selectedLevels: $selectedLevels,
                systemLogs: systemLogs,
                search: $search,
                searchFocus: searchFocus
            )
        } content: {
            content
        }
            .background(WindowAccessor(identifier: "logs"))
            .buttonStyle(OnePlusButtonStyle())
            .onChange(of: page) { _, newPage in
                if newPage == .systemIssues && systemLogs.entries.isEmpty { systemLogs.refresh(range: systemRange) }
            }
            .onChange(of: systemRange) { _, _ in
                if page == .systemIssues { systemLogs.refresh(range: systemRange) }
            }
            .onDisappear { systemLogs.cancel() }
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
        OnePlusSidebar(title: "Logs") {
            OnePlusSearchField(
                prompt: "Search logs",
                text: $search,
                width: nil,
                focusTrigger: searchFocus,
                accessibilityIdentifier: "logs.search",
                height: OnePlusMetrics.searchHeight,
                shortcutHint: "⌘F"
            )
        } navigation: {
            OnePlusNavCaption("Sources")
            OnePlusNavRow(
                "Internal",
                systemImage: LogsPage.internalLogs.icon,
                selected: page == .internalLogs,
                count: logManager.logs.count
            ) { page = .internalLogs }
                .keyboardShortcut("1")
            OnePlusNavRow(
                "System issues",
                systemImage: LogsPage.systemIssues.icon,
                selected: page == .systemIssues,
                count: systemLogs.entries.count
            ) { page = .systemIssues }
                .keyboardShortcut("2")

            OnePlusNavCaption("Levels")
            ForEach(LogLevel.allCases, id: \.self) { level in
                OnePlusNavRow(
                    level.name,
                    systemImage: selectedLevels.contains(level) ? level.icon : "circle",
                    selected: false,
                    count: count(for: level)
                ) { toggle(level) }
                    .accessibilityValue(selectedLevels.contains(level) ? "Included" : "Excluded")
            }
        } bottom: {
            OnePlusNavRow("Settings", systemImage: "gearshape", selected: page == .settings) { page = .settings }
                .keyboardShortcut(",")
        }
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
    let page: LogsPage
    let selectedLevels: Set<LogLevel>
    @Binding var systemRange: SystemLogRange
    let systemLogs: SystemLogReader
    let search: String

    @State private var logManager = LogManager.shared
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\LogsRow.timestamp, order: .reverse)]
    @State private var visibleRows: [LogsRow] = []
    @State private var visibleSpan: String?
    @State private var rowLoadTask: Task<Void, Never>?
    @State private var detailID: String?
    @State private var confirmClear = false
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
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: page.title, subtitle: subtitle) {
                if page == .systemIssues {
                    OnePlusSelect(
                        choices: SystemLogRange.allCases.map { ($0, $0.title) },
                        selection: $systemRange,
                        width: OnePlusMetrics.controlColumn,
                        accessibilityLabel: "System log time range"
                    )
                    Button { systemLogs.refresh(range: systemRange) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(OnePlusButtonStyle(.icon))
                        .disabled(systemLogs.isLoading)
                        .help("Refresh system issues")
                        .accessibilityLabel("Refresh system issues")
                }
                Button("Copy") { copyRows() }.buttonStyle(OnePlusButtonStyle(.ghost)).disabled(visibleRows.isEmpty)
                Button("Export") { exportRows() }.buttonStyle(OnePlusButtonStyle(.ghost)).disabled(visibleRows.isEmpty)
                if page == .internalLogs {
                    Button("Clear") { confirmClear = true }.buttonStyle(OnePlusButtonStyle(.ghost)).disabled(logManager.logs.isEmpty)
                }
            }
        } content: {
            if let error = systemLogs.errorMessage, page == .systemIssues {
                OnePlusBanner(error, tone: .error) {
                    Button("Try Again") { systemLogs.refresh(range: systemRange) }
                }
            }
            if systemLogs.isLoading && page == .systemIssues && systemLogs.entries.isEmpty {
                OnePlusCard {
                    ProgressView("Reading system issues…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(OnePlusMetrics.spacing[8])
                }
                .frame(maxHeight: .infinity)
            } else if visibleRows.isEmpty {
                OnePlusCard {
                    OnePlusEmptyState(
                        page == .internalLogs ? "No internal logs" : "No system issues",
                        systemImage: page == .internalLogs ? "doc.text" : "checkmark.circle",
                        caption: search.isEmpty ? "No entries match the selected levels." : "Clear the search or include another level."
                    )
                    .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            } else {
                OnePlusCard {
                    Table(visibleRows, selection: $selection, sortOrder: sortBinding) {
                        TableColumn("Time", value: \LogsRow.timestamp) { row in
                            Text(row.time)
                                .onePlusText(.mono)
                                .textSelection(.enabled)
                        }
                        .width(116)
                        TableColumn("Level", value: \LogsRow.level) { row in
                            HStack(spacing: OnePlusMetrics.spacing[1]) {
                                Image(systemName: row.symbol)
                                    .foregroundStyle(levelGlyphColor(row))
                                    .accessibilityHidden(true)
                                Text(row.level)
                                    .foregroundStyle(OnePlusColor.secondary)
                            }
                                .textSelection(.enabled)
                        }
                        .width(84)
                        TableColumn("Source", value: \LogsRow.source) { row in
                            Text(row.source)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .width(215)
                        TableColumn("Message", value: \LogsRow.message) { row in
                            Text(row.message)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                        }
                        .width(min: 300, ideal: 500)
                    }
                    .contextMenu(forSelectionType: String.self) { selected in
                        logContextMenu(selected)
                    } primaryAction: { selected in
                        detailID = selected.first
                    }
                    .onePlusNativeTable()
                }
                .frame(maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("logs.\(page.rawValue)")
        .task { rebuildRows() }
        .onChange(of: page) {
            selection.removeAll()
            rebuildRows()
        }
        .onChange(of: search) { rebuildRows() }
        .onChange(of: selectedLevels) { rebuildRows() }
        .onChange(of: internalVersion) { rebuildRows() }
        .onChange(of: systemVersion) { rebuildRows() }
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
    }

    private var subtitle: String {
        guard let visibleSpan else {
            return page == .systemIssues
                ? "0 entries · read on demand · \(SystemLogReader.maximumEntries)-entry limit"
                : "0 entries"
        }
        let summary = "\(visibleRows.count) entries · \(visibleSpan)"
        return page == .systemIssues
            ? "\(summary) · \(SystemLogReader.maximumEntries)-entry limit"
            : summary
    }

    private var sortBinding: Binding<[KeyPathComparator<LogsRow>]> {
        Binding(
            get: { sortOrder },
            set: {
                sortOrder = $0
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
        let search = search
        let sortOrder = sortOrder

        rowLoadTask = Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                let rowTimeFormatter = LogsPresentation.rowTimeFormatter()
                let source = page == .internalLogs
                    ? internalEntries.map { LogsRow($0, time: rowTimeFormatter.string(from: $0.timestamp)) }
                    : systemEntries.map { LogsRow($0, time: rowTimeFormatter.string(from: $0.timestamp)) }
                let rows = source
                    .filter {
                        selectedLevels.contains($0.levelFilter)
                            && (search.isEmpty
                                || $0.source.localizedCaseInsensitiveContains(search)
                                || $0.message.localizedCaseInsensitiveContains(search))
                    }
                    .sorted(using: sortOrder)
                let firstTimestamp = rows.map(\.timestamp).min()
                let lastTimestamp = rows.map(\.timestamp).max()
                let span: String?
                if let firstTimestamp, let lastTimestamp {
                    span = LogsPresentation.span(from: firstTimestamp, to: lastTimestamp)
                } else {
                    span = nil
                }
                return PreparedLogs(rows: rows, span: span)
            }.value
            guard !Task.isCancelled else { return }
            visibleRows = prepared.rows
            visibleSpan = prepared.span
        }
    }

    private func row(for id: String) -> LogsRow? { visibleRows.first { $0.id == id } }

    private func openDetail(_ ids: Set<String>) { detailID = ids.first }

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
        if row.level == SystemLogLine.Level.fault.rawValue { return OnePlusColor.danger }
        switch row.levelFilter {
        case .error: return OnePlusColor.danger
        case .warning: return OnePlusColor.warn
        case .info: return OnePlusColor.secondary
        case .debug: return OnePlusColor.muted
        }
    }

    private func selectedOrVisibleRows() -> [LogsRow] {
        let chosen = visibleRows.filter { selection.contains($0.id) }
        return chosen.isEmpty ? visibleRows : chosen
    }

    private func rowText(_ row: LogsRow) -> String {
        "[\(row.time)] [\(row.level)] \(row.source): \(row.message)"
    }

    private func copyRows() { copy(selectedOrVisibleRows().map(rowText).joined(separator: "\n")) }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func exportRows() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = page == .internalLogs ? "MacPowerToys-Internal-Logs.txt" : "MacPowerToys-System-Issues.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try selectedOrVisibleRows().map(rowText).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            LogManager.shared.error("Could not export logs: \(error.localizedDescription)", source: "LogsWindowView")
        }
    }
}

private struct LogDetailSheet: View {
    let row: LogsRow
    let fontSize: Int
    let close: () -> Void

    var body: some View {
        OnePlusSheet("Log Entry", width: .large, close: close) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[3]) {
                OnePlusKeyValueRow("Time", value: row.timestamp.formatted(date: .abbreviated, time: .standard), monospaced: true)
                OnePlusKeyValueRow("Level", value: row.level)
                OnePlusKeyValueRow("Source", value: row.source, monospaced: true)
                OnePlusColor.lineSoft.frame(height: 1)
                Text(row.message)
                    .font(.system(size: CGFloat(fontSize), design: .monospaced))
                    .foregroundStyle(OnePlusColor.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.spacing[8] * 4, alignment: .topLeading)
            }
        } footer: {
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.message, forType: .string)
            }
            .buttonStyle(OnePlusButtonStyle(.neutral))
            Button("Done", action: close)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnePlusButtonStyle(.primary))
        }
    }
}

struct LogsSettingsPage: View {
    var body: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Settings", subtitle: "Log display and retention")
        } content: {
            LogsSettingsView()
        }
        .accessibilityIdentifier("logs.settings")
    }
}

struct LogsSettingsView: View {
    @AppStorage("logs.fontSize") private var fontSize = 11

    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusCardHeader("Logs")
                OnePlusSettingRow("Font size", caption: "Used for selectable log detail text.") {
                    OnePlusSelect(
                        choices: [(10, "Small"), (11, "Medium"), (12, "Default"), (14, "Large")],
                        selection: $fontSize,
                        accessibilityLabel: "Log font size"
                    )
                }
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[1]) {
                    OnePlusKeyValueRow("Retention", value: "2 days")
                    Text("Fixed policy for internal logs.")
                        .onePlusText(.caption)
                }
                .padding(.horizontal, OnePlusMetrics.cardPadding)
                .frame(height: OnePlusMetrics.captionedSettingRow)
                .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[1]) {
                    OnePlusKeyValueRow("System issues", value: "Not stored")
                    Text("Read from macOS only when requested.")
                        .onePlusText(.caption)
                }
                .padding(.horizontal, OnePlusMetrics.cardPadding)
                .frame(height: OnePlusMetrics.captionedSettingRow)
            }
        }
    }
}

#Preview { LogsWindowView() }
