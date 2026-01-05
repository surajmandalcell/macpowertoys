//
//  ToolSidebarView.swift
//  powertoys
//

import SwiftUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?
    @State private var searchText = ""
    @Environment(\.openWindow) private var openWindow

        var body: some View {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 12)
                    .padding(.top, 52)
                    .padding(.bottom, 12)
    
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            SidebarRow(icon: "square.grid.2x2", title: "All Tools", isSelected: selectedTool == "all-tools") {
                                selectedTool = "all-tools"
                            }
    
                            ForEach(filteredCategories, id: \.id) { category in
                                SidebarHeader(title: category.rawValue)
    
                                ForEach(filteredTools(for: category), id: \.id) { tool in
                                    SidebarRow(icon: tool.icon, title: tool.name, isSelected: selectedTool == tool.id) {
                                        selectedTool = tool.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
    
                    Spacer(minLength: 0)
    
                    VStack(spacing: 4) {
                        SidebarRow(icon: "gearshape", title: "Settings", isSelected: selectedTool == "settings") {
                            selectedTool = "settings"
                        }

                        SidebarExternalRow(icon: "doc.text.magnifyingglass", title: "Logs") {
                            openWindow(id: "logs")
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }

                        SidebarRow(icon: "rectangle.portrait.and.arrow.right", title: "Exit", isSelected: false) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
    
                            Text("PowerToys")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.leading, 84)
                                .padding(.top, 8)
                        }            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct SidebarHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

struct SidebarRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovering {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
}

struct SidebarExternalRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    ToolSidebarView(selectedTool: .constant("all-tools"))
        .frame(width: 220, height: 500)
}
