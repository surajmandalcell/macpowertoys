//
//  AllToolsGridView.swift
//  powertoys
//

import SwiftUI

struct AllToolsGridView: View {
    @Binding var selectedTool: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

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
                            dismissWindow(id: "main")
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
            HStack(alignment: .center, spacing: 12) {
                Image(tool.logoAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(tool.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }

            Text(tool.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(action: openAction) {
                    Text("Open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isOpenHovering ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isOpenHovering ? Color.accentColor : Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { isOpenHovering = $0 }
            }
        }
        .padding(12)
        .frame(minHeight: 110)
        .background(Color.primary.opacity(isHovering ? 0.06 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.06 : 0), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
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
