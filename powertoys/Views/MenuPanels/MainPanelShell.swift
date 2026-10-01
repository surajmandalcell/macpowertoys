import OnePlusUI
import SwiftUI

enum TrayTab: String, CaseIterable, Identifiable {
    case home
    case cloudSync = "rclone"
    case inputDevices = "input-devices"
    case systemCare = "system-care"
    case systemMonitor = "system-monitor"
    case netToys = "nettoys"
    case switchAccounts = "switch"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .cloudSync: "Cloud Sync"
        case .inputDevices: "Input Devices"
        case .systemCare: "System Care"
        case .systemMonitor: "Task Manager"
        case .netToys: "NetToys"
        case .switchAccounts: "Switch"
        }
    }

    var symbol: String {
        ToolGlyph(rawValue: rawValue)?.symbol ?? "house"
    }

    var toolID: String? { self == .home ? nil : rawValue }

    var panelID: String {
        self == .cloudSync ? "cloud-sync" : rawValue
    }

    init?(panelID: String) {
        self.init(rawValue: panelID == "cloud-sync" ? Self.cloudSync.rawValue : panelID)
    }
}

struct TrayPopoverView: View {
    private let diagnostic: Bool
    @AppStorage("tray.selectedTab.v2") private var selectedTabID = TrayTab.home.rawValue
    @AppStorage("tray.tabOrder.v2") private var storedTabOrder = ""
    @Environment(\.openWindow) private var openWindow
    @State private var switchModel = SwitchWorkspaceModel.shared
    @State private var netToysSnapshot = NetToysTraySnapshot()
    @State private var careSnapshot = SystemCareTraySnapshot()
    @State private var startupDisk: SystemCareStartupDiskSnapshot?
    @State private var diskLoaded = false
    @State private var cloudJobs: [TransferJob]
    @State private var preparedHomeTools: [String] = []
    @State private var preparedTabs: [TrayTab] = [.home]

    init(diagnostic: Bool = false) {
        self.diagnostic = diagnostic
        let order = UserDefaults.standard.string(forKey: "tray.tabOrder.v2") ?? ""
        _preparedHomeTools = State(initialValue: Self.homeToolIDs())
        _preparedTabs = State(initialValue: [.home] + Self.complexTabs(order: order))
        _cloudJobs = State(initialValue: TrayPopoverLayout.visibleTransferJobs(RcloneJobManager.shared.jobs))
    }

    private static func homeToolIDs() -> [String] {
        return TrayPopoverLayout.homeToolIDs.dropLast().filter { id in
            guard SettingsManager.shared.isToolEnabled(id),
                  let tool = IndividualMenuBarTool(rawValue: id)
            else { return false }
            return tool.usesMenuBarMode(.combined, enabled: true)
        } + (SettingsManager.shared.isToolEnabled("ruler") ? ["ruler"] : [])
    }

    private static func complexTabs(order: String) -> [TrayTab] {
        let available = TrayPopoverLayout.defaultComplexTabs.filter { tab in
            guard let toolID = tab.toolID,
                  SettingsManager.shared.isToolEnabled(toolID),
                  ToolRegistry.tool(for: toolID)?.hasTrayTab == true else {
                return false
            }
            if let menuBarTool = IndividualMenuBarTool(rawValue: toolID) {
                return menuBarTool.usesMenuBarMode(.combined, enabled: true)
            }
            return true
        }
        return TrayPopoverLayout.orderedComplexTabs(
            available: available,
            savedIDs: order.split(separator: ",").map(String.init)
        )
    }

    private var tabs: [TrayTab] { preparedTabs }
    private var selectedTab: TrayTab { TrayTab(rawValue: selectedTabID) ?? .home }

    var body: some View {
        OnePlusMenuPanel(maximumHeight: (NSScreen.main?.visibleFrame.height ?? 900) * TrayPopoverLayout.heightFraction,
                         contentID: selectedTabID) {
            TrayTabStrip(
                tabs: tabs,
                selected: Binding(get: { selectedTab }, set: { select($0) }),
                reorder: reorder
            )
        } actions: {
            OnePlusMenuOpenApp {
                if selectedTab == .systemCare {
                    ToolActionRouter.shared.open(toolID: "system-care", page: "cleanup")
                } else {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Button {
                if selectedTab == .systemCare {
                    ToolActionRouter.shared.open(toolID: "system-care", page: "settings/general")
                } else {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .openToolSettings, object: "home")
                    }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .accessibilityLabel("Open Settings")
            .help("Open Settings")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .accessibilityLabel("Quit MacPowerToys")
            .help("Quit MacPowerToys")
        } toolbar: {
            if selectedTab == .systemCare { systemCareRegion(.toolbar) }
        } footer: {
            if selectedTab == .systemCare { systemCareRegion(.footer) }
        } content: {
            tabContent
        }
        .onePlusPanelTimings(panel: "main", tab: selectedTab.panelID)
        .onOpenToolPage(diagnostic ? "menu.main" : nil) { id in
            if let tab = TrayTab(panelID: id), tabs.contains(tab) { select(tab) }
        }
        .onAppear(perform: prepareTabs)
        .onChange(of: storedTabOrder) { prepareTabs() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            prepareTabs()
        }
        .task {
            let candidates = SystemCareManager.shared.cleanupCandidates
            let preparedCare = await Task.detached(priority: .utility) { SystemCareTraySnapshot.prepare(candidates) }.value
            guard !Task.isCancelled else { return }
            if !careSnapshot.isPrepared { careSnapshot = preparedCare }
        }
        .task(id: SystemCareManager.shared.cleanupScanDate) {
            let disk = await Task.detached(priority: .utility) { SystemCareStartupDiskSnapshot.load() }.value
            guard !Task.isCancelled else { return }
            startupDisk = disk
            diskLoaded = true
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            TrayHomeView(toolIDs: preparedHomeTools)
        case .cloudSync:
            CloudSyncTrayView(jobs: $cloudJobs)
        case .inputDevices:
            InputDevicesTrayView()
        case .systemCare:
            systemCareRegion(.rows)
        case .systemMonitor:
            EmptyView()
        case .netToys:
            NetToysTrayView(snapshot: $netToysSnapshot)
        case .switchAccounts:
            SwitchTrayView(model: switchModel)
        }
    }

    private func systemCareRegion(_ region: SystemCareTrayView.Region) -> some View {
        SystemCareTrayView(snapshot: $careSnapshot, disk: startupDisk, diskLoaded: diskLoaded, region: region)
    }

    private func select(_ tab: TrayTab) {
        guard tab != selectedTab else { return }
        if !OnePlusPanelTimings.shared.hasPending("main", tab: tab.panelID) {
            OnePlusPanelTimings.shared.begin(panel: "main", operation: .tabSwitch, tab: tab.panelID)
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTabID = tab.rawValue
        }
    }

    private func prepareTabs() {
        let home = Self.homeToolIDs()
        let available = [.home] + Self.complexTabs(order: storedTabOrder)
        if preparedHomeTools != home { preparedHomeTools = home }
        if preparedTabs != available { preparedTabs = available }
        guard !tabs.contains(selectedTab) else { return }
        selectedTabID = TrayTab.home.rawValue
    }

    private func reorder(_ source: TrayTab, before destination: TrayTab) {
        let complexTabs = Array(tabs.dropFirst())
        guard source != .home, destination != .home, source != destination,
              let sourceIndex = complexTabs.firstIndex(of: source),
              let destinationIndex = complexTabs.firstIndex(of: destination)
        else { return }
        var reordered = complexTabs
        let tab = reordered.remove(at: sourceIndex)
        reordered.insert(tab, at: min(destinationIndex, reordered.count))
        storedTabOrder = reordered.map(\.rawValue).joined(separator: ",")
    }
}

struct IndividualToolMenuPanel: View {
    let tool: IndividualMenuBarTool
    @State private var cloudJobs: [TransferJob]

    init(tool: IndividualMenuBarTool) {
        self.tool = tool
        _cloudJobs = State(initialValue: tool == .cloudSync
            ? TrayPopoverLayout.visibleTransferJobs(RcloneJobManager.shared.jobs) : [])
    }

    var body: some View {
        OnePlusMenuPanel {
            HStack(spacing: 7) {
                Image(systemName: tool.symbol).font(.system(size: 13))
                Text(tool.title).onePlusText(.cardTitle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } actions: {
            OnePlusMenuOpenApp {
                ToolActionRouter.shared.open(toolID: tool.id)
            }
        } content: {
            content
        }
        .onePlusPanelTimings(panel: tool.id, tab: tool.id)
    }

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .cloudSync:
            CloudSyncTrayView(jobs: $cloudJobs, showsHeader: false)
        case .awake:
            AwakeTrayRow()
        case .colorPicker:
            quickAction("Pick Color", symbol: ToolGlyph.colorPicker.symbol, action: .colorPickerPick)
        case .textExtractor:
            quickAction("Extract Text", symbol: ToolGlyph.textExtractor.symbol, action: .textExtractorCapture)
        case .inputDevices:
            InputDevicesTrayView(showsHeader: false)
        }
    }

    private func quickAction(_ title: String, symbol: String, action: ToolActionID) -> some View {
        OnePlusMenuTile(span: 3, height: 32, textured: false, action: {
            ToolActionRouter.shared.execute(ToolActionRequest(action: action))
        }) {
            Label(title, systemImage: symbol)
        }
        .accessibilityLabel(title)
    }
}

private struct TrayTabStrip: View {
    let tabs: [TrayTab]
    @Binding var selected: TrayTab
    let reorder: (TrayTab, TrayTab) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabRow.fixedSize(horizontal: true, vertical: false).onePlusMenuTabGroup()
            ScrollView(.horizontal) {
                tabRow
            }
            .thinScrollIndicators()
            .scrollClipDisabled()
            .frame(height: TrayPopoverLayout.tabHeight)
            .onePlusMenuTabGroup()
        }
    }

    private var tabRow: some View {
        HStack(spacing: TrayPopoverLayout.tabSpacing) {
            ForEach(tabs) { tab in
                let index = tabs.firstIndex(of: tab) ?? 0
                if tab == .home {
                    TrayTabButton(tab: tab, selected: selected == tab) { selected = tab }
                } else {
                    TrayTabButton(tab: tab, selected: selected == tab) { selected = tab }
                        .draggable(tab.rawValue)
                        .dropDestination(for: String.self) { values, _ in
                            guard let source = values.first.flatMap(TrayTab.init(rawValue:)) else { return false }
                            reorder(source, tab)
                            return source != .home
                        }
                        .contextMenu {
                            Button("Move Left", systemImage: "arrow.left") {
                                reorder(tab, tabs[index - 1])
                            }
                            .disabled(index <= 1)
                            Button("Move Right", systemImage: "arrow.right") {
                                reorder(tab, tabs[index + 1])
                            }
                            .disabled(index >= tabs.count - 1)
                        }
                }
            }
        }
        .onMoveCommand { direction in
            guard direction == .left || direction == .right else { return }
            if let next = OnePlusSegmented<TrayTab>.nextSelection(in: tabs, current: selected, direction: direction == .left ? -1 : 1) {
                selected = next
            }
        }
    }
}

private struct TrayTabButton: View {
    let tab: TrayTab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TrayTabIcon(tab: tab, selected: selected, size: 12)
                .foregroundStyle(selected ? OnePlusColor.ink : OnePlusColor.secondary)
                .frame(width: TrayPopoverLayout.tabHeight, height: TrayPopoverLayout.tabHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(selected: selected))
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tray.tab.\(tab.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(tab.title)
    }
}

private struct TrayTabIcon: View {
    let tab: TrayTab
    let selected: Bool
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        Image(systemName: tab.symbol)
            .font(.system(size: size, weight: .regular))
    }
}
