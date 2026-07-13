//
//  ToolAboutView.swift
//  powertoys
//

import SwiftUI

struct ToolAboutView: View {
    let toolId: String

    @Environment(\.dismissWindow) private var dismissWindow

    private var tool: (any Tool)? {
        ToolRegistry.tool(for: toolId)
    }

    var body: some View {
        if let tool {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header(for: tool)

                    Text(tool.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineSpacing(4)
                        .textSelection(.enabled)

                    manualSection(for: tool)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyStateView(icon: "questionmark.circle", message: "Unknown tool")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for tool: any Tool) -> some View {
        HStack(spacing: 16) {
            ToolIconView(tool: tool, size: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(tool.name)
                    .font(.system(size: 22, weight: .semibold))

                Text(tool.category.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            Button {
                ToolActionRouter.shared.open(toolID: tool.id)
                dismissWindow(id: "main")
            } label: {
                Text("Open \(tool.name)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
    }

    private func manualSection(for tool: any Tool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to use".uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(tool.manual) { section in
                manualCard(section)
            }
        }
    }

    private func manualCard(_ section: ToolManualSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.system(size: 13, weight: .medium))

            ForEach(section.points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(.tertiary)

                    Text(point)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ToolAboutView(toolId: "rclone")
        .frame(width: 560, height: 700)
}
