//
//  CCHistoryDetailView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct CCHistoryDetailView: View {
    @Environment(ProjectManager.self) private var projectManager
    @Environment(SelectionManager.self) private var selectionManager
    @Environment(BookmarkManager.self) private var bookmarkManager

    @State private var filterOptions = FilterOptions()
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var searchMatchIndices: [Int] = []
    @State private var currentSearchIndex: Int = 0
    @State private var selectedTool: ToolUseBlock?
    @State private var showThinkingPanel: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if projectManager.selectedSession != nil {
                    FilterToolbarView(
                        filterOptions: $filterOptions,
                        searchText: $searchText,
                        isSearching: $isSearching,
                        showThinkingPanel: $showThinkingPanel,
                        hasThinking: hasThinkingContent
                    )

                    Divider()

                    if filteredMessages.isEmpty {
                        ContentUnavailableView(
                            "No Messages",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("No messages match the current filters.")
                        )
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
                    ContentUnavailableView(
                        "Select a Conversation",
                        systemImage: "text.bubble",
                        description: Text("Choose a conversation from the sidebar to view messages.")
                    )
                }
            }

            if selectedTool != nil {
                SlideOverPanel(
                    isPresented: Binding(
                        get: { selectedTool != nil },
                        set: { if !$0 { selectedTool = nil } }
                    ),
                    title: selectedTool?.name ?? "Tool Details",
                    persistenceKey: "toolDetails"
                ) {
                    ToolDetailsPanelContent(tool: selectedTool!)
                }
            }

            if showThinkingPanel {
                SlideOverPanel(
                    isPresented: $showThinkingPanel,
                    title: "Thinking",
                    persistenceKey: "thinking"
                ) {
                    ThinkingPanelContent(messages: filteredMessages)
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
        .onReceive(NotificationCenter.default.publisher(for: .conversationSearch)) { _ in
            isSearching = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .copySelected)) { _ in
            selectionManager.copySelected(messages: projectManager.currentMessages)
        }
    }
    
    private var filteredMessages: [CCMessage] {
        projectManager.currentMessages.filter { message in
            filterOptions.shouldShow(message: message)
        }
    }

    private var hasThinkingContent: Bool {
        projectManager.currentMessages.contains { $0.thinking != nil && !($0.thinking?.isEmpty ?? true) }
    }
}

// MARK: - Filter Toolbar

struct FilterToolbarView: View {
    @Binding var filterOptions: FilterOptions
    @Binding var searchText: String
    @Binding var isSearching: Bool
    @Binding var showThinkingPanel: Bool
    let hasThinking: Bool

    @Environment(ProjectManager.self) private var projectManager
    @Environment(BookmarkManager.self) private var bookmarkManager

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                FilterToggle(label: "User", isOn: $filterOptions.showUser)
                FilterToggle(label: "Claude", isOn: $filterOptions.showAssistant)
                FilterToggle(label: "System", isOn: $filterOptions.showSystem)

                Divider()
                    .frame(height: 20)

                FilterToggle(label: "Tools", isOn: $filterOptions.showToolCalls)
                FilterToggle(label: "Outputs", isOn: $filterOptions.showToolOutputs)
                FilterToggle(label: "Thinking", isOn: $filterOptions.showThinking)

                Divider()
                    .frame(height: 20)

                FilterToggle(label: "Empty", isOn: $filterOptions.showEmptyMessages)
            }

            Spacer()

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
                .help("Toggle Thinking Panel")
            }

            if isSearching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    TextField("Search in conversation...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(width: 180)

                    Button {
                        searchText = ""
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Button {
                    isSearching = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let session = projectManager.selectedSession {
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
                .help(bookmarkManager.isBookmarked(session) ? "Remove Bookmark" : "Add Bookmark")

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
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .padding(.top, 52)
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

    @Environment(SelectionManager.self) private var selectionManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(messages, id: \.id) { message in
                        MessageRowView(
                            message: message,
                            isSelected: selectionManager.isSelected(message.id),
                            searchText: searchText,
                            showToolCalls: filterOptions.showToolCalls,
                            showToolOutputs: filterOptions.showToolOutputs,
                            showThinking: filterOptions.showThinking,
                            onToolSelect: onToolSelect
                        )
                        .id(message.id)
                        .onTapGesture {
                            handleTap(message: message)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func handleTap(message: CCMessage) {
        if NSEvent.modifierFlags.contains(.shift) {
            if let firstSelected = selectionManager.selectedMessageIds.first {
                selectionManager.selectRange(from: firstSelected, to: message.id, in: messages)
            } else {
                selectionManager.selectMessage(message.id)
            }
        } else if NSEvent.modifierFlags.contains(.command) {
            selectionManager.toggleMessage(message.id)
        } else {
            selectionManager.selectMessage(message.id)
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(messages.filter { $0.thinking != nil && !($0.thinking?.isEmpty ?? true) }) { message in
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
        .environment(SelectionManager())
        .environment(BookmarkManager())
        .frame(width: 600, height: 500)
}
