import AppKit
import OSLog
import SwiftUI

private enum LogsSource: String, CaseIterable, Identifiable {
    case internalLogs = "Internal Logs"
    case systemIssues = "System Issues"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .internalLogs: "app.badge.checkmark"
        case .systemIssues: "desktopcomputer.trianglebadge.exclamationmark"
        }
    }
}

enum SystemLogRange: TimeInterval, CaseIterable, Identifiable, Sendable {
    case oneHour = 3600
    case sixHours = 21600
    case oneDay = 86400

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
    enum Level: String, Sendable {
        case error = "E"
        case fault = "F"
    }

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
                let entries = try await Task.detached(priority: .utility) {
                    try Self.readEntries(range: range)
                }.value
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
        let predicate = NSPredicate(format: "messageType == error OR messageType == fault")
        let sequence = try store.getEntries(
            with: [.reverse],
            at: store.position(date: now),
            matching: predicate
        )
        var result: [SystemLogLine] = []
        result.reserveCapacity(maximumEntries)

        for case let entry as OSLogEntryLog in sequence {
            try Task.checkCancellation()
            guard entry.date >= cutoff else { break }
            let level: SystemLogLine.Level = entry.level == .fault ? .fault : .error
            let detail = [entry.subsystem, entry.category]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
            result.append(SystemLogLine(
                id: UUID(),
                timestamp: entry.date,
                level: level,
                source: detail.isEmpty ? entry.process : "\(entry.process) · \(detail)",
                message: entry.composedMessage
            ))
            if result.count == maximumEntries { break }
        }
        return result
    }
}

struct LogsWindowView: View {
    @State private var selectedSource = LogsSource.internalLogs
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var systemRange = SystemLogRange.oneHour
    @State private var systemLogs = SystemLogReader()
    @State private var searchText = ""
    @State private var showSettings = false
    @AppStorage("logs.fontSize") private var logsFontSize = 11

    private var filteredLogs: [LogEntryData] {
        LogManager.shared.logs.filter { entry in
            guard selectedLevels.contains(entry.level) else { return false }
            return matchesSearch(source: entry.source, message: entry.message)
        }
    }

    private var filteredSystemLogs: [SystemLogLine] {
        systemLogs.entries.filter { matchesSearch(source: $0.source, message: $0.message) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
                .utilityContentTransition(value: selectedSource)
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "logs"))
        .onChange(of: selectedSource) {
            if selectedSource == .systemIssues && systemLogs.entries.isEmpty {
                systemLogs.refresh(range: systemRange)
            }
        }
        .onChange(of: systemRange) {
            if selectedSource == .systemIssues { systemLogs.refresh(range: systemRange) }
        }
        .onDisappear { systemLogs.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("logs") == true else { return }
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            LogsSettingsSheet()
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            sidebarBody
            SidebarTitle(text: "Logs")
        }
    }

    private var sidebarBody: some View {
        let levelCounts = Dictionary(grouping: LogManager.shared.logs, by: \.level).mapValues(\.count)
        return VStack(spacing: 0) {
            SidebarSearchField(text: $searchText, placeholder: "Search logs...")
                .padding(.horizontal, 12)
                .padding(.top, UtilityLayout.workspaceContentTopInset)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 4) {
                SidebarSectionHeader(title: "Sources")
                    .padding(.horizontal, 4)

                ForEach(LogsSource.allCases) { source in
                    SidebarRow(
                        icon: source.icon,
                        title: source.rawValue,
                        isSelected: selectedSource == source
                    ) {
                        selectedSource = source
                    }
                    .accessibilityIdentifier("logs.source.\(source.id)")
                }
            }
            .padding(.horizontal, 12)

            if selectedSource == .internalLogs {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarSectionHeader(title: "Internal Levels")
                        .padding(.horizontal, 4)

                    ForEach(LogLevel.allCases, id: \.self) { level in
                        LogLevelFilterRow(
                            level: level,
                            isSelected: selectedLevels.contains(level),
                            count: levelCounts[level, default: 0]
                        ) {
                            if selectedLevels.contains(level) {
                                selectedLevels.remove(level)
                            } else {
                                selectedLevels.insert(level)
                            }
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
            }

            Spacer()

            VStack(spacing: 4) {
                SidebarActionRow(icon: "gearshape", title: "Settings") {
                    showSettings = true
                }
                if selectedSource == .internalLogs {
                    SidebarActionRow(icon: "trash", title: "Clear Internal Logs") {
                        LogManager.shared.clearMemoryLogs()
                    }
                } else {
                    SidebarActionRow(icon: "arrow.clockwise", title: "Refresh Issues") {
                        systemLogs.refresh(range: systemRange)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: UtilityLayout.compactSidebarWidth)
        .background(VisualEffectBackground())
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSource {
        case .internalLogs:
            internalContent
        case .systemIssues:
            systemContent
        }
    }

    private var internalContent: some View {
        let entries = filteredLogs
        return VStack(spacing: 0) {
            contentHeader(title: "Internal Logs", detail: "\(entries.count) entries")
            QuietDivider()
            SelectableLogTextView(
                lines: entries.reversed().map { RenderedLogLine($0) },
                fontSize: CGFloat(logsFontSize),
                emptyMessage: "No internal logs to display"
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var systemContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("System Issues")
                        .font(.system(size: 13, weight: .semibold))
                    Text("macOS errors and faults · read on demand · up to \(SystemLogReader.maximumEntries)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if systemLogs.isLoading { ProgressView().controlSize(.small) }
                Picker("Time Range", selection: $systemRange) {
                    ForEach(SystemLogRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                Button("Refresh") { systemLogs.refresh(range: systemRange) }
                    .controlSize(.small)
                    .disabled(systemLogs.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            QuietDivider()

            if let error = systemLogs.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Unable to read system logs")
                        .font(.system(size: 13, weight: .medium))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Button("Try Again") { systemLogs.refresh(range: systemRange) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if systemLogs.isLoading && systemLogs.entries.isEmpty {
                ProgressView("Reading system issues…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SelectableLogTextView(
                    lines: filteredSystemLogs.map { RenderedLogLine($0) },
                    fontSize: CGFloat(logsFontSize),
                    emptyMessage: "No system errors or faults in \(systemRange.title.lowercased())"
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func contentHeader(title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func matchesSearch(source: String, message: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return source.localizedCaseInsensitiveContains(searchText)
            || message.localizedCaseInsensitiveContains(searchText)
    }
}

private struct LogsSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs Settings")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                UtilityModalCloseButton { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            QuietDivider()
            LogsSettingsView()
        }
        .frame(width: 420, height: 240)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct LogsSettingsView: View {
    @AppStorage("logs.fontSize") private var logsFontSize = 11

    var body: some View {
        Form {
            Section {
                Picker("Font Size", selection: $logsFontSize) {
                    Text("Small").tag(10)
                    Text("Medium").tag(11)
                    Text("Default").tag(12)
                    Text("Large").tag(14)
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("System Issues are read from macOS only when requested and are never saved by MacPowerToys.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .thinScrollIndicators()
    }
}

private struct RenderedLogLine {
    let id: UUID
    let timestamp: Date
    let level: String
    let source: String
    let message: String
    let color: NSColor

    init(_ entry: LogEntryData) {
        id = entry.id
        timestamp = entry.timestamp
        level = entry.level.name.prefix(1).uppercased()
        source = entry.source
        message = entry.message
        color = switch entry.level {
        case .error: NSColor.systemRed.withAlphaComponent(0.85)
        case .warning: NSColor.systemOrange.withAlphaComponent(0.85)
        case .info: .secondaryLabelColor
        case .debug: .tertiaryLabelColor
        }
    }

    init(_ entry: SystemLogLine) {
        id = entry.id
        timestamp = entry.timestamp
        level = entry.level.rawValue
        source = entry.source
        message = entry.message
        color = entry.level == .fault
            ? NSColor.systemRed.withAlphaComponent(0.9)
            : NSColor.systemOrange.withAlphaComponent(0.9)
    }
}

private struct SelectableLogTextView: NSViewRepresentable {
    let lines: [RenderedLogLine]
    let fontSize: CGFloat
    let emptyMessage: String

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    final class Coordinator {
        var signature: Signature?
    }

    struct Signature: Equatable {
        let lineIDs: [UUID]
        let fontSize: CGFloat
        let emptyMessage: String
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.configureThinScrollIndicators()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.isRichText = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let signature = Signature(lineIDs: lines.map(\.id), fontSize: fontSize, emptyMessage: emptyMessage)
        guard signature != context.coordinator.signature else { return }
        context.coordinator.signature = signature
        textView.textStorage?.setAttributedString(attributedString())
    }

    private func attributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            let time = Self.timeFormatter.string(from: line.timestamp)
            result.append(NSAttributedString(
                string: "[\(time)] [\(line.level)] \(line.source): \(line.message)",
                attributes: [.font: font, .foregroundColor: line.color]
            ))
        }
        if result.length == 0 {
            result.append(NSAttributedString(
                string: emptyMessage,
                attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        }
        return result
    }
}

private struct SidebarActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle())
        .focusEffectDisabled()
    }
}

private struct LogLevelFilterRow: View {
    let level: LogLevel
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))
                    .font(.system(size: 14))
                Image(systemName: level.icon)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                Text(level.name).font(.system(size: 13))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle())
        .focusEffectDisabled()
    }
}

#Preview {
    LogsWindowView()
        .frame(width: 900, height: 600)
}
