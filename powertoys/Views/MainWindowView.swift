//
//  MainWindowView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct MainWindowView: View {
    @State private var selectedTool: String? = "all-tools"
    @Environment(\.openWindow) private var openWindow

    private let sidebarWidth: CGFloat = 240

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ToolSidebarView(selectedTool: $selectedTool)
                .navigationSplitViewColumnWidth(sidebarWidth)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            if selectedTool == "all-tools" {
                AllToolsGridView(selectedTool: $selectedTool)
            } else if selectedTool == "settings" {
                SettingsView()
            } else if let toolId = selectedTool {
                ToolSettingsView(toolId: toolId, openWindow: openWindow)
            } else {
                ContentUnavailableView(
                    "Select a Tool",
                    systemImage: "wrench.adjustable",
                    description: Text("Choose a tool from the sidebar to get started.")
                )
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
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
