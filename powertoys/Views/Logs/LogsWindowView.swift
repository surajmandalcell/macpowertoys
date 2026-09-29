import AppKit
import OnePlusUI
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private enum LogsPage: String, CaseIterable, Identifiable {
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

nonisolated private struct LogsRow: Identifiable {
    let id: String
    let timestamp: Date
    let level: String
    let levelFilter: LogLevel
    let symbol: String
    let source: String
    let message: String

    init(_ entry: LogEntryData) {
        id = entry.id.uuidString
        timestamp = entry.timestamp
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

    init(_ entry: SystemLogLine) {
        id = entry.id.uuidString
        timestamp = entry.timestamp
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

struct LogsWindowView: View {
    @State private var page = LogsPage.internalLogs
    @State private var selectedLevels = Set(LogLevel.allCases)
    @State private var systemRange = SystemLogRange.oneHour
    @State private var systemLogs = SystemLogReader()
    @State private var logManager = LogManager.shared
    @State private var search = ""
    @State private var searchFocus = 0
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\LogsRow.timestamp, order: .reverse)]
    @State private var detailID: String?
    @State private var confirmClear = false
    @AppStorage("logs.fontSize") private var logsFontSize = 11

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    private static let spanFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var sourceRows: [LogsRow] {
        switch page {
        case .internalLogs, .settings: logManager.logs.map(LogsRow.init)
        case .systemIssues: systemLogs.entries.map(LogsRow.init)
        }
    }
    private var visibleRows: [LogsRow] {
        sourceRows
            .filter {
                selectedLevels.contains($0.levelFilter)
                    && (search.isEmpty
                        || $0.source.localizedCaseInsensitiveContains(search)
                        || $0.message.localizedCaseInsensitiveContains(search))
            }
            .sorted(using: sortOrder)
    }

    var body: some View {
        OnePlusWindowRoot(canvas: .logs) { sidebar } content: { content }
            .background(WindowAccessor(identifier: "logs"))
            .buttonStyle(OnePlusButtonStyle())
            .onChange(of: page) { _, newPage in
                selection.removeAll()
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
            .overlay(alignment: .topLeading) {
                Button("") { searchFocus &+= 1 }
                    .keyboardShortcut("f")
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
    }

    private var sidebar: some View {
        let counts = Dictionary(grouping: logManager.logs, by: \.level).mapValues(\.count)
        return OnePlusSidebar(title: "Logs") {
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
            OnePlusNavRow("Internal", systemImage: LogsPage.internalLogs.icon, selected: page == .internalLogs, count: logManager.logs.count) {
                page = .internalLogs
            }
            .keyboardShortcut("1")
            OnePlusNavRow("System issues", systemImage: LogsPage.systemIssues.icon, selected: page == .systemIssues, count: systemLogs.entries.count) {
                page = .systemIssues
            }
            .keyboardShortcut("2")

            OnePlusNavCaption("Levels")
            ForEach(LogLevel.allCases, id: \.self) { level in
                OnePlusNavRow(
                    level.name,
                    systemImage: selectedLevels.contains(level) ? level.icon : "circle",
                    selected: false,
                    count: counts[level, default: 0]
                ) { toggle(level) }
                .accessibilityValue(selectedLevels.contains(level) ? "Included" : "Excluded")
            }
        } bottom: {
            OnePlusNavRow("Settings", systemImage: "gearshape", selected: page == .settings) { page = .settings }
                .keyboardShortcut(",")
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .internalLogs, .systemIssues: logPage
        case .settings: LogsSettingsView()
        }
    }

    private var logPage: some View {
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
                    Button("Clear") { confirmClear = true }.buttonStyle(OnePlusButtonStyle(.destructive)).disabled(logManager.logs.isEmpty)
                }
            }
        } content: {
            if let error = systemLogs.errorMessage, page == .systemIssues {
                OnePlusBanner(error, tone: .error) {
                    Button("Try Again") { systemLogs.refresh(range: systemRange) }
                }
            }
            if systemLogs.isLoading && page == .systemIssues && systemLogs.entries.isEmpty {
                OnePlusCard { ProgressView("Reading system issues…").frame(maxWidth: .infinity).padding(OnePlusMetrics.spacing[8]) }
            } else if visibleRows.isEmpty {
                OnePlusCard {
                    OnePlusEmptyState(
                        page == .internalLogs ? "No internal logs" : "No system issues",
                        systemImage: page == .internalLogs ? "doc.text" : "checkmark.circle",
                        caption: search.isEmpty ? "No entries match the selected levels." : "Clear the search or include another level."
                    )
                }
            } else {
                OnePlusCard {
                    Table(visibleRows, selection: $selection, sortOrder: $sortOrder) {
                        TableColumn("Time", value: \LogsRow.timestamp) { row in
                            Text(Self.timeFormatter.string(from: row.timestamp))
                                .onePlusText(.mono)
                                .textSelection(.enabled)
                        }
                        .width(min: 92, ideal: 104)
                        TableColumn("Level", value: \LogsRow.level) { row in
                            Label(row.level, systemImage: row.symbol)
                                .foregroundStyle(levelColor(row))
                                .textSelection(.enabled)
                        }
                        .width(min: 82, ideal: 92)
                        TableColumn("Source", value: \LogsRow.source) { row in
                            Text(row.source)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .help(row.source)
                        }
                        .width(min: 150, ideal: 180)
                        TableColumn("Message", value: \LogsRow.message) { row in
                            Text(row.message)
                                .lineLimit(1)
                                .textSelection(.enabled)
                                .help(row.message)
                        }
                        .width(min: 280, ideal: 430)
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
    }

    private var subtitle: String {
        guard let first = visibleRows.map(\.timestamp).min(), let last = visibleRows.map(\.timestamp).max() else {
            return page == .systemIssues ? "0 entries · read on demand · up to \(SystemLogReader.maximumEntries)" : "0 entries"
        }
        return "\(visibleRows.count) entries · \(Self.spanFormatter.string(from: first)) – \(Self.spanFormatter.string(from: last))"
    }

    private func open(page pageID: String) {
        guard let requested = LogsPage(rawValue: pageID) else { return }
        page = requested
    }

    private func toggle(_ level: LogLevel) {
        if selectedLevels.contains(level) { selectedLevels.remove(level) }
        else { selectedLevels.insert(level) }
    }

    private func row(for id: String) -> LogsRow? { sourceRows.first { $0.id == id } }

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

    private func levelColor(_ row: LogsRow) -> Color {
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
        "[\(Self.timeFormatter.string(from: row.timestamp))] [\(row.level)] \(row.source): \(row.message)"
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

struct LogsSettingsView: View {
    @AppStorage("logs.fontSize") private var fontSize = 11

    var body: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Settings", subtitle: "Log display and retention")
        } content: {
            OnePlusSectionTitle("Logs")
            OnePlusCard {
                OnePlusSettingRow("Font size", caption: "Used for selectable log detail text.") {
                    OnePlusSelect(
                        choices: [(10, "Small"), (11, "Medium"), (12, "Default"), (14, "Large")],
                        selection: $fontSize,
                        accessibilityLabel: "Log font size"
                    )
                }
                OnePlusSettingRow("Retention", caption: "Internal entries older than this are removed.", separator: false) {
                    Text("2 days").onePlusText(.mono)
                }
            }
            OnePlusBanner("System issues are read from macOS only when requested. MacPowerToys never saves them.")
        }
        .accessibilityIdentifier("logs.settings")
    }
}

#Preview { LogsWindowView() }
