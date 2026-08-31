import SwiftUI

struct AllToolsGridView: View {
    @Binding var selectedTool: String?
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("app.closeMainWindowAfterOpeningTool") private var closeMainWindowAfterOpeningTool = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(ToolRegistry.allTools, id: \.id) { tool in
                    ToolCard(
                        tool: tool,
                        selectAction: { selectedTool = tool.id },
                        openAction: {
                            ToolActionRouter.shared.open(toolID: tool.id)
                            if closeMainWindowAfterOpeningTool {
                                dismissWindow(id: "main")
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .thinScrollIndicators()
    }
}

struct ToolCard: View {
    let tool: any Tool
    let selectAction: () -> Void
    let openAction: () -> Void

    @State private var settings = SettingsManager.shared
    @State private var isHovering = false

    private var isEnabled: Bool { settings.isToolEnabled(tool.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: selectAction) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        ToolIconView(tool: tool, size: 36)

                        Text(tool.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .layoutPriority(1)

                        Spacer(minLength: 0)
                    }

                    Text(tool.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 8))
            .focusEffectDisabled()
            .accessibilityIdentifier("tool.\(tool.id).card")

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { settings.setToolEnabled($0, for: tool.id) }
                )) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(settings.isToolTransitioning(tool.id))
                .accessibilityLabel("Enable \(tool.name)")
                .accessibilityIdentifier("tool.\(tool.id).quick-toggle")

                Spacer()

                Button("Open", action: openAction)
                .accessibilityIdentifier("tool.\(tool.id).open")
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isEnabled || settings.isToolTransitioning(tool.id))
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .frame(minHeight: 110)
        .background(Color.primary.opacity(isHovering ? 0.06 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.06 : 0), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0), radius: 8, y: 2)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    AllToolsGridView(selectedTool: .constant(nil))
        .frame(width: 500, height: 300)
}
