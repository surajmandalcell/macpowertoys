//
//  CCHistoryWindowView.swift
//  powertoys
//

import SwiftUI

struct CCHistoryWindowView: View {
    @State private var projectManager = ProjectManager()
    @State private var bookmarkManager = BookmarkManager()

    var body: some View {
        HStack(spacing: 0) {
            CCHistorySidebarView()
                .frame(width: 280)

            CCHistoryDetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .environment(projectManager)
        .environment(bookmarkManager)
        .ignoresSafeArea()
        .background(WindowAccessor())
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
