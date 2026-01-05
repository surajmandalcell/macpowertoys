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
        HStack(spacing: 8) {
            HStack(spacing: 4) {
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
                Button {
                    bookmarkManager.toggleBookmark(session)
                } label: {
                    Image(systemName: bookmarkManager.isBookmarked(session) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14))
                        .foregroundStyle(bookmarkManager.isBookmarked(session) ? .orange : .secondary)
                        .frame(width: 32, height: 32)
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
                            .frame(width: 32, height: 32)
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
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
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
        .padding(.horizontal, 12)
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
                .background(isOn ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                .foregroundStyle(isOn ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Message List (Terminal Style)

struct MessageListView: View {
    let messages: [CCMessage]
    let searchText: String
    let filterOptions: FilterOptions

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var formattedContent: AttributedString {
        var result = AttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let boldMonoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

        for message in messages {
            // Thinking (if enabled)
            if filterOptions.showThinking, let thinking = message.thinking, !thinking.isEmpty {
                var thinkingPrefix = AttributedString("[thinking] ")
                thinkingPrefix.foregroundColor = .purple
                thinkingPrefix.font = boldMonoFont
                result.append(thinkingPrefix)

                var thinkingText = AttributedString(thinking + "\n")
                thinkingText.foregroundColor = NSColor.secondaryLabelColor
                thinkingText.font = monoFont
                result.append(thinkingText)
            }

            // Role prefix with color
            let (prefix, color) = roleInfo(for: message.type)
            var roleAttr = AttributedString(prefix + " ")
            roleAttr.foregroundColor = color
            roleAttr.font = boldMonoFont
            result.append(roleAttr)

            // Timestamp
            var timeAttr = AttributedString(Self.timeFormatter.string(from: message.timestamp) + " ")
            timeAttr.foregroundColor = NSColor.tertiaryLabelColor
            timeAttr.font = monoFont
            result.append(timeAttr)

            // Content (strip code block markers, flatten to plain text)
            let plainContent = stripCodeBlockMarkers(message.content)
            var contentAttr = highlightSearch(plainContent, searchText: searchText)
            contentAttr.font = monoFont
            result.append(contentAttr)
            result.append(AttributedString("\n"))

            // Tool calls (if enabled)
            if filterOptions.showToolCalls {
                for tool in message.toolUse {
                    var toolPrefix = AttributedString("[tool] ")
                    toolPrefix.foregroundColor = .orange
                    toolPrefix.font = boldMonoFont
                    result.append(toolPrefix)

                    var toolName = AttributedString(tool.name + "\n")
                    toolName.foregroundColor = NSColor.secondaryLabelColor
                    toolName.font = monoFont
                    result.append(toolName)

                    var toolInput = AttributedString("  " + tool.input + "\n")
                    toolInput.foregroundColor = NSColor.tertiaryLabelColor
                    toolInput.font = monoFont
                    result.append(toolInput)

                    // Tool output (if enabled)
                    if filterOptions.showToolOutputs, let output = tool.output {
                        var outputPrefix = AttributedString("[output] ")
                        outputPrefix.foregroundColor = .green
                        outputPrefix.font = boldMonoFont
                        result.append(outputPrefix)

                        let truncatedOutput = output.count > 500 ? String(output.prefix(500)) + "..." : output
                        var outputText = AttributedString(truncatedOutput + "\n")
                        outputText.foregroundColor = NSColor.tertiaryLabelColor
                        outputText.font = monoFont
                        result.append(outputText)
                    }
                }
            }

            result.append(AttributedString("\n"))
        }

        return result
    }

    var body: some View {
        ScrollView {
            Text(formattedContent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private func roleInfo(for type: MessageType) -> (String, NSColor) {
        switch type {
        case .user: return ("[user]", NSColor.systemBlue)
        case .assistant: return ("[claude]", NSColor.secondaryLabelColor)
        case .system: return ("[system]", NSColor.systemOrange)
        }
    }

    private func stripCodeBlockMarkers(_ text: String) -> String {
        var result = text
        let pattern = "```\\w*\\n?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        return result.replacingOccurrences(of: "```", with: "")
    }

    private func highlightSearch(_ text: String, searchText: String) -> AttributedString {
        var attributedString = AttributedString(text)
        guard !searchText.isEmpty else { return attributedString }

        let lowercasedText = text.lowercased()
        let lowercasedSearch = searchText.lowercased()

        var searchStart = lowercasedText.startIndex
        while let range = lowercasedText.range(of: lowercasedSearch, range: searchStart..<lowercasedText.endIndex) {
            if let attrLower = AttributedString.Index(range.lowerBound, within: attributedString),
               let attrUpper = AttributedString.Index(range.upperBound, within: attributedString) {
                attributedString[attrLower..<attrUpper].backgroundColor = .systemYellow.withAlphaComponent(0.3)
            }
            searchStart = range.upperBound
        }

        return attributedString
    }
}

// MARK: - Panel Contents

struct ToolDetailsPanelContent: View {
    let tool: ToolUseBlock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(tool.input)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if let output = tool.output {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(16)
        }
    }
}

struct ThinkingPanelContent: View {
    let messages: [CCMessage]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var formattedThinking: AttributedString {
        var result = AttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let boldMonoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

        let thinkingMessages = messages.filter { $0.thinking != nil && !($0.thinking?.isEmpty ?? true) }.reversed()

        for message in thinkingMessages {
            var timeAttr = AttributedString(Self.timeFormatter.string(from: message.timestamp) + " ")
            timeAttr.foregroundColor = NSColor.tertiaryLabelColor
            timeAttr.font = monoFont
            result.append(timeAttr)

            var prefix = AttributedString("[thinking] ")
            prefix.foregroundColor = .purple
            prefix.font = boldMonoFont
            result.append(prefix)

            var content = AttributedString((message.thinking ?? "") + "\n\n")
            content.foregroundColor = NSColor.secondaryLabelColor
            content.font = monoFont
            result.append(content)
        }

        return result
    }

    var body: some View {
        ScrollView {
            Text(formattedThinking)
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
