//
//  CCHistoryDetailView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct CCHistoryDetailView: View {
    @Environment(ProjectManager.self) private var projectManager
    @Environment(BookmarkManager.self) private var bookmarkManager

    @AppStorage("cchistory.filter.showUser") private var showUser = true
    @AppStorage("cchistory.filter.showAssistant") private var showAssistant = true
    @AppStorage("cchistory.filter.showSystem") private var showSystem = false
    @AppStorage("cchistory.filter.showToolCalls") private var showToolCalls = false
    @AppStorage("cchistory.filter.showToolOutputs") private var showToolOutputs = false
    @AppStorage("cchistory.filter.showThinking") private var showThinking = false
    @AppStorage("cchistory.filter.showEmpty") private var showEmpty = false

    @State private var searchText: String = ""
    @State private var showThinkingPanel: Bool = false

    private var filterOptions: FilterOptions {
        FilterOptions(
            showUser: showUser,
            showAssistant: showAssistant,
            showSystem: showSystem,
            showToolCalls: showToolCalls,
            showToolOutputs: showToolOutputs,
            showThinking: showThinking,
            showEmptyMessages: showEmpty
        )
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if projectManager.selectedSession != nil {
                        FilterToolbarView(
                            showUser: $showUser,
                            showAssistant: $showAssistant,
                            showSystem: $showSystem,
                            showToolCalls: $showToolCalls,
                            showToolOutputs: $showToolOutputs,
                            showThinking: $showThinking,
                            showEmpty: $showEmpty,
                            searchText: $searchText,
                            showThinkingPanel: $showThinkingPanel,
                            hasThinking: hasThinkingContent
                        )

                        Divider()

                        if projectManager.isLoadingMessages {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        } else if filteredMessages.isEmpty {
                            Spacer()
                            EmptyStateView(icon: "bubble.left.and.bubble.right", message: "No Messages")
                            Spacer()
                        } else {
                            MessageListView(
                                messages: filteredMessages,
                                searchText: searchText,
                                filterOptions: filterOptions
                            )
                        }
                    } else {
                        Spacer()
                        EmptyStateView(icon: "text.bubble", message: "Select a Conversation")
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showThinkingPanel {
                CenteredModal(isPresented: $showThinkingPanel, title: "Thinking") {
                    ThinkingPanelContent(messages: projectManager.currentMessages)
                }
            }
        }
        .onChange(of: projectManager.selectedSession) { _, session in
            if let session = session {
                Task {
                    await projectManager.loadMessages(for: session)
                }
            }
        }
    }
    
    private var filteredMessages: [CCMessage] {
        projectManager.currentMessages.filter { message in
            filterOptions.shouldShow(message: message)
        }.reversed()
    }

    private var hasThinkingContent: Bool {
        projectManager.currentMessages.contains { $0.thinking != nil && !($0.thinking?.isEmpty ?? true) }
    }
}

// MARK: - Filter Toolbar

struct FilterToolbarView: View {
    @Binding var showUser: Bool
    @Binding var showAssistant: Bool
    @Binding var showSystem: Bool
    @Binding var showToolCalls: Bool
    @Binding var showToolOutputs: Bool
    @Binding var showThinking: Bool
    @Binding var showEmpty: Bool
    @Binding var searchText: String
    @Binding var showThinkingPanel: Bool
    let hasThinking: Bool

    @Environment(ProjectManager.self) private var projectManager
    @Environment(BookmarkManager.self) private var bookmarkManager

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                FilterToggle(label: "User", isOn: $showUser)
                FilterToggle(label: "Claude", isOn: $showAssistant)
                FilterToggle(label: "System", isOn: $showSystem)

                Divider().frame(height: 20)

                FilterToggle(label: "Tools", isOn: $showToolCalls)
                FilterToggle(label: "Outputs", isOn: $showToolOutputs)
                FilterToggle(label: "Thinking", isOn: $showThinking)

                Divider().frame(height: 20)

                FilterToggle(label: "Empty", isOn: $showEmpty)
            }

            Spacer()

            if let session = projectManager.selectedSession {
                HStack(spacing: 4) {
                    Button {
                        bookmarkManager.toggleBookmark(session)
                    } label: {
                        Image(systemName: bookmarkManager.isBookmarked(session) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 14))
                            .foregroundStyle(bookmarkManager.isBookmarked(session) ? .orange : .secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if hasThinking {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showThinkingPanel.toggle()
                            }
                        } label: {
                            Image(systemName: showThinkingPanel ? "brain.head.profile.fill" : "brain.head.profile")
                                .font(.system(size: 14))
                                .foregroundStyle(showThinkingPanel ? .purple : .secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Menu {
                        Button { ExportManager.export(messages: projectManager.currentMessages, format: .markdown) } label: {
                            Label("Export as Markdown", systemImage: "doc.text")
                        }
                        Button { ExportManager.export(messages: projectManager.currentMessages, format: .json) } label: {
                            Label("Export as JSON", systemImage: "curlybraces")
                        }
                        Button { ExportManager.export(messages: projectManager.currentMessages, format: .plainText) } label: {
                            Label("Export as Plain Text", systemImage: "doc.plaintext")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 160)
            .padding(8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .padding(.top, 44)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FilterToggle: View {
    let label: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOn ? Color.accentColor.opacity(0.2) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                .foregroundStyle(isOn ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Message List (Terminal Style with NSTextView)

struct MessageListView: View {
    let messages: [CCMessage]
    let searchText: String
    let filterOptions: FilterOptions

    var body: some View {
        TerminalTextView(
            messages: messages,
            searchText: searchText,
            filterOptions: filterOptions
        )
    }
}

enum CCHistoryTextSearch {
    static func ranges(in text: String, matching query: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex

        while let range = text.range(
            of: query,
            options: [.caseInsensitive],
            range: searchStart..<text.endIndex
        ) {
            ranges.append(range)
            searchStart = range.upperBound
        }

        return ranges
    }
}

private struct TerminalTextView: NSViewRepresentable {
    let messages: [CCMessage]
    let searchText: String
    let filterOptions: FilterOptions

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let codeBlockRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "```\\w*\\n?", options: [])
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
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(buildAttributedString())
    }

    private func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let boldMonoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

        for (index, message) in messages.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            if filterOptions.showThinking, let thinking = message.thinking, !thinking.isEmpty {
                result.append(NSAttributedString(
                    string: "[thinking] ",
                    attributes: [.font: boldMonoFont, .foregroundColor: NSColor.systemPurple]
                ))
                result.append(NSAttributedString(
                    string: thinking + "\n",
                    attributes: [.font: monoFont, .foregroundColor: NSColor.secondaryLabelColor]
                ))
            }

            let (prefix, color) = roleInfo(for: message.type)
            result.append(NSAttributedString(
                string: prefix + " ",
                attributes: [.font: boldMonoFont, .foregroundColor: color]
            ))

            result.append(NSAttributedString(
                string: Self.timeFormatter.string(from: message.timestamp) + " ",
                attributes: [.font: monoFont, .foregroundColor: NSColor.tertiaryLabelColor]
            ))

            let plainContent = stripCodeBlockMarkers(message.content)
            appendWithSearchHighlight(to: result, text: plainContent, font: monoFont)
            result.append(NSAttributedString(string: "\n"))

            if filterOptions.showToolCalls {
                for tool in message.toolUse {
                    result.append(NSAttributedString(
                        string: "[tool] ",
                        attributes: [.font: boldMonoFont, .foregroundColor: NSColor.systemOrange]
                    ))
                    result.append(NSAttributedString(
                        string: tool.name + "\n",
                        attributes: [.font: monoFont, .foregroundColor: NSColor.secondaryLabelColor]
                    ))
                    result.append(NSAttributedString(
                        string: "  " + tool.input + "\n",
                        attributes: [.font: monoFont, .foregroundColor: NSColor.tertiaryLabelColor]
                    ))

                    if filterOptions.showToolOutputs, let output = tool.output {
                        result.append(NSAttributedString(
                            string: "[output] ",
                            attributes: [.font: boldMonoFont, .foregroundColor: NSColor.systemGreen]
                        ))
                        let truncatedOutput = output.count > 500 ? String(output.prefix(500)) + "..." : output
                        result.append(NSAttributedString(
                            string: truncatedOutput + "\n",
                            attributes: [.font: monoFont, .foregroundColor: NSColor.tertiaryLabelColor]
                        ))
                    }
                }
            }
        }

        if result.length == 0 {
            result.append(NSAttributedString(
                string: "No messages to display",
                attributes: [.font: monoFont, .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        }

        return result
    }

    private func roleInfo(for type: MessageType) -> (String, NSColor) {
        switch type {
        case .user: return ("[user]", NSColor.systemBlue)
        case .assistant: return ("[claude]", NSColor.secondaryLabelColor)
        case .system: return ("[system]", NSColor.systemOrange)
        }
    }

    private func stripCodeBlockMarkers(_ text: String) -> String {
        guard let regex = Self.codeBlockRegex else {
            return text.replacingOccurrences(of: "```", with: "")
        }
        var result = text
        result = regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
        return result.replacingOccurrences(of: "```", with: "")
    }

    private func appendWithSearchHighlight(to result: NSMutableAttributedString, text: String, font: NSFont) {
        let textColor = NSColor.labelColor

        guard !searchText.isEmpty else {
            result.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor]))
            return
        }

        var lastEnd = text.startIndex

        for range in CCHistoryTextSearch.ranges(in: text, matching: searchText) {
            if range.lowerBound > lastEnd {
                let beforeRange = lastEnd..<range.lowerBound
                result.append(NSAttributedString(string: String(text[beforeRange]), attributes: [.font: font, .foregroundColor: textColor]))
            }

            let matchText = String(text[range])
            result.append(NSAttributedString(
                string: matchText,
                attributes: [.font: font, .foregroundColor: textColor, .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.3)]
            ))

            lastEnd = range.upperBound
        }

        if lastEnd < text.endIndex {
            result.append(NSAttributedString(string: String(text[lastEnd...]), attributes: [.font: font, .foregroundColor: textColor]))
        }
    }
}

@MainActor
struct ThinkingPanelContent: View {
    let messages: [CCMessage]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var formattedThinking: Text {
        var result = Text("")
        let monoFont = Font.system(size: 12, weight: .regular, design: .monospaced)
        let boldMonoFont = Font.system(size: 12, weight: .medium, design: .monospaced)
        let thinkingMessages = messages.filter { $0.thinking != nil && !($0.thinking?.isEmpty ?? true) }.reversed()

        for message in thinkingMessages {
            let time = Text(Self.timeFormatter.string(from: message.timestamp) + " ")
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .font(monoFont)
            let prefix = Text("[thinking] ")
                .foregroundColor(.purple)
                .font(boldMonoFont)
            let content = Text((message.thinking ?? "") + "\n\n")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .font(monoFont)
            result = Text("\(result)\(time)\(prefix)\(content)")
        }

        return result
    }

    var body: some View {
        ScrollView {
            formattedThinking
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }
}

#Preview {
    CCHistoryDetailView()
        .environment(ProjectManager())
        .environment(BookmarkManager())
        .frame(width: 600, height: 500)
}
