//
//  LogsWindowView.swift
//  powertoys
//

import SwiftUI
import AppKit

struct LogsWindowView: View {
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var searchText = ""
    @State private var showSettings = false
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
        VStack(spacing: 0) {
            SearchField(text: $searchText, placeholder: "Search logs...")
                .padding(.horizontal, 12)
                .padding(.top, 52)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 4) {
                SidebarSectionHeader(title: "Filter by Level")
                    .padding(.horizontal, 4)

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
                SidebarActionRow(icon: "gearshape", title: "Settings") {
                    showSettings = true
                }
                SidebarActionRow(icon: "trash", title: "Clear Logs") {
                    LogManager.shared.clearMemoryLogs()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 220)
        .background(VisualEffectBackground())
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filteredLogs.count) logs")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.top, 52)

            Divider()

            LogTextView(logs: filteredLogs.reversed(), fontSize: CGFloat(logsFontSize))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Settings Sheet

private struct LogsSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("logs.fontSize") private var logsFontSize: Int = 11

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs Settings")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

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
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 420, height: 240)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - NSTextView Wrapper for Drag Selection

private struct LogTextView: NSViewRepresentable {
    let logs: [LogEntryData]
    let fontSize: CGFloat

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

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

        for (index, entry) in logs.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let timeStr = Self.timeFormatter.string(from: entry.timestamp)
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
        .focusEffectDisabled()
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
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))
                    .font(.system(size: 14))

                Image(systemName: level.icon)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                Text(level.name)
                    .font(.system(size: 13))

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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
    }
}

#Preview {
    LogsWindowView()
        .frame(width: 900, height: 600)
}
