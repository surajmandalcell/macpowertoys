//
//  HomeView.swift
//  powertoys
//

import SwiftUI

struct HomeView: View {
    @State private var selectedTool: String? = "all-tools"

    var body: some View {
        HStack(spacing: 0) {
            ToolSidebarView(selectedTool: $selectedTool)
                .frame(width: UtilityLayout.compactSidebarWidth)

            ZStack(alignment: .topLeading) {
                contentView
                    .padding(.top, 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCategory)) { notification in
            if let category = notification.object as? ToolCategory {
                selectedTool = category == .all ? "all-tools" : ToolRegistry.tools(for: category).first?.id
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTool {
        case "all-tools":
            AllToolsGridView(selectedTool: $selectedTool)
        case let toolId?:
            ToolAboutView(toolId: toolId)
        default:
            ContentUnavailableView("Select a Tool", systemImage: "wrench.adjustable", description: Text("Choose a tool from the sidebar."))
        }
    }
}

#Preview {
    HomeView()
        .frame(width: 1150, height: 760)
}
