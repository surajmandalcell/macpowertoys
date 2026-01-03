//
//  ToolSidebarView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?

    var body: some View {
        List(selection: $selectedTool) {
            // All Tools item (shows grid)
            Label {
                Text("All Tools")
            } icon: {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.blue)
            }
            .tag("all-tools")

            // Only show categories that have tools
            ForEach(categoriesWithTools, id: \.id) { category in
                Section(category.rawValue) {
                    ForEach(ToolRegistry.tools(for: category), id: \.id) { tool in
                        Label {
                            Text(tool.name)
                        } icon: {
                            Image(systemName: tool.icon)
                                .foregroundStyle(.blue)
                        }
                        .tag(tool.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCategory)) { notification in
            if let category = notification.object as? ToolCategory {
                if category == .all {
                    selectedTool = "all-tools"
                } else {
                    selectedTool = ToolRegistry.tools(for: category).first?.id
                }
            }
        }
    }

    private var categoriesWithTools: [ToolCategory] {
        ToolCategory.allCases.filter { category in
            category != .all && !ToolRegistry.tools(for: category).isEmpty
        }
    }
}

#Preview {
    ToolSidebarView(selectedTool: .constant(CCHistoryTool.shared.id))
        .frame(width: 200, height: 400)
}
