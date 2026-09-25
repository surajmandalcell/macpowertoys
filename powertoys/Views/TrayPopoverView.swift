//
//  TrayPopoverView.swift
//  powertoys
//

import AIManagerCore
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
        case .systemMonitor: "System Monitor"
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
}

enum TrayPopoverLayout {
    static let width: CGFloat = 360
    static let horizontalInset: CGFloat = 12
    static let tabHeight: CGFloat = 24
    static let tabSpacing: CGFloat = 3
    static let netToysDisclosureHorizontalPadding: CGFloat = 6
    static let netToysDisclosureVerticalPadding: CGFloat = 6
    static let minimumBodyHeight: CGFloat = 54
    static let topChromeHeight: CGFloat = 38
    static let heightFraction: CGFloat = 0.7
    static let transitionDuration = UtilityMotion.standardDuration
    static let homeToolIDs = ["color-picker", "text-extractor", "awake", "ruler"]
    static let defaultComplexTabs: [TrayTab] = [
        .cloudSync, .inputDevices, .systemCare, .systemMonitor, .netToys,
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
    @Environment(\.colorSchemeContrast) private var contrast
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
        VStack(spacing: 0) {
            topChrome
            TrayMeasuredScroll {
                tabContent
                    .id(selectedTabID)
                    .transition(.opacity)
            }
        }
        .frame(width: TrayPopoverLayout.width)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .onAppear(perform: normalizeSelection)
        .onChange(of: storedTabOrder) { normalizeSelection() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            configurationRevision += 1
            normalizeSelection()
        }
    }

    private var topChrome: some View {
        HStack(spacing: 0) {
            TrayTabStrip(
                tabs: tabs,
                selected: Binding(get: { selectedTab }, set: { select($0) }),
                reorder: reorder
            )
            .padding(3)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.18 : 0.08))
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                TrayChromeButton(title: "Open MacPowerToys", systemImage: "arrow.up.forward.square", visibleTitle: "Open App") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                TrayChromeButton(title: "Open Settings", systemImage: "gearshape") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .openToolSettings, object: "home")
                    }
                }
                TrayChromeButton(title: "Quit MacPowerToys", systemImage: "power") {
                    NSApp.terminate(nil)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 4)
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
            SystemMonitorTrayView()
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

struct TrayMeasuredScroll<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var contentHeight = TrayPopoverLayout.minimumBodyHeight

    private var maximumHeight: CGFloat {
        TrayPopoverLayout.maximumBodyHeight(screenHeight: NSScreen.main?.visibleFrame.height ?? 900)
    }

    var body: some View {
        ScrollView {
            content
                .frame(width: TrayPopoverLayout.width, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .thinScrollIndicators()
        .frame(height: min(max(contentHeight, TrayPopoverLayout.minimumBodyHeight), maximumHeight))
    }
}

private struct TrayTabStrip: View {
    let tabs: [TrayTab]
    @Binding var selected: TrayTab
    let reorder: (TrayTab, TrayTab) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabRow.fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal) {
                tabRow
            }
            .thinScrollIndicators()
            .scrollClipDisabled()
        }
        .frame(height: TrayPopoverLayout.tabHeight)
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
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TrayTabIcon(tab: tab, selected: selected, size: 12)
                .foregroundStyle(Color.primary.opacity(selected || hovering ? 1 : 0.58))
                .frame(width: TrayPopoverLayout.tabHeight, height: TrayPopoverLayout.tabHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .background(Color.primary.opacity(selected ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(tab.title)
        .onHover { hovering = $0 }
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

private struct TrayChromeButton: View {
    let title: String
    let systemImage: String
    var visibleTitle: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let visibleTitle {
                    Text(visibleTitle)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .frame(width: 24)
                }
            }
            .foregroundStyle(Color.primary.opacity(hovering ? 1 : 0.62))
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .accessibilityLabel(title)
        .help(title)
        .onHover { hovering = $0 }
    }
}

private struct TrayHomeView: View {
    let toolIDs: [String]

    var body: some View {
        VStack(spacing: 0) {
            if toolIDs.isEmpty && !SettingsManager.shared.isToolEnabled("system-monitor") {
                EmptyStateView(icon: "switch.2", message: "No Home tools are in the combined menu")
                    .frame(height: 120)
            } else {
                if toolIDs.contains("color-picker") || toolIDs.contains("text-extractor") || toolIDs.contains("ruler") {
                    HStack(spacing: 6) {
                        if toolIDs.contains("color-picker") {
                            TrayHomeActionButton(title: "Pick Color", symbol: "eyedropper") {
                                ToolActionRouter.shared.execute(ToolActionRequest(action: .colorPickerPick))
                            }
                        }
                        if toolIDs.contains("text-extractor") {
                            TrayHomeActionButton(title: "Extract Text", symbol: "text.viewfinder") {
                                ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorCapture))
                            }
                        }
                        if toolIDs.contains("ruler") {
                            TrayHomeActionButton(title: "Ruler", symbol: "ruler", iconRotation: -45) {
                                ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerOpen))
                            }
                        }
                    }
                    .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                    .padding(.top, 8)
                    .padding(.bottom, toolIDs.contains("awake") ? 4 : 8)
                }
                if toolIDs.contains("awake") {
                    AwakeTrayRow()
                }
                if SettingsManager.shared.isToolEnabled("system-monitor") {
                    FanControlView(owner: "tray-home", compact: true)
                        .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct TrayHomeActionButton: View {
    let title: String
    let symbol: String
    var iconRotation = 0.0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .rotationEffect(.degrees(iconRotation))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 12, weight: .medium))
                Text(title).lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.88))
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Awake", systemImage: "moon.zzz")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.84))
                Spacer(minLength: 8)
                Picker("Awake duration", selection: quickMode) {
                    Text("Off").tag(AwakeQuickMode?.some(.off))
                    Text("30m").tag(AwakeQuickMode?.some(.thirtyMinutes))
                    Text("1h").tag(AwakeQuickMode?.some(.oneHour))
                    Text("∞").accessibilityLabel("Indefinite").tag(AwakeQuickMode?.some(.indefinite))
                }
                .pickerStyle(.segmented)
                .tint(Color.primary.opacity(0.18))
                .labelsHidden()
                .frame(width: 204)
            }
            if let assertionError = service.assertionError {
                Text(assertionError)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red)
                    .lineLimit(2)
                    .padding(.leading, 32)
            }
        }
        .padding(.leading, TrayPopoverLayout.horizontalInset + 4)
        .padding(.trailing, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 8)
    }
}

private struct TrayToolLink: View {
    let tab: TrayTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button {
            ToolActionRouter.shared.open(toolID: tab.rawValue)
        } label: {
            HStack(spacing: 7) {
                TrayTabIcon(tab: tab, selected: false, size: 12).frame(width: 18)
                Text(tab.title).font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(x: hovering && !reduceMotion ? 1 : 0, y: hovering && !reduceMotion ? -1 : 0)
            }
            .foregroundStyle(Color.primary.opacity(hovering ? 1 : 0.84))
            .padding(.horizontal, 6)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .help("Open \(tab.title)")
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.86))
                .padding(.horizontal, 9)
                .frame(minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

private struct TrayToolHeader: View {
    let tab: TrayTab

    var body: some View {
        TrayToolLink(tab: tab)
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.top, 5)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SwitchTrayView: View {
    @State private var model: SwitchWorkspaceModel

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
                        Button {
                            Task { await model.makeDefault(account.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: account.identity.providerID == .codex
                                      ? "chevron.left.forwardslash.chevron.right" : "bolt.fill")
                                    .font(.system(size: 13))
                                    .frame(width: 22)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.identity.email ?? account.identity.accountID ?? "Saved account")
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(account.identity.providerID == .codex ? "Codex CLI" : "Grok Build")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if let percent = model.usage[account.id]?.rateLimits?.defaultBucket?.primary?.usedPercent {
                                    Text("\(percent)% used")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
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

    private var jobs: [TransferJob] {
        TrayPopoverLayout.visibleTransferJobs(manager.jobs)
    }

    private var activeJobs: [TransferJob] { jobs.filter { $0.state.isActive } }
    private var recentJobs: [TransferJob] { jobs.filter { $0.state.isTerminal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .cloudSync)
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
    case home, cpu, gpu, memory, network, disk, battery, sensors

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "RAM"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .sensors: "Sensors"
        }
    }
    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .sensors: "thermometer.medium"
        }
    }
    var metrics: Set<SystemMonitorMenuMetric> {
        switch self {
        case .home: Set(SystemMonitorMenuMetric.allCases)
        case .cpu: [.cpu, .thermal]
        case .gpu: [.gpu]
        case .memory: [.memory]
        case .network: [.network]
        case .disk: [.disk]
        case .battery: [.battery]
        case .sensors: [.thermal]
        }
    }
}

struct SystemMonitorTrayView: View {
    @State private var service = SystemMonitorService.shared
    @AppStorage("systemMonitor.trayPage") private var pageID = SystemMonitorTrayPage.home.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var sample: SystemMonitorSample? { service.snapshot }
    private var page: SystemMonitorTrayPage { SystemMonitorTrayPage(rawValue: pageID) ?? .home }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .systemMonitor)
            HStack(spacing: 4) {
                ForEach(SystemMonitorTrayPage.allCases) { item in
                    Button {
                        pageID = item.rawValue
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(page == item ? Color.primary : Color.secondary)
                    .background(page == item ? Color.primary.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .help(item.title)
                    .accessibilityLabel("Monitor \(item.title)")
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                    .accessibilityIdentifier("system-monitor.tray.\(item.rawValue)")
                }
            }
            .padding(.horizontal, TrayPopoverLayout.horizontalInset)
            .padding(.bottom, 8)

            if page == .home { homePage } else { detailPage }
            if page == .sensors {
                FanControlView(owner: "system-monitor-tray", compact: true)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 18)
        .onAppear { service.startDetailed(owner: "tray", metrics: page.metrics) }
        .onChange(of: pageID) { _, _ in service.updateDetailed(owner: "tray", metrics: page.metrics) }
        .onDisappear { service.stopDetailed(owner: "tray") }
    }

    private var homePage: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                summary(.cpu, metric(
                    "CPU", symbol: "cpu", value: percent(sample?.cpuUsage, metric: .cpu),
                    detail: "All cores", level: sample?.cpuUsage,
                    values: service.history.compactMap(\.cpuUsage), surfaceTint: SystemMonitorPalette.teal
                ))
                summary(.gpu, metric(
                    "GPU", symbol: "rectangle.3.group", value: percent(sample?.gpuUsage, metric: .gpu),
                    detail: "Graphics utilization", level: sample?.gpuUsage,
                    values: service.history.compactMap(\.gpuUsage), surfaceTint: SystemMonitorPalette.blue
                ))
                summary(.memory, metric(
                    "RAM", symbol: "memorychip", value: percent(sample?.memoryUsage, metric: .memory),
                    detail: memoryDetail, level: sample?.memoryUsage,
                    values: service.history.compactMap(\.memoryUsage), surfaceTint: SystemMonitorPalette.coral
                ))
                summary(.disk, metric(
                    "Disk", symbol: "internaldrive", value: percent(sample?.diskUsage, metric: .disk),
                    detail: diskDetail, level: sample?.diskUsage,
                    values: service.history.compactMap(\.diskUsage), surfaceTint: SystemMonitorPalette.orange
                ))
                summary(.network, metric(
                    "Network", symbol: "network", value: sample?.networkDownload.map(Self.rate) ?? "...",
                    detail: "Up \(sample?.networkUpload.map(Self.rate) ?? "...")", level: nil,
                    values: service.history.compactMap { point in
                        guard let down = point.networkDownload, let up = point.networkUpload else { return nil }
                        return max(down, up)
                    }, tint: SystemMonitorPalette.cyan
                ))
                summary(.battery, metric(
                    "Battery", symbol: "battery.75percent",
                    value: sample?.batteryPercent.map { "\($0)%" } ?? "Unavailable",
                    detail: batteryDetail,
                    level: sample?.batteryPercent.map(Double.init),
                    values: service.history.compactMap { $0.batteryPercent.map(Double.init) },
                    tint: batteryTint, surfaceTint: SystemMonitorPalette.gold
                ))
                summary(.sensors, metric(
                    "Thermal", symbol: "thermometer.medium", value: sample?.thermalState ?? "Unavailable",
                    detail: "System pressure", level: thermalLevel,
                    values: service.history.compactMap { Self.thermalLevel($0.thermalState) },
                    tint: thermalTint, surfaceTint: SystemMonitorPalette.green
                ))
                summary(.cpu, metric(
                    "Load · 1 min", symbol: "chart.bar", value: loadValue,
                    detail: "Average CPU demand", level: loadLevel,
                    values: service.history.compactMap { $0.loadAverage.map { $0.0 } },
                    surfaceTint: SystemMonitorPalette.blue
                ))
                .help("Load is the average number of processes running or ready for a CPU. Compare it with \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs. It is not a percent.")
            }
            .padding(.horizontal, TrayPopoverLayout.horizontalInset)
            FanControlView(owner: "system-monitor-tray", compact: true)
                .padding(.top, 8)
        }
    }

    private func summary<Content: View>(_ destination: SystemMonitorTrayPage, _ content: Content) -> some View {
        Button { pageID = destination.rawValue } label: { content }
            .buttonStyle(.plain)
            .accessibilityHint("Show \(destination.title) details")
    }

    @ViewBuilder
    private var detailPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch page {
            case .cpu:
                detailHero("CPU", symbol: "cpu", value: percent(sample?.cpuUsage, metric: .cpu),
                           detail: "Usage across all cores", level: sample?.cpuUsage,
                           values: service.history.compactMap(\.cpuUsage), tint: SystemMonitorPalette.teal)
                detailRows([
                    ("Load · 1 min", loadValue),
                    ("Load · 5 min", sample?.loadAverage.map { Self.decimal($0.1) } ?? "..."),
                    ("Load · 15 min", sample?.loadAverage.map { Self.decimal($0.2) } ?? "..."),
                    ("Logical CPUs", "\(ProcessInfo.processInfo.activeProcessorCount)"),
                    ("Thermal pressure", sample?.thermalState ?? "Unavailable"),
                ])
                .help("Load is the average number of processes running or ready for a CPU. It is not a percentage.")
            case .gpu:
                detailHero("GPU", symbol: "rectangle.3.group", value: percent(sample?.gpuUsage, metric: .gpu),
                           detail: "Graphics utilization", level: sample?.gpuUsage,
                           values: service.history.compactMap(\.gpuUsage), tint: SystemMonitorPalette.blue)
            case .memory:
                detailHero("RAM", symbol: "memorychip", value: percent(sample?.memoryUsage, metric: .memory),
                           detail: "Physical memory in use", level: sample?.memoryUsage,
                           values: service.history.compactMap(\.memoryUsage), tint: SystemMonitorPalette.coral)
                detailRows([
                    ("Used", sample?.memoryUsed.map(Self.bytes) ?? "..."),
                    ("Available", memoryAvailable),
                    ("Total", sample?.memoryTotal.map(Self.bytes) ?? "..."),
                ])
            case .network:
                detailHero("Network", symbol: "network",
                           value: sample?.networkDownload.map(Self.rate) ?? "...",
                           detail: "Download · all active interfaces", level: nil,
                           values: service.history.compactMap(\.networkDownload), tint: SystemMonitorPalette.cyan)
                detailRows([
                    ("Download", sample?.networkDownload.map(Self.rate) ?? "..."),
                    ("Upload", sample?.networkUpload.map(Self.rate) ?? "..."),
                ])
            case .disk:
                detailHero("Disk", symbol: "internaldrive", value: percent(sample?.diskUsage, metric: .disk),
                           detail: "Startup volume used", level: sample?.diskUsage,
                           values: service.history.compactMap(\.diskUsage), tint: SystemMonitorPalette.orange)
                detailRows([
                    ("Used", sample?.diskUsed.map(Self.bytes) ?? "..."),
                    ("Free", diskAvailable),
                    ("Capacity", sample?.diskTotal.map(Self.bytes) ?? "..."),
                ])
            case .battery:
                detailHero("Battery", symbol: "battery.75percent",
                           value: sample?.batteryPercent.map { "\($0)%" } ?? "Unavailable",
                           detail: batteryDetail, level: sample?.batteryPercent.map(Double.init),
                           values: service.history.compactMap { $0.batteryPercent.map(Double.init) },
                           tint: SystemMonitorPalette.gold)
                detailRows([("Status", batteryDetail)])
            case .sensors:
                detailHero("Sensors", symbol: "thermometer.medium",
                           value: sample?.thermalState ?? "Unavailable", detail: "System thermal pressure",
                           level: nil,
                           values: service.history.compactMap { Self.thermalLevel($0.thermalState) },
                           tint: SystemMonitorPalette.green)
            case .home:
                EmptyView()
            }
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
    }

    private func detailHero(
        _ title: String, symbol: String, value: String, detail: String,
        level: Double?, values: [Double], tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let level {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.12), lineWidth: 5)
                        Circle().trim(from: 0, to: min(max(level / 100, 0), 1))
                            .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 43, height: 43)
                    .accessibilityHidden(true)
                }
            }
            .padding(14)
            Text("History")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 5)
            TrayMetricSparkline(values: values, color: tint)
                .frame(height: 56)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SystemMonitorPalette.gradient(tint), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.25)) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func detailRows(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Details")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.bottom, 5)
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text(rows[index].0).foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text(rows[index].1)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 11))
                .frame(minHeight: 24)
                if index < rows.count - 1 { QuietDivider() }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(
        _ title: String,
        symbol: String,
        value: String,
        detail: String,
        level: Double?,
        values: [Double],
        tint: Color? = nil,
        surfaceTint: Color? = nil
    ) -> some View {
        let color = tint ?? level.map(Self.usageTint) ?? .gray
        let surface = surfaceTint ?? color
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.caption2.weight(.medium))
                        .foregroundStyle(colorScheme == .dark ? color : .primary)
                    Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            Spacer(minLength: 0)
            TrayMetricSparkline(values: values, color: color)
                .frame(height: 10)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(SystemMonitorPalette.gradient(surface), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(surface.opacity(0.25))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func percent(_ value: Double?, metric: SystemMonitorMenuMetric) -> String {
        if let value { return "\(Int(value.rounded()))%" }
        return sample?.unavailableMetrics.contains(metric) == true ? "Unavailable" : "..."
    }

    private var memoryDetail: String {
        guard let used = sample?.memoryUsed, let total = sample?.memoryTotal else { return "Physical memory" }
        return "\(Self.bytes(used)) / \(Self.bytes(total))"
    }

    private var memoryAvailable: String {
        guard let used = sample?.memoryUsed, let total = sample?.memoryTotal else { return "..." }
        return Self.bytes(max(total - used, 0))
    }

    private var diskAvailable: String {
        guard let used = sample?.diskUsed, let total = sample?.diskTotal else { return "..." }
        return Self.bytes(max(total - used, 0))
    }

    private var batteryDetail: String {
        guard sample?.batteryPercent != nil else { return "No battery data" }
        return sample?.batteryCharging == true ? "Charging" : "On battery"
    }

    private var diskDetail: String {
        guard let used = sample?.diskUsed, let total = sample?.diskTotal else { return "Startup volume" }
        return "\(Self.bytes(max(total - used, 0))) free"
    }

    private var loadValue: String {
        sample?.loadAverage.map { $0.0.formatted(.number.precision(.fractionLength(2))) } ?? "..."
    }

    private var loadLevel: Double? {
        sample?.loadAverage.map { min($0.0 / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1)) * 100, 100) }
    }

    private var thermalLevel: Double? { Self.thermalLevel(sample?.thermalState) }

    private var thermalTint: Color {
        switch sample?.thermalState {
        case "Critical": .red
        case "Serious": .orange
        case "Fair": .blue
        default: .green
        }
    }

    private var batteryTint: Color {
        guard let percent = sample?.batteryPercent else { return .gray }
        if sample?.batteryCharging == true { return .green }
        if percent < 20 { return .red }
        if percent < 50 { return .orange }
        return .blue
    }

    nonisolated private static func usageTint(_ value: Double) -> Color {
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        if value >= 35 { return .blue }
        return .green
    }

    nonisolated private static func thermalLevel(_ state: String?) -> Double? {
        switch state {
        case "Nominal": 20
        case "Fair": 50
        case "Serious": 75
        case "Critical": 100
        default: nil
        }
    }

    nonisolated private static func rate(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 0)), countStyle: .file) + "/s"
    }

    nonisolated private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    nonisolated private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }
}

private struct TrayMetricSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            var guide = Path()
            guide.move(to: CGPoint(x: 0, y: size.height * 0.75))
            guide.addLine(to: CGPoint(x: size.width, y: size.height * 0.75))
            context.stroke(guide, with: .color(color.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            guard !values.isEmpty, let minimum = values.min(), let maximum = values.max() else { return }
            if values.count == 1 {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height * 0.5))
                line.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                context.stroke(line, with: .color(color.opacity(0.46)), lineWidth: 1)
                return
            }
            let range = max(maximum - minimum, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height - size.height * CGFloat((value - minimum) / range)
                )
            }
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: size.height))
            points.forEach { fill.addLine(to: $0) }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.16), color.opacity(0.015)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            var line = Path()
            line.addLines(points)
            context.stroke(line, with: .color(color.opacity(0.46)), lineWidth: 1)
        }
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
