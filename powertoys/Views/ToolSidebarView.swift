import SwiftUI
import OnePlusUI

struct ToolSidebarView: View {
    @Binding var selectedTool: String?
    @Binding var searchText: String
    var modifiedRevision: Int
    @State private var settings = SettingsManager.shared
    @State private var hasChanges = false
    @State private var visibleTools: [any Tool] = []

    var body: some View {
        OnePlusSidebar(title: "MacPowerToys") {
            OnePlusSidebarSearch(text: $searchText, alternateShortcut: "f")
        } navigation: {
            OnePlusNavRow("All tools", systemImage: "square.grid.2x2", selected: selectedTool == "all-tools") {
                selectedTool = "all-tools"
            }
            OnePlusNavCaption("Your tools")
            ForEach(visibleTools, id: \.id) { tool in
                OnePlusNavRow(tool.name, systemImage: tool.icon, selected: selectedTool == tool.id,
                              muted: !settings.isToolEnabled(tool.id)) { selectedTool = tool.id }
                    .accessibilityIdentifier("main.sidebar.\(tool.id)")
                    .accessibilityValue(settings.isToolEnabled(tool.id) ? "Enabled" : "Disabled")
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        guard settings.isToolEnabled(tool.id), !settings.isToolTransitioning(tool.id) else { return }
                        ToolActionRouter.shared.open(toolID: tool.id)
                    })
                    .contextMenu { MainToolContextMenu(tool: tool) { selectedTool = tool.id } }
            }
        } bottom: {
            OnePlusNavRow("Modified", systemImage: "arrow.counterclockwise", selected: selectedTool == "modified") {
                selectedTool = "modified"
            }
            .disabled(!hasChanges)
            OnePlusNavRow("Settings", systemImage: "gearshape", selected: selectedTool == "settings") {
                selectedTool = "settings"
            }
            OnePlusNavRow("Exit", systemImage: "rectangle.portrait.and.arrow.right") { NSApp.terminate(nil) }
        }
        .onChange(of: modifiedRevision, initial: true) { _, _ in
            hasChanges = SettingsRegistry.hasChanges()
        }
        .onChange(of: searchText, initial: true) { _, _ in refreshVisibleTools() }
        .onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)) { _ in refreshVisibleTools() }
    }

    private func refreshVisibleTools() {
        visibleTools = ToolRegistry.allTools.filter { MainCatalog.matches($0, query: searchText) }
    }
}
