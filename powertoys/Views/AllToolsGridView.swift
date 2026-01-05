//
//  AllToolsGridView.swift
//  powertoys
//

import SwiftUI

struct AllToolsGridView: View {
    @Binding var selectedTool: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(ToolRegistry.allTools, id: \.id) { tool in
                    ToolCard(
                        tool: tool,
                        selectAction: { selectedTool = tool.id },
                        openAction: {
                            openWindow(id: tool.id)
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    )
                }
            }
            .padding([.horizontal, .bottom], 24)
        }
    }
}

struct ToolCard: View {
    let tool: any Tool
    let selectAction: () -> Void
    let openAction: () -> Void

    @State private var isHovering = false
    @State private var isOpenHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(tool.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                }
                
                Spacer()
            }

            Text(tool.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button(action: openAction) {
                    Text("Open")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOpenHovering ? .white : .accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(isOpenHovering ? Color.accentColor : Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                        .animation(.easeInOut(duration: 0.1), value: isOpenHovering)
                }
                .buttonStyle(.plain)
                .onHover { isOpenHovering = $0 }
            }
        }
        .padding(12)
        .background(isHovering ? Color.secondary.opacity(0.05) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHovering ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .contentShape(Rectangle())
        .onTapGesture {
            selectAction()
        }
        .onHover { isHovering = $0 }
    }
}

#Preview {
    AllToolsGridView(selectedTool: .constant(nil))
        .frame(width: 500, height: 300)
}
