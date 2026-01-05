//
//  ToolSidebarView.swift
//  powertoys
//

import SwiftUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?

    var body: some View {
        List(selection: $selectedTool) {
            Label("All Tools", systemImage: "square.grid.2x2")
                .tag("all-tools")

            ForEach(categoriesWithTools, id: \.id) { category in
                Section(category.rawValue) {
                    ForEach(ToolRegistry.tools(for: category), id: \.id) { tool in
                        Label(tool.name, systemImage: tool.icon)
                            .tag(tool.id)
                    }
                }
            }

            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag("settings")

                Label("Exit", systemImage: "rectangle.portrait.and.arrow.right")
                    .onTapGesture { NSApplication.shared.terminate(nil) }
            }
        }
        .listStyle(.sidebar)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCategory)) { notification in
            if let category = notification.object as? ToolCategory {
                selectedTool = category == .all ? "all-tools" : ToolRegistry.tools(for: category).first?.id
            }
        }
    }

    private var categoriesWithTools: [ToolCategory] {
        ToolCategory.allCases.filter { $0 != .all && !ToolRegistry.tools(for: $0).isEmpty }
    }
}

#Preview {
    ToolSidebarView(selectedTool: .constant("all-tools"))
        .frame(width: 220, height: 400)
}
