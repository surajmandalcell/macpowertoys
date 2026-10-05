import SwiftUI
import OnePlusUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?
    @Binding var searchText: String
    var searchFocusTrigger = 0
    @State private var settings = SettingsManager.shared
    @State private var groups: [MainToolGroup] = []

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: OnePlusMetrics.titleRow)
                .contentShape(Rectangle()).gesture(WindowDragGesture())
            OnePlusSidebarSearch(text: $searchText, focusTrigger: searchFocusTrigger)
                .padding(.horizontal, OnePlusMetrics.navContainerInset)
                .padding(.bottom, MainPaneMetrics.sidebarGroupGap)
            ScrollView {
                VStack(alignment: .leading, spacing: MainPaneMetrics.sidebarGroupGap) {
                    MainSidebarRow(title: "All tools", selected: selectedTool == "all-tools") {
                        MainAppIconTile()
                    } action: { selectedTool = "all-tools" }
                    .accessibilityIdentifier("main.sidebar.all-tools")
                    ForEach(groups) { group in
                        VStack(spacing: 0) { ForEach(group.tools, id: \.id) { toolRow($0) } }
                    }
                }
                .padding(.horizontal, OnePlusMetrics.navContainerInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onePlusScrollIndicators(axes: .vertical)
            VStack(spacing: 0) {
                MainSidebarRow(title: "Settings", selected: selectedTool == "settings") {
                    MainSymbolTile(systemImage: "gearshape")
                } action: { selectedTool = "settings" }
                MainSidebarRow(title: "Exit") {
                    MainSymbolTile(systemImage: "power")
                } action: { NSApp.terminate(nil) }
            }
            .padding(.horizontal, OnePlusMetrics.navContainerInset)
            .padding(.vertical, MainPaneMetrics.sectionGap)
            .overlay(alignment: .top) { OnePlusColor.lineSoft.frame(height: 1) }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: searchText, initial: true) { _, _ in refreshVisibleTools() }
        .onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)) { _ in refreshVisibleTools() }
    }

    private func toolRow(_ tool: any Tool) -> some View {
        MainSidebarRow(title: tool.name, selected: selectedTool == tool.id, muted: !settings.isToolEnabled(tool.id)) {
            ToolIconView(tool: tool, size: MainPaneMetrics.sidebarIcon)
        } action: { selectedTool = tool.id }
        .accessibilityIdentifier("main.sidebar.\(tool.id)")
        .accessibilityValue(settings.isToolEnabled(tool.id) ? "Enabled" : "Disabled")
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard settings.isToolEnabled(tool.id), !settings.isToolTransitioning(tool.id) else { return }
            ToolActionRouter.shared.open(toolID: tool.id)
        })
        .contextMenu { MainToolContextMenu(tool: tool) { selectedTool = tool.id } }
    }

    private func refreshVisibleTools() {
        groups = MainCatalog.groups(ToolRegistry.allTools.filter { MainCatalog.matches($0, query: searchText) })
    }
}
