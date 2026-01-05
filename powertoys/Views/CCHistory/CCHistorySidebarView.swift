//
//  CCHistorySidebarView.swift
//  powertoys
//

import SwiftUI

struct CCHistorySidebarView: View {
    @Environment(ProjectManager.self) private var projectManager
    @Environment(BookmarkManager.self) private var bookmarkManager

    @State private var searchText: String = ""
    @State private var expandedProjects: Set<String> = []
    @State private var isSearching = false
    @AppStorage("cchistory.expandedProjects") private var storedExpandedProjects: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                SearchField(text: $searchText, placeholder: "Search conversations...", isLoading: isSearching)
                    .padding(.horizontal, 12)
                    .padding(.top, 52)
                    .padding(.bottom, 12)

                if !bookmarkManager.bookmarks.isEmpty {
                    BookmarksSection()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if searchText.isEmpty {
                            projectsList
                        } else {
                            searchResultsList
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, projectManager.isLoading ? 44 : 0)
                }
            }

            SidebarTitle(text: "CC History")

            if projectManager.isLoading {
                VStack {
                    Spacer()
                    VStack(spacing: 4) {
                        ProgressView(value: projectManager.loadingProgress)
                            .progressViewStyle(.linear)
                        Text("Loading projects...")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
        .onAppear { loadExpandedState() }
        .onChange(of: expandedProjects) { _, _ in saveExpandedState() }
        .task(id: searchText) {
            guard !searchText.isEmpty else {
                searchResults = []
                isSearching = false
                return
            }
            isSearching = true
            try? await Task.sleep(nanoseconds: 300_000_000)
            searchResults = await projectManager.searchGlobally(query: searchText)
            isSearching = false
        }
    }

    @ViewBuilder
    private var projectsList: some View {
        ForEach(projectManager.projects) { project in
            ProjectRow(
                project: project,
                isExpanded: expandedProjects.contains(project.id),
                onToggle: {
                    if expandedProjects.contains(project.id) {
                        expandedProjects.remove(project.id)
                    } else {
                        expandedProjects.insert(project.id)
                    }
                }
            )

            if expandedProjects.contains(project.id) {
                ForEach(project.sessions) { session in
                    SessionRow(session: session)
                        .padding(.leading, 20)
                }
            }
        }

        if projectManager.projects.isEmpty && !projectManager.isLoading {
            ContentUnavailableView(
                "No Projects",
                systemImage: "folder",
                description: Text("No Claude Code projects found")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    @State private var searchResults: [SearchResult] = []

    @ViewBuilder
    private var searchResultsList: some View {
        ForEach(searchResults) { result in
            VStack(alignment: .leading, spacing: 2) {
                Text(result.project.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)

                SessionRow(session: result.session)
            }
        }

        if searchResults.isEmpty && !searchText.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No conversations match '\(searchText)'")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    private func loadExpandedState() {
        expandedProjects = Set(storedExpandedProjects.split(separator: ",").map(String.init))
    }

    private func saveExpandedState() {
        storedExpandedProjects = expandedProjects.joined(separator: ",")
    }
}

// MARK: - Bookmarks Section

private struct BookmarksSection: View {
    @Environment(BookmarkManager.self) private var bookmarkManager
    @Environment(ProjectManager.self) private var projectManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BOOKMARKS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(bookmarkManager.bookmarks) { session in
                        Button {
                            bookmarkManager.clearUpdateMark(session.id)
                            Task { await projectManager.loadMessages(for: session) }
                        } label: {
                            HStack(spacing: 4) {
                                if bookmarkManager.hasUpdate(session.id) {
                                    Circle()
                                        .fill(.blue)
                                        .frame(width: 5, height: 5)
                                }
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 9))
                                Text(session.displayTitle)
                                    .lineLimit(1)
                                    .font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let project: CCProject
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Text(project.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()

                Text("\(project.sessions.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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

// MARK: - Session Row

private struct SessionRow: View {
    let session: CCSession

    @Environment(ProjectManager.self) private var projectManager
    @Environment(BookmarkManager.self) private var bookmarkManager
    @State private var isHovered = false

    private var isSelected: Bool {
        projectManager.selectedSession?.id == session.id
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private var formattedTimestamp: String {
        guard let timestamp = session.timestamp else { return "" }
        let now = Date()
        let seconds = now.timeIntervalSince(timestamp)

        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 172800 { return "Yesterday" }
        if seconds < 604800 { return "\(Int(seconds / 86400))d ago" }
        return Self.dateFormatter.string(from: timestamp)
    }

    var body: some View {
        Button {
            Task { await projectManager.loadMessages(for: session) }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if session.timestamp != nil {
                            Text(formattedTimestamp)
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                        }
                        Text("\(session.messageCount) msgs")
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.7))
                    }
                }

                Spacer()

                if bookmarkManager.isBookmarked(session) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(isSelected ? .white : .orange)
                        .font(.system(size: 10))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                bookmarkManager.toggleBookmark(session)
            } label: {
                Label(
                    bookmarkManager.isBookmarked(session) ? "Remove Bookmark" : "Add Bookmark",
                    systemImage: bookmarkManager.isBookmarked(session) ? "bookmark.slash" : "bookmark"
                )
            }
        }
    }
}

#Preview {
    CCHistorySidebarView()
        .environment(ProjectManager())
        .environment(BookmarkManager())
        .frame(width: 280, height: 600)
}
