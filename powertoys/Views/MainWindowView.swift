//
//  MainWindowView.swift
//  powertoys
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
            switch selectedTool {
            case "all-tools": AllToolsGridView(selectedTool: $selectedTool)
            case "settings": SettingsView()
            case let toolId?: ToolSettingsView(toolId: toolId, openWindow: openWindow)
            default: ContentUnavailableView("Select a Tool", systemImage: "wrench.adjustable", description: Text("Choose a tool from the sidebar."))
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .navigationTitle("PowerToys")
        .frame(width: 780, height: 560)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(ProjectManager())
        .environmentObject(BookmarkManager())
        .environmentObject(SelectionManager())
        .frame(width: 1000, height: 700)
}
