import SwiftUI
import OnePlusUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?
    @Binding var searchText: String
    var searchFocusTrigger = 0
    @State private var settings = SettingsManager.shared
    @State private var groups: [MainToolGroup] = []

    var body: some View {
        OnePlusLinearSidebar {
            OnePlusLinearSearchField(text: $searchText, accessibilityIdentifier: "main.sidebar.search",
                                     focusTrigger: searchFocusTrigger)
        } navigation: {
            OnePlusLinearNavRow("All tools", glyph: Image(SidebarGlyph.allTools), selected: selectedTool == "all-tools") {
                selectedTool = "all-tools"
            }
            .accessibilityIdentifier("main.sidebar.all-tools")
            ForEach(groups) { group in
                OnePlusLinearNavCaption(group.category.rawValue)
                ForEach(group.tools, id: \.id) { toolRow($0) }
                // Owner, 2026-11-20: Fan is a system control, so it sits last in System, not at the bottom.
                if group.category == .system, searchText.isEmpty || FanPageView.title.localizedCaseInsensitiveContains(searchText) {
                    OnePlusLinearNavRow(FanPageView.title, glyph: Image(SidebarGlyph.fan),
                                        selected: selectedTool == FanPageView.pageID) {
                        selectedTool = FanPageView.pageID
                    }
                    .accessibilityIdentifier("main.sidebar.fan")
                }
            }
        } bottom: {
            OnePlusLinearNavRow(AppsBySamView.title, glyph: Image(systemName: SidebarGlyph.appsBySam), symbol: true,
                                selected: selectedTool == AppsBySamView.pageID) {
                selectedTool = AppsBySamView.pageID
            }
            .accessibilityIdentifier("main.sidebar.apps-by-sam")
            OnePlusLinearNavRow("Settings", glyph: Image(systemName: "gearshape"), symbol: true, selected: selectedTool == "settings", shortcut: "⌘,") {
                selectedTool = "settings"
            }
            .accessibilityIdentifier("main.sidebar.settings")
            OnePlusLinearNavRow("Exit", glyph: Image(systemName: "power"), symbol: true, shortcut: "⌘Q") { NSApp.terminate(nil) }
                .accessibilityIdentifier("main.sidebar.exit")
        }
        .linearSidebarTitle(AppIdentity.displayName)
        .onChange(of: searchText, initial: true) { _, _ in refreshVisibleTools() }
        .onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)) { _ in refreshVisibleTools() }
    }

    private func toolRow(_ tool: any Tool) -> some View {
        Group {
            if let glyph = SidebarGlyph.glyph(for: tool.id) {
                OnePlusLinearNavRow(tool.name, glyph: glyph, selected: selectedTool == tool.id,
                                    dimmed: !settings.isToolEnabled(tool.id)) { selectedTool = tool.id }
            } else {
                OnePlusLinearNavRow(tool.name, image: MainToolIcon.image(for: tool), selected: selectedTool == tool.id,
                                    dimmed: !settings.isToolEnabled(tool.id)) { selectedTool = tool.id }
            }
        }
        .accessibilityIdentifier("main.sidebar.\(tool.id)")
        .accessibilityValue(settings.isToolEnabled(tool.id) ? "Enabled" : "Disabled")
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard settings.isToolEnabled(tool.id), !settings.isToolTransitioning(tool.id) else { return }
            ToolActionRouter.shared.open(toolID: tool.id)
        })
        .contextMenu { MainToolContextMenu(tool: tool) { selectedTool = tool.id } }
    }

    private func refreshVisibleTools() {
        var visible = MainCatalog.groups(ToolRegistry.allTools.filter { MainCatalog.matches($0, query: searchText) })
        // Fan is a page, not a tool, so a search that finds only Fan still needs its System caption.
        if !visible.contains(where: { $0.category == .system }), FanPageView.title.localizedCaseInsensitiveContains(searchText) {
            visible.insert(MainToolGroup(category: .system, tools: []), at: 0)
        }
        groups = visible
    }
}
