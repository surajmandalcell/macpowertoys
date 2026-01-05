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
    
    var body: some View {
        VStack(spacing: 0) {
            if projectManager.selectedSession != nil {
                // Toolbar
                FilterToolbarView(
                    filterOptions: $filterOptions,
                    searchText: $searchText,
                    isSearching: $isSearching
                )
                
                Divider()
                
                // Messages
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
                        filterOptions: filterOptions
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if projectManager.selectedSession != nil {
                    Menu {
                        Button {
                            ExportManager.export(messages: filteredMessages, format: .markdown)
                        } label: {
                            Label("Export as Markdown", systemImage: "doc.text")
                        }
                        
                        Button {
                            ExportManager.export(messages: filteredMessages, format: .json)
                        } label: {
                            Label("Export as JSON", systemImage: "curlybraces")
                        }
                        
                        Button {
                            ExportManager.export(messages: filteredMessages, format: .plainText)
                        } label: {
                            Label("Export as Plain Text", systemImage: "doc.plaintext")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    
                    if let session = projectManager.selectedSession {
                        Button {
                            bookmarkManager.toggleBookmark(session)
                        } label: {
                            Label(
                                bookmarkManager.isBookmarked(session) ? "Remove Bookmark" : "Add Bookmark",
                                systemImage: bookmarkManager.isBookmarked(session) ? "bookmark.fill" : "bookmark"
                            )
                        }
                    }
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
}

// MARK: - Filter Toolbar

struct FilterToolbarView: View {
    @Binding var filterOptions: FilterOptions
    @Binding var searchText: String
    @Binding var isSearching: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Filter toggles
            HStack(spacing: 4) {
                FilterToggle(label: "User", isOn: $filterOptions.showUser)
                FilterToggle(label: "Claude", isOn: $filterOptions.showAssistant)
                FilterToggle(label: "System", isOn: $filterOptions.showSystem)
                
                Divider()
                    .frame(height: 20)
                
                FilterToggle(label: "Tools", isOn: $filterOptions.showToolCalls)
                FilterToggle(label: "Outputs", isOn: $filterOptions.showToolOutputs)
                FilterToggle(label: "Thinking", isOn: $filterOptions.showThinking)
            }
            
            Spacer()
            
            // Search
            if isSearching {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search in conversation...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                    
                    Button {
                        searchText = ""
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Button {
                    isSearching = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FilterToggle: View {
    let label: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.clear)
                .foregroundStyle(isOn ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Message List

struct MessageListView: View {
    let messages: [CCMessage]
    let searchText: String
    let filterOptions: FilterOptions

    @Environment(SelectionManager.self) private var selectionManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        MessageRowView(
                            message: message,
                            isSelected: selectionManager.isSelected(message.id),
                            searchText: searchText,
                            showToolCalls: filterOptions.showToolCalls,
                            showToolOutputs: filterOptions.showToolOutputs,
                            showThinking: filterOptions.showThinking
                        )
                        .id(message.id)
                        .onTapGesture {
                            handleTap(message: message, index: index)
                        }
                    }
                }
                .padding(16)
            }
        }
    }
    
    private func handleTap(message: CCMessage, index: Int) {
        if NSEvent.modifierFlags.contains(.shift) {
            // Shift-click for range selection
            if let firstSelected = selectionManager.selectedMessageIds.first {
                selectionManager.selectRange(from: firstSelected, to: message.id, in: messages)
            } else {
                selectionManager.selectMessage(message.id)
            }
        } else if NSEvent.modifierFlags.contains(.command) {
            // Cmd-click for toggle
            selectionManager.toggleMessage(message.id)
        } else {
            // Regular click
            selectionManager.selectMessage(message.id)
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
