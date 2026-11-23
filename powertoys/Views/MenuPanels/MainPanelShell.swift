import OnePlusUI
import SwiftUI

enum TrayTab: String, CaseIterable, Identifiable {
    case home
    case cloudSync = "rclone"
    case inputDevices = "input-devices"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .cloudSync: "RSync UI"
        case .inputDevices: "Input Devices"
        }
    }

    var symbol: String {
        ToolGlyph(rawValue: rawValue)?.symbol ?? "square.grid.2x2"
    }

    var toolID: String? { self == .home ? nil : rawValue }
    /// What the panel's Open arrow opens on this tab.
    var openToolID: String { toolID ?? "main" }

    var panelID: String {
        self == .cloudSync ? "cloud-sync" : rawValue
    }

    init?(panelID: String) {
        self.init(rawValue: panelID == "cloud-sync" ? Self.cloudSync.rawValue : panelID)
    }
}

/// The combined menu panel (DESIGN.md v15): the toolbar with the tab icons, Settings, and Open App, then the
/// selected tab's body. Only the selected tab is mounted; Quit lives in the status item's context menu.
struct TrayPopoverView: View {
    private let diagnostic: Bool
    @AppStorage("tray.selectedTab.v2") private var selectedTabID = TrayTab.home.rawValue
    @AppStorage("tray.tabOrder.v2") private var storedTabOrder = ""
    @Environment(\.onePlusMenuMaximumHeight) private var suppliedCeiling
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

    static func homeToolIDs() -> [String] {
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
    private var panelCeiling: CGFloat {
        suppliedCeiling ?? (NSScreen.main?.visibleFrame.height ?? 800) * TrayPopoverLayout.heightFraction
    }

    var body: some View {
        MainPanelFrame(maximumHeight: TrayPopoverLayout.maximumBodyHeight(panelCeiling: panelCeiling),
                       tabs: tabs, selection: Binding(get: { selectedTab }, set: { select($0) }),
                       onMove: move, openSettings: openSettings, openApp: openApp) {
            MainPanelScrollBody { tabContent }
        }
        .onePlusLiveUpdates()
        .onePlusPanelTimings(panel: "main", tab: selectedTab.panelID)
        .focusedValue(\.appOpenSettings, openSettings)
        .onOpenToolPage(diagnostic ? "menu.main" : nil) { id in
            if let tab = TrayTab(panelID: id), tabs.contains(tab) { select(tab) }
        }
        .onAppear(perform: prepareTabs)
        .onChange(of: MainPanelAwakeMark.shared.pending) { _, pending in if pending && !diagnostic { select(.home) } }
        .onChange(of: storedTabOrder) { prepareTabs() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            prepareTabs()
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
        }
    }

    private func openApp() {
        ToolActionRouter.shared.openFromPanel(toolID: selectedTab.openToolID)
    }

    private func openSettings() {
        ToolActionRouter.shared.openFromPanel(toolID: "main", page: "settings")
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

    /// Home stays first; the tool tabs move among themselves.
    private func move(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source), tabs.indices.contains(destination) else { return }
        reorder(tabs[source], before: tabs[destination])
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

/// The v15 panel frame: the toolbar with the tab icons, Settings, and Open App above the body regions.
struct MainPanelFrame<Regions: View>: View {
    let maximumHeight: CGFloat
    let tabs: [TrayTab]
    @Binding var selection: TrayTab
    let onMove: (Int, Int) -> Void
    let openSettings: () -> Void
    let openApp: () -> Void
    @ViewBuilder let regions: Regions

    var body: some View {
        OnePlusLinearPanel(style: TrayPopoverLayout.style) {
            OnePlusLinearPanelFooter(edge: .top) {
                OnePlusLinearIconTabs(tabs: menuTabs, selection: $selection, onMove: onMove)
            } trailing: {
                AttentionBell()
                OnePlusLinearIconTrack {
                    OnePlusLinearIconButton(systemImage: "gearshape", help: "Open Settings",
                                            size: OnePlusLinearMetrics.iconTab, action: openSettings)
                    OnePlusLinearIconButton(systemImage: "arrow.up.right", help: "Open MacPowerToys",
                                            size: OnePlusLinearMetrics.iconTab, action: openApp)
                        .accessibilityIdentifier("tray.open-app")
                }
            }
        } content: {
            MainPanelBodyLayout(maximumHeight: maximumHeight) { regions }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onePlusDensity(.compact)
        .onePlusNeutralControls()
        .onePlusFocusPolicy()
        .onePlusAppAppearance()
        .transaction { $0.animation = nil }
    }

    private var menuTabs: [OnePlusMenuTab<TrayTab>] {
        tabs.map { tab in
            OnePlusMenuTab(tab, tab.title, systemImage: tab.symbol, image: ToolGlyph(rawValue: tab.rawValue)?.assetImage,
                           accessibilityIdentifier: "tray.tab.\(tab.rawValue)")
        }
    }
}

/// The tab body: natural height, scrolling only when the panel reaches its display ceiling.
struct MainPanelScrollBody<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            content.frame(width: TrayPopoverLayout.bodyWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onePlusScrollIndicators(axes: .vertical)
        .layoutValue(key: MainPanelScrollingBody.self, value: true)
    }
}

/// Marks the one region of the panel body that scrolls once the panel reaches its display ceiling.
struct MainPanelScrollingBody: LayoutValueKey {
    static let defaultValue = false
}

/// Stacks the fixed regions and the scrolling body 12 pt apart. Every region keeps its natural height; the
/// scrolling body gets what remains under `maximumHeight`, so the panel height is known in the first layout pass.
struct MainPanelBodyLayout: Layout {
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? TrayPopoverLayout.bodyWidth
        return CGSize(width: width, height: heights(subviews, width: width).reduce(0, +) + gaps(subviews, width: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for (subview, height) in zip(subviews, heights(subviews, width: bounds.width)) where height > 0 {
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + TrayPopoverLayout.style.blockGap
        }
    }

    private func heights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let natural = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let fixed = zip(subviews, natural).filter { !$0.0[MainPanelScrollingBody.self] }.map(\.1).reduce(0, +)
        let gapTotal = CGFloat(max(0, natural.filter { $0 > 0 }.count - 1)) * TrayPopoverLayout.style.blockGap
        let room = max(0, maximumHeight - fixed - gapTotal)
        return zip(subviews, natural).map { $0.0[MainPanelScrollingBody.self] ? min($0.1, room) : $0.1 }
    }

    private func gaps(_ subviews: Subviews, width: CGFloat) -> CGFloat {
        CGFloat(max(0, heights(subviews, width: width).filter { $0 > 0 }.count - 1)) * TrayPopoverLayout.style.blockGap
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
        OnePlusLinearMenuPanel {
            HStack(spacing: OnePlusLinearMetrics.rowGap) {
                if let logo = ToolRegistry.builtInTools.first(where: { $0.id == tool.id }) {
                    ToolIconView(tool: logo, size: OnePlusLinearMetrics.iconTab).accessibilityHidden(true)
                }
                Text(tool.title).linearText(weight: .semibold).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } trailing: {
            AttentionBell()
            OnePlusLinearIconTrack {
                OnePlusLinearIconButton(systemImage: "gearshape", help: "Open Settings", size: OnePlusLinearMetrics.iconTab) {
                    ToolActionRouter.shared.openFromPanel(toolID: tool.id, page: "settings")
                }
                OnePlusLinearIconButton(systemImage: "arrow.up.right", help: "Open App", size: OnePlusLinearMetrics.iconTab) {
                    ToolActionRouter.shared.openFromPanel(toolID: tool.id)
                }
                .accessibilityIdentifier("tray.\(tool.id).open-app")
            }
        } content: {
            content
        }
        .onePlusPanelTimings(panel: tool.id, tab: tool.id)
        .focusedValue(\.appOpenSettings) {
            ToolActionRouter.shared.open(toolID: tool.id, page: "settings")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .cloudSync:
            CloudSyncTrayView(jobs: $cloudJobs, showsOpenKey: false)
        case .awake:
            AwakeTrayRow()
        case .colorPicker:
            quickAction("Pick Color", symbol: ToolGlyph.colorPicker.symbol, action: .colorPickerPick)
        case .textExtractor:
            quickAction("Extract Text", symbol: ToolGlyph.textExtractor.symbol, action: .textExtractorCapture)
        case .inputDevices:
            InputDevicesTrayView(showsOpenKey: false)
        }
    }

    private func quickAction(_ title: String, symbol: String, action: ToolActionID) -> some View {
        OnePlusLinearActionBar([OnePlusLinearAction(title, systemImage: symbol) {
            ToolActionRouter.shared.execute(ToolActionRequest(action: action))
        }])
    }
}
