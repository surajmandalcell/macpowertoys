//
//  CCHistoryWindowView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct CCHistoryWindowView: View {
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var bookmarkManager = BookmarkManager()
    @StateObject private var selectionManager = SelectionManager()

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CCHistorySidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)
        } detail: {
            CCHistoryDetailView()
        }
        .environmentObject(projectManager)
        .environmentObject(bookmarkManager)
        .environmentObject(selectionManager)
        .onAppear {
            Task {
                await projectManager.loadProjects()
                projectManager.startWatching()
            }
        }
        .onDisappear {
            projectManager.stopWatching()
        }
        .navigationTitle("CC History")
    }
}

#Preview {
    CCHistoryWindowView()
        .frame(width: 1000, height: 700)
}
