import SwiftUI
import OnePlusUI

private enum MainToolTab: String { case settings, guide }

struct ToolAboutView: View {
    let toolId: String
    var showsModalCloseButton = false
    var showsSettings = true
    var changed: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var tab = MainToolTab.settings

    var body: some View {
        if let tool = ToolRegistry.tool(for: toolId) {
            OnePlusPage {
                header(tool)
            } tabs: {
                if showsSettings { tabs(tool) }
            } content: {
                if !showsSettings || tab == .guide {
                    ForEach(tool.manual) { section in manualCard(section) }
                } else if tool.id == "ruler" {
                    rulerSettings
                } else {
                    ToolSettingsContent(toolID: tool.id, changed: changed)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .clipped()
            .onChange(of: toolId) { _, _ in tab = .settings }
        } else {
            OnePlusEmptyState("Unknown tool", systemImage: "questionmark.circle",
                              caption: "This tool is no longer installed.")
        }
    }

    private func header(_ tool: any Tool) -> some View {
        OnePlusToolPageHeader(title: tool.name, subtitle: tool.description) {
            ToolIconView(tool: tool, size: OnePlusCatalogMetrics.iconSize)
        } actions: {
            if showsSettings { MainToolEnableSwitch(tool: tool) }
            if showsModalCloseButton {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(OnePlusButtonStyle(.icon))
                    .help("Close").accessibilityLabel("Close")
            } else if showsSettings {
                MainOpenToolButton(toolID: tool.id, toolName: tool.name)
            }
        }
    }

    private func tabs(_ tool: any Tool) -> some View {
        OnePlusTabStrip(tabs: [OnePlusTab(.settings, "Settings"), OnePlusTab(.guide, "How to use")], selection: $tab) {
            if let menuTool = IndividualMenuBarTool(rawValue: tool.id) { MainMenuBarPlacement(tool: menuTool, changed: changed) }
        }
        .accessibilityIdentifier("tool.\(tool.id).page")
    }

    private func manualCard(_ section: ToolManualSection) -> some View {
        OnePlusCard {
            OnePlusCardHeader(section.title)
            VStack(alignment: .leading, spacing: OnePlusCatalogMetrics.gap) {
                ForEach(section.points.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: OnePlusCatalogMetrics.gap) {
                        Text(String(index + 1) + ".").onePlusText(.mono)
                        Text(section.points[index]).onePlusText(.row).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(OnePlusMetrics.cardPadding)
        }
    }

    private var rulerSettings: some View {
        HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusCardHeader("Ruler", systemImage: "ruler")
                OnePlusSettingRow("Active rulers", separator: false) {
                    Button("Open Ruler Settings") {
                        ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
                    }.buttonStyle(OnePlusButtonStyle())
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Defaults", systemImage: "slider.horizontal.3")
                OnePlusSettingRow("New rulers", separator: false) {
                    Button("Open Defaults") { AppDelegate.current?.openPreferences(self) }
                        .buttonStyle(OnePlusButtonStyle())
                }
            }
        }
    }
}

private struct MainMenuBarPlacement: View {
    let tool: IndividualMenuBarTool
    let changed: () -> Void
    @AppStorage private var mode: MenuBarDisplayMode

    init(tool: IndividualMenuBarTool, changed: @escaping () -> Void) {
        self.tool = tool
        self.changed = changed
        _mode = AppStorage(wrappedValue: tool.displayMode(), tool.preferenceKey)
    }

    var body: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Text("Menu bar").onePlusText(.caption)
            OnePlusSegmented(choices: MenuBarDisplayMode.allCases.map { ($0, $0.title) },
                             selection: $mode, accessibilityLabel: "Menu bar placement")
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("tool.\(tool.id).menu-bar-icon")
        }
        .onChange(of: mode) { _, _ in IndividualMenuBarController.shared.refresh(); changed() }
    }
}
