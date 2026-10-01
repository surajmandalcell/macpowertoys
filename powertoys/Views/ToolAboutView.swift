import SwiftUI
import OnePlusUI

enum MainToolTab: String {
    case settings, guide
    static func storageKey(for toolID: String) -> String { "main.tool.\(toolID).tab" }
    static func select(_ tab: Self, for toolID: String) {
        UserDefaults.standard.set(tab.rawValue, forKey: storageKey(for: toolID))
    }
}

struct ToolAboutView: View {
    let toolId: String
    var showsModalCloseButton = false
    var showsSettings = true
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var storedTab: String

    init(toolId: String, showsModalCloseButton: Bool = false, showsSettings: Bool = true) {
        self.toolId = toolId
        self.showsModalCloseButton = showsModalCloseButton
        self.showsSettings = showsSettings
        _storedTab = AppStorage(wrappedValue: MainToolTab.settings.rawValue, MainToolTab.storageKey(for: toolId))
    }

    private var tab: Binding<MainToolTab> {
        Binding(get: { MainToolTab(rawValue: storedTab) ?? .settings }, set: { storedTab = $0.rawValue })
    }

    var body: some View {
        if let tool = ToolRegistry.tool(for: toolId) {
            OnePlusPage {
                header(tool)
            } tabs: {
                if showsSettings { tabs(tool) }
            } footer: {
                if showsSettings && !showsModalCloseButton {
                    HStack {
                        Spacer(minLength: 0)
                        MainOpenToolButton(toolID: tool.id, toolName: tool.name,
                                           title: "Open \(tool.name)", primary: true)
                    }
                }
            } content: {
                if !showsSettings || tab.wrappedValue == .guide {
                    ForEach(tool.manual) { section in manualCard(section) }
                } else {
                    ToolSettingsContent(toolID: tool.id)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .clipped()
            .onChange(of: toolId, initial: true) { _, _ in
                if MainToolTab(rawValue: storedTab) == nil { storedTab = MainToolTab.settings.rawValue }
            }
        } else {
            OnePlusEmptyState("Unknown tool", systemImage: "questionmark.circle",
                              caption: "This tool is no longer installed.")
        }
    }

    private func header(_ tool: any Tool) -> some View {
        OnePlusToolPageHeader(title: tool.name, subtitle: tool.id == "mac-tweaks" ? tool.summary : tool.description) {
            ToolIconView(tool: tool, size: OnePlusCatalogMetrics.iconSize)
        } actions: {
            if showsSettings { MainToolEnableSwitch(tool: tool) }
            if showsModalCloseButton {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(OnePlusButtonStyle(.icon))
                    .help("Close").accessibilityLabel("Close")
            }
        }
    }

    private func tabs(_ tool: any Tool) -> some View {
        OnePlusTabStrip(tabs: [OnePlusTab(.settings, "Settings"), OnePlusTab(.guide, "How to use")], selection: tab) {
            if let menuTool = IndividualMenuBarTool(rawValue: tool.id) { MainMenuBarPlacement(tool: menuTool) }
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
}

private struct MainMenuBarPlacement: View {
    let tool: IndividualMenuBarTool
    @AppStorage private var mode: MenuBarDisplayMode

    init(tool: IndividualMenuBarTool) {
        self.tool = tool
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
        .onChange(of: mode) { _, _ in IndividualMenuBarController.shared.refresh() }
    }
}
