//
//  LogsWindowView.swift
//  powertoys
//

import SwiftUI
import AppKit

struct LogsWindowView: View {
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var searchText = ""
    @AppStorage("logs.fontSize") private var logsFontSize: Int = 11

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

            LogTextView(logs: filteredLogs.reversed(), fontSize: CGFloat(logsFontSize))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - NSTextView Wrapper for Drag Selection

private struct LogTextView: NSViewRepresentable {
    let logs: [LogEntryData]
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
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
        textView.textStorage?.setAttributedString(buildAttributedString())
    }

    private func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for (index, entry) in logs.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let timeStr = timeFormatter.string(from: entry.timestamp)
            let levelStr = entry.level.name.prefix(1).uppercased()
            let line = "[\(timeStr)] [\(levelStr)] \(entry.source): \(entry.message)"

            let attrs: [NSAttributedString.Key: Any] = [
                .font: monoFont,
                .foregroundColor: colorForLevel(entry.level)
            ]

            result.append(NSAttributedString(string: line, attributes: attrs))
        }

        if result.length == 0 {
            let emptyFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: emptyFont,
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            result.append(NSAttributedString(string: "No logs to display", attributes: emptyAttrs))
        }

        return result
    }

    private func colorForLevel(_ level: LogLevel) -> NSColor {
        switch level {
        case .error: return NSColor.systemRed.withAlphaComponent(0.85)
        case .warning: return NSColor.systemOrange.withAlphaComponent(0.85)
        case .info: return .secondaryLabelColor
        case .debug: return .tertiaryLabelColor
        }
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    LogsWindowView()
        .frame(width: 900, height: 600)
}
