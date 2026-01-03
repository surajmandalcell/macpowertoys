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
            Section("All Tools") {
                ForEach(ToolRegistry.allTools, id: \.id) { tool in
                    Label {
                        Text(tool.name)
                    } icon: {
                        Image(systemName: tool.icon)
                            .foregroundStyle(.blue)
                    }
                    .tag(tool.id)
                }
            }
            
            Section("Categories") {
                ForEach(ToolCategory.allCases.filter { $0 != .all }) { category in
                    Label {
                        Text(category.rawValue)
                    } icon: {
                        Image(systemName: category.icon)
                            .foregroundStyle(.secondary)
                    }
                    .tag("category-\(category.id)")
                }
            }
        }
        .listStyle(.sidebar)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCategory)) { notification in
            if let category = notification.object as? ToolCategory {
                if category == .all {
                    selectedTool = ToolRegistry.allTools.first?.id
                } else {
                    selectedTool = "category-\(category.id)"
                }
            }
        }
    }
}

#Preview {
    ToolSidebarView(selectedTool: .constant(CCHistoryTool.shared.id))
        .frame(width: 200, height: 400)
}
