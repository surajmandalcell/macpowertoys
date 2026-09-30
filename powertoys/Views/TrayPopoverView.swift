//
//  TrayPopoverView.swift
//  powertoys
//

import AIManagerCore
import OnePlusUI
import Observation
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
        switch self {
        case .home: "house"
        case .cloudSync: "cloud"
        case .inputDevices: "computermouse"
        case .systemCare: "internaldrive"
        case .systemMonitor: "chart.xyaxis.line"
        case .netToys: "network"
        case .switchAccounts: "person.2"
        }
    }

    var toolID: String? { self == .home ? nil : rawValue }

    var panelID: String {
        self == .cloudSync ? "cloud-sync" : rawValue
    }

    init?(panelID: String) {
        self.init(rawValue: panelID == "cloud-sync" ? Self.cloudSync.rawValue : panelID)
    }
}

enum TrayPopoverLayout {
    static let width = OnePlusMenuMetrics.width
    static let horizontalInset = OnePlusMenuMetrics.bodyInset
    static let tabHeight = OnePlusMenuMetrics.tab
    static let tabSpacing = OnePlusMenuMetrics.tabGap
    static let netToysDisclosureHorizontalPadding: CGFloat = 6
    static let netToysDisclosureVerticalPadding: CGFloat = 6
    static let minimumBodyHeight: CGFloat = 54
    static let topChromeHeight = OnePlusMenuMetrics.topBar
    static let heightFraction = OnePlusMenuMetrics.heightFraction
    static let homeToolIDs = ["color-picker", "text-extractor", "awake", "ruler"]
    static let defaultComplexTabs: [TrayTab] = [
        .cloudSync, .inputDevices, .systemCare, .netToys,
        .switchAccounts,
    ]

    static func maximumBodyHeight(screenHeight: CGFloat) -> CGFloat {
        max(minimumBodyHeight, screenHeight * heightFraction - topChromeHeight)
    }

    static func orderedComplexTabs(available: [TrayTab], savedIDs: [String]) -> [TrayTab] {
        let availableSet = Set(available)
        var seen = Set<TrayTab>()
        let saved = savedIDs.compactMap(TrayTab.init(rawValue:)).filter {
            $0 != .home && availableSet.contains($0) && seen.insert($0).inserted
        }
        return saved + defaultComplexTabs.filter { availableSet.contains($0) && !seen.contains($0) }
    }

    static func visibleTransferJobs(
        _ jobs: [TransferJob],
        activeLimit: Int = 5,
        recentLimit: Int = 3
    ) -> [TransferJob] {
        let active = jobs
            .filter { $0.state.isActive }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(activeLimit)
        let recent = jobs
            .filter { $0.state.isTerminal }
            .sorted { ($0.finishedAt ?? $0.createdAt) > ($1.finishedAt ?? $1.createdAt) }
            .prefix(recentLimit)
        return Array(active) + Array(recent)
    }

    static func latestTransfersByRemote(_ jobs: [TransferJob]) -> [String: TransferJob] {
        var latest: [String: TransferJob] = [:]
        for job in jobs {
            for endpoint in [job.sourceFs, job.destinationFs] {
                guard let colon = endpoint.firstIndex(of: ":") else { continue }
                let name = String(endpoint[..<colon])
                let date = job.finishedAt ?? job.createdAt
                if let previous = latest[name], date < (previous.finishedAt ?? previous.createdAt) { continue }
                latest[name] = job
            }
        }
        return latest
    }

    nonisolated static func recentAnchors(
        _ anchors: [SSHAnchorConfiguration],
        statuses: [SSHAnchorStatus],
        limit: Int = 5
    ) -> [SSHAnchorConfiguration] {
        let checkedAt = Dictionary(
            statuses.map { ($0.anchorID, $0.lastCheck) },
            uniquingKeysWith: { max($0, $1) }
        )
        return Array(anchors.enumerated().sorted {
            let left = checkedAt[$0.element.id] ?? .distantPast
            let right = checkedAt[$1.element.id] ?? .distantPast
            return left == right ? $0.offset < $1.offset : left > right
        }.prefix(limit).map(\.element))
    }

    nonisolated static func recentNetworkIssues(
        _ events: [NetworkTransitionEvent],
        limit: Int = 5
    ) -> [NetworkTransitionEvent] {
        Array(events.reversed().filter { event in
            event.changes.contains { change in
                switch change {
                case .network(_, let to): to == "disconnected"
                case .gateway(_, let to), .internet(_, let to): to == .unreachable
                }
            }
        }.prefix(limit))
    }
}

struct TrayPopoverView: View {
    @AppStorage("tray.selectedTab.v2") private var selectedTabID = TrayTab.home.rawValue
    @AppStorage("tray.tabOrder.v2") private var storedTabOrder = ""
    @Environment(\.openWindow) private var openWindow
    @State private var switchModel = SwitchWorkspaceModel()
    @State private var netToysSnapshot = NetToysTraySnapshot()
    @State private var careSnapshot = SystemCareTraySnapshot()
    @State private var startupDisk: SystemCareStartupDiskSnapshot?
    @State private var diskLoaded = false
    @State private var cloudJobs: [TransferJob]
    @State private var preparedHomeTools: [String] = []
    @State private var preparedTabs: [TrayTab] = [.home]

    init() {
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
        OnePlusMenuPanel(maximumHeight: (NSScreen.main?.visibleFrame.height ?? 900) * TrayPopoverLayout.heightFraction) {
            TrayTabStrip(
                tabs: tabs,
                selected: Binding(get: { selectedTab }, set: { select($0) }),
                reorder: reorder
            )
        } actions: {
            OnePlusMenuOpenApp {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openToolSettings, object: "home")
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
        } content: {
            tabContent
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
            SystemCareTrayView(snapshot: $careSnapshot, disk: startupDisk, diskLoaded: diskLoaded)
        case .systemMonitor:
            EmptyView()
        case .netToys:
            NetToysTrayView(snapshot: $netToysSnapshot)
        case .switchAccounts:
            SwitchTrayView(model: switchModel)
        }
    }

    private func select(_ tab: TrayTab) {
        guard tab != selectedTab else { return }
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
    }

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .cloudSync:
            CloudSyncTrayView(jobs: $cloudJobs, showsHeader: false)
        case .awake:
            AwakeTrayRow()
        case .colorPicker:
            quickAction("Pick Color", symbol: "eyedropper", action: .colorPickerPick)
        case .textExtractor:
            quickAction("Extract Text", symbol: "text.viewfinder", action: .textExtractorCapture)
        case .inputDevices:
            InputDevicesTrayView(showsHeader: false)
        }
    }

    private func quickAction(_ title: String, symbol: String, action: ToolActionID) -> some View {
        OnePlusMenuTile(span: 3, height: 70, action: {
            ToolActionRouter.shared.execute(ToolActionRequest(action: action))
        }) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 13))
                Text(title).onePlusText(.row)
            }
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
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
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
        if tab == .cloudSync {
            ZStack {
                Image(systemName: "cloud.fill")
                    .font(.system(size: size * 0.84))
                    .opacity(0.36)
                    .offset(x: 2, y: -2)
                Image(systemName: "cloud")
                    .font(.system(size: size, weight: selected ? .semibold : .regular))
                    .offset(x: -2, y: 2)
            }
        } else {
            Image(systemName: tab.symbol)
                .symbolVariant(selected ? .fill : .none)
                .font(.system(size: size, weight: selected ? .semibold : .regular))
        }
    }
}

private struct TrayHomeView: View {
    let toolIDs: [String]

    var body: some View {
        VStack(spacing: OnePlusMenuMetrics.tileGap) {
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                TrayHomeActionButton(
                    title: "Pick Color", symbol: "eyedropper",
                    enabled: toolIDs.contains("color-picker")
                ) {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: .colorPickerPick))
                }
                TrayHomeActionButton(
                    title: "Extract Text", symbol: "text.viewfinder",
                    enabled: toolIDs.contains("text-extractor")
                ) {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorCapture))
                }
                TrayHomeActionButton(
                    title: "Ruler", symbol: "ruler", iconRotation: -45,
                    enabled: toolIDs.contains("ruler")
                ) {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerOpen))
                }
            }
            if toolIDs.contains("awake") {
                AwakeTrayRow()
            }
        }
    }
}

private struct TrayHomeActionButton: View {
    let title: String
    let symbol: String
    var iconRotation = 0.0
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .rotationEffect(.degrees(iconRotation))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16, height: 16)
                Text(title).onePlusText(.row).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(OnePlusColor.panelHover, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(OnePlusColor.line, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(OnePlusInteractionStyle(radius: 6))
        .disabled(!enabled)
        .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
        .accessibilityLabel(title)
    }
}

private struct AwakeTrayRow: View {
    @State private var service = AwakeService.shared

    private var quickMode: Binding<AwakeQuickMode?> {
        Binding(
            get: {
                let mode = AwakeQuickMode(configuration: service.configuration)
                return mode == .custom ? nil : mode
            },
            set: { mode in
                guard let mode else { return }
                switch mode {
                case .off: service.setMode(.passive)
                case .thirtyMinutes: service.setMode(.timed, duration: 30 * 60)
                case .oneHour: service.setMode(.timed, duration: 60 * 60)
                case .indefinite: service.setMode(.indefinite)
                case .custom: break
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            OnePlusMenuControlRow("Awake", systemImage: "moon.zzz", status: status) {
                OnePlusSegmented(
                    choices: [
                        (AwakeQuickMode?.some(.off), "Off"),
                        (AwakeQuickMode?.some(.thirtyMinutes), "30m"),
                        (AwakeQuickMode?.some(.oneHour), "1h"),
                        (AwakeQuickMode?.some(.indefinite), "∞"),
                    ],
                    selection: quickMode
                )
                .accessibilityLabel("Awake duration")
            }
            OnePlusMenuControlRow("Keep display on", systemImage: "display") {
                Toggle("Keep display on", isOn: Binding(
                    get: { service.configuration.keepDisplayOn },
                    set: service.setKeepDisplayOn
                ))
                .labelsHidden()
                .toggleStyle(OnePlusSwitchStyle())
                .accessibilityIdentifier("awake.keep-display-on")
            }
            if let assertionError = service.assertionError {
                Text(assertionError)
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.danger)
                    .lineLimit(2)
            }
        }
    }

    private var status: String {
        guard service.configuration.mode != .passive else { return "Off" }
        guard let remaining = service.remaining else { return "On" }
        let seconds = max(Int(remaining), 0)
        return String(format: "%d:%02d:%02d left", seconds / 3_600, seconds / 60 % 60, seconds % 60)
    }
}

private struct TrayQuietActionButton: View {
    let title: String
    let symbol: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
        .disabled(disabled)
    }
}

private struct TrayToolHeader: View {
    let tab: TrayTab

    var body: some View {
        OnePlusMenuControlRow(tab.title, systemImage: tab.symbol) {
            Button {
                ToolActionRouter.shared.open(toolID: tab.rawValue)
            } label: {
                Image(systemName: "arrow.up.right")
            }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .accessibilityLabel("Open \(tab.title)")
            .help("Open \(tab.title)")
        }
    }
}

private struct InputDevicesTrayView: View {
    @State private var manager = InputDevicesManager.shared
    @AppStorage("tray.inputDevices.controls.expanded") private var showsControls = false
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            if showsHeader { TrayToolHeader(tab: .inputDevices) }
            OnePlusMenuSectionHeader("Devices", actionTitle: "Refresh") { manager.refresh() }
            if manager.devices.isEmpty {
                OnePlusMenuCard { Text("No pointing devices detected").onePlusText(.caption) }
            } else {
                ForEach(manager.devices) { device in deviceCard(device) }
            }
            OnePlusMenuSectionHeader("Scrolling", actionTitle: showsControls ? "Hide controls" : "Show controls") {
                showsControls.toggle()
            }
            if showsControls {
                InputDevicesSettingsContent()
            } else {
                quickControl
            }
        }
    }

    private var quickControl: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            OnePlusMenuControlRow("Adjust scrolling", systemImage: "scroll") {
                Toggle("Adjust scrolling system wide", isOn: Binding(
                    get: { manager.settings.scrollControlEnabled },
                    set: { value in manager.update { $0.scrollControlEnabled = value } }
                )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            if !manager.permissionGranted {
                OnePlusMenuControlRow("Permission needed", systemImage: "hand.raised") {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Button("Grant") { manager.requestPermission() }
                            .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
                        Button("Settings") { manager.openPrivacySettings() }
                            .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    }
                }
            }
            if let error = manager.errorMessage {
                Text(error).onePlusText(.caption, color: OnePlusColor.danger)
            }
        }
    }

    private func deviceCard(_ device: InputDeviceDescriptor) -> some View {
        let profile = device.kind == .mouse ? manager.settings.mouse : manager.settings.trackpad
        let state = InputControlState.state(settings: manager.settings, permissionGranted: manager.permissionGranted,
                                            kind: device.kind)
        return OnePlusMenuCard(textured: true) {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: device.kind.icon).onePlusText(.row)
                    Text(device.name).onePlusText(.cardTitle).lineLimit(1).help(device.name)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    if let battery = device.batteryPercent {
                        Text("\(battery)%").onePlusText(.mono, color: battery <= 20 ? OnePlusColor.warn : OnePlusColor.dataBlue)
                            .accessibilityLabel("Battery \(battery) percent")
                    }
                }
                Text(device.connectionSummary.components(separatedBy: " · ").first ?? device.transport)
                    .onePlusText(.caption)
                HStack {
                    Text(state.title).onePlusText(.caption)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    Text("\(profile.reverseVertical ? "Reversed" : "Natural") · \(profile.speed.formatted(.number.precision(.fractionLength(2))))×")
                        .onePlusText(.mono)
                }
                if let battery = device.batteryPercent {
                    OnePlusUsageBar(value: Double(battery) / 100, color: battery <= 20 ? OnePlusColor.warn : OnePlusColor.dataBlue)
                        .accessibilityLabel("Battery \(battery) percent")
                }
            }
        }
    }
}

struct SwitchTrayView: View {
    @State private var model: SwitchWorkspaceModel
    @AppStorage("switchUsageShowsUsed") private var showUsageAsUsed = true
    @AppStorage(SwitchTrayUsagePreferences.defaultKey) private var defaultShowUsage = true
    @AppStorage(SwitchTrayUsagePreferences.periodKey) private var tokenPeriod = SwitchTrayTokenPeriod.sinceReset.rawValue

    init() {
        _model = State(initialValue: SwitchWorkspaceModel())
    }

    init(model: SwitchWorkspaceModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            TrayToolHeader(tab: .switchAccounts)
            OnePlusMenuSectionHeader("CLI accounts", actionTitle: "Refresh", compactAction: true) {
                Task { await model.refresh() }
            }
            .disabled(model.isWorking)
            if model.snapshot == nil && model.isWorking {
                OnePlusMenuCard { ProgressView("Loading accounts…").controlSize(.small) }
            } else if model.accounts.isEmpty {
                OnePlusMenuCard { Text("No saved accounts").onePlusText(.caption) }
            } else {
                VStack(spacing: OnePlusMenuMetrics.tileGap) {
                    ForEach(model.accounts) { account in accountCard(account) }
                }
                if model.accounts.contains(where: { $0.identity.providerID == .codex }) {
                    Button("Refresh Usage") {
                        Task {
                            for account in model.accounts where account.identity.providerID == .codex {
                                guard !Task.isCancelled else { return }
                                await model.loadUsage(account.id)
                            }
                        }
                    }
                    .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    .disabled(model.isWorking || !model.usageLoading.isEmpty)
                }
            }
        }
        .task { if model.snapshot == nil { await model.load() } }
        .alert("Switch needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func accountCard(_ account: AccountRecord) -> some View {
        let isDefault = model.snapshot?.status.isDefault(account) == true
        let showsUsage = SwitchTrayUsagePreferences.explicitValue(for: account.id) ?? defaultShowUsage
        return Button {
            guard !isDefault else { return }
            Task { await model.makeDefault(account.id) }
        } label: {
            OnePlusMenuCard {
                VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        SwitchProviderIcon(providerID: account.identity.providerID, size: OnePlusMetrics.compactControlHeight)
                        VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                            Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                                .onePlusText(.row).lineLimit(1)
                            Text(account.identity.providerID.displayName).onePlusText(.caption)
                        }
                        Spacer(minLength: OnePlusMetrics.actionSpacing)
                        if isDefault {
                            Label("Default", systemImage: "checkmark.circle.fill")
                                .onePlusText(.caption, color: OnePlusColor.ink)
                        }
                    }
                    if showsUsage, let snapshot = model.usage[account.id] {
                        if let primary = snapshot.rateLimits?.defaultBucket?.primary?.usedPercent {
                            usageBar(primary, title: "Current window")
                        }
                        if let secondary = snapshot.rateLimits?.defaultBucket?.secondary?.usedPercent {
                            usageBar(secondary, title: "Secondary window")
                        }
                        if let period = SwitchTrayTokenPeriod(rawValue: tokenPeriod) {
                            Text("\(period.tokens(in: snapshot).formatted(.number.notation(.compactName))) tokens")
                                .onePlusText(.caption).help(period.label)
                        }
                    } else if showsUsage, account.identity.providerID == .codex {
                        Text(model.usageLoading.contains(account.id) ? "Loading usage…" : "Refresh Usage to load limits")
                            .onePlusText(.caption)
                    }
                    if let error = model.usageErrors[account.id] {
                        Text(error).onePlusText(.caption, color: OnePlusColor.danger).lineLimit(2).help(error)
                    }
                }
            }
        }
        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.menuTileRadius))
        .disabled(model.isWorking)
        .accessibilityIdentifier("switch.tray.account.\(account.id)")
        .accessibilityValue(isDefault ? "Default" : "Make default")
    }

    private func usageBar(_ percent: Int, title: String) -> some View {
        let fraction = Double(min(max(percent, 0), 100)) / 100
        let label = SwitchTrayUsagePreferences.percentageLabel(used: percent, showUsed: showUsageAsUsed)
        return VStack(spacing: OnePlusMetrics.navRowGap) {
            HStack { Text(title); Spacer(); Text(label).monospacedDigit() }.onePlusText(.caption)
            OnePlusUsageBar(value: showUsageAsUsed ? fraction : 1 - fraction, color: OnePlusColor.accent)
                .accessibilityLabel("\(title), \(label)")
        }
    }
}

private struct CloudSyncTrayView: View {
    @State private var manager = RcloneJobManager.shared
    @State private var remoteTransfers: [String: TransferJob] = [:]
    @Environment(\.onePlusIsVisible) private var isVisible
    @Binding var jobs: [TransferJob]
    var showsHeader = true

    private var activeJobs: [TransferJob] { jobs.filter { $0.state.isActive } }
    private var recentJobs: [TransferJob] { jobs.filter { $0.state.isTerminal } }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            if showsHeader { TrayToolHeader(tab: .cloudSync) }
            if !manager.daemonIsHealthy {
                HStack {
                    Text("The engine is not responding.").onePlusText(.caption, color: OnePlusColor.warn)
                    Spacer()
                    TrayQuietActionButton(title: "Retry", symbol: "arrow.clockwise") {
                        Task { await manager.start() }
                    }
                }
            }
            OnePlusMenuSectionHeader("Remotes", actionTitle: "New Transfer") {
                ToolActionRouter.shared.open(toolID: "rclone", page: "new-transfer")
            }
            if manager.remotes.isEmpty {
                OnePlusMenuCard {
                    Text(manager.daemonIsHealthy ? "No remotes loaded" : "Open Cloud Sync to load remotes")
                        .onePlusText(.caption)
                }
            } else {
                ForEach(manager.remotes) { remote in remoteCard(remote) }
            }
            if jobs.isEmpty {
                OnePlusMenuCard { Text("No transfers yet").onePlusText(.caption) }
            } else {
                HStack(spacing: OnePlusMenuMetrics.tileGap) {
                    OnePlusMenuTile(span: 2) {
                        VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                            Label("Active transfers", systemImage: "cloud").onePlusText(.caption)
                            Text(String(activeJobs.count)).onePlusText(.metric, color: OnePlusColor.dataBlue)
                            Text(RcloneFormat.speed(activeJobs.reduce(0) { $0 + $1.stats.speed }))
                                .onePlusText(.caption).monospacedDigit()
                        }
                    }
                    OnePlusMenuTile {
                        VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                            Text("Recent").onePlusText(.caption)
                            Text(String(recentJobs.count)).onePlusText(.metric)
                        }
                    }
                }
                jobSection("Active", jobs: activeJobs)
                jobSection("Recent", jobs: recentJobs)
            }
        }
        .onChange(of: manager.jobs.map { TrayTransferOrderKey(id: $0.id, state: $0.state) }, initial: true) {
            guard isVisible else { return }
            jobs = TrayPopoverLayout.visibleTransferJobs(manager.jobs)
            remoteTransfers = TrayPopoverLayout.latestTransfersByRemote(manager.jobs)
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            jobs = TrayPopoverLayout.visibleTransferJobs(manager.jobs)
            remoteTransfers = TrayPopoverLayout.latestTransfersByRemote(manager.jobs)
            await manager.refreshRemotes()
        }
    }

    private func remoteCard(_ remote: RcloneRemote) -> some View {
        let lastTransfer = remoteTransfers[remote.name]
        return OnePlusMenuCard {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: remote.icon).onePlusText(.row)
                    Text(remote.displayName).onePlusText(.row, color: OnePlusColor.dataBlue)
                        .lineLimit(1).help(remote.displayName)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    Text(lastTransfer?.state.displayName ?? "Configured").onePlusText(.caption)
                }
                if let lastTransfer {
                    Text("\(lastTransfer.finishedAt == nil ? "Started" : "Last transfer") · \((lastTransfer.finishedAt ?? lastTransfer.createdAt).formatted(date: .abbreviated, time: .shortened))")
                        .onePlusText(.caption)
                } else {
                    Text("No transfers yet · \(remote.typeLabel)").onePlusText(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func jobSection(_ title: String, jobs: [TransferJob]) -> some View {
        if !jobs.isEmpty {
            OnePlusMenuSectionHeader(title)
            ForEach(jobs) { job in
                TrayTransferRow(job: job)
            }
        }
    }
}

private struct TrayTransferOrderKey: Equatable {
    let id: UUID
    let state: TransferState
}

private struct TrayTransferRow: View {
    let job: TransferJob
    @State private var manager = RcloneJobManager.shared
    @State private var showsError = false

    var body: some View {
        OnePlusMenuCard {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack(spacing: OnePlusMenuMetrics.tileGap) {
                    Button {
                        manager.setExpanded(!job.isExpanded, for: job)
                    } label: {
                        Image(systemName: job.isExpanded ? "chevron.down" : "chevron.right")
                            .onePlusText(.caption)
                            .frame(width: OnePlusMetrics.compactControlHeight, height: OnePlusMetrics.compactControlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.iconButtonRadius))
                    .accessibilityLabel(job.isExpanded ? "Hide transfer files" : "Show transfer files")
                    .help(job.isExpanded ? "Hide transfer files" : "Show transfer files")
                    Image(systemName: job.operation.icon).onePlusText(.caption)
                    Text("\(job.sourceDisplay) → \(job.destinationDisplay)")
                        .onePlusText(.row).lineLimit(1).truncationMode(.middle)
                        .help("\(job.sourceDisplay) → \(job.destinationDisplay)")
                    Spacer(minLength: 4)
                    if job.state == .failed, job.errorMessage?.isEmpty == false {
                        Button { showsError.toggle() } label: { stateBadge }
                            .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.iconButtonRadius))
                            .accessibilityLabel(showsError ? "Hide transfer error" : "Show transfer error")
                    } else {
                        stateBadge
                    }
                    if job.canPause {
                        transferButton("Pause transfer", symbol: "pause.fill") { manager.pause(job) }
                    } else if job.canResume {
                        transferButton("Resume transfer", symbol: "play.fill") { manager.resume(job) }
                    } else if job.canRetry {
                        transferButton("Retry transfer", symbol: "arrow.clockwise") { manager.retry(job) }
                    }
                }

                if job.effectiveTotalBytes > 0 || job.state.isActive {
                    OnePlusUsageBar(value: job.progressFraction, color: stateColor)
                    HStack(spacing: OnePlusMenuMetrics.tileGap) {
                        Text("\(RcloneFormat.bytes(job.displayBytes)) of \(RcloneFormat.bytes(job.effectiveTotalBytes))")
                        if job.effectiveTotalFiles > 0 {
                            Text("· \(job.displayFiles) of \(job.effectiveTotalFiles) files")
                        }
                        Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    }
                    .onePlusText(.caption)
                    .lineLimit(1).monospacedDigit()
                    if job.stats.speed > 0 || job.displayEta != nil {
                        HStack {
                            if job.stats.speed > 0 { Text(RcloneFormat.speed(job.stats.speed)) }
                            Spacer()
                            if job.displayEta != nil { Text("ETA \(RcloneFormat.eta(job.displayEta))") }
                        }.onePlusText(.caption).monospacedDigit()
                    }
                }

                if showsError, let error = job.errorMessage, !error.isEmpty {
                    Text(error)
                        .onePlusText(.caption, color: OnePlusColor.danger)
                        .lineLimit(2).help(error)
                }

                if job.isExpanded {
                    VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                        if job.stats.transferring.isEmpty {
                            Text(job.state.isTerminal ? "No in-flight files" : "Waiting for file activity")
                                .onePlusText(.caption)
                        } else {
                            ForEach(Array(job.stats.transferring.prefix(4))) { file in
                                TrayTransferFileRow(file: file)
                            }
                            if job.stats.transferring.count > 4 {
                                Text("\(job.stats.transferring.count - 4) more in-flight files")
                                    .onePlusText(.caption)
                            }
                        }
                    }
                    .padding(.leading, OnePlusMetrics.compactControlHeight + OnePlusMenuMetrics.tileGap)
                }
            }
        }
    }

    private var stateBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: job.state.icon)
            Text(job.state.displayName)
        }
        .onePlusText(.caption, color: stateColor)
        .lineLimit(1)
    }

    private var stateColor: Color {
        switch job.state {
        case .running: OnePlusColor.dataBlue
        case .retrying, .paused: OnePlusColor.warn
        case .completed: OnePlusColor.ok
        case .failed: OnePlusColor.danger
        case .queued, .cancelled: OnePlusColor.secondary
        }
    }

    private func transferButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct TrayTransferFileRow: View {
    let file: FileProgress

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            HStack(spacing: 6) {
                Image(systemName: "doc").onePlusText(.caption)
                Text(file.name).onePlusText(.caption, color: OnePlusColor.ink)
                    .lineLimit(1).truncationMode(.middle).help(file.name)
                Spacer(minLength: 4)
                Text("\(file.percentage)%")
                    .onePlusText(.mono)
            }
            OnePlusUsageBar(value: file.fraction, color: OnePlusColor.dataBlue)
            HStack {
                Text("\(RcloneFormat.bytes(file.bytes)) of \(RcloneFormat.bytes(file.size))")
                Spacer()
                if file.speed > 0 { Text(RcloneFormat.speed(file.speed)) }
                if file.eta != nil { Text("ETA \(RcloneFormat.eta(file.eta))") }
            }
            .onePlusText(.caption)
            .monospacedDigit()
        }
    }
}

nonisolated struct SystemCareStartupDiskSnapshot: Sendable {
    let capacity: Int64
    let free: Int64
    let purgeable: Int64?
    var used: Int64 { capacity - free - (purgeable ?? 0) }

    init?(capacity: Int64, free: Int64, availableForImportantUsage: Int64?) {
        guard capacity > 0 else { return nil }
        self.capacity = capacity
        let boundedFree = min(max(free, 0), capacity)
        self.free = boundedFree
        purgeable = availableForImportantUsage.map { max(min(max($0, 0), capacity) - boundedFree, 0) }
    }

    static func load() -> Self? {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]), let capacity = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity else { return nil }
        return Self(capacity: Int64(capacity), free: Int64(free),
                    availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage)
    }
}

nonisolated struct SystemCareTraySnapshot: Sendable {
    var groups: [SystemCareCategoryID: [SystemCareCleanupRow]] = [:]
    var totals: [(category: SystemCareCategoryID, size: Int64)] = []
    var isPrepared = false
    var totalSize: Int64 { totals.reduce(0) { $0 + $1.size } }

    static func prepare(_ candidates: [CleanupCandidate]) -> Self {
        let groups = Dictionary(grouping: SystemCarePresentationRows.cleanup(candidates)) { $0.candidate.category }
        let totals = SystemCareCategoryID.allCases.compactMap { category -> (SystemCareCategoryID, Int64)? in
            guard let rows = groups[category] else { return nil }
            return (category, rows.reduce(0) { $0 + $1.candidate.size })
        }
        return Self(groups: groups, totals: totals, isPrepared: true)
    }
}

private struct SystemCareTrayView: View {
    @State private var manager = SystemCareManager.shared
    @Binding var snapshot: SystemCareTraySnapshot
    let disk: SystemCareStartupDiskSnapshot?
    let diskLoaded: Bool
    @State private var expandedCategories = Set<SystemCareCategoryID>()
    @State private var confirmTrash = false
    @State private var startedScan = false

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            TrayToolHeader(tab: .systemCare)
            startupDiskSummary
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                Button(manager.hasCleanupScan ? "Scan Again" : "Scan for Cleanup", systemImage: "magnifyingglass") {
                    startedScan = true
                    manager.scanCleanup(categories: Set(SystemCareCategoryID.allCases))
                }
                .buttonStyle(OnePlusButtonStyle(.primary, size: .small))
                .disabled(manager.isWorking)
                if manager.hasCleanupScan {
                    TrayQuietActionButton(title: "Clear Scan", symbol: "xmark.circle", disabled: manager.isWorking) {
                        manager.clearCleanupScan()
                        expandedCategories.removeAll()
                    }
                }
                Spacer(minLength: 0)
                if manager.isWorking {
                    ProgressView().controlSize(.small)
                }
            }


            if manager.isWorking {
                Text(manager.progressMessage ?? "Analyzing cleanup locations…")
                    .onePlusText(.caption)

            }
            if let error = manager.errorMessage {
                Text(error)
                    .onePlusText(.caption, color: OnePlusColor.danger)

            }

            if !manager.hasCleanupScan {
                OnePlusMenuCard { Text("Scan to measure reclaimable storage").onePlusText(.caption) }
            } else if manager.cleanupCandidates.isEmpty {
                OnePlusMenuCard { Text("0 bytes reclaimable in the saved scan").onePlusText(.caption) }
            } else if !snapshot.isPrepared {
                ProgressView("Preparing saved scan…")
            } else {
                cleanupSummary
                selectionBar
                ForEach(SystemCareCategoryID.allCases) { category in
                    categorySection(category)
                }
            }
        }

        .confirmationDialog("Move selected items to Trash?", isPresented: $confirmTrash) {
            Button("Move \(manager.selectedCandidateIDs.count) Items to Trash", role: .destructive) {
                manager.moveSelectedToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Self.bytes(manager.selectedSize)) will remain recoverable in macOS Trash.")
        }
        .onDisappear {
            if startedScan && manager.isWorking { manager.cancel() }
        }
        .task(id: manager.cleanupCandidates) {
            let candidates = manager.cleanupCandidates
            let prepared = await Task.detached(priority: .utility) { SystemCareTraySnapshot.prepare(candidates) }.value
            guard !Task.isCancelled else { return }
            snapshot = prepared
        }
    }

    private var startupDiskSummary: some View {
        OnePlusMenuCard(textured: true) {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack {
                    Label("Startup disk", systemImage: "internaldrive").onePlusText(.caption)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    Text(disk.map { Self.bytes($0.capacity) } ?? (diskLoaded ? "Unavailable" : "Loading…"))
                        .onePlusText(.mono)
                }
                OnePlusSegmentBar(values: disk.map { [Double($0.used), Double($0.purgeable ?? 0), Double($0.free)] } ?? [],
                                  colors: [OnePlusColor.dataBlue, OnePlusColor.warn, OnePlusColor.ok])
                HStack(alignment: .top, spacing: OnePlusMenuMetrics.tileGap) {
                    diskValue("Used", bytes: disk?.used, color: OnePlusColor.dataBlue)
                    diskValue("Purgeable", bytes: disk?.purgeable, color: OnePlusColor.warn)
                        .help("Space macOS can make available when needed")
                    diskValue("Free", bytes: disk?.free, color: OnePlusColor.ok)
                }
            }
        }
    }

    private func diskValue(_ title: String, bytes: Int64?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
            Text(title).onePlusText(.caption, color: color)
            Text(bytes.map { Self.bytes($0) } ?? "—").onePlusText(.mono)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cleanupSummary: some View {
        OnePlusMenuCard(textured: true) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                        Text("Reclaimable storage").onePlusText(.caption)
                        Text(Self.bytes(snapshot.totalSize)).onePlusText(.metric, color: OnePlusColor.warn)
                    }
                    Spacer()
                    Text("\(manager.cleanupCandidates.count) items").onePlusText(.caption)
                }
                OnePlusSegmentBar(values: snapshot.totals.map { Double($0.size) },
                                  colors: snapshot.totals.map { categoryColor($0.category) })
                ForEach(snapshot.totals, id: \.category) { item in
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Image(systemName: item.category.icon).foregroundStyle(categoryColor(item.category))
                        Text(item.category.title)
                        Spacer()
                        Text(Self.bytes(item.size)).monospacedDigit()
                    }.onePlusText(.caption)
                }
            }
        }
    }

    private var selectionBar: some View {
        VStack(spacing: OnePlusMenuMetrics.tileGap) {
            HStack {
                Text("\(manager.selectedCandidateIDs.count) selected · \(Self.bytes(manager.selectedSize))")
                    .onePlusText(.caption).monospacedDigit()
                Spacer(minLength: OnePlusMetrics.actionSpacing)
                Button("Move to Trash", systemImage: "trash") { confirmTrash = true }
                    .buttonStyle(OnePlusButtonStyle(.destructive, size: .small))
                    .disabled(manager.selectedCandidateIDs.isEmpty || manager.isWorking)
            }
            HStack {
                Button("Select All") {
                    manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: true)
                }
                Button("Select None") {
                    manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: false)
                }
                Spacer()
            }.buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
        }
    }

    private func categorySection(_ category: SystemCareCategoryID) -> some View {
        let rows = snapshot.groups[category] ?? []
        return Group {
            if !rows.isEmpty {
                OnePlusMenuCard {
                    VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                        HStack(spacing: 7) {
                            Button {
                                if expandedCategories.contains(category) { expandedCategories.remove(category) }
                                else { expandedCategories.insert(category) }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .onePlusText(.caption)
                                    .rotationEffect(.degrees(expandedCategories.contains(category) ? 90 : 0))
                                    .frame(width: OnePlusMetrics.compactControlHeight, height: OnePlusMetrics.compactControlHeight)
                            }
                            .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.controlRadius))
                            .accessibilityLabel(expandedCategories.contains(category) ? "Collapse \(category.title)" : "Expand \(category.title)")
                            Image(systemName: category.icon).foregroundStyle(categoryColor(category))
                            Text(category.title).onePlusText(.row).lineLimit(1).help("\(category.title): \(category.detail)")
                            Spacer(minLength: OnePlusMenuMetrics.tileGap)
                            Text("\(rows.count)")
                                .onePlusText(.caption)
                                .monospacedDigit()
                            Toggle("Select \(category.title)", isOn: Binding(
                                get: { rows.allSatisfy { manager.selectedCandidateIDs.contains($0.id) } },
                                set: { manager.setCandidates(Set(rows.map(\.id)), selected: $0) }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        }
                        if expandedCategories.contains(category) {
                            LazyVStack(spacing: 2) {
                                ForEach(rows) { row in
                                    Toggle(isOn: Binding(
                                        get: { manager.selectedCandidateIDs.contains(row.id) },
                                        set: { manager.setCandidate(row.id, selected: $0) }
                                    )) {
                                        HStack(spacing: 6) {
                                            Text(row.candidate.name).onePlusText(.caption, color: OnePlusColor.ink)
                                                .lineLimit(1).truncationMode(.middle).help(row.candidate.url.path)
                                            Spacer(minLength: 4)
                                            Text(row.size)
                                                .onePlusText(.caption)
                                                .monospacedDigit()
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .padding(.leading, 29)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                }
            }
        }
    }

    private func categoryColor(_ category: SystemCareCategoryID) -> Color {
        switch category {
        case .caches: OnePlusColor.dataBlue
        case .logs: OnePlusColor.ok
        case .installers: OnePlusColor.warn
        case .developer: OnePlusColor.accent
        }
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

enum SystemMonitorTrayPage: String, CaseIterable, Identifiable {
    case home, cpu, gpu, memory, network, disk, battery, sensors, processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .sensors: "Sensors"
        case .processes: "Processes"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .sensors: "thermometer.medium"
        case .processes: "list.bullet.rectangle"
        }
    }

    var metrics: Set<SystemMonitorMenuMetric> {
        switch self {
        case .home: Set(SystemMonitorMenuMetric.allCases)
        case .cpu: [.cpu, .thermal]
        case .gpu: [.gpu, .thermal]
        case .memory: [.memory]
        case .network: [.network]
        case .disk: [.disk]
        case .battery: [.battery]
        case .sensors: [.thermal]
        case .processes: []
        }
    }
}

struct SystemMonitorMenuPopoverView: View {
    private let defaults: UserDefaults
    private let loadsRemoteProfiles: Bool
    private let onPreferredHeight: (CGFloat) -> Void
    @State private var remoteProfiles: [SystemMonitorRemoteProfile]

    init(
        remoteProfiles: [SystemMonitorRemoteProfile]? = nil,
        defaults: UserDefaults = .standard,
        onPreferredHeight: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.defaults = defaults
        let profiles = remoteProfiles ?? []
        loadsRemoteProfiles = remoteProfiles == nil
        self.onPreferredHeight = onPreferredHeight
        _remoteProfiles = State(initialValue: profiles)
    }

    var body: some View {
        SystemMonitorTrayView(remoteProfiles: remoteProfiles, onPreferredHeight: onPreferredHeight)
        .frame(width: OnePlusMenuMetrics.width)
        .defaultAppStorage(defaults)
        .utilityMotionPolicy()
        .task {
            guard loadsRemoteProfiles else { return }
            let defaults = defaults
            let profiles = await Task.detached(priority: .userInitiated) {
                SystemMonitorRemoteProfiles.load(defaults: defaults)
            }.value
            guard !Task.isCancelled else { return }
            remoteProfiles = profiles
        }
    }
}

struct SystemMonitorTrayView: View {
    @AppStorage("systemMonitor.trayPage") private var pageID = SystemMonitorTrayPage.home.rawValue
    private let remoteProfiles: [SystemMonitorRemoteProfile]
    private let onPreferredHeight: (CGFloat) -> Void
    @State private var processModel = TaskManagerMenuProcessModel()

    init(
        remoteProfiles: [SystemMonitorRemoteProfile] = [],
        onPreferredHeight: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.remoteProfiles = remoteProfiles
        self.onPreferredHeight = onPreferredHeight
    }

    private var service: SystemMonitorService { .shared }
    private var sample: SystemMonitorSample? { service.snapshot }
    private var page: SystemMonitorTrayPage { SystemMonitorTrayPage(rawValue: pageID) ?? .home }
    private func history(_ metric: SystemMonitorMenuMetric) -> [SystemMonitorSample] {
        service.history.samples(for: metric)
    }

    var body: some View {
        OnePlusMenuPanel {
            OnePlusMenuTabStrip(
                tabs: SystemMonitorTrayPage.allCases.map {
                    OnePlusMenuTab($0, $0.title, systemImage: $0.symbol,
                                   accessibilityIdentifier: "system-monitor.tray.\($0.rawValue)")
                },
                selection: Binding(get: { page }, set: { pageID = $0.rawValue })
            )
        } actions: {
            OnePlusMenuOpenApp {
                ToolActionRouter.shared.open(toolID: "system-monitor")
            }
            .accessibilityIdentifier("system-monitor.menu.open-app")
        } content: {
            SystemMonitorObservationScope {
                switch page {
                case .home: homePage
                case .processes: TaskManagerMenuProcessesView(model: processModel)
                default: detailPage
                }
            }
            .modifier(TaskManagerMenuSampling(page: page))
        }
        .onOnePlusMenuHeightChange(onPreferredHeight)
    }

    private var homePage: some View {
        VStack(alignment: .leading, spacing: 5) {
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    metricButton(.cpu, card(
                        .cpu, value: percent(sample?.cpuUsage),
                        detail: "Load \(loadValue)",
                        values: history(.cpu).compactMap(\.cpuUsage)
                    ))
                    metricButton(.gpu, card(
                        .gpu, value: percent(sample?.gpuUsage),
                        detail: "Graphics utilization",
                        values: history(.gpu).compactMap(\.gpuUsage)
                    ))
                    metricButton(.memory, card(
                        .memory, value: percent(sample?.memoryUsage),
                        detail: memoryDetail,
                        values: history(.memory).compactMap(\.memoryUsage),
                        accent: true
                    ))
                }
                GridRow {
                    metricButton(.network, networkCard)
                    .gridCellColumns(2)
                    metricButton(.disk, diskCard)
                }
                GridRow {
                    metricButton(.sensors, thermalCard)
                    .gridCellColumns(2)
                    metricButton(.battery, batteryCard)
                }
            }

            FanControlView(owner: "system-monitor-tray-home", compact: true)
                .frame(height: 30)

            remoteSummary
        }
    }

    private var remoteSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            OnePlusMenuSectionHeader("Remote instances", actionTitle: "Manage", compactAction: true) {
                UserDefaults.standard.set("remote", forKey: "systemMonitor.windowPage")
                ToolActionRouter.shared.open(toolID: "system-monitor")
            }

            TaskManagerRemoteMenuCard(profiles: remoteProfiles)
        }
    }

    @ViewBuilder
    private var detailPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailHero
            if page == .disk {
                OnePlusMenuCard {
                    VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                        HStack {
                            Text("Disk activity").onePlusText(.cardTitle)
                            Spacer()
                            Text("MB/s").onePlusText(.tableHeader)
                        }
                        menuChart
                    }
                }
            }
            detailRows
            if page == .sensors {
                FanControlView(owner: "system-monitor-tray-sensors", compact: true)
                    .frame(height: 30)
            }
        }
    }

    private var detailHero: some View {
        let value: String = switch page {
        case .cpu: percent(sample?.cpuUsage)
        case .gpu: percent(sample?.gpuUsage)
        case .memory: sample?.memoryUsed.map(Self.bytes) ?? "—"
        case .network: sample?.networkDownload.map(Self.rate) ?? "—"
        case .disk: percent(sample?.diskUsage)
        case .battery: sample?.batteryPercent.map { "\($0)%" } ?? "—"
        case .sensors: sample?.thermalState ?? "—"
        case .home, .processes: "—"
        }
        return OnePlusMenuCard(textured: true) {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                        Label(heroTitle, systemImage: page.symbol).onePlusText(.caption)
                        panelMetricValue(value)
                    }
                    Spacer(minLength: OnePlusMetrics.actionSpacing)
                    heroAccessory
                }
                Text(heroCaption).onePlusText(.caption).lineLimit(1)
                if page == .disk {
                    OnePlusUsageBar(value: (sample?.diskUsage ?? 0) / 100)
                        .accessibilityLabel("Disk usage")
                } else {
                    menuChart
                }
            }
        }
    }

    private var heroTitle: String {
        switch page {
        case .cpu: "CPU usage"
        case .gpu: "GPU usage"
        case .memory: "Memory used"
        case .network: "Download"
        case .disk: "System disk"
        case .battery: "Battery"
        case .sensors: "Thermal pressure"
        case .home, .processes: page.title
        }
    }

    private var heroCaption: String {
        switch page {
        case .cpu: "Across \(ProcessInfo.processInfo.activeProcessorCount) cores"
        case .gpu: "Integrated graphics"
        case .memory: sample?.memoryTotal.map { "\(Self.bytes($0)) unified memory" } ?? "—"
        case .network: sample?.networkDetails?.interfaceName ?? "—"
        case .disk: memoryOfDisk
        case .battery: batteryDetail
        case .sensors: "System-reported state"
        case .home, .processes: ""
        }
    }

    @ViewBuilder
    private var heroAccessory: some View {
        switch page {
        case .cpu:
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                heroStat("User", percent(sample?.cpuDetails?.user))
                heroStat("System", percent(sample?.cpuDetails?.system))
            }
        case .memory: heroStat("Used", percent(sample?.memoryUsage))
        case .network: heroStat("Upload", sample?.networkUpload.map(Self.rate) ?? "—")
        case .disk: heroStat("Available", diskAvailable)
        case .battery: heroStat("Health", sample?.batteryDetails?.health ?? "—")
        default: EmptyView()
        }
    }

    private func heroStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: OnePlusMetrics.navRowGap) {
            Text(title).onePlusText(.caption)
            Text(value).onePlusText(.mono).lineLimit(1)
        }
    }

    private var memoryOfDisk: String {
        guard let used = sample?.diskUsed, let total = sample?.diskTotal else { return "—" }
        return "\(Self.bytes(used)) of \(Self.bytes(total)) used"
    }

    private var menuChart: some View {
        let primary: [Double] = switch page {
        case .cpu: history(.cpu).compactMap(\.cpuUsage)
        case .gpu: history(.gpu).compactMap(\.gpuUsage)
        case .memory: history(.memory).compactMap { $0.memoryUsed.map { Double($0) / 1_073_741_824 } }
        case .network: history(.network).compactMap(\.networkDownload)
        case .disk: history(.disk).compactMap { $0.diskDetails?.readPerSecond }
        case .battery: history(.battery).compactMap { $0.batteryPercent.map(Double.init) }
        case .sensors: history(.thermal).compactMap { Self.thermalLevel($0.thermalState) }
        case .home, .processes: []
        }
        let secondary: [Double] = switch page {
        case .network: history(.network).compactMap(\.networkUpload)
        case .disk: history(.disk).compactMap { $0.diskDetails?.writePerSecond }
        default: []
        }
        let ceiling: Double = switch page {
        case .network, .disk: max((primary + secondary).filter(\.isFinite).max() ?? 1, 1)
        case .memory: max(sample?.memoryTotal.map { Double($0) / 1_073_741_824 } ?? 1, 1)
        default: 100
        }
        return VStack(spacing: OnePlusMetrics.navRowGap) {
            if page == .network {
                Text("MB/s").onePlusText(.tableHeader)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                VStack(alignment: .trailing) {
                    Text(chartScale(ceiling))
                    Spacer()
                    Text(chartScale(ceiling / 2))
                    Spacer()
                    Text(page == .sensors ? "Nominal" : "0")
                }.onePlusText(.tableHeader).lineLimit(1)
                .frame(width: [.sensors, .network, .disk].contains(page)
                    ? OnePlusMetrics.titleRow : OnePlusMetrics.compactControlHeight)
                TaskManagerHistoryChart(values: primary, secondary: secondary, range: 0...ceiling,
                                        unit: page == .memory ? "GB" : page == .network || page == .disk ? "B/s" : page == .sensors ? "" : "%",
                                        compact: true, stepped: page == .sensors,
                                        primaryColor: page == .memory ? OnePlusColor.accent : OnePlusColor.chartLine)
            }.frame(height: OnePlusMetrics.searchHeight * 2)
            HStack { Text("−2 min"); Spacer(); Text("Now") }.onePlusText(.tableHeader)
            if page == .network || page == .disk {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Label(page == .network ? "Download" : "Read", systemImage: "minus")
                        .foregroundStyle(OnePlusColor.chartLine)
                    Label(page == .network ? "Upload" : "Write", systemImage: "minus")
                        .foregroundStyle(OnePlusColor.accent)
                }.onePlusText(.caption)
            }
        }
    }

    private func chartScale(_ value: Double) -> String {
        switch page {
        case .network, .disk:
            (value / 1_000_000).formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        case .sensors: value == 100 ? "Critical" : ""
        default: value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    private var detailRows: some View {
        let rows: [(String, String)] = switch page {
        case .cpu:
            [
                ("Load · 1 minute", loadValue),
                ("Load · 5 minutes", sample?.loadAverage.map { Self.decimal($0.1) } ?? "—"),
                ("Load · 15 minutes", sample?.loadAverage.map { Self.decimal($0.2) } ?? "—"),
                ("Logical CPUs", "\(ProcessInfo.processInfo.activeProcessorCount)"),
                ("Thermal pressure", sample?.thermalState ?? "—"),
            ]
        case .gpu:
            [
                ("Graphics utilization", percent(sample?.gpuUsage)),
                ("Memory", "Unified"),
                ("Thermal pressure", sample?.thermalState ?? "—"),
            ]
        case .memory:
            [
                ("Applications", memoryApplications),
                ("Wired", sample?.memoryDetails.map { Self.bytes($0.wired) } ?? "—"),
                ("Available", memoryAvailable),
                ("Total", sample?.memoryTotal.map(Self.bytes) ?? "—"),
                ("Compressed", sample?.memoryDetails.map { Self.bytes($0.compressed) } ?? "—"),
                ("Swap used", sample?.memoryDetails?.swapUsed.map(Self.bytes) ?? "—"),
            ]
        case .network:
            [
                ("Download", sample?.networkDownload.map(Self.rate) ?? "—"),
                ("Upload", sample?.networkUpload.map(Self.rate) ?? "—"),
                ("Interface", sample?.networkDetails?.interfaceName ?? "—"),
                ("Local address", sample?.networkDetails?.localAddress ?? "—"),
            ]
        case .disk:
            [
                ("Used", sample?.diskUsed.map(Self.bytes) ?? "—"),
                ("Available", diskAvailable),
                ("Capacity", sample?.diskTotal.map(Self.bytes) ?? "—"),
                ("Read", sample?.diskDetails?.readPerSecond.map(Self.rate) ?? "—"),
                ("Write", sample?.diskDetails?.writePerSecond.map(Self.rate) ?? "—"),
            ]
        case .battery:
            batteryPanelRows
        case .sensors:
            [("Thermal pressure", sample?.thermalState ?? "—")]
        case .home, .processes:
            []
        }
        return OnePlusMenuCard {
            VStack(spacing: 0) {
                HStack { Text(detailTitle).onePlusText(.cardTitle); Spacer() }
                    .padding(.bottom, OnePlusMenuMetrics.tileGap)
                OnePlusRule()
                ForEach(rows.indices, id: \.self) { index in
                    OnePlusKeyValueRow(rows[index].0, value: rows[index].1, monospaced: true)
                    if index < rows.count - 1 {
                        Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                    }
                }
            }
        }
    }

    private var detailTitle: String {
        switch page {
        case .cpu: "Load average"
        case .gpu: "Graphics"
        case .memory: "Allocation"
        case .network: "Interface"
        case .disk: "Disk details"
        case .battery: "Battery details"
        case .sensors: "Sensors"
        case .home, .processes: page.title
        }
    }

    private func metricButton<Content: View>(
        _ destination: SystemMonitorTrayPage,
        _ content: Content
    ) -> some View {
        Button { pageID = destination.rawValue } label: {
            content.contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.menuTileRadius))
        .accessibilityHint("Show \(destination.title) details")
        .accessibilityIdentifier("system-monitor.tray.summary.\(destination.rawValue)")
    }

    private func card(
        _ metric: SystemMonitorMenuMetric,
        title: String? = nil,
        value: String,
        detail: String,
        values: [Double],
        accent: Bool = false
    ) -> some View {
        OnePlusMenuTile {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    metricIcon(metric)
                    Text(title ?? metric.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(TaskManagerTheme.secondary)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    panelMetricValue(value)
                    Spacer(minLength: 2)
                    TaskManagerHistoryChart(
                        values: values,
                        range: chartRange(values, metric: metric),
                        unit: metric == .network ? "/s" : "%",
                        compact: true,
                        primaryColor: accent ? TaskManagerTheme.accent : TaskManagerTheme.ink.opacity(0.76)
                    )
                    .frame(width: 36, height: 19)
                }
                .frame(height: 23)
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(TaskManagerTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var networkCard: some View {
        OnePlusMenuTile(span: 2, height: 51, textured: false) {
            VStack(alignment: .leading, spacing: 3) {
                metricLabel(.network)
                HStack(spacing: 8) {
                    compactRate("↓", sample?.networkDownload)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    compactRate("↑", sample?.networkUpload, accent: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var diskCard: some View {
        OnePlusMenuTile(height: 51, textured: false) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    metricIcon(SystemMonitorMenuMetric.disk)
                    Text("Disk")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(TaskManagerTheme.secondary)
                    Spacer(minLength: 3)
                    Text(percent(sample?.diskUsage))
                        .font(.system(size: 15, weight: .medium))
                        .monospacedDigit()
                }
                Text(diskAvailable)
                    .font(.system(size: 8))
                    .foregroundStyle(TaskManagerTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var thermalCard: some View {
        OnePlusMenuTile(span: 2, height: 34, textured: false) {
            HStack(spacing: 8) {
                metricLabel(.thermal, title: "Thermal")
                Spacer(minLength: 4)
                Text(sample?.thermalState ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
            }
        }
    }

    private var batteryCard: some View {
        OnePlusMenuTile(height: 34, textured: false) {
            HStack(spacing: 5) {
                metricIcon(SystemMonitorMenuMetric.battery)
                Spacer(minLength: 2)
                Text(sample?.batteryPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                if sample?.batteryCharging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(TaskManagerTheme.muted)
                }
            }
        }
    }

    private func metricLabel(_ metric: SystemMonitorMenuMetric, title: String? = nil) -> some View {
        HStack(spacing: 5) {
            metricIcon(metric)
            Text(title ?? metric.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(TaskManagerTheme.secondary)
        }
    }

    private func compactRate(_ arrow: String, _ value: Double?, accent: Bool = false) -> some View {
        let parts = TaskManagerMetricText.parts(value.map(Self.rate) ?? "—")
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(arrow)
                .foregroundStyle(accent ? TaskManagerTheme.accent.opacity(0.78) : TaskManagerTheme.secondary)
            Text(parts.value)
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: 9))
                    .foregroundStyle(TaskManagerTheme.secondary)
            }
        }
    }

    private func panelMetricValue(_ text: String) -> some View {
        let parts = TaskManagerMetricText.parts(text)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(parts.value)
                .font(.system(size: 21, weight: .medium))
                .monospacedDigit()
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: 10))
                    .foregroundStyle(TaskManagerTheme.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func metricIcon(_ page: SystemMonitorTrayPage) -> some View {
        Image(systemName: page.symbol)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(TaskManagerTheme.secondary)
    }

    private func metricIcon(_ metric: SystemMonitorMenuMetric) -> some View {
        Image(systemName: metric == .gpu ? SystemMonitorTrayPage.gpu.symbol : metric.symbol)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(TaskManagerTheme.secondary)
    }

    private func chartRange(
        _ values: [Double],
        metric: SystemMonitorMenuMetric? = nil
    ) -> ClosedRange<Double> {
        if metric == .network || (metric == nil && page == .network) {
            0...max(values.max() ?? 1, 1)
        } else {
            0...100
        }
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    private var memoryDetail: String {
        guard let used = sample?.memoryUsed, let total = sample?.memoryTotal else { return "—" }
        return "\(Self.shortBytes(used)) / \(Self.shortBytes(total))"
    }

    private var memoryApplications: String {
        guard let used = sample?.memoryUsed, let details = sample?.memoryDetails else { return "—" }
        return Self.bytes(max(used - details.wired - details.compressed, 0))
    }

    private var memoryAvailable: String {
        guard let used = sample?.memoryUsed, let total = sample?.memoryTotal else { return "—" }
        return Self.bytes(max(total - used, 0))
    }

    private var diskAvailable: String {
        guard let used = sample?.diskUsed, let total = sample?.diskTotal else { return "—" }
        return Self.bytes(max(total - used, 0)) + " free"
    }

    private var batteryDetail: String {
        guard let charging = sample?.batteryCharging else { return "—" }
        return charging ? "Connected to power" : "On battery"
    }

    private var batteryPower: String {
        guard let voltage = sample?.batteryDetails?.voltageMillivolts,
              let amperage = sample?.batteryDetails?.amperageMilliamps else { return "—" }
        let watts = Double(voltage) * Double(abs(amperage)) / 1_000_000
        return "\(Self.decimal(watts)) W"
    }

    private var batteryPanelRows: [(String, String)] {
        var rows = [("Status", batteryDetail)]
        if let health = sample?.batteryDetails?.health { rows.append(("Health", health)) }
        if let cycles = sample?.batteryDetails?.cycleCount { rows.append(("Cycle count", String(cycles))) }
        if batteryPower != "—" { rows.append(("Power draw", batteryPower)) }
        return rows
    }

    private var loadValue: String {
        sample?.loadAverage.map { Self.decimal($0.0) } ?? "—"
    }

    nonisolated private static func thermalLevel(_ state: String?) -> Double? {
        switch state {
        case "Nominal": 0
        case "Fair": 33
        case "Serious": 66
        case "Critical": 100
        default: nil
        }
    }

    nonisolated private static func rate(_ bytes: Double) -> String {
        SystemMonitorDisplayFormat.byteRate(bytes)
    }

    nonisolated private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    nonisolated private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    nonisolated private static func shortBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }
}

private struct TaskManagerRemoteMenuCard: View {
    let profiles: [SystemMonitorRemoteProfile]

    @ViewBuilder
    var body: some View {
        if profiles.isEmpty {
            OnePlusMenuTile(span: 3, height: 51, textured: false, action: openRemoteStats) {
                HStack(spacing: 9) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 10))
                        .foregroundStyle(OnePlusColor.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No remote hosts").onePlusText(.row)
                        Text("Add a Mac, Windows, or Linux computer")
                            .onePlusText(.caption)
                    }
                    Spacer()
                    Text("Add  →").onePlusText(.caption)
                }
            }
        } else {
            LazyVStack(spacing: 6) {
                ForEach(profiles) { profile in
                    remoteCard(profile)
                }
            }
        }
    }

    private func remoteCard(_ profile: SystemMonitorRemoteProfile) -> some View {
        OnePlusMenuItemCard(
            profile.name,
            status: "Offline",
            online: false,
            metrics: [
                OnePlusMenuMetric("CPU", value: "—"),
                OnePlusMenuMetric("RAM", value: "—"),
                OnePlusMenuMetric("Network", value: "—"),
            ]
        ) {
            Text("Connect on demand").onePlusText(.caption)
        } actions: {
            Button("Open SSH") { SystemMonitorRemoteTerminal.open(profile) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Open SSH for \(profile.name)")
            OnePlusColor.lineSoft.frame(height: 1)
            Button("Open App", action: openRemoteStats)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Open Task Manager for \(profile.name)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.platform.rawValue), offline")
    }

    private func openRemoteStats() {
        UserDefaults.standard.set("remote", forKey: "systemMonitor.windowPage")
        ToolActionRouter.shared.open(toolID: "system-monitor")
    }
}

private struct TaskManagerMenuProcessRequest: Hashable {
    let generation: Int
    let search: String
}

private struct TaskManagerMenuSampling: ViewModifier {
    let page: SystemMonitorTrayPage
    @Environment(\.onePlusIsVisible) private var isVisible

    func body(content: Content) -> some View {
        content
            .onChange(of: isVisible, initial: true) {
                if isVisible {
                    SystemMonitorService.shared.startDetailed(owner: "tray", metrics: page.metrics)
                } else {
                    SystemMonitorService.shared.stopDetailed(owner: "tray")
                }
            }
            .onChange(of: page) {
                if isVisible { SystemMonitorService.shared.updateDetailed(owner: "tray", metrics: page.metrics) }
            }
            .onDisappear { SystemMonitorService.shared.stopDetailed(owner: "tray") }
    }
}

@Observable
private final class TaskManagerMenuProcessModel {
    @ObservationIgnored let sampler = SystemMonitorProcessSampler()
    var processes: [SystemMonitorProcess] = []
    var rows: [SystemMonitorProcessHierarchy.Row] = []
    var processCount = 0
    var generation = 0
    var search = ""
}

private struct TaskManagerMenuProcessesView: View {
    @Bindable var model: TaskManagerMenuProcessModel
    @Environment(\.onePlusIsVisible) private var isVisible

    private var request: TaskManagerMenuProcessRequest {
        TaskManagerMenuProcessRequest(generation: model.generation, search: model.search)
    }

    var body: some View {
        VStack(spacing: 8) {
            TaskManagerSearchField(prompt: "Find a process…", text: $model.search, width: OnePlusMenuMetrics.bodyWidth)

            OnePlusMenuCard(padded: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Process").padding(.leading, OnePlusMetrics.compactControlHeight)
                        Spacer()
                        Text("CPU").frame(width: 52, alignment: .trailing)
                        Text("Memory").frame(width: 72, alignment: .trailing)
                    }
                    .onePlusText(.tableHeader)
                    .padding(.horizontal, OnePlusMenuMetrics.bodyInset)
                    .frame(height: OnePlusTable.rowHeight(.compact))
                    .background(OnePlusColor.sidebar)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.rows) { row in
                                Button { openProcesses() } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "app")
                                            .onePlusText(.caption)
                                            .frame(width: OnePlusMetrics.navIcon, height: OnePlusMetrics.navIcon)
                                        Text(row.process.name)
                                            .onePlusText(.caption, color: OnePlusColor.ink)
                                            .lineLimit(1).help(row.process.name)
                                        Spacer(minLength: 4)
                                        Text(row.cpuText)
                                            .frame(width: 52, alignment: .trailing)
                                        Text(row.memoryText)
                                            .frame(width: 72, alignment: .trailing)
                                    }
                                    .onePlusText(.mono)
                                    .padding(.horizontal, OnePlusMenuMetrics.bodyInset)
                                    .frame(height: OnePlusTable.rowHeight(.compact))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.menuTileRadius))
                                .overlay(alignment: .bottom) { OnePlusRule() }
                            }
                        }
                    }
                    .frame(height: OnePlusTable.rowHeight(.compact) * 8)
                    .thinScrollIndicators()

                    Button("All \(model.processCount) processes  →") { openProcesses() }
                        .onePlusText(.caption)
                        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.menuTileRadius))
                        .frame(maxWidth: .infinity, minHeight: OnePlusTable.rowHeight(.compact), alignment: .trailing)
                        .padding(.horizontal, OnePlusMenuMetrics.bodyInset)
                }
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            while !Task.isCancelled {
                let processes = await model.sampler.sample()
                guard !Task.isCancelled else { return }
                model.processes = processes
                model.processCount = processes.count
                model.generation &+= 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task(id: request) { await prepareRows(request) }
    }

    private func prepareRows(_ request: TaskManagerMenuProcessRequest) async {
        let result = await SystemMonitorProcessRows.prepareOffMain(
            model.processes,
            search: request.search,
            hierarchy: false,
            column: .cpu,
            descending: true,
            limit: 9
        )
        guard !Task.isCancelled, self.request == request else { return }
        model.rows = result.rows
    }

    private func openProcesses() {
        UserDefaults.standard.set("processes", forKey: "systemMonitor.windowPage")
        ToolActionRouter.shared.open(toolID: "system-monitor")
    }
}

private struct NetToysTraySnapshot: Sendable {
    var configuration = NetToysConfiguration()
    var helperStatus: NetToysHelperStatus?
    var recentAnchors: [SSHAnchorConfiguration] = []
    var recentIssues: [NetworkTransitionEvent] = []
    var route: DefaultRoute?
    var localNetwork: LocalIPv4Network?
    var ssid: String?
    var isWiFi = false
    var gatewayMilliseconds: Double?
    var isLoaded = false

    nonisolated static func load() async -> Self {
        var result = await Task.detached(priority: .utility) {
            let configuration = NetToysConfigurationStore.load()
            let status = NetToysConfigurationStore.status()
            return Self(configuration: configuration, helperStatus: status,
                        recentAnchors: TrayPopoverLayout.recentAnchors(configuration.anchors, statuses: status?.anchors ?? []),
                        recentIssues: TrayPopoverLayout.recentNetworkIssues(NetToysConfigurationStore.history().events),
                        isLoaded: true)
        }.value
        guard !Task.isCancelled else { return result }
        let routeData = try? await TailscalePeerCatalog.runStatusCommand(
            executableURL: URL(fileURLWithPath: "/sbin/route"), arguments: ["-n", "get", "default"],
            maximumOutputBytes: 8_192, timeout: 2
        )
        guard !Task.isCancelled else { return result }
        result.route = routeData.flatMap { DefaultRoute.parse(String(decoding: $0, as: UTF8.self)) }
        if let route = result.route {
            let local = await Task.detached(priority: .utility) {
                (LocalIPv4Network.active(preferredInterfaceName: route.interfaceName),
                 NetworkSSID.current(interfaceName: route.interfaceName),
                 NetworkSSID.isWiFi(interfaceName: route.interfaceName))
            }.value
            result.localNetwork = local.0?.interfaceName == route.interfaceName ? local.0 : nil
            result.ssid = local.1
            result.isWiFi = local.2
            guard !Task.isCancelled else { return result }
            let ping = try? await TailscalePeerCatalog.runStatusCommand(
                executableURL: URL(fileURLWithPath: "/sbin/ping"), arguments: ["-n", "-c", "1", "-W", "1000", route.gateway],
                environment: ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new },
                maximumOutputBytes: 8_192, timeout: 2
            )
            result.gatewayMilliseconds = ping.flatMap { PingProbe.parse(String(decoding: $0, as: UTF8.self))?.averageMilliseconds }
        }
        return result
    }
}

private struct NetToysTrayView: View {
    @Binding var snapshot: NetToysTraySnapshot
    @Environment(\.onePlusIsVisible) private var isVisible
    @State private var loading = false
    @State private var refreshRequest = UUID()

    private var configuration: NetToysConfiguration {
        get { snapshot.configuration }
        nonmutating set { snapshot.configuration = newValue }
    }
    @State private var errorMessage: String?
    @AppStorage("tray.nettoys.anchor.expanded") private var anchorExpanded = false
    @AppStorage("tray.nettoys.wifi.expanded") private var wifiExpanded = false
    @AppStorage("tray.nettoys.history.expanded") private var historyExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .netToys)
            VStack(spacing: OnePlusMenuMetrics.tileGap) {
                networkTiles
                OnePlusMenuSectionHeader("Network controls", actionTitle: "Refresh", compactAction: true) {
                    refreshRequest = UUID()
                }
                .disabled(loading)
                activitySection(
                    title: "SSH Anchor",
                    detail: configuration.anchors.isEmpty
                        ? "No configured anchors"
                        : "\(configuration.monitoredAnchors.count) of \(configuration.anchors.count) active",
                    symbol: "link",
                    isOn: Binding(
                        get: { configuration.sshAnchorEnabled },
                        set: { configuration.sshAnchorEnabled = $0; save() }
                    ),
                    disabled: configuration.anchors.isEmpty,
                    isExpanded: $anchorExpanded
                ) {
                    if snapshot.recentAnchors.isEmpty {
                        emptyActivity("No anchors to show")
                    } else {
                        ForEach(snapshot.recentAnchors) { anchor in
                            anchorRow(anchor)
                        }
                    }
                    openPageButton("Open all anchors", page: .anchor)
                }
                activitySection(
                    title: "Wi-Fi Priority",
                    detail: "\(configuration.wifiPriority.ssids.count) saved networks",
                    symbol: "wifi",
                    isOn: Binding(
                        get: { configuration.wifiPriority.isEnabled },
                        set: {
                            configuration.wifiPriority.isEnabled = $0
                                && configuration.wifiPriority.ssids.count >= 2
                            save()
                        }
                    ),
                    disabled: configuration.wifiPriority.ssids.count < 2,
                    isExpanded: $wifiExpanded
                ) {
                    if configuration.wifiPriority.ssids.isEmpty {
                        emptyActivity("No priority networks")
                    } else {
                        ForEach(Array(configuration.wifiPriority.ssids.prefix(5).enumerated()), id: \.offset) { index, ssid in
                            activityRow(
                                symbol: snapshot.helperStatus?.network?.ssid == ssid ? "wifi" : "line.3.horizontal",
                                title: ssid,
                                detail: snapshot.helperStatus?.network?.ssid == ssid ? "Connected" : "Priority \(index + 1)"
                            )
                        }
                    }
                    openPageButton("Open Wi-Fi Priority", page: .wifiPriority)
                }
                activitySection(
                    title: "Network History",
                    detail: configuration.recordsNetworkHistory ? "Recording changes" : "Not recording",
                    symbol: "chart.xyaxis.line",
                    isOn: Binding(
                        get: { configuration.recordsNetworkHistory },
                        set: { configuration.recordsNetworkHistory = $0; save() }
                    ),
                    isExpanded: $historyExpanded
                ) {
                    if snapshot.recentIssues.isEmpty {
                        emptyActivity("No recent network issues")
                    } else {
                        ForEach(Array(snapshot.recentIssues.enumerated()), id: \.offset) { _, event in
                            activityRow(
                                symbol: "exclamationmark.circle",
                                title: event.displayName,
                                detail: event.changes.map(NetToysHistoryViewModel.description).joined(separator: " · ")
                            )
                        }
                    }
                    openPageButton("Open Network History", page: .history)
                }
            }
            .disabled(!snapshot.isLoaded)
            if let errorMessage {
                Text(errorMessage)
                    .onePlusText(.caption, color: OnePlusColor.danger)
                    .padding(.top, OnePlusMenuMetrics.tileGap)
            }
        }
        .task(id: isVisible ? refreshRequest : nil) {
            guard isVisible else { loading = false; return }
            await refresh()
        }
    }

    private var helperDetail: String {
        guard let status = snapshot.helperStatus else { return "Background helper is not reporting" }
        return "Updated \(status.heartbeat.formatted(date: .omitted, time: .shortened))"
    }

    private var networkTiles: some View {
        VStack(spacing: OnePlusMenuMetrics.tileGap) {
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                OnePlusMenuTile(span: 2) {
                    VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                        Label("Current network", systemImage: "network").onePlusText(.caption)
                        Text(snapshot.ssid ?? snapshot.route?.interfaceName ?? (snapshot.isLoaded ? "Disconnected" : "Loading…"))
                            .onePlusText(.cardTitle, color: OnePlusColor.dataBlue).lineLimit(1)
                        Text(snapshot.isWiFi && snapshot.ssid == nil ? "Wi-Fi name unavailable" : helperDetail)
                            .onePlusText(.caption).lineLimit(1)
                    }
                }
                networkTile("Interface", value: snapshot.route?.interfaceName ?? "—", detail: reachability)
            }
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                networkTile("Local IP", value: snapshot.localNetwork?.address.description ?? "—", detail: "IPv4", span: 2)
                networkTile("Gateway", value: snapshot.gatewayMilliseconds.map {
                    $0.formatted(.number.precision(.fractionLength(1))) + " ms"
                } ?? (snapshot.route == nil ? "—" : "No reply"), detail: snapshot.route?.gateway ?? "—")
            }
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                Button("Scan network", systemImage: "magnifyingglass") {
                    open(.scanner)
                }
                Button("Copy IP", systemImage: "doc.on.doc") {
                    if let address = snapshot.localNetwork?.address.description {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(address, forType: .string)
                    }
                }
                .disabled(snapshot.localNetwork == nil)
                Spacer(minLength: 0)
            }
            .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
        }
    }

    private func networkTile(_ title: String, value: String, detail: String, span: Int = 1) -> some View {
        OnePlusMenuTile(span: span) {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                Text(title).onePlusText(.caption)
                Text(value).onePlusText(.cardTitle, color: OnePlusColor.dataBlue).lineLimit(1).help(value)
                Text(detail).onePlusText(.caption).lineLimit(1)
            }
        }
    }

    private var reachability: String {
        guard snapshot.helperStatus?.network?.networkID == snapshot.route?.networkID else { return "Unknown" }
        return switch snapshot.helperStatus?.network?.internet {
        case .reachable: "Online"
        case .unreachable: "Offline"
        default: "Unknown"
        }
    }

    private func refresh() async {
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        let savedConfiguration = configuration
        var result = await NetToysTraySnapshot.load()
        guard !Task.isCancelled else { return }
        if configuration != savedConfiguration { result.configuration = configuration }
        snapshot = result
    }

    private func activitySection<Content: View>(
        title: String,
        detail: String,
        symbol: String,
        isOn: Binding<Bool>,
        disabled: Bool = false,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        OnePlusMenuCard {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button { isExpanded.wrappedValue.toggle() } label: {
                        HStack(spacing: 9) {
                            Image(systemName: symbol)
                                .onePlusText(.row, color: OnePlusColor.secondary)
                                .frame(width: OnePlusMetrics.compactControlHeight)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).onePlusText(.row)
                                Text(detail).onePlusText(.caption).lineLimit(1).help(detail)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .onePlusText(.caption)
                                .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        }
                        .padding(.horizontal, TrayPopoverLayout.netToysDisclosureHorizontalPadding)
                        .padding(.vertical, TrayPopoverLayout.netToysDisclosureVerticalPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.controlRadius))
                    .accessibilityLabel("\(isExpanded.wrappedValue ? "Hide" : "Show") \(title) activity")
                    Toggle(title, isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(OnePlusSwitchStyle())
                        .disabled(disabled)
                }
                if isExpanded.wrappedValue {
                    VStack(spacing: 0) { content() }
                        .padding(.leading, OnePlusMetrics.compactControlHeight + OnePlusMenuMetrics.tileGap)
                        .padding(.bottom, OnePlusMenuMetrics.tileGap)
                }
            }
        }
    }

    private func anchorRow(_ anchor: SSHAnchorConfiguration) -> some View {
        let status = snapshot.helperStatus?.anchors.first { $0.anchorID == anchor.id }
        return activityRow(
            symbol: status?.state == .healthy ? "checkmark.circle" : "link",
            title: anchor.hostAlias,
            detail: status.map { "\($0.currentHostName) · \($0.lastCheck.formatted(date: .omitted, time: .shortened))" }
                ?? anchor.hostName
        )
    }

    private func activityRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .onePlusText(.caption)
                .frame(width: OnePlusMetrics.compactControlHeight)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).onePlusText(.row).lineLimit(1).help(title)
                Text(detail).onePlusText(.caption).lineLimit(1).help(detail)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, OnePlusMenuMetrics.tileGap)
    }

    private func emptyActivity(_ message: String) -> some View {
        Text(message)
            .onePlusText(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, OnePlusMenuMetrics.tileGap)
    }

    private func openPageButton(_ title: String, page: NetToysPage) -> some View {
        Button { open(page) } label: {
            Label(title, systemImage: "arrow.up.forward.square")
                .onePlusText(.caption, color: OnePlusColor.secondary)
                .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.compactControlHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.controlRadius))
        .padding(.top, OnePlusMenuMetrics.tileGap)
    }

    private func open(_ page: NetToysPage) {
        ToolActionRouter.shared.open(toolID: "nettoys")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .netToysOpenPage, object: page)
        }
    }

    private func save() {
        do {
            try NetToysConfigurationStore.save(configuration)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
