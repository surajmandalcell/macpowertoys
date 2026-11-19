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

/// A tool pane: the editorial header, the menu-bar placement, the tool's inline settings, then How to use at the bottom.
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
                OnePlusLinearEditorialBody {
                    header(tool)
                    if let menuTool = IndividualMenuBarTool(rawValue: tool.id) {
                        OnePlusLinearAppletGroup { MainMenuBarPlacement(tool: menuTool) }
                    }
                    ToolSettingsContent(toolID: tool.id)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } footer: {
                    VStack(alignment: .leading, spacing: OnePlusLinearMetrics.sectionCaptionBelow) {
                        OnePlusLinearSectionCaption("How to use")
                        VStack(alignment: .leading, spacing: OnePlusLinearEditorialMetrics.blockGap) {
                            ForEach(tool.manual) { section in manualSection(section, titled: tool.manual.count > 1) }
                        }
                    }
                    .id(Self.guideAnchor)
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

    private func header(_ tool: any Tool) -> some View {
        OnePlusLinearToolHeader(tool.name, detail: tool.description) {
            ToolIconView(tool: tool, size: OnePlusLinearEditorialMetrics.headerIcon)
        } actions: {
            MainLaunchTile(tool: tool)
        }
    }

    private func manualSection(_ section: ToolManualSection, titled: Bool) -> some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.sectionCaptionBelow) {
            if titled { Text(section.title).linearText(color: OnePlusLinearColor.secondary) }
            OnePlusLinearChecklist(steps: section.steps, keys: section.keys, notes: section.notes)
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
        OnePlusLinearAppletRow("Menu bar icon", systemImage: "menubar.rectangle") {
            OnePlusLinearSegmented(choices: MenuBarDisplayMode.allCases.map { ($0, $0.title) },
                                   selection: $mode, accessibilityLabel: "Menu bar placement", sizing: .fitted)
                .accessibilityIdentifier("tool.\(tool.id).menu-bar-icon")
        }
        .onChange(of: mode) { _, _ in IndividualMenuBarController.shared.refresh() }
    }
}
