import SwiftUI
import OnePlusUI

struct HomeView: View {
    @State private var selectedTool: String? = "all-tools"
    @State private var query = ""
    @State private var filter = MainCatalogFilter.all
    @State private var settingsTab = MainSettingsTab.general
    @State private var focusedToolID: String?
    @State private var modifiedRevision = 0

    var body: some View {
        OnePlusWindowRoot(canvas: .main) {
            ToolSidebarView(selectedTool: $selectedTool, searchText: $query,
                            modifiedRevision: modifiedRevision)
        } content: {
            content
        }
        .background { keyboardActions }
        .onOpenToolPage("main", perform: openPage)
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard ToolActionRouter.windowIdentifier(NSApp.keyWindow?.identifier?.rawValue, matches: "main") else { return }
            openPage("settings")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openToolSettings)) { note in
            guard note.object as? String == "home" else { return }
            openPage("settings")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCategory)) { note in
            guard let category = note.object as? ToolCategory else { return }
            openPage(category == .all ? "all-tools" : ToolRegistry.tools(for: category).first?.id ?? "all-tools")
        }
        .onChange(of: query) { _, value in
            if !value.isEmpty { selectedTool = "all-tools" }
        }
        .onChange(of: selectedTool) { _, value in
            if value != "all-tools" { query = "" }
            focusedToolID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            modifiedRevision += 1
        }
    }

    @ViewBuilder private var content: some View {
        switch selectedTool {
        case "all-tools":
            AllToolsGridView(selectedTool: $selectedTool, query: query, filter: $filter,
                             focusedToolID: $focusedToolID) { modifiedRevision += 1 }
        case "settings":
            MainSettingsView(tab: $settingsTab) { modifiedRevision += 1 }
        case "modified":
            MainModifiedView { modifiedRevision += 1 }
        case let toolID?:
            ToolAboutView(toolId: toolID, changed: { modifiedRevision += 1 })
        default:
            OnePlusEmptyState("Select a tool", systemImage: "wrench.adjustable",
                              caption: "Choose a tool from the sidebar.")
        }
    }

    private var keyboardActions: some View {
        Group {
            Button("All tools") { openPage("all-tools") }.keyboardShortcut("1")
            ForEach(Array(ToolRegistry.allTools.prefix(8).indices), id: \.self) { index in
                Button(ToolRegistry.allTools[index].name) { openPage(ToolRegistry.allTools[index].id) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 2))))
            }
            MainOpenToolButton(toolID: selectedLaunchToolID, title: "Open selected tool")
                .keyboardShortcut("o")
        }.hidden().accessibilityHidden(true)
    }

    private var selectedLaunchToolID: String? {
        if let selectedTool, ToolRegistry.tool(for: selectedTool) != nil { return selectedTool }
        return focusedToolID
    }

    private func openPage(_ id: String) {
        guard let route = MainPageRoute.resolve(id, toolIDs: ToolRegistry.allTools.map(\.id)) else { return }
        query = ""
        switch route {
        case .catalog(let requestedFilter): filter = requestedFilter; selectedTool = "all-tools"
        case .settings(let tab): settingsTab = tab; selectedTool = "settings"
        case .modified: selectedTool = "modified"
        case .tool(let id): selectedTool = id
        }
    }
}
