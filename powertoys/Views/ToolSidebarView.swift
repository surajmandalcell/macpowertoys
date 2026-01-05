//
//  ToolSidebarView.swift
//  powertoys
//

import SwiftUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?

    var body: some View {
        ZStack {
            VisualEffect(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        SidebarItem(icon: "square.grid.2x2", title: "All Tools", isSelected: selectedTool == "all-tools") {
                            selectedTool = "all-tools"
                        }

                        ForEach(categoriesWithTools, id: \.id) { category in
                            SidebarSection(title: category.rawValue)

                            ForEach(ToolRegistry.tools(for: category), id: \.id) { tool in
                                SidebarItem(icon: tool.icon, title: tool.name, isSelected: selectedTool == tool.id, indented: true) {
                                    selectedTool = tool.id
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Divider().padding(.horizontal, 12).padding(.bottom, 4)

                    SidebarItem(icon: "gearshape", title: "Settings", isSelected: selectedTool == "settings") {
                        selectedTool = "settings"
                    }

                    SidebarItem(icon: "rectangle.portrait.and.arrow.right", title: "Exit", isSelected: false) {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
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

struct SidebarSection: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var indented: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.leading, indented ? 24 : 8)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#Preview {
    ToolSidebarView(selectedTool: .constant("all-tools"))
        .frame(width: 220, height: 400)
}
