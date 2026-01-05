//
//  CCHistoryWindowView.swift
//  powertoys
//

import SwiftUI

struct CCHistoryWindowView: View {
    @State private var projectManager = ProjectManager()
    @State private var bookmarkManager = BookmarkManager()
    @State private var selectionManager = SelectionManager()

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
        .environment(selectionManager)
        .ignoresSafeArea()
        .background(WindowAccessor())
        .task {
            projectManager.startWatching()
            await projectManager.loadProjects()
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
