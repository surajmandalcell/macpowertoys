//
//  LogsWindowView.swift
//  powertoys
//

import SwiftUI

struct LogsWindowView: View {
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var searchText = ""

    private var filteredLogs: [LogEntryData] {
        LogManager.shared.logs.filter { entry in
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
        .ignoresSafeArea()
        .background(WindowAccessor())
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12)
                .padding(.top, 52)
                .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("FILTER BY LEVEL")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)

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

                Spacer()

                VStack(spacing: 4) {
                    SidebarActionRow(icon: "trash", title: "Clear Logs") {
                        LogManager.shared.clearMemoryLogs()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Text("Logs")
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 84)
                .padding(.top, 8)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.top, 28)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLogs.reversed()) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
                .textSelection(.enabled)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Sidebar Action Row

private struct SidebarActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 13))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                    .foregroundStyle(isSelected ? .secondary : .tertiary)
                    .font(.system(size: 14))

                Image(systemName: level.icon)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                Text(level.name)
                    .font(.system(size: 13))

                Spacer()

                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntryData

    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.level.icon)
                .foregroundStyle(.tertiary)
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

                    levelBadge
                }

                Text(entry.message)
                    .font(.system(size: 12))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var levelBadge: some View {
        Text(entry.level.name.uppercased())
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(levelColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(levelColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
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

#Preview {
    LogsWindowView()
        .frame(width: 900, height: 600)
}
