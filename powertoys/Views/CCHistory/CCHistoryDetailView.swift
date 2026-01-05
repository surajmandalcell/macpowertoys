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
    @State private var selectedTool: ToolUseBlock?
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
                                filterOptions: filterOptions,
                                onToolSelect: { tool in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedTool = tool
                                    }
                                }
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

            if let tool = selectedTool {
                CenteredModal(
                    isPresented: Binding(
                        get: { selectedTool != nil },
                        set: { if !$0 { selectedTool = nil } }
                    ),
                    title: tool.name
                ) {
                    ToolDetailsPanelContent(tool: tool)
                }
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

// MARK: - Message List

struct MessageListView: View {
    let messages: [CCMessage]
    let searchText: String
    let filterOptions: FilterOptions
    var onToolSelect: ((ToolUseBlock) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(messages, id: \.id) { message in
                    MessageRowView(
                        message: message,
                        searchText: searchText,
                        showToolCalls: filterOptions.showToolCalls,
                        showToolOutputs: filterOptions.showToolOutputs,
                        showThinking: filterOptions.showThinking,
                        onToolSelect: onToolSelect
                    )
                    .id(message.id)
                }
            }
            .padding(.vertical, 8)
            .textSelection(.enabled)
        }
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

    private var thinkingMessages: [CCMessage] {
        messages.filter { $0.thinking != nil && !($0.thinking?.isEmpty ?? true) }.reversed()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(thinkingMessages) { message in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: message.type.icon)
                                .font(.caption)
                            Text(message.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(message.thinking ?? "")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
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
