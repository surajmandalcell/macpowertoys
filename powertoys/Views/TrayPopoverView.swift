//
//  TrayPopoverView.swift
//  powertoys
//

import SwiftUI

enum TrayTab: String, CaseIterable, Identifiable {
    case home
    case cloudSync = "rclone"
    case logs
    case inputDevices = "input-devices"
    case systemCare = "system-care"
    case systemMonitor = "system-monitor"
    case netToys = "nettoys"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .cloudSync: "Cloud Sync"
        case .logs: "Logs"
        case .inputDevices: "Input Devices"
        case .systemCare: "System Care"
        case .systemMonitor: "System Monitor"
        case .netToys: "NetToys"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .cloudSync: "arrow.up.arrow.down.circle"
        case .logs: "terminal"
        case .inputDevices: "computermouse"
        case .systemCare: "sparkles"
        case .systemMonitor: "chart.xyaxis.line"
        case .netToys: "network"
        }
    }

    var toolID: String? { self == .home ? nil : rawValue }
}

enum TrayPopoverLayout {
    static let width: CGFloat = 360
    static let horizontalInset: CGFloat = 12
    static let tabHeight: CGFloat = 32
    static let tabSpacing: CGFloat = 4
    static let minimumBodyHeight: CGFloat = 54
    static let topChromeHeight: CGFloat = 56
    static let heightFraction: CGFloat = 0.7
    static let transitionDuration = UtilityMotion.standardDuration
    static let homeToolIDs = ["color-picker", "text-extractor", "awake", "ruler"]
    static let defaultComplexTabs: [TrayTab] = [
        .cloudSync, .logs, .inputDevices, .systemCare, .systemMonitor, .netToys,
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
}

struct TrayPopoverView: View {
    @AppStorage("tray.selectedTab.v2") private var selectedTabID = TrayTab.home.rawValue
    @AppStorage("tray.tabOrder.v2") private var storedTabOrder = ""
    @Environment(\.colorScheme) private var colorScheme
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
            guard let toolID = tab.toolID, SettingsManager.shared.isToolEnabled(toolID) else {
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
            QuietDivider()
            TrayMeasuredScroll {
                tabContent
                    .id(selectedTabID)
                    .transition(.opacity)
            }
        }
        .frame(width: TrayPopoverLayout.width)
        .background {
            Color.black
                .opacity(colorScheme == .dark ? 0.18 : 0.035)
                .ignoresSafeArea()
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: storedTabOrder) { normalizeSelection() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            configurationRevision += 1
            normalizeSelection()
        }
    }

    private var topChrome: some View {
        HStack(spacing: 8) {
            TrayTabStrip(
                tabs: tabs,
                selected: Binding(get: { selectedTab }, set: { select($0) }),
                reorder: reorder
            )
            .padding(4)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.18 : 0.08))
            }

            TrayChromeButton(title: "Open MacPowerToys", systemImage: "gearshape") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            TrayChromeButton(title: "Quit MacPowerToys", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            TrayHomeView(toolIDs: homeToolIDs)
        case .cloudSync:
            CloudSyncTrayView()
        case .logs:
            LogsTrayView()
        case .inputDevices:
            VStack(spacing: 0) {
                TrayToolHeader(tab: .inputDevices, detail: "Mouse and trackpad scrolling")
                QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
                InputDevicesSettingsView(showsHeader: true, showsContainerScroll: false)
            }
        case .systemCare:
            SystemCareTrayView()
        case .systemMonitor:
            SystemMonitorTrayView()
        case .netToys:
            NetToysTrayView()
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

private struct TrayMeasuredScroll<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var contentHeight = TrayPopoverLayout.minimumBodyHeight

    private var maximumHeight: CGFloat {
        TrayPopoverLayout.maximumBodyHeight(screenHeight: NSScreen.main?.visibleFrame.height ?? 900)
    }

    var body: some View {
        ScrollView {
            content
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
        ScrollView(.horizontal) {
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
        .thinScrollIndicators()
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: TrayPopoverLayout.tabHeight)
    }
}

private struct TrayTabButton: View {
    let tab: TrayTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .symbolVariant(selected ? .fill : .none)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(Color.primary.opacity(selected || hovering ? 1 : 0.58))
                .frame(width: TrayPopoverLayout.tabHeight, height: TrayPopoverLayout.tabHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 7))
        .background(Color.primary.opacity(selected ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(tab.title)
        .onHover { hovering = $0 }
    }
}

private struct TrayChromeButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(hovering ? 1 : 0.62))
                .frame(width: 28, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 7))
        .accessibilityLabel(title)
        .help(title)
        .onHover { hovering = $0 }
    }
}

private struct TrayHomeView: View {
    let toolIDs: [String]

    var body: some View {
        VStack(spacing: 0) {
            if toolIDs.isEmpty {
                EmptyStateView(icon: "switch.2", message: "No Home tools are in the combined menu")
                    .frame(height: 120)
            } else {
                ForEach(Array(toolIDs.enumerated()), id: \.element) { index, toolID in
                    if index > 0 { QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset) }
                    homeRow(toolID)
                }
            }
        }
    }

    @ViewBuilder
    private func homeRow(_ toolID: String) -> some View {
        switch toolID {
        case "color-picker":
            TrayQuickRow(toolID: toolID, title: "Color Picker", symbol: "eyedropper") {
                TrayQuietActionButton(title: "Pick", symbol: "eyedropper") {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: .colorPickerPick))
                }
            }
        case "text-extractor":
            TrayQuickRow(toolID: toolID, title: "Text Extractor", symbol: "text.viewfinder") {
                TrayQuietActionButton(title: "Extract", symbol: "text.viewfinder") {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorCapture))
                }
            }
        case "awake":
            AwakeTrayRow()
        case "ruler":
            TrayQuickRow(toolID: toolID, title: "Ruler", symbol: "ruler") { EmptyView() }
        default:
            EmptyView()
        }
    }
}

private struct TrayQuickRow<Accessory: View>: View {
    let toolID: String
    let title: String
    let symbol: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            TrayToolLink(toolID: toolID, title: title, symbol: symbol)
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 10)
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
            HStack(spacing: 10) {
                TrayToolLink(toolID: "awake", title: "Awake", symbol: "moon.zzz")
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
                .frame(width: 176)
            }
            if service.isActive || service.assertionError != nil {
                Text(service.assertionError ?? service.statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(service.assertionError == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                    .padding(.leading, 32)
            }
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 10)
    }
}

private struct TrayToolLink: View {
    let toolID: String
    let title: String
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button {
            ToolActionRouter.shared.open(toolID: toolID)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: .medium))
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
        .help("Open \(title)")
    }
}

private struct TrayQuietActionButton: View {
    let title: String
    let symbol: String
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
    }
}

private struct TrayToolHeader: View {
    let tab: TrayTab
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TrayToolLink(toolID: tab.rawValue, title: tab.title, symbol: tab.symbol)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 32)
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CloudSyncTrayView: View {
    @State private var manager = RcloneJobManager.shared

    private var status: String {
        if !manager.daemonIsHealthy { return "Sync engine needs attention" }
        let count = manager.activeJobs.count
        return count == 0 ? "Ready · No active transfers" : "\(count) active transfer\(count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .cloudSync, detail: status)
            if !manager.daemonIsHealthy {
                QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
                HStack {
                    Text("The engine is not responding.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    TrayQuietActionButton(title: "Retry", symbol: "arrow.clockwise") {
                        Task { await manager.start() }
                    }
                }
                .padding(TrayPopoverLayout.horizontalInset)
            }
            ForEach(manager.activeJobs.prefix(4)) { job in
                QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
                TrayTransferRow(job: job).padding(TrayPopoverLayout.horizontalInset)
            }
        }
    }
}

private struct TrayTransferRow: View {
    let job: TransferJob
    @State private var manager = RcloneJobManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: job.operation.icon).font(.system(size: 10)).foregroundStyle(.secondary)
                Text("\(job.sourceDisplay) → \(job.destinationDisplay)")
                    .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(job.state == .paused ? "Paused" : RcloneFormat.speed(job.stats.speed))
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                if job.canPause {
                    transferButton("Pause transfer", symbol: "pause.fill") { manager.pause(job) }
                } else if job.canResume {
                    transferButton("Resume transfer", symbol: "play.fill") { manager.resume(job) }
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color.primary.opacity(0.48))
                        .frame(width: max(0, min(1, job.progressFraction)) * geometry.size.width)
                }
            }
            .frame(height: 4)
        }
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

private struct LogsTrayView: View {
    @State private var manager = LogManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .logs, detail: "Recent application activity")
            if manager.logs.isEmpty {
                QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
                Text("No recent log entries").font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(TrayPopoverLayout.horizontalInset)
            } else {
                ForEach(Array(manager.logs.suffix(5).reversed())) { entry in
                    QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
                    HStack(spacing: 8) {
                        Image(systemName: entry.level.icon).font(.system(size: 10)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message).font(.system(size: 11)).lineLimit(1)
                            Text(entry.source).font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 4)
                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 9)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct SystemCareTrayView: View {
    @State private var manager = SystemCareManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .systemCare, detail: manager.isWorking ? manager.progressMessage ?? "Working" : "Storage and cleanup status")
            statusRow("Storage", value: manager.storageURL == nil ? "Not analyzed" : Self.bytes(manager.storageTotal))
            statusRow("Cleanup", value: manager.cleanupCandidates.isEmpty ? "Not scanned" : "\(manager.cleanupCandidates.count) items")
            statusRow("Recovered", value: manager.lastRecoveredBytes == 0 ? "None this session" : Self.bytes(manager.lastRecoveredBytes))
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        VStack(spacing: 0) {
            QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text(value).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, TrayPopoverLayout.horizontalInset)
            .padding(.vertical, 9)
        }
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

private struct SystemMonitorTrayView: View {
    @State private var service = SystemMonitorService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .systemMonitor, detail: "Live system health")
            QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metric("CPU", service.snapshot?.cpuUsage.map { "\(Int($0.rounded()))%" } ?? "Waiting")
                metric("Memory", service.snapshot?.memoryUsage.map { "\(Int($0.rounded()))%" } ?? "Waiting")
                metric("Disk", service.snapshot?.diskUsage.map { "\(Int($0.rounded()))%" } ?? "Waiting")
                metric("Battery", service.snapshot?.batteryPercent.map { "\($0)%" } ?? "Unavailable")
            }
            .padding(TrayPopoverLayout.horizontalInset)
        }
        .onAppear { service.startDetailed() }
        .onDisappear { service.stopDetailed() }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct NetToysTrayView: View {
    @State private var model = NetToysHistoryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .netToys, detail: "Current network and helper status")
            QuietDivider().padding(.horizontal, TrayPopoverLayout.horizontalInset)
            HStack(spacing: 9) {
                Image(systemName: "network").font(.system(size: 12)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.helperStatus?.network?.displayName ?? "Network unavailable")
                        .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(helperDetail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(TrayPopoverLayout.horizontalInset)
        }
        .onAppear { model.refresh() }
    }

    private var helperDetail: String {
        guard let status = model.helperStatus else { return "Background helper is not reporting" }
        return "Updated \(status.heartbeat.formatted(date: .omitted, time: .shortened))"
    }
}
