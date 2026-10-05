import SwiftUI
import OnePlusUI

/// `guide` is a one-shot request to scroll a tool page to How to use.
enum MainToolTab: String {
    case settings, guide
    static func storageKey(for toolID: String) -> String { "main.tool.\(toolID).tab" }
    static func select(_ tab: Self, for toolID: String) {
        UserDefaults.standard.set(tab.rawValue, forKey: storageKey(for: toolID))
    }
}

/// A Settings-style tool pane: identity block, then grouped settings and manual sections.
struct ToolAboutView: View {
    let toolId: String
    @AppStorage private var storedTab: String
    private static let guideAnchor = "guide"

    init(toolId: String) {
        self.toolId = toolId
        _storedTab = AppStorage(wrappedValue: MainToolTab.settings.rawValue, MainToolTab.storageKey(for: toolId))
    }

    var body: some View {
        if let tool = ToolRegistry.tool(for: toolId) {
            ScrollViewReader { proxy in
                MainPaneScroll {
                    hero(tool)
                    if let menuTool = IndividualMenuBarTool(rawValue: tool.id) {
                        MainSection { MainMenuBarPlacement(tool: menuTool) }
                    }
                    ToolSettingsContent(toolID: tool.id)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    Text("How to use").onePlusText(.sectionTitle).accessibilityAddTraits(.isHeader)
                        .padding(.leading, MainPaneMetrics.sectionTitleInset)
                        .padding(.top, MainPaneMetrics.gutter)
                        .id(Self.guideAnchor)
                    ForEach(tool.manual) { section in manualSection(section) }
                }
                .onChange(of: storedTab, initial: true) { _, value in
                    guard MainToolTab(rawValue: value) != .settings else { return }
                    if MainToolTab(rawValue: value) == .guide {
                        DispatchQueue.main.async { proxy.scrollTo(Self.guideAnchor, anchor: .top) }
                    }
                    storedTab = MainToolTab.settings.rawValue
                }
            }
            .accessibilityIdentifier("tool.\(tool.id).page")
        } else {
            OnePlusEmptyState("Unknown tool", systemImage: "questionmark.circle",
                              caption: "This tool is no longer installed.")
        }
    }

    private func hero(_ tool: any Tool) -> some View {
        MainHero(title: tool.name, subtitle: tool.id == "mac-tweaks" ? tool.summary : tool.description) {
            ToolIconView(tool: tool, size: MainPaneMetrics.heroIcon)
        } controls: {
            HStack(spacing: OnePlusMetrics.cardGap) {
                MainToolEnableSwitch(tool: tool)
                MainOpenToolButton(toolID: tool.id, toolName: tool.name, title: "Open \(tool.name)", primary: true)
            }
        }
    }

    private func manualSection(_ section: ToolManualSection) -> some View {
        MainSection(title: section.title) {
            ForEach(section.points.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: OnePlusCatalogMetrics.gap) {
                    Text(String(index + 1) + ".").onePlusText(.mono)
                    Text(section.points[index]).onePlusText(.row).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, OnePlusMetrics.cardPadding)
                .padding(.vertical, OnePlusCatalogMetrics.gap)
                .overlay(alignment: .bottom) {
                    if index != section.points.count - 1 {
                        OnePlusColor.lineSoft.frame(height: 1).padding(.horizontal, OnePlusCatalogMetrics.cardInset)
                    }
                }
            }
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
        OnePlusSettingRow("Menu bar icon", controlWidth: OnePlusCatalogMetrics.placementWidth, separator: false) {
            OnePlusSegmented(choices: MenuBarDisplayMode.allCases.map { ($0, $0.title) },
                             selection: $mode, accessibilityLabel: "Menu bar placement")
                .accessibilityIdentifier("tool.\(tool.id).menu-bar-icon")
        }
        .onChange(of: mode) { _, _ in IndividualMenuBarController.shared.refresh() }
    }
}
