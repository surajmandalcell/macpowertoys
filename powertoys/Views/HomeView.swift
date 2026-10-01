import SwiftUI
import OnePlusUI

struct HomeView: View {
    @AppStorage("main.page") private var storedPage = "all-tools"
    private var selectedTool: String? {
        get { storedPage }
        nonmutating set { storedPage = newValue ?? "all-tools" }
    }
    private var selectedToolBinding: Binding<String?> {
        Binding(get: { storedPage }, set: { storedPage = $0 ?? "all-tools" })
    }
    @State private var query = ""
    @State private var searchFocusTrigger = 0
    @State private var toolRouter = ToolActionRouter.shared
    @State private var filter = MainCatalogFilter.all
    @AppStorage("main.settingsTab") private var storedSettingsTab = MainSettingsTab.general.rawValue
    @State private var focusedToolID: String?
    @State private var modifiedRevision = 0
    @State private var shortcutTools: [any Tool] = []
    @State private var preferenceObserver: ToolSettingsPreferenceObserver?

    var body: some View {
        OnePlusWindowRoot(canvas: .main) {
            ToolSidebarView(selectedTool: selectedToolBinding, searchText: $query,
                            modifiedRevision: modifiedRevision, searchFocusTrigger: searchFocusTrigger)
        } content: {
            content
        }
        .background { keyboardActions }
        .focusedSceneValue(\.appOpenSettings, { openPage("settings") })
        .focusedSceneValue(\.appGlobalSearch, focusSearch)
        .focusedSceneValue(\.appFind, AppCommandAction(title: "Find a Tool", perform: focusSearch))
        .alert("Could not open tool", isPresented: Binding(
            get: { toolRouter.launchFailure != nil },
            set: { if !$0 { toolRouter.launchFailure = nil } }
        ), presenting: toolRouter.launchFailure) { failure in
            Button("Retry") { toolRouter.open(toolID: failure.toolID) }
            Button("Open Logs") { toolRouter.open(toolID: "logs") }
                .disabled(!SettingsManager.shared.isToolEnabled("logs"))
            Button("Cancel", role: .cancel) {}
        } message: { failure in
            Text("\(ToolRegistry.tool(for: failure.toolID)?.name ?? failure.toolID): \(failure.message)")
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)) { _ in
            refreshShortcutTools()
            observePreferences()
            modifiedRevision += 1
        }
        .onAppear {
            let enabledIDs = ToolRegistry.allTools.filter { SettingsManager.shared.isToolEnabled($0.id) }.map(\.id)
            if MainPageRoute.resolve(selectedTool ?? "", toolIDs: enabledIDs) == nil { selectedTool = "all-tools" }
            refreshShortcutTools()
            observePreferences()
        }
        .onDisappear {
            preferenceObserver?.stop()
            preferenceObserver = nil
        }
    }

    @ViewBuilder private var content: some View {
        switch selectedTool {
        case "all-tools":
            AllToolsGridView(selectedTool: selectedToolBinding, query: query, filter: $filter,
                             focusedToolID: $focusedToolID) { modifiedRevision += 1 }
        case "settings":
            MainSettingsView(tab: settingsTab, showManual: { openPage("manual/" + $0) }) { modifiedRevision += 1 }
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
            ForEach(shortcutTools.indices, id: \.self) { index in
                Button(shortcutTools[index].name) { openPage(shortcutTools[index].id) }
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
        guard let route = MainPageRoute.resolve(id, toolIDs: ToolRegistry.allTools.map(\.id),
                                               savedSettingsTab: storedSettingsTab) else { return }
        query = ""
        switch route {
        case .catalog(let requestedFilter): filter = requestedFilter; selectedTool = "all-tools"
        case .settings(let tab): storedSettingsTab = tab.rawValue; selectedTool = "settings"
        case .modified: selectedTool = "modified"
        case .tool(let id): selectedTool = id
        case .manual(let id): MainToolTab.select(.guide, for: id); selectedTool = id
        }
    }

    private var settingsTab: Binding<MainSettingsTab> {
        Binding(get: { MainSettingsTab(rawValue: storedSettingsTab) ?? .general },
                set: { storedSettingsTab = $0.rawValue })
    }

    private func focusSearch() {
        searchFocusTrigger &+= 1
    }

    private func refreshShortcutTools() {
        shortcutTools = Array(ToolRegistry.allTools.prefix(8))
    }

    private func observePreferences() {
        preferenceObserver?.stop()
        preferenceObserver = ToolSettingsPreferenceObserver(keys: Set(SettingsRegistry.entries.map(\.key))) {
            modifiedRevision += 1
        }
    }
}
