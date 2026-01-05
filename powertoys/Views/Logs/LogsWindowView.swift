//
//  LogsWindowView.swift
//  powertoys
//

import SwiftUI

struct LogsWindowView: View {
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var searchText = ""
    @State private var selectedLog: LogEntryData?

    private var filteredLogs: [LogEntryData] {
        let logs = LogManager.shared.logs

        return logs.filter { entry in
            guard selectedLevels.contains(entry.level) else { return false }

            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return entry.message.lowercased().contains(searchLower) ||
                       entry.source.lowercased().contains(searchLower)
            }

            return true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Logs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 52)

                LogSearchField(text: $searchText, placeholder: "Search logs...")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("FILTER BY LEVEL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                ForEach(LogLevel.allCases, id: \.self) { level in
                    LogLevelFilterRow(
                        level: level,
                        isSelected: selectedLevels.contains(level),
                        count: LogManager.shared.logs.filter { $0.level == level }.count
                    ) {
                        if selectedLevels.contains(level) {
                            selectedLevels.remove(level)
                        } else {
                            selectedLevels.insert(level)
                        }
                    }
                }
            }
            .padding(.bottom, 12)

            Divider()

            Spacer()

            VStack(spacing: 8) {
                Button {
                    LogManager.shared.clearMemoryLogs()
                } label: {
                    Label("Clear Logs", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .padding(.bottom, 12)
        }
        .frame(width: 220)
        .background(VisualEffectBackground())
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filteredLogs.count) logs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    LogManager.shared.info("Test log entry", source: "User")
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Add test log")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLogs.reversed()) { entry in
                        LogEntryRow(entry: entry, isSelected: selectedLog?.id == entry.id)
                            .onTapGesture {
                                selectedLog = entry
                            }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

// MARK: - Log Level Filter Row

private struct LogLevelFilterRow: View {
    let level: LogLevel
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? levelColor : .secondary)
                    .font(.system(size: 14))

                Image(systemName: level.icon)
                    .foregroundStyle(levelColor)
                    .font(.system(size: 12))

                Text(level.name)
                    .font(.system(size: 13))

                Spacer()

                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var levelColor: Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .purple
        }
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntryData
    let isSelected: Bool

    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.level.icon)
                .foregroundStyle(levelColor)
                .font(.system(size: 11))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.source)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(entry.message)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.03) : Color.clear))
        .onHover { isHovered = $0 }
    }

    private var levelColor: Color {
        switch entry.level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .purple
        }
    }
}

// MARK: - Log Search Field

private struct LogSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    LogsWindowView()
        .frame(width: 900, height: 600)
}
