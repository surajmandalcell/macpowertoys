//
//  ToolSidebarView.swift
//  powertoys
//

import SwiftUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            sidebarBody
            SidebarTitle(text: "PowerToys")
        }
    }

    private var sidebarBody: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, placeholder: "Search")
                .padding(.horizontal, 12)
                .padding(.top, 52)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarRow(icon: "square.grid.2x2", title: "All Tools", isSelected: selectedTool == "all-tools") {
                        selectedTool = "all-tools"
                    }

                    ForEach(filteredCategories, id: \.id) { category in
                        SidebarSectionHeader(title: category.rawValue)

                        ForEach(filteredTools(for: category), id: \.id) { tool in
                            SidebarRow(icon: tool.icon, title: tool.name, isSelected: selectedTool == tool.id, logoAsset: tool.logoAsset) {
                                selectedTool = tool.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                SidebarExternalRow(icon: "doc.text.magnifyingglass", title: "Logs") {
                    openWindow(id: "logs")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }

                SidebarRow(icon: "gearshape", title: "Settings", isSelected: false) {
                    NotificationCenter.default.post(name: .openToolSettings, object: "home")
                }

                SidebarRow(icon: "rectangle.portrait.and.arrow.right", title: "Exit", isSelected: false) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
    }
    private var categoriesWithTools: [ToolCategory] {
        ToolCategory.allCases.filter { $0 != .all && !ToolRegistry.tools(for: $0).isEmpty }
    }

    private var filteredCategories: [ToolCategory] {
        if searchText.isEmpty {
            return categoriesWithTools
        }
        return categoriesWithTools.filter { !filteredTools(for: $0).isEmpty }
    }

    private func filteredTools(for category: ToolCategory) -> [any Tool] {
        let tools = ToolRegistry.tools(for: category)
        if searchText.isEmpty {
            return tools
        }
        return tools.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

#Preview {
    ToolSidebarView(selectedTool: .constant("all-tools"))
        .frame(width: 220, height: 500)
}
