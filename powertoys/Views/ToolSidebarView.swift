//
//  ToolSidebarView.swift
//  powertoys
//

import SwiftUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?
    @State private var searchText = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            sidebarBody
            SidebarTitle(text: "MacPowerToys")
        }
    }

    private var sidebarBody: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, placeholder: "Search")
                .padding(.horizontal, 12)
                .padding(.top, UtilityLayout.workspaceContentTopInset)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarRow(icon: "square.grid.2x2", title: "All Tools", isSelected: selectedTool == "all-tools") {
                        selectedTool = "all-tools"
                    }

                    ForEach(filteredTools, id: \.id) { tool in
                        SidebarRow(icon: tool.icon, title: tool.name, isSelected: selectedTool == tool.id, logoAsset: tool.logoAsset) {
                            selectedTool = tool.id
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                ToolActionRouter.shared.open(toolID: tool.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            .thinScrollIndicators()

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                SidebarExternalRow(icon: "doc.text.magnifyingglass", title: "Logs") {
                    ToolActionRouter.shared.open(toolID: "logs")
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
    private var filteredTools: [any Tool] {
        let tools = ToolRegistry.allTools
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
