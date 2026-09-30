//
//  TrayPopoverView.swift
//  powertoys
//

import AIManagerCore
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
    static let transitionDuration = UtilityMotion.standardDuration
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

    static func recentAnchors(
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

    static func recentNetworkIssues(
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
    @State private var configurationRevision = 0

    private var homeToolIDs: [String] {
        _ = configurationRevision
        return TrayPopoverLayout.homeToolIDs.dropLast().filter { id in
            guard SettingsManager.shared.isToolEnabled(id),
                  let tool = IndividualMenuBarTool(rawValue: id)
            else { return false }
            return tool.usesMenuBarMode(.combined, enabled: true)
        } + (SettingsManager.shared.isToolEnabled("ruler") ? ["ruler"] : [])
    }

    private var complexTabs: [TrayTab] {
        _ = configurationRevision
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
            savedIDs: storedTabOrder.split(separator: ",").map(String.init)
        )
    }

    private var tabs: [TrayTab] { [.home] + complexTabs }
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
                .id(selectedTabID)
                .transition(.opacity)
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: storedTabOrder) { normalizeSelection() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            configurationRevision += 1
            normalizeSelection()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            TrayHomeView(toolIDs: homeToolIDs)
        case .cloudSync:
            CloudSyncTrayView()
        case .inputDevices:
            VStack(spacing: 0) {
                TrayToolHeader(tab: .inputDevices)
                InputDevicesSettingsView(
                    showsHeader: true,
                    showsContainerScroll: false,
                    contentTopInset: 6
                )
            }
        case .systemCare:
            SystemCareTrayView()
        case .systemMonitor:
            EmptyView()
        case .netToys:
            NetToysTrayView()
        case .switchAccounts:
            SwitchTrayView()
        }
    }

    private func select(_ tab: TrayTab) {
        guard tab != selectedTab else { return }
        withAnimation(.easeInOut(duration: TrayPopoverLayout.transitionDuration)) {
            selectedTabID = tab.rawValue
        }
    }

    private func normalizeSelection() {
        guard !tabs.contains(selectedTab) else { return }
        selectedTabID = TrayTab.home.rawValue
    }

    private func reorder(_ source: TrayTab, before destination: TrayTab) {
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
            CloudSyncTrayView(showsHeader: false)
        case .awake:
            AwakeTrayRow()
        case .colorPicker:
            quickAction("Pick Color", symbol: "eyedropper", action: .colorPickerPick)
        case .textExtractor:
            quickAction("Extract Text", symbol: "text.viewfinder", action: .textExtractorCapture)
        case .inputDevices:
            InputDevicesSettingsView(
                showsHeader: true,
                showsContainerScroll: false,
                contentTopInset: 6
            )
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
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .switchAccounts)
            HStack {
                Text("CLI ACCOUNTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .labelStyle(.iconOnly)
                .help("Refresh accounts")
                .disabled(model.isWorking)
            }
            .controlSize(.small)
            .padding(.horizontal, TrayPopoverLayout.horizontalInset)
            .padding(.top, 6)
            .padding(.bottom, 7)

            if model.snapshot == nil && model.isWorking {
                ProgressView("Loading accounts…")
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else if model.accounts.isEmpty {
                EmptyStateView(icon: "person.crop.circle.badge.plus", message: "No saved accounts")
                    .frame(height: 96)
            } else {
                LazyVStack(spacing: 3) {
                    ForEach(model.accounts) { account in
                        let isDefault = model.snapshot?.status.isDefault(account) == true
                        let showsUsage = SwitchTrayUsagePreferences.explicitValue(for: account.id)
                            ?? defaultShowUsage
                        Button {
                            Task { await model.makeDefault(account.id) }
                        } label: {
                            HStack(spacing: 10) {
                                SwitchProviderIcon(providerID: account.identity.providerID, size: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(account.identity.providerID.displayName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if showsUsage, let snapshot = model.usage[account.id] {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        if let percent = snapshot.rateLimits?.defaultBucket?.primary?.usedPercent {
                                            Text(SwitchTrayUsagePreferences.percentageLabel(
                                                used: percent, showUsed: showUsageAsUsed))
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                        }
                                        if let period = SwitchTrayTokenPeriod(rawValue: tokenPeriod) {
                                            Text("\(period.tokens(in: snapshot).formatted(.number.notation(.compactName))) tokens")
                                                .font(.system(size: 9))
                                                .help(period.label)
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                if isDefault {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("Default")
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isDefault ? Color.accentColor.opacity(0.09) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 8))
                        .disabled(isDefault || model.isWorking)
                        .accessibilityIdentifier("switch.tray.account.\(account.id)")
                        .accessibilityValue(isDefault ? "Default" : "Make default")
                    }
                }
                .padding(.horizontal, TrayPopoverLayout.horizontalInset)

                if model.accounts.contains(where: { $0.identity.providerID == .codex }) {
                    Button("Refresh Usage") {
                        Task {
                            for account in model.accounts where account.identity.providerID == .codex {
                                await model.loadUsage(account.id)
                            }
                        }
                    }
                    .controlSize(.small)
                    .disabled(model.isWorking)
                    .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                    .padding(.vertical, 8)
                }
            }
        }
        .task { await model.load() }
        .alert("Switch needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct CloudSyncTrayView: View {
    @State private var manager = RcloneJobManager.shared
    var showsHeader = true

    private var jobs: [TransferJob] {
        TrayPopoverLayout.visibleTransferJobs(manager.jobs)
    }

    private var activeJobs: [TransferJob] { jobs.filter { $0.state.isActive } }
    private var recentJobs: [TransferJob] { jobs.filter { $0.state.isTerminal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader { TrayToolHeader(tab: .cloudSync) }
            if !manager.daemonIsHealthy {
                HStack {
                    Text("The engine is not responding.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    TrayQuietActionButton(title: "Retry", symbol: "arrow.clockwise") {
                        Task { await manager.start() }
                    }
                }
                .padding(TrayPopoverLayout.horizontalInset)
                .background(Color.orange.opacity(0.08))
            }
            if jobs.isEmpty {
                EmptyStateView(icon: "cloud", message: "No transfers yet")
                    .frame(height: 96)
            } else {
                jobSection("Active", jobs: activeJobs)
                jobSection("Recent", jobs: recentJobs)
            }
        }
    }

    @ViewBuilder
    private func jobSection(_ title: String, jobs: [TransferJob]) -> some View {
        if !jobs.isEmpty {
            Text(title.uppercased())
                .utilitySectionHeader()
                .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                .padding(.top, 5)
            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                if index > 0 {
                    QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
                }
                TrayTransferRow(job: job)
                    .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                    .padding(.vertical, 8)
            }
        }
    }
}

private struct TrayTransferRow: View {
    let job: TransferJob
    @State private var manager = RcloneJobManager.shared
    @State private var showsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button {
                    manager.setExpanded(!job.isExpanded, for: job)
                } label: {
                    Image(systemName: job.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 4))
                .accessibilityLabel(job.isExpanded ? "Hide transfer files" : "Show transfer files")
                Image(systemName: job.operation.icon).font(.system(size: 10)).foregroundStyle(.secondary)
                Text("\(job.sourceDisplay) → \(job.destinationDisplay)")
                    .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if job.state == .failed, job.errorMessage?.isEmpty == false {
                    Button { showsError.toggle() } label: { stateBadge }
                        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 8))
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
                trayProgress(job.progressFraction, tint: stateColor)
                HStack(spacing: 6) {
                    Text("\(RcloneFormat.bytes(job.displayBytes)) of \(RcloneFormat.bytes(job.effectiveTotalBytes))")
                    if job.effectiveTotalFiles > 0 {
                        Text("· \(job.displayFiles) of \(job.effectiveTotalFiles) files")
                    }
                    Spacer(minLength: 4)
                    if job.stats.speed > 0 {
                        Text(RcloneFormat.speed(job.stats.speed))
                    }
                    if job.displayEta != nil {
                        Text("ETA \(RcloneFormat.eta(job.displayEta))")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            if showsError, let error = job.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.red.opacity(0.86))
                    .lineLimit(2)
            }

            if job.isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    if job.stats.transferring.isEmpty {
                        Text(job.state.isTerminal ? "No in-flight files" : "Waiting for file activity")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(job.stats.transferring.prefix(4))) { file in
                            TrayTransferFileRow(file: file)
                        }
                        if job.stats.transferring.count > 4 {
                            Text("\(job.stats.transferring.count - 4) more in-flight files")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.leading, 30)
            }
        }
    }

    private var stateBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: job.state.icon)
            Text(job.state.displayName)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(stateColor)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(stateColor.opacity(0.08), in: Capsule())
    }

    private var stateColor: Color {
        switch job.state {
        case .running: Color.blue.opacity(0.78)
        case .retrying, .paused: Color.orange.opacity(0.80)
        case .completed: Color.green.opacity(0.76)
        case .failed: Color.red.opacity(0.80)
        case .queued, .cancelled: Color.secondary
        }
    }

    private func trayProgress(_ fraction: Double, tint: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: 4)
    }

    private func transferButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).frame(width: 24, height: 24)
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct TrayTransferFileRow: View {
    let file: FileProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(file.name).font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(file.percentage)%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule().fill(Color.blue.opacity(0.58))
                        .frame(width: max(0, min(1, file.fraction)) * geometry.size.width)
                }
            }
            .frame(height: 3)
            HStack {
                Text("\(RcloneFormat.bytes(file.bytes)) of \(RcloneFormat.bytes(file.size))")
                Spacer()
                if file.speed > 0 { Text(RcloneFormat.speed(file.speed)) }
                if file.eta != nil { Text("ETA \(RcloneFormat.eta(file.eta))") }
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }
}

private struct SystemCareTrayView: View {
    @State private var manager = SystemCareManager.shared
    @State private var expandedCategories = Set<SystemCareCategoryID>()
    @State private var confirmTrash = false
    @State private var startedScan = false

    private var totalSize: Int64 {
        manager.cleanupCandidates.reduce(0) { $0 + $1.size }
    }

    private var categoryTotals: [(category: SystemCareCategoryID, size: Int64)] {
        SystemCareCategoryID.allCases.compactMap { category in
            let size = manager.cleanupCandidates.lazy
                .filter { $0.category == category }
                .reduce(0) { $0 + $1.size }
            return size > 0 ? (category, size) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrayToolHeader(tab: .systemCare)
            HStack(spacing: 6) {
                TrayQuietActionButton(
                    title: manager.hasCleanupScan ? "Analyze Again" : "Analyze",
                    symbol: "magnifyingglass",
                    disabled: manager.isWorking
                ) {
                    startedScan = true
                    manager.scanCleanup(categories: Set(SystemCareCategoryID.allCases))
                }
                TrayQuietActionButton(
                    title: "Clear Scan",
                    symbol: "xmark.circle",
                    disabled: !manager.hasCleanupScan || manager.isWorking
                ) {
                    manager.clearCleanupScan()
                    expandedCategories.removeAll()
                }
                Spacer(minLength: 0)
                if manager.isWorking {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, TrayPopoverLayout.horizontalInset)

            if manager.isWorking {
                Text(manager.progressMessage ?? "Analyzing cleanup locations…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TrayPopoverLayout.horizontalInset)
            }
            if let error = manager.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red.opacity(0.86))
                    .padding(.horizontal, TrayPopoverLayout.horizontalInset)
            }

            if !manager.hasCleanupScan {
                EmptyStateView(icon: "internaldrive", message: "Analyze cleanup locations")
                    .frame(maxWidth: .infinity, minHeight: 108)
            } else if manager.cleanupCandidates.isEmpty {
                EmptyStateView(icon: "checkmark.circle", message: "Nothing reclaimable in the saved scan")
                    .frame(maxWidth: .infinity, minHeight: 108)
            } else {
                cleanupSummary
                selectionBar
                ForEach(SystemCareCategoryID.allCases) { category in
                    categorySection(category)
                }
            }
        }
        .padding(.bottom, 10)
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
    }

    private var cleanupSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.07), lineWidth: 7)
                ForEach(Array(categoryTotals.enumerated()), id: \.element.category) { index, item in
                    Circle()
                        .trim(from: categoryStart(at: index), to: categoryEnd(at: index))
                        .stroke(categoryColor(item.category), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: "internaldrive")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(Self.bytes(totalSize)).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                    Spacer()
                    Text("\(manager.cleanupCandidates.count) items")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                ForEach(categoryTotals, id: \.category) { item in
                    HStack(spacing: 7) {
                        Text(item.category.title)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .frame(width: 96, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                Capsule().fill(categoryColor(item.category).opacity(0.72))
                                    .frame(width: geometry.size.width * CGFloat(Double(item.size) / Double(max(totalSize, 1))))
                            }
                        }
                        .frame(height: 4)
                        Text(Self.bytes(item.size))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
    }

    private var selectionBar: some View {
        HStack(spacing: 6) {
            Button("Select All") {
                manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: true)
            }
            Button("Select None") {
                manager.setCandidates(Set(manager.cleanupCandidates.map(\.id)), selected: false)
            }
            Spacer()
            Text("\(manager.selectedCandidateIDs.count) · \(Self.bytes(manager.selectedSize))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            TrayQuietActionButton(
                title: "Move to Trash",
                symbol: "trash",
                disabled: manager.selectedCandidateIDs.isEmpty || manager.isWorking
            ) { confirmTrash = true }
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .font(.system(size: 9))
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
    }

    private func categorySection(_ category: SystemCareCategoryID) -> some View {
        let candidates = manager.cleanupCandidates.filter { $0.category == category }
        return Group {
            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Button {
                            if expandedCategories.contains(category) { expandedCategories.remove(category) }
                            else { expandedCategories.insert(category) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(expandedCategories.contains(category) ? 90 : 0))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
                        .accessibilityLabel(expandedCategories.contains(category) ? "Collapse \(category.title)" : "Expand \(category.title)")
                        Image(systemName: category.icon).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(category.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(candidates.count) · \(Self.bytes(candidates.reduce(0) { $0 + $1.size }))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Toggle("Select \(category.title)", isOn: Binding(
                            get: { candidates.allSatisfy { manager.selectedCandidateIDs.contains($0.id) } },
                            set: { manager.setCandidates(Set(candidates.map(\.id)), selected: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    if expandedCategories.contains(category) {
                        LazyVStack(spacing: 2) {
                            ForEach(candidates) { candidate in
                                Toggle(isOn: Binding(
                                    get: { manager.selectedCandidateIDs.contains(candidate.id) },
                                    set: { manager.setCandidate(candidate.id, selected: $0) }
                                )) {
                                    HStack(spacing: 6) {
                                        Text(candidate.name).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 4)
                                        Text(Self.bytes(candidate.size))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
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
                .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                .padding(.vertical, 3)
            }
        }
    }

    private func categoryStart(at index: Int) -> CGFloat {
        CGFloat(Double(categoryTotals.prefix(index).reduce(0) { $0 + $1.size }) / Double(max(totalSize, 1)))
    }

    private func categoryEnd(at index: Int) -> CGFloat {
        categoryStart(at: index) + CGFloat(Double(categoryTotals[index].size) / Double(max(totalSize, 1)))
    }

    private func categoryColor(_ category: SystemCareCategoryID) -> Color {
        switch category {
        case .caches: Color.blue
        case .logs: Color.teal
        case .installers: Color.orange
        case .developer: Color.purple
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

enum TaskManagerMenuLayout {
    static let width = OnePlusMenuMetrics.width
    static let minimumHeight: CGFloat = 220

    static func initialHomeHeight(profileCount: Int) -> CGFloat {
        profileCount == 0 ? 334 : 388 + CGFloat(profileCount - 1) * 115
    }

    static func preferredHeight(for page: SystemMonitorTrayPage, profileCount: Int) -> CGFloat {
        switch page {
        case .home:
            initialHomeHeight(profileCount: profileCount)
        case .cpu, .memory, .disk:
            392
        case .network, .battery:
            363
        case .gpu:
            334
        case .sensors:
            311
        case .processes:
            407
        }
    }

    static func initialHeight(
        profileCount: Int,
        defaults: UserDefaults = .standard
    ) -> CGFloat {
        let remembersPage = defaults.object(forKey: "systemMonitor.rememberTrayPage") == nil
            || defaults.bool(forKey: "systemMonitor.rememberTrayPage")
        let savedPage = defaults.string(forKey: "systemMonitor.trayPage")
            .flatMap(SystemMonitorTrayPage.init(rawValue:)) ?? .home
        return preferredHeight(for: remembersPage ? savedPage : .home, profileCount: profileCount)
    }
}

private struct TaskManagerMenuMeasuredHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SystemMonitorMenuPopoverView: View {
    private let loadsRemoteProfiles: Bool
    private let onPreferredHeight: (CGFloat) -> Void
    @State private var remoteProfiles: [SystemMonitorRemoteProfile]
    @State private var preferredHeight: CGFloat

    init(
        remoteProfiles: [SystemMonitorRemoteProfile]? = nil,
        onPreferredHeight: @escaping (CGFloat) -> Void = { _ in }
    ) {
        let profiles = remoteProfiles ?? []
        loadsRemoteProfiles = remoteProfiles == nil
        self.onPreferredHeight = onPreferredHeight
        _remoteProfiles = State(initialValue: profiles)
        _preferredHeight = State(initialValue: TaskManagerMenuLayout.initialHomeHeight(
            profileCount: profiles.count
        ))
    }

    var body: some View {
        SystemMonitorTrayView(remoteProfiles: remoteProfiles) { height in
            guard abs(preferredHeight - height) > 0.5 else { return }
            preferredHeight = height
            onPreferredHeight(height)
        }
        .frame(width: TaskManagerMenuLayout.width)
        .utilityMotionPolicy()
        .task {
            guard loadsRemoteProfiles else { return }
            let profiles = await Task.detached(priority: .userInitiated) {
                SystemMonitorRemoteProfiles.load()
            }.value
            guard !Task.isCancelled else { return }
            remoteProfiles = profiles
        }
    }
}

struct SystemMonitorTrayView: View {
    @AppStorage("systemMonitor.trayPage") private var pageID = SystemMonitorTrayPage.home.rawValue
    @AppStorage("systemMonitor.rememberTrayPage") private var rememberPage = true
    private let remoteProfiles: [SystemMonitorRemoteProfile]
    private let onPreferredHeight: (CGFloat) -> Void

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
                case .processes: TaskManagerMenuProcessesView()
                default: detailPage
                }
            }
            .onAppear {
                service.startDetailed(owner: "tray", metrics: page.metrics)
            }
            .onDisappear {
                service.stopDetailed(owner: "tray")
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TaskManagerMenuMeasuredHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(TaskManagerMenuMeasuredHeightKey.self) { height in
            guard height > 0 else { return }
            onPreferredHeight(height)
        }
        .onAppear {
            if !rememberPage { pageID = SystemMonitorTrayPage.home.rawValue }
            reportPreferredHeight(for: rememberPage ? page : .home)
        }
        .onChange(of: pageID) { _, _ in
            service.updateDetailed(owner: "tray", metrics: page.metrics)
            reportPreferredHeight(for: page)
        }
        .onChange(of: remoteProfiles.count) { _, _ in
            reportPreferredHeight(for: page)
        }
    }

    private func reportPreferredHeight(for page: SystemMonitorTrayPage) {
        onPreferredHeight(TaskManagerMenuLayout.preferredHeight(
            for: page,
            profileCount: remoteProfiles.count
        ))
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
            detailRows
            if page == .sensors {
                FanControlView(owner: "system-monitor-tray-sensors", compact: true)
                    .frame(height: 30)
            }
        }
    }

    private var detailHero: some View {
        let values: [Double] = switch page {
        case .cpu: history(.cpu).compactMap(\.cpuUsage)
        case .gpu: history(.gpu).compactMap(\.gpuUsage)
        case .memory: history(.memory).compactMap(\.memoryUsage)
        case .network: history(.network).compactMap(\.networkDownload)
        case .disk: history(.disk).compactMap(\.diskUsage)
        case .battery: history(.battery).compactMap { $0.batteryPercent.map(Double.init) }
        case .sensors: history(.thermal).compactMap { Self.thermalLevel($0.thermalState) }
        case .home, .processes: []
        }
        let value: String = switch page {
        case .cpu: percent(sample?.cpuUsage)
        case .gpu: percent(sample?.gpuUsage)
        case .memory: percent(sample?.memoryUsage)
        case .network: sample?.networkDownload.map(Self.rate) ?? "—"
        case .disk: percent(sample?.diskUsage)
        case .battery: sample?.batteryPercent.map { "\($0)%" } ?? "—"
        case .sensors: sample?.thermalState ?? "—"
        case .home, .processes: "—"
        }
        return TaskManagerPanel(textured: true) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    metricIcon(page)
                    Text(page.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(TaskManagerTheme.secondary)
                    Spacer()
                }
                panelMetricValue(value)
                TaskManagerHistoryChart(
                    values: values,
                    secondary: page == .network ? history(.network).compactMap(\.networkUpload) : [],
                    range: chartRange(values),
                    unit: page == .network ? "/s" : "%",
                    compact: true,
                    stepped: page == .sensors
                )
                .frame(height: 92)
            }
            .padding(12)
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
                ("Used", sample?.memoryUsed.map(Self.bytes) ?? "—"),
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
        return TaskManagerPanel {
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack {
                        Text(rows[index].0).foregroundStyle(TaskManagerTheme.secondary)
                        Spacer(minLength: 8)
                        Text(rows[index].1).monospacedDigit()
                    }
                    .font(.system(size: 10))
                    .frame(minHeight: 28)
                    if index < rows.count - 1 {
                        Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 3)
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
        .focusEffectDisabled()
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
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(profile.platform.rawValue)
                    Spacer()
                    Text("—").monospacedDigit()
                }
                .onePlusText(.caption)
                Capsule().fill(OnePlusColor.line).frame(height: 3)
                Text("Connect on demand").onePlusText(.caption)
            }
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

private struct TaskManagerMenuProcessesView: View {
    @State private var sampler = SystemMonitorProcessSampler()
    @State private var processes: [SystemMonitorProcess] = []
    @State private var rows: [SystemMonitorProcessHierarchy.Row] = []
    @State private var processCount = 0
    @State private var generation = 0
    @State private var search = ""

    private var request: TaskManagerMenuProcessRequest {
        TaskManagerMenuProcessRequest(generation: generation, search: search)
    }

    var body: some View {
        VStack(spacing: 8) {
            TaskManagerSearchField(prompt: "Find a process…", text: $search, width: 336)

            TaskManagerPanel {
                VStack(spacing: 0) {
                    HStack {
                        Text("Process")
                        Spacer()
                        Text("CPU").frame(width: 52, alignment: .trailing)
                        Text("Memory").frame(width: 72, alignment: .trailing)
                    }
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(TaskManagerTheme.muted)
                    .textCase(.uppercase)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(TaskManagerTheme.desktop.opacity(0.12))

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                Button { openProcesses() } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "app")
                                            .font(.system(size: 8))
                                            .frame(width: 16, height: 16)
                                        Text(row.process.name)
                                            .font(.system(size: 9.5))
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(row.cpuText)
                                            .frame(width: 52, alignment: .trailing)
                                        Text(row.memoryText)
                                            .frame(width: 72, alignment: .trailing)
                                    }
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(TaskManagerTheme.secondary)
                                    .padding(.horizontal, 9)
                                    .frame(height: 28)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                                Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                            }
                        }
                    }
                    .frame(height: 232)
                    .thinScrollIndicators()

                    Button("All \(processCount) processes  →") { openProcesses() }
                        .font(.system(size: 8))
                        .foregroundStyle(TaskManagerTheme.muted)
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .trailing)
                        .padding(.horizontal, 9)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                processes = await sampler.sample()
                processCount = processes.count
                generation &+= 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task(id: request) { await prepareRows(request) }
    }

    private func prepareRows(_ request: TaskManagerMenuProcessRequest) async {
        let result = await SystemMonitorProcessRows.prepareOffMain(
            processes,
            search: request.search,
            hierarchy: false,
            column: .cpu,
            descending: true,
            limit: 9
        )
        guard !Task.isCancelled, self.request == request else { return }
        rows = result.rows
    }

    private func openProcesses() {
        UserDefaults.standard.set("processes", forKey: "systemMonitor.windowPage")
        ToolActionRouter.shared.open(toolID: "system-monitor")
    }
}

private struct NetToysTrayView: View {
    @State private var model = NetToysHistoryViewModel()
    @State private var configuration = NetToysConfigurationStore.load()
    @State private var errorMessage: String?
    @AppStorage("tray.nettoys.anchor.expanded") private var anchorExpanded = false
    @AppStorage("tray.nettoys.wifi.expanded") private var wifiExpanded = false
    @AppStorage("tray.nettoys.history.expanded") private var historyExpanded = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .netToys)
            VStack(spacing: 0) {
                statusRow(
                    title: model.helperStatus?.network?.displayName ?? "Network unavailable",
                    detail: helperDetail,
                    symbol: "network"
                )
                QuietDivider()
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
                    if recentAnchors.isEmpty {
                        emptyActivity("No anchors to show")
                    } else {
                        ForEach(recentAnchors) { anchor in
                            anchorRow(anchor)
                        }
                    }
                    openPageButton("Open all anchors", page: .anchor)
                }
                QuietDivider()
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
                                symbol: model.helperStatus?.network?.ssid == ssid ? "wifi" : "line.3.horizontal",
                                title: ssid,
                                detail: model.helperStatus?.network?.ssid == ssid ? "Connected" : "Priority \(index + 1)"
                            )
                        }
                    }
                    openPageButton("Open Wi-Fi Priority", page: .wifiPriority)
                }
                QuietDivider()
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
                    if recentIssues.isEmpty {
                        emptyActivity("No recent network issues")
                    } else {
                        ForEach(Array(recentIssues.enumerated()), id: \.offset) { _, event in
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
            .padding(.horizontal, TrayPopoverLayout.horizontalInset)
            .padding(.top, 4)
            .padding(.bottom, 8)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.red.opacity(0.86))
                    .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            configuration = NetToysConfigurationStore.load()
            Task { await model.refresh() }
        }
    }

    private var helperDetail: String {
        guard let status = model.helperStatus else { return "Background helper is not reporting" }
        return "Updated \(status.heartbeat.formatted(date: .omitted, time: .shortened))"
    }

    private var recentAnchors: [SSHAnchorConfiguration] {
        TrayPopoverLayout.recentAnchors(
            configuration.anchors,
            statuses: model.helperStatus?.anchors ?? []
        )
    }

    private var recentIssues: [NetworkTransitionEvent] {
        TrayPopoverLayout.recentNetworkIssues(model.history.events)
    }

    private func statusRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
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
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { isExpanded.wrappedValue.toggle() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 11, weight: .medium))
                            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    }
                    .padding(.horizontal, TrayPopoverLayout.netToysDisclosureHorizontalPadding)
                    .padding(.vertical, TrayPopoverLayout.netToysDisclosureVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
                .accessibilityLabel("\(isExpanded.wrappedValue ? "Hide" : "Show") \(title) activity")
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(disabled)
            }
            .padding(.vertical, 1)

            if isExpanded.wrappedValue {
                VStack(spacing: 0) { content() }
                    .padding(.leading, 27)
                    .padding(.bottom, 7)
            }
        }
        .utilityAnimation(value: isExpanded.wrappedValue)
    }

    private func anchorRow(_ anchor: SSHAnchorConfiguration) -> some View {
        let status = model.helperStatus?.anchors.first { $0.anchorID == anchor.id }
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
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
    }

    private func emptyActivity(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
    }

    private func openPageButton(_ title: String, page: NetToysPage) -> some View {
        Button { open(page) } label: {
            Label(title, systemImage: "arrow.up.forward.square")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 4))
        .padding(.top, 3)
    }

    private func open(_ page: NetToysPage) {
        openWindow(id: "nettoys")
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
