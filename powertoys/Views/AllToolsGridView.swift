//
//  AllToolsGridView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct AllToolsGridView: View {
    @Binding var selectedTool: String?

    let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(ToolRegistry.allTools, id: \.id) { tool in
                    ToolCard(tool: tool, selectedTool: $selectedTool)
                }
            }
            .padding(24)
        }
        .navigationTitle("All Tools")
    }
}

// MARK: - Tool Card

struct ToolCard: View {
    let tool: any Tool
    @Binding var selectedTool: String?

    var body: some View {
        Button {
            selectedTool = tool.id
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: tool.icon)
                        .font(.title)
                        .foregroundStyle(.blue)
                        .frame(width: 48, height: 48)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    // Category badge
                    Text(tool.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(toolDescription(for: tool.id))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                HStack {
                    Image(systemName: tool.isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(tool.isEnabled ? .green : .secondary)
                        .font(.caption)

                    Text(tool.isEnabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .padding(16)
            .frame(height: 180)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toolDescription(for toolId: String) -> String {
        switch toolId {
        case "cc-history":
            return "Browse and search through your Claude Code conversation history"
        default:
            return "Tool description"
        }
    }
}

#Preview {
    AllToolsGridView(selectedTool: .constant(nil))
        .frame(width: 600, height: 400)
}
