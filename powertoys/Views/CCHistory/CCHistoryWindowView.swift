//
//  CCHistoryWindowView.swift
//  powertoys
//

import SwiftUI

struct CCHistoryWindowView: View {
    @State private var projectManager = ProjectManager()
    @State private var bookmarkManager = BookmarkManager()
    @State private var showSettingsPage = false

    var body: some View {
        HStack(spacing: 0) {
            CCHistorySidebarView(openSettings: { showSettingsPage = true })
                .frame(width: UtilityLayout.conversationSidebarWidth)

            Group {
                if showSettingsPage {
                    CCHistorySettingsPage(onDone: { showSettingsPage = false })
                } else {
                    CCHistoryDetailView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .environment(projectManager)
        .environment(bookmarkManager)
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "cc-history"))
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("cc-history") == true else { return }
            showSettingsPage = true
        }
        .onChange(of: projectManager.recentlyUpdatedSessionIds) { _, sessionIds in
            for sessionId in sessionIds {
                bookmarkManager.markAsUpdated(sessionId)
            }
        }
        .onAppear {
            projectManager.startWatching()
            projectManager.loadProjectsInBackground()
        }
        .onDisappear {
            projectManager.stopWatching()
        }
    }
}

#Preview {
    CCHistoryWindowView()
        .frame(width: 1200, height: 800)
}
