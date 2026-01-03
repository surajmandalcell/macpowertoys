//
//  MainWindowView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct MainWindowView: View {
    @State private var selectedTool: String? = CCHistoryTool.shared.id
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ToolSidebarView(selectedTool: $selectedTool)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } content: {
            if selectedTool == CCHistoryTool.shared.id {
                CCHistorySidebarView()
                    .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)
            } else {
                EmptyToolView()
            }
        } detail: {
            if selectedTool == CCHistoryTool.shared.id {
                CCHistoryDetailView()
            } else {
                ContentUnavailableView(
                    "Select a Tool",
                    systemImage: "wrench.adjustable",
                    description: Text("Choose a tool from the sidebar to get started.")
                )
            }
        }
        .navigationTitle("PowerToys")
    }
}

struct EmptyToolView: View {
    var body: some View {
        ContentUnavailableView(
            "No Tool Selected",
            systemImage: "square.grid.2x2",
            description: Text("Select a tool from the sidebar.")
        )
    }
}

#Preview {
    MainWindowView()
        .environmentObject(ProjectManager())
        .environmentObject(BookmarkManager())
        .environmentObject(SelectionManager())
        .frame(width: 1000, height: 700)
}
