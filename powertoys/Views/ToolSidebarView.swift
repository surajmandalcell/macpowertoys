//
//  ToolSidebarView.swift
//  powertoys
//

import SwiftUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTool) {
                SidebarItem(icon: "square.grid.2x2", title: "All Tools", color: .blue)
                    .tag("all-tools")

                ForEach(categoriesWithTools, id: \.id) { category in
                    Section(category.rawValue) {
                        ForEach(ToolRegistry.tools(for: category), id: \.id) { tool in
                            SidebarItem(icon: tool.icon, title: tool.name, color: .purple)
                                .tag(tool.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer()

            VStack(alignment: .leading, spacing: 0) {

                VStack(spacing: 2) {
                    SidebarButton(icon: "gearshape", title: "Settings", isSelected: selectedTool == "settings") {
                        selectedTool = "settings"
                    }

                    SidebarButton(icon: "rectangle.portrait.and.arrow.right", title: "Exit", isSelected: false) {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(.ultraThinMaterial)
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
        ToolCategory.allCases.filter { $0 != .all && !ToolRegistry.tools(for: $0).isEmpty }
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }
}

struct SidebarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ToolSidebarView(selectedTool: .constant("all-tools"))
        .frame(width: 240, height: 500)
}
