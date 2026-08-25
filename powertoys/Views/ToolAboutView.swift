import SwiftUI

private enum ToolDetailPage: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case guide = "How to Use"

    var id: String { rawValue }
}

struct ToolAboutView: View {
    let toolId: String

    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("app.closeMainWindowAfterOpeningTool") private var closeMainWindowAfterOpeningTool = false
    @State private var settings = SettingsManager.shared
    @State private var page = ToolDetailPage.settings

    private var tool: (any Tool)? {
        ToolRegistry.tool(for: toolId)
    }

    var body: some View {
        if let tool {
            VStack(spacing: 0) {
                header(for: tool)
                HStack(spacing: 2) {
                    ForEach(ToolDetailPage.allCases) { page in
                        UtilityTabPill(
                            title: page.rawValue,
                            isSelected: self.page == page
                        ) {
                            self.page = page
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .padding(.bottom, 12)
                .accessibilityIdentifier("tool.\(tool.id).page")

                QuietDivider()

                Group {
                    switch page {
                    case .settings:
                        VStack(spacing: 0) {
                            ToolDetailIntro(tool: tool)
                            ToolSettingsContent(toolID: tool.id)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .disabled(!settings.isToolEnabled(tool.id))
                    case .guide:
                        manualSection(for: tool)
                    }
                }
                .utilityContentTransition(value: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            EmptyStateView(icon: "questionmark.circle", message: "Unknown tool")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for tool: any Tool) -> some View {
        HStack(spacing: 10) {
            ToolIconView(tool: tool, size: 30)

            Text(tool.name)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Toggle(isOn: enabledBinding(for: tool.id)) { EmptyView() }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(settings.isToolTransitioning(tool.id))
                    .accessibilityLabel("Enable \(tool.name)")
                    .accessibilityIdentifier("tool.\(tool.id).enabled")

                Button("Open") {
                    ToolActionRouter.shared.open(toolID: tool.id)
                    if closeMainWindowAfterOpeningTool {
                        dismissWindow(id: "main")
                    }
                }
                .accessibilityLabel("Open \(tool.name)")
                .accessibilityIdentifier("tool.\(tool.id).launch")
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!settings.isToolEnabled(tool.id) || settings.isToolTransitioning(tool.id))
                .help(settings.isToolEnabled(tool.id) ? "Open \(tool.name)" : "Enable \(tool.name) to open it")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func enabledBinding(for toolID: String) -> Binding<Bool> {
        Binding(
            get: { settings.isToolEnabled(toolID) },
            set: { settings.setToolEnabled($0, for: toolID) }
        )
    }

    private func manualSection(for tool: any Tool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(tool.manual) { section in
                    manualCard(section)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .thinScrollIndicators()
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

private struct ToolDetailIntro: View {
    let tool: any Tool
    @AppStorage private var menuBarMode: MenuBarDisplayMode

    init(tool: any Tool) {
        self.tool = tool
        let menuBarTool = IndividualMenuBarTool(rawValue: tool.id)
        _menuBarMode = AppStorage(
            wrappedValue: menuBarTool?.displayMode() ?? .none,
            menuBarTool?.preferenceKey ?? "tool.\(tool.id).menuBarDisplayMode"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tool.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if IndividualMenuBarTool(rawValue: tool.id) != nil {
                HStack(spacing: 12) {
                    Text("Menu Bar Icon")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 12)
                    Picker("Menu Bar Icon", selection: $menuBarMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .accessibilityIdentifier("tool.\(tool.id).menu-bar-icon")
                    .frame(width: 240)
                }
                .onChange(of: menuBarMode) { _, _ in
                    IndividualMenuBarController.shared.refresh()
                }
            }
        }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

        QuietDivider()
    }
}

private struct ToolSettingsContent: View {
    let toolID: String

    @ViewBuilder
    var body: some View {
        switch toolID {
        case "cc-history":
            CCHistorySettingsPage(showsHeader: false)
        case "rclone":
            RcloneSettingsPage(showsHeader: false)
        case "ruler":
            RulerLauncherSettingsView()
        case "awake":
            ScrollView {
                AwakeSettingsView()
                    .padding(24)
            }
            .thinScrollIndicators()
        case "color-picker":
            ColorPickerSettingsView()
        case "text-extractor":
            TextExtractorSettingsView()
        case "nettoys":
            NetToysSettingsView()
        case "input-devices":
            EmptyView()
        case "logs":
            LogsSettingsView()
        default:
            EmptyStateView(icon: "slider.horizontal.3", message: "No settings available")
        }
    }
}

private struct RulerLauncherSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RULER SETTINGS").utilitySectionHeader()

            VStack(alignment: .leading, spacing: 12) {
                Text("Ruler settings stay in the native panels used by the Ruler window.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Open Ruler Settings") {
                        ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
                    }
                    Button("Open Defaults") {
                        AppDelegate.current?.openPreferences(self)
                    }
                }
                .controlSize(.small)
            }
            .utilitySectionCard()

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    ToolAboutView(toolId: "rclone")
        .frame(width: 560, height: 700)
}
