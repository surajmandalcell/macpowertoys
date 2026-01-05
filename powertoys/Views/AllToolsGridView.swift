//
//  AllToolsGridView.swift
//  powertoys
//

import SwiftUI

struct AllToolsGridView: View {
    @Binding var selectedTool: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)], spacing: 12) {
                ForEach(ToolRegistry.allTools, id: \.id) { tool in
                    ToolCard(tool: tool) { selectedTool = tool.id }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

struct ToolCard: View {
    let tool: any Tool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)

                Text(tool.name)
                    .font(.callout)
                    .fontWeight(.medium)

                Text(tool.category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    AllToolsGridView(selectedTool: .constant(nil))
        .frame(width: 500, height: 300)
}
