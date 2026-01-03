//
//  CCHistorySidebarView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct CCHistorySidebarView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    @State private var searchText: String = ""
    @State private var expandedProjects: Set<String> = []
    @AppStorage("cchistory.expandedProjects") private var storedExpandedProjects: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Global Search
            SearchField(text: $searchText, placeholder: "Search all conversations...")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            Divider()
            
            // Main List
            List(selection: $projectManager.selectedSession) {
                // Bookmarks Section
                if !bookmarkManager.bookmarks.isEmpty {
                    Section("Bookmarks") {
                        BookmarksChipsView()
                    }
                }
                
                // Projects
                if searchText.isEmpty {
                    projectsSection
                } else {
                    searchResultsSection
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("CC History")
        .onAppear {
            loadExpandedState()
        }
        .onChange(of: expandedProjects) { _, newValue in
            saveExpandedState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .globalSearch)) { _ in
            // Focus search field - would need focus state
        }
    }
    
    // MARK: - Projects Section
    
    private var projectsSection: some View {
        ForEach(filteredProjects) { project in
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedProjects.contains(project.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedProjects.insert(project.id)
                        } else {
                            expandedProjects.remove(project.id)
                        }
                    }
                )
            ) {
                ForEach(project.sessions) { session in
                    SessionRowView(session: session, projectName: project.displayName)
                        .tag(session)
                }
            } label: {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(project.displayName)
                        .lineLimit(1)
                    Spacer()
                    Text("\(project.sessions.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Search Results
    
    @State private var searchResults: [SearchResult] = []
    
    private var searchResultsSection: some View {
        Group {
            if searchResults.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No conversations match '\(searchText)'")
                )
            } else {
                ForEach(searchResults) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(result.project.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        SessionRowView(session: result.session, projectName: result.project.displayName)
                    }
                    .tag(result.session)
                }
            }
        }
        .task(id: searchText) {
            guard !searchText.isEmpty else {
                searchResults = []
                return
            }
            
            // Debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            searchResults = await projectManager.searchGlobally(query: searchText)
        }
    }
    
    // MARK: - Helpers
    
    private var filteredProjects: [CCProject] {
        projectManager.projects
    }
    
    private func loadExpandedState() {
        let ids = storedExpandedProjects.split(separator: ",").map(String.init)
        expandedProjects = Set(ids)
    }
    
    private func saveExpandedState() {
        storedExpandedProjects = expandedProjects.joined(separator: ",")
    }
}

// MARK: - Search Field

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Bookmarks Chips

struct BookmarksChipsView: View {
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(bookmarkManager.bookmarks) { session in
                    Button {
                        Task {
                            await projectManager.loadMessages(for: session)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bookmark.fill")
                                .font(.caption2)
                            Text(session.displayTitle)
                                .lineLimit(1)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: CCSession
    let projectName: String
    
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .lineLimit(2)
                    .font(.body)
                
                HStack(spacing: 8) {
                    if let timestamp = session.timestamp {
                        Text(timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(session.messageCount) messages")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            if bookmarkManager.isBookmarked(session) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                bookmarkManager.toggleBookmark(session)
            } label: {
                if bookmarkManager.isBookmarked(session) {
                    Label("Remove Bookmark", systemImage: "bookmark.slash")
                } else {
                    Label("Add Bookmark", systemImage: "bookmark")
                }
            }
        }
    }
}

#Preview {
    CCHistorySidebarView()
        .environmentObject(ProjectManager())
        .environmentObject(BookmarkManager())
        .frame(width: 280, height: 600)
}
