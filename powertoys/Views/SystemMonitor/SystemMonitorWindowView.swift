import AppKit
import SwiftUI

enum SystemMonitorPalette {
    static let accent = TaskManagerTheme.accent
    static let teal = TaskManagerTheme.ink
    static let coral = TaskManagerTheme.accent
    static let gold = TaskManagerTheme.ink
    static let orange = TaskManagerTheme.ink
    static let cyan = TaskManagerTheme.ink
    static let green = TaskManagerTheme.ink
    static let blue = TaskManagerTheme.ink

    static func surface(_ tint: Color = TaskManagerTheme.ink, radius: CGFloat = 9) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(TaskManagerTheme.card)
            TaskManagerDitherTexture()
                .clipShape(RoundedRectangle(cornerRadius: radius))
        }
    }
}

struct GPUCardIcon: View {
    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(lineWidth: 1.2)
                .overlay {
                    HStack(spacing: 1.5) {
                        Circle().strokeBorder(lineWidth: 0.9)
                        Circle().strokeBorder(lineWidth: 0.9)
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2.5)
                }
                .frame(width: 12, height: 9)
            RoundedRectangle(cornerRadius: 0.5).frame(width: 1.5, height: 4)
        }
        .frame(width: 15, height: 13)
        .accessibilityHidden(true)
    }
}

struct SystemMonitorPlacementPicker: View {
    let metric: SystemMonitorMenuMetric
    @Binding var selection: SystemMonitorMenuPlacement

    var body: some View {
        TaskManagerSegments(
            choices: SystemMonitorMenuPlacement.allCases.map { ($0, $0.title) },
            selection: $selection
        )
        .frame(width: 204, height: UtilityLayout.workspaceActionHeight)
        .help("Show \(metric.title) in one Task Manager item, a separate item, or neither")
        .accessibilityIdentifier("system-monitor.\(metric.rawValue).menu-placement")
    }
}

private enum SystemMonitorPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Processes"
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"
    case battery = "Battery"
    case sensors = "Sensors"
    case remote = "Remote Stats"
    case report = "System Report"
    case about = "About"
    case settings = "Settings"

    var id: String { rawValue }

    var detailedMetrics: Set<SystemMonitorMenuMetric> {
        switch self {
        case .overview: Set(SystemMonitorMenuMetric.allCases)
        case .cpu: [.cpu, .thermal]
        case .gpu: [.gpu, .thermal]
        case .memory: [.memory]
        case .network: [.network]
        case .disk: [.disk]
        case .battery: [.battery]
        case .sensors: [.thermal]
        case .processes, .remote, .report, .about, .settings: []
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .processes: "list.bullet.rectangle"
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .sensors: "thermometer.medium"
        case .remote: "server.rack"
        case .report: "doc.text.magnifyingglass"
        case .about: "info.circle"
        case .settings: "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .report: "Hardware, network, and software information"
        case .settings: "Menu bar and monitoring preferences"
        case .about: "Task Manager"
        default: TaskManagerHardwareSummary.current
        }
    }

    static let primary: [Self] = [.overview, .processes]
    static let metrics: [Self] = [.cpu, .gpu, .memory, .network, .disk, .battery, .sensors]
    static let secondary: [Self] = [.remote, .report]
    static let bottom: [Self] = [.about, .settings]
}

struct SystemMonitorWindowView: View {
    private let reportSnapshot: [TaskManagerReportCategory]
    @State private var service = SystemMonitorService.shared
    @State private var overviewSampler = SystemMonitorProcessSampler()
    @State private var overviewProcesses: [SystemMonitorProcess] = []
    @AppStorage("systemMonitor.windowPage") private var pageID = SystemMonitorPage.overview.rawValue
    @AppStorage("systemMonitor.processHierarchy") private var processHierarchy = false
    @AppStorage("systemMonitor.historyMinutes") private var historyMinutes = 2
    @State private var processSearch = ""
    @State private var reportSearch = ""
    @State private var reportAction: TaskManagerSystemReportAction?
    @State private var processSearchFocusTrigger = 0

    init(reportSnapshot: [TaskManagerReportCategory] = []) {
        self.reportSnapshot = reportSnapshot
    }

    private var page: SystemMonitorPage { SystemMonitorPage(rawValue: pageID) ?? .overview }
    private var remoteProfiles: [SystemMonitorRemoteProfile] { SystemMonitorRemoteProfiles.load() }
    private var recentHistory: [SystemMonitorSample] {
        Array(service.history.suffix(max(60, historyMinutes * 60)))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: TaskManagerTheme.sidebarWidth)
            VStack(spacing: 0) {
                header
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .utilityContentTransition(value: pageID)
            }
            .background(TaskManagerTheme.window)
        }
        .foregroundStyle(TaskManagerTheme.ink)
        .background(TaskManagerTheme.window)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "system-monitor"))
        .onAppear { service.startDetailed(metrics: page.detailedMetrics) }
        .onChange(of: pageID) { _, _ in service.updateDetailed(metrics: page.detailedMetrics) }
        .onDisappear { service.stopDetailed() }
        .task(id: pageID) {
            guard page == .overview else { return }
            await sampleOverviewProcesses()
        }
        .overlay(alignment: .topLeading) {
            Button("") {
                pageID = SystemMonitorPage.processes.rawValue
                processSearchFocusTrigger &+= 1
            }
            .keyboardShortcut("k", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 64)
                TaskManagerDotTitle(text: "Task Manager", height: 9.5)
                Spacer(minLength: 8)
            }
            .frame(height: 48)

            sidebarGroup(SystemMonitorPage.primary)
            sidebarBreak
            sidebarGroup(SystemMonitorPage.metrics)
            sidebarBreak
            sidebarGroup(SystemMonitorPage.secondary)
            Spacer(minLength: 20)
            sidebarBreak
                .padding(.bottom, 9)
            sidebarGroup(SystemMonitorPage.bottom)
                .padding(.bottom, 11)
        }
        .padding(.horizontal, 10)
        .background(TaskManagerTheme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(TaskManagerTheme.line).frame(width: 1) }
    }

    private func sidebarGroup(_ pages: [SystemMonitorPage]) -> some View {
        VStack(spacing: 1) {
            ForEach(pages) { item in
                Button { pageID = item.rawValue } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .regular))
                            .frame(width: 14)
                            .foregroundStyle(page == item ? TaskManagerTheme.ink : TaskManagerTheme.secondary)
                        Text(item.rawValue)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if item == .remote, !remoteProfiles.isEmpty {
                            Text("\(remoteProfiles.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(TaskManagerTheme.muted)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 29, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(page == item ? Color.white.opacity(0.085) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 5))
                .focusEffectDisabled()
                .accessibilityAddTraits(page == item ? .isSelected : [])
                .accessibilityIdentifier("task-manager.sidebar.\(item.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
            }
        }
    }

    private var sidebarBreak: some View {
        Rectangle()
            .fill(TaskManagerTheme.lineSoft)
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
    }

    @ViewBuilder
    private var header: some View {
        switch page {
        case .processes:
            TaskManagerHeader(title: page.rawValue, subtitle: page.subtitle) {
                HStack(spacing: 14) {
                    TaskManagerSearchField(
                        prompt: "Search name, path, or PID",
                        text: $processSearch,
                        focusTrigger: processSearchFocusTrigger
                    )
                    HStack(spacing: 7) {
                        Text("Hierarchy")
                            .font(.system(size: 9))
                            .foregroundStyle(TaskManagerTheme.secondary)
                        Toggle("Hierarchy", isOn: $processHierarchy)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }
            }
        case .report:
            TaskManagerHeader(title: page.rawValue, subtitle: page.subtitle) {
                HStack(spacing: 8) {
                    TaskManagerSearchField(prompt: "Search all system information", text: $reportSearch, width: 320)
                    reportButton("doc.on.doc", label: "Copy current report") { reportAction = .copy }
                    Menu {
                        Button("Save Text Report…") { reportAction = .exportText }
                        Button("Save JSON Report…") { reportAction = .exportJSON }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10))
                            .frame(width: 29, height: 29)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
                            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(TaskManagerTheme.line) }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .focusEffectDisabled()
                    .help("Export system report")
                    .accessibilityLabel("Export system report")
                }
            }
        case .cpu:
            metricHeader(.cpu)
        case .gpu:
            metricHeader(.gpu)
        case .memory:
            metricHeader(.memory)
        case .network:
            metricHeader(.network)
        case .disk:
            metricHeader(.disk)
        case .battery:
            metricHeader(.battery)
        case .sensors:
            metricHeader(.thermal)
        default:
            TaskManagerHeader(page.rawValue, subtitle: page.subtitle)
        }
    }

    private func metricHeader(_ metric: SystemMonitorMenuMetric) -> some View {
        TaskManagerHeader(title: page.rawValue, subtitle: page.subtitle) {
            menuPlacement(metric)
        }
    }

    private func menuPlacement(_ metric: SystemMonitorMenuMetric) -> some View {
        SystemMonitorPlacementPicker(metric: metric, selection: Binding(
            get: {
                guard let item = service.menuSettings.items.first(where: { $0.metric == metric }),
                      service.menuSettings.enabled, item.enabled else { return .off }
                return item.placement
            },
            set: { placement in service.updateMenuSettings { $0.setPlacement(placement, for: metric) } }
        ))
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .overview: scrollPage { overviewPage }
        case .processes:
            SystemMonitorProcessesView(
                search: $processSearch,
                hierarchy: $processHierarchy,
                showsToolbar: false
            )
            .padding(.horizontal, TaskManagerTheme.contentInset)
            .padding(.bottom, 18)
        case .cpu: scrollPage { cpuPage }
        case .gpu: scrollPage { gpuPage }
        case .memory: scrollPage { memoryPage }
        case .network: scrollPage { networkPage }
        case .disk: scrollPage { diskPage }
        case .battery: scrollPage { batteryPage }
        case .sensors: scrollPage { sensorsPage }
        case .remote:
            SystemMonitorRemoteView()
                .padding(.horizontal, TaskManagerTheme.contentInset)
                .padding(.bottom, 18)
        case .report:
            TaskManagerSystemReportView(
                search: $reportSearch,
                requestedAction: $reportAction,
                initialCategories: reportSnapshot
            )
                .padding(.horizontal, TaskManagerTheme.contentInset)
                .padding(.bottom, 18)
        case .about: scrollPage { aboutPage }
        case .settings: scrollPage { settingsPage }
        }
    }

    private func scrollPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentMargins(.horizontal, TaskManagerTheme.contentInset, for: .scrollContent)
        .contentMargins(.bottom, 18, for: .scrollContent)
        .thinScrollIndicators()
    }

    private var overviewPage: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                metricCard(.cpu, value: percent(service.snapshot?.cpuUsage), detail: "Across \(ProcessInfo.processInfo.activeProcessorCount) cores",
                           values: recentHistory.compactMap(\.cpuUsage), range: 0...100)
                metricCard(.gpu, value: percent(service.snapshot?.gpuUsage), detail: "Graphics utilization",
                           values: recentHistory.compactMap(\.gpuUsage), range: 0...100)
                metricCard(.memory, value: service.snapshot?.memoryUsage.percent ?? "...", detail: memoryDetail,
                           values: recentHistory.compactMap(\.memoryUsage), range: 0...100, accent: true)
                metricCard(.network, value: service.snapshot?.networkDownload.map(Self.rate) ?? "...",
                           detail: "↓ Download · ↑ \(service.snapshot?.networkUpload.map(Self.rate) ?? "...")",
                           values: recentHistory.compactMap(\.networkDownload),
                           secondary: recentHistory.compactMap(\.networkUpload), range: networkRange)
                metricCard(.disk, value: service.snapshot?.diskUsage.percent ?? "...", detail: "\(diskAvailable) available")
                metricCard(.battery, value: service.snapshot?.batteryPercent.map { "\($0)%" } ?? "...", detail: batteryDetail)
                metricCard(.thermal, title: "Thermal", value: service.snapshot?.thermalState ?? "...", detail: "System thermal pressure")
                metricCard(.cpu, title: "Load average", value: loadValue, detail: "1 minute · \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs",
                           values: recentHistory.compactMap { $0.loadAverage?.0 }, range: loadRange)
                    .help(loadExplanation)
            }

            remoteOverview

            LazyVGrid(columns: [GridItem(.flexible(minimum: 0), spacing: 14), GridItem(.flexible(minimum: 0))], spacing: 14) {
                topProcesses
                memoryAllocation
            }
        }
    }

    private func metricCard(
        _ metric: SystemMonitorMenuMetric,
        title: String? = nil,
        value: String,
        detail: String,
        values: [Double] = [],
        secondary: [Double] = [],
        range: ClosedRange<Double> = 0...100,
        accent: Bool = false
    ) -> some View {
        Button {
            pageID = switch metric {
            case .cpu: SystemMonitorPage.cpu.rawValue
            case .gpu: SystemMonitorPage.gpu.rawValue
            case .memory: SystemMonitorPage.memory.rawValue
            case .network: SystemMonitorPage.network.rawValue
            case .disk: SystemMonitorPage.disk.rawValue
            case .battery: SystemMonitorPage.battery.rawValue
            case .thermal: SystemMonitorPage.sensors.rawValue
            }
        } label: {
            TaskManagerPanel(textured: true) {
                ZStack(alignment: .bottom) {
                    if !values.isEmpty {
                        TaskManagerHistoryChart(
                            values: values,
                            secondary: secondary,
                            range: range,
                            unit: metric == .network ? "/s" : "%",
                            compact: true,
                            primaryColor: accent ? TaskManagerTheme.accent : TaskManagerTheme.ink.opacity(0.76)
                        )
                            .frame(height: 33)
                            .padding(.horizontal, 11)
                            .padding(.bottom, 8)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            monitorIcon(metric)
                                .foregroundStyle(accent ? TaskManagerTheme.accent : TaskManagerTheme.secondary)
                            Text(title ?? metric.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(TaskManagerTheme.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(TaskManagerTheme.muted)
                        }
                        Text(value)
                            .font(.system(size: value.count > 9 ? 22 : 27, weight: .medium))
                            .tracking(-0.7)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.top, 7)
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(TaskManagerTheme.secondary)
                            .lineLimit(1)
                            .padding(.top, 4)
                        Spacer(minLength: 28)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 11)
                    .padding(.bottom, 9)
                }
            }
            .frame(height: 124)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: TaskManagerTheme.panelRadius))
        .focusEffectDisabled()
        .accessibilityLabel("Open \(title ?? metric.title), \(value)")
    }

    private var remoteOverview: some View {
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Remote instances", action: "Manage") { pageID = SystemMonitorPage.remote.rawValue }
            if remoteProfiles.isEmpty {
                Button { pageID = SystemMonitorPage.remote.rawValue } label: {
                    TaskManagerPanel {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 13))
                                .foregroundStyle(TaskManagerTheme.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("No remote hosts").font(.system(size: 11, weight: .medium))
                                Text("Add a Linux, macOS, or Windows SSH host in Remote Stats.")
                                    .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                            }
                            Spacer()
                            Text("Add  →").font(.system(size: 9)).foregroundStyle(TaskManagerTheme.muted)
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(height: 58)
                }
                .buttonStyle(.plain).focusEffectDisabled()
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(remoteProfiles.prefix(2)) { profile in
                        TaskManagerRemoteCard(
                            profile: profile,
                            reading: nil,
                            state: "Offline",
                            primaryTitle: "Open",
                            primarySymbol: "arrow.right",
                            onPrimary: { pageID = SystemMonitorPage.remote.rawValue }
                        )
                    }
                }
            }
        }
    }

    private var topProcesses: some View {
        let sorted = Array(SystemMonitorProcessSorting.sorted(overviewProcesses, by: .cpu, descending: true).prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Top processes", action: "View all") { pageID = SystemMonitorPage.processes.rawValue }
            TaskManagerPanel {
                VStack(spacing: 0) {
                    tableHeader([("Process", nil), ("CPU", 62), ("Memory", 82)])
                    ForEach(sorted) { process in
                        Button {
                            pageID = SystemMonitorPage.processes.rawValue
                            processSearch = String(process.pid)
                        } label: {
                            HStack(spacing: 8) {
                                processIdentity(process).frame(maxWidth: .infinity, alignment: .leading)
                                Text(process.cpuPercent.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "...")
                                    .frame(width: 62, alignment: .trailing)
                                Text(process.residentBytes == 0 ? "..." : Self.bytes(process.residentBytes))
                                    .frame(width: 82, alignment: .trailing)
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(TaskManagerTheme.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 33)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 0))
                        .focusEffectDisabled()
                        if process.id != sorted.last?.id {
                            Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                        }
                    }
                    if sorted.isEmpty {
                        Text("...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(TaskManagerTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 165)
                    }
                }
            }
            .frame(height: 203)
        }
    }

    private var memoryAllocation: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Memory allocation", action: "Details") { pageID = SystemMonitorPage.memory.rawValue }
            memoryAllocationPanel
                .frame(height: 203)
        }
    }

    private var memoryAllocationPanel: some View {
        let used = service.snapshot?.memoryUsed ?? 0
        let total = max(service.snapshot?.memoryTotal ?? 1, 1)
        let wired = service.snapshot?.memoryDetails?.wired ?? 0
        let compressed = service.snapshot?.memoryDetails?.compressed ?? 0
        let applications = max(used - wired - compressed, 0)
        let available = max(total - used, 0)
        return TaskManagerPanel {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Rectangle().fill(TaskManagerTheme.ink.opacity(0.82))
                            .frame(width: proxy.size.width * CGFloat(Double(applications) / Double(total)))
                        Rectangle().fill(TaskManagerTheme.ink.opacity(0.58))
                            .frame(width: proxy.size.width * CGFloat(Double(wired) / Double(total)))
                        Rectangle().fill(TaskManagerTheme.ink.opacity(0.35))
                            .frame(width: proxy.size.width * CGFloat(Double(compressed) / Double(total)))
                        Rectangle().fill(TaskManagerTheme.lineSoft)
                            .frame(width: proxy.size.width * CGFloat(Double(available) / Double(total)))
                    }
                }
                .frame(height: 10)
                allocationRow("Applications", value: Self.bytes(applications))
                allocationRow("Wired", value: Self.bytes(wired))
                allocationRow("Compressed", value: Self.bytes(compressed))
                Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                allocationRow("Available", value: Self.bytes(available))
            }
            .padding(14)
        }
    }

    private func detailHero(
        label: String,
        value: String,
        unit: String = "",
        detail: String,
        values: [Double],
        secondary: [Double] = [],
        range: ClosedRange<Double>,
        stats: [(String, String)]
    ) -> some View {
        TaskManagerPanel(textured: true) {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(TaskManagerTheme.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(value)
                                .font(.system(size: 32, weight: .medium))
                                .tracking(-1)
                                .monospacedDigit()
                            if !unit.isEmpty {
                                Text(unit).font(.system(size: 14)).foregroundStyle(TaskManagerTheme.secondary)
                            }
                        }
                        Text(detail).font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 20) {
                        ForEach(stats.indices, id: \.self) { index in
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(stats[index].0).font(.system(size: 8)).foregroundStyle(TaskManagerTheme.muted)
                                Text(stats[index].1)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(index == stats.count - 1 && stats[index].1 == "Elevated" ? TaskManagerTheme.accent : TaskManagerTheme.ink)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                TaskManagerHistoryChart(values: values, secondary: secondary, range: range, unit: unit)
                    .frame(height: 138)
                    .padding(.horizontal, 14)
                HStack {
                    Text("−\(historyMinutes) min")
                    Spacer()
                    Text("Now")
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(TaskManagerTheme.muted)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private var cpuPage: some View {
        VStack(spacing: 12) {
            detailHero(
                label: "CPU usage", value: service.snapshot?.cpuUsage.map(Self.decimal) ?? "...", unit: "%",
                detail: "Across \(ProcessInfo.processInfo.activeProcessorCount) logical cores",
                values: recentHistory.compactMap(\.cpuUsage), range: 0...100,
                stats: [
                    ("User", service.snapshot?.cpuDetails.map { "\(Int($0.user.rounded()))%" } ?? "..."),
                    ("System", service.snapshot?.cpuDetails.map { "\(Int($0.system.rounded()))%" } ?? "..."),
                    ("Idle", service.snapshot?.cpuDetails.map { "\(Int($0.idle.rounded()))%" } ?? "..."),
                ]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                coreActivity
                informationPanel("Load average", rows: [
                    ("1 minute", service.snapshot?.loadAverage.map { Self.decimal($0.0) } ?? "..."),
                    ("5 minutes", service.snapshot?.loadAverage.map { Self.decimal($0.1) } ?? "..."),
                    ("15 minutes", service.snapshot?.loadAverage.map { Self.decimal($0.2) } ?? "..."),
                    ("Thermal pressure", service.snapshot?.thermalState ?? "..."),
                ])
                .help(loadExplanation)
            }
        }
    }

    private var coreActivity: some View {
        let cores = service.snapshot?.cpuDetails?.cores ?? []
        return TaskManagerPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Core activity").font(.system(size: 10.5, weight: .medium))
                    Spacer()
                    Text(coreLayoutDescription)
                        .font(.system(size: 8)).foregroundStyle(TaskManagerTheme.muted)
                }
                Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                if cores.isEmpty {
                    Text("...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(TaskManagerTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 92)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                       count: min(7, max(cores.count, 1))),
                        spacing: 6
                    ) {
                        ForEach(cores.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(coreLabel(index))
                                    .font(.system(size: 7, design: .monospaced))
                                    .foregroundStyle(TaskManagerTheme.muted)
                                Text("\(Int(cores[index].rounded()))%")
                                    .font(.system(size: 9.5, design: .monospaced))
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(TaskManagerTheme.lineSoft)
                                        Rectangle().fill(TaskManagerTheme.ink.opacity(0.72))
                                            .frame(width: proxy.size.width * CGFloat(min(max(cores[index] / 100, 0), 1)))
                                    }
                                }
                                .frame(height: 3)
                            }
                            .padding(7)
                            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 4))
                            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(TaskManagerTheme.lineSoft) }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private var gpuPage: some View {
        VStack(spacing: 12) {
            detailHero(
                label: "GPU usage", value: service.snapshot?.gpuUsage.map(Self.decimal) ?? "...", unit: "%",
                detail: "Integrated graphics",
                values: recentHistory.compactMap(\.gpuUsage), range: 0...100,
                stats: [("Memory", "Unified"), ("Thermal pressure", service.snapshot?.thermalState ?? "...")]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                informationPanel("Graphics details", rows: [
                    ("Architecture", "Integrated"), ("Memory", "Unified"),
                    ("Utilization", percent(service.snapshot?.gpuUsage)),
                ])
                informationPanel("Engine activity", rows: [
                    ("Combined activity", percent(service.snapshot?.gpuUsage)),
                    ("Per-engine counters", "Not exposed by macOS"),
                ])
            }
        }
    }

    private var memoryPage: some View {
        VStack(spacing: 12) {
            detailHero(
                label: "Memory in use", value: service.snapshot?.memoryUsed.map(Self.bytes) ?? "...",
                detail: "\(service.snapshot?.memoryTotal.map(Self.bytes) ?? "...") unified memory",
                values: recentHistory.compactMap { $0.memoryUsed.map(Double.init) },
                range: 0...Double(max(service.snapshot?.memoryTotal ?? 1, 1)),
                stats: [("Used", service.snapshot?.memoryUsage.percent ?? "..."), ("Available", memoryAvailable)]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Allocation").font(.system(size: 11, weight: .medium))
                    memoryAllocationPanel.frame(height: 203)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("Virtual memory").font(.system(size: 11, weight: .medium))
                    informationPanel("Memory details", rows: [
                        ("Swap used", service.snapshot?.memoryDetails?.swapUsed.map(Self.bytes) ?? "Unavailable"),
                        ("Compressed", service.snapshot?.memoryDetails.map { Self.bytes($0.compressed) } ?? "..."),
                        ("Cached files", service.snapshot?.memoryDetails.map { Self.bytes($0.cached) } ?? "..."),
                        ("Page-ins", service.snapshot?.memoryDetails.map { "\($0.pageIns.formatted()) pages" } ?? "..."),
                        ("Page-outs", service.snapshot?.memoryDetails.map { "\($0.pageOuts.formatted()) pages" } ?? "..."),
                    ])
                }
            }
        }
    }

    private var networkPage: some View {
        VStack(spacing: 12) {
            detailHero(
                label: "Download", value: service.snapshot?.networkDownload.map(Self.rate) ?? "...",
                detail: "All active non-loopback interfaces",
                values: recentHistory.compactMap(\.networkDownload),
                secondary: recentHistory.compactMap(\.networkUpload), range: networkRange,
                stats: [
                    ("Upload", service.snapshot?.networkUpload.map(Self.rate) ?? "..."),
                    ("Interface", service.snapshot?.networkDetails?.interfaceName ?? "..."),
                ]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                informationPanel("Interface", rows: [
                    ("Name", service.snapshot?.networkDetails?.interfaceName ?? "..."),
                    ("Local address", service.snapshot?.networkDetails?.localAddress ?? "Unavailable"),
                    ("Transferred down", service.snapshot?.networkDetails.map { Self.bytes($0.receivedTotal) } ?? "..."),
                    ("Transferred up", service.snapshot?.networkDetails.map { Self.bytes($0.sentTotal) } ?? "..."),
                ])
                informationPanel("Activity", rows: [
                    ("Download", service.snapshot?.networkDownload.map(Self.rate) ?? "..."),
                    ("Upload", service.snapshot?.networkUpload.map(Self.rate) ?? "..."),
                    ("Process endpoints", "Available in Process Information"),
                ])
            }
        }
    }

    private var diskPage: some View {
        VStack(spacing: 12) {
            TaskManagerPanel(textured: true) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("Startup volume", systemImage: "internaldrive")
                                .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
                            Text(service.snapshot?.diskUsed.map(Self.bytes) ?? "...")
                                .font(.system(size: 32, weight: .medium)).tracking(-1).monospacedDigit()
                            Text("used of \(service.snapshot?.diskTotal.map(Self.bytes) ?? "...")")
                                .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                        }
                        Spacer()
                        detailStat("Available", diskAvailable)
                        detailStat("Used", service.snapshot?.diskUsage.percent ?? "...")
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            Rectangle().fill(TaskManagerTheme.ink.opacity(0.76))
                                .frame(width: proxy.size.width * CGFloat((service.snapshot?.diskUsage ?? 0) / 100))
                            Rectangle().fill(TaskManagerTheme.lineSoft)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(14)
            }
            detailHero(
                label: "Disk activity",
                value: service.snapshot?.diskDetails?.readPerSecond.map(Self.rate) ?? "...",
                detail: "Read throughput across physical storage",
                values: recentHistory.compactMap { $0.diskDetails?.readPerSecond },
                secondary: recentHistory.compactMap { $0.diskDetails?.writePerSecond },
                range: diskRateRange,
                stats: [
                    ("Write", service.snapshot?.diskDetails?.writePerSecond.map(Self.rate) ?? "..."),
                    ("Read total", service.snapshot?.diskDetails.map { Self.bytes($0.readTotal) } ?? "..."),
                ]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                informationPanel("Volume", rows: [("Mount point", "/"), ("Used", service.snapshot?.diskUsed.map(Self.bytes) ?? "..."), ("Available", diskAvailable)])
                informationPanel("Storage", rows: [
                    ("Capacity", service.snapshot?.diskTotal.map(Self.bytes) ?? "..."),
                    ("Read", service.snapshot?.diskDetails?.readPerSecond.map(Self.rate) ?? "..."),
                    ("Write", service.snapshot?.diskDetails?.writePerSecond.map(Self.rate) ?? "..."),
                    ("Status", "Mounted"),
                ])
            }
        }
    }

    private var batteryPage: some View {
        VStack(spacing: 12) {
            detailHero(
                label: "Battery charge", value: service.snapshot?.batteryPercent.map(String.init) ?? "...", unit: "%",
                detail: batteryDetail,
                values: recentHistory.compactMap { $0.batteryPercent.map(Double.init) }, range: 0...100,
                stats: [("Power source", powerSourceDetail), ("Status", batteryDetail)]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                informationPanel("Battery details", rows: [
                    ("Charge", service.snapshot?.batteryPercent.map { "\($0)%" } ?? "..."),
                    ("Power source", powerSourceDetail),
                    ("Health", service.snapshot?.batteryDetails?.health ?? "Unavailable"),
                    ("Cycle count", service.snapshot?.batteryDetails?.cycleCount.map(String.init) ?? "Unavailable"),
                    ("Voltage", service.snapshot?.batteryDetails?.voltageMillivolts.map { "\($0) mV" } ?? "Unavailable"),
                    ("Amperage", service.snapshot?.batteryDetails?.amperageMilliamps.map { "\($0) mA" } ?? "Unavailable"),
                ])
                powerDrawPanel
            }
        }
    }

    private var powerDrawPanel: some View {
        let values = recentHistory.compactMap(Self.powerDraw)
        return TaskManagerPanel(textured: true) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Power draw", systemImage: "bolt")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TaskManagerTheme.secondary)
                Text(service.snapshot.flatMap(Self.powerDraw).map { "\(Self.decimal($0)) W" } ?? "Unavailable")
                    .font(.system(size: 28, weight: .medium))
                    .monospacedDigit()
                TaskManagerHistoryChart(
                    values: values,
                    range: 0...max((values.max() ?? 1) * 1.15, 1),
                    unit: " W",
                    compact: true
                )
                .frame(height: 82)
                Spacer(minLength: 0)
                Text("Calculated from battery voltage and current when macOS reports both values.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(TaskManagerTheme.muted)
            }
            .padding(14)
        }
    }

    private var sensorsPage: some View {
        VStack(spacing: 12) {
            detailHero(
                label: "Thermal pressure", value: service.snapshot?.thermalState ?? "...",
                detail: "System-reported thermal state",
                values: recentHistory.compactMap { Self.thermalLevel($0.thermalState) }, range: 0...100,
                stats: [("State", service.snapshot?.thermalState ?? "..."), ("Temperature", "Hardware dependent")]
            )
            informationPanel("Temperature sensors", rows: [
                ("System pressure", service.snapshot?.thermalState ?? "..."),
                ("Per-sensor temperatures", "Unavailable through public macOS APIs"),
            ])
            FanControlView(owner: "system-monitor-window")
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("MENU BAR").taskManagerSectionTitle()
            TaskManagerPanel { settingsRows }
            Text("ADVANCED ITEMS").taskManagerSectionTitle()
            SystemMonitorMenuSettingsView(showsContainerScroll: false, showsDisplaySection: false)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var settingsRows: some View {
        VStack(spacing: 0) {
            settingRow("Menu bar items", detail: "Show one grouped monitor or separate metrics.") {
                TaskManagerSegments(choices: [("grouped", "Grouped"), ("separate", "Separate"), ("off", "Off")],
                                    selection: menuDisplayBinding)
            }
            rowDivider
            settingRow("Remember last panel", detail: "Reopen the last selected menu-bar tab.") {
                Toggle("Remember last panel", isOn: rememberPanelBinding)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            rowDivider
            settingRow("Refresh interval", detail: "Used by enabled menu-bar readings.") {
                Picker("Refresh interval", selection: menuIntervalBinding) {
                    ForEach([10.0, 30.0, 60.0], id: \.self) { value in
                        Text("\(Int(value)) seconds").tag(value)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 120)
            }
            rowDivider
            settingRow("History window", detail: "The visible range for live charts.") {
                Picker("History window", selection: $historyMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 120)
            }
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 16) {
            TaskManagerPanel(textured: true) {
                HStack(spacing: 20) {
                    Image("SystemMonitorLogo")
                        .resizable().scaledToFit().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        TaskManagerDotTitle(text: "Task Manager", height: 24)
                        Text("A focused view of your Mac's activity.")
                            .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
                    }
                    Spacer()
                }
                .padding(22)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                aboutPanel("Main window", icon: "display", text: "Processes, compute, memory, storage, network, battery, and thermal activity in dedicated workspaces.")
                aboutPanel("Menu bar", icon: "chart.bar.xaxis", text: "A compact panel with icon tabs, live metrics, remote instances, processes, and fan controls.")
            }
            informationPanel("Keyboard shortcuts", rows: [("Find a process", "⌘ K"), ("Dismiss a sheet or menu", "Esc")])
        }
    }

    private func informationPanel(_ title: String, rows: [(String, String)]) -> some View {
        TaskManagerPanel {
            VStack(spacing: 0) {
                HStack { Text(title).font(.system(size: 10.5, weight: .medium)); Spacer() }
                    .padding(.horizontal, 14).frame(height: 42)
                rowDivider
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text(rows[index].0).foregroundStyle(TaskManagerTheme.secondary)
                        Spacer(minLength: 12)
                        Text(rows[index].1)
                            .foregroundStyle(TaskManagerTheme.ink)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    if index < rows.count - 1 { rowDivider }
                }
            }
        }
    }

    private func aboutPanel(_ title: String, icon: String, text: String) -> some View {
        TaskManagerPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.system(size: 21)).foregroundStyle(TaskManagerTheme.secondary)
                Text(title).font(.system(size: 11, weight: .medium))
                Text(text).font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary).lineSpacing(4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
        }
    }

    private func sectionHeader(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        return HStack {
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Button(action, action: perform)
                .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                .buttonStyle(.plain).focusEffectDisabled()
        }
        .frame(minHeight: 17)
    }

    private func reportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .frame(width: 29, height: 29)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(TaskManagerTheme.line) }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(label)
        .accessibilityLabel(label)
    }

    private func tableHeader(_ columns: [(String, CGFloat?)]) -> some View {
        HStack(spacing: 8) {
            ForEach(columns.indices, id: \.self) { index in
                Text(columns[index].0.uppercased())
                    .font(.system(size: 8))
                    .tracking(0.4)
                    .foregroundStyle(TaskManagerTheme.muted)
                    .frame(width: columns[index].1, alignment: columns[index].1 == nil ? .leading : .trailing)
                    .frame(maxWidth: columns[index].1 == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 33)
        .background(Color(red: 0.11, green: 0.11, blue: 0.11))
    }

    private func processIdentity(_ process: SystemMonitorProcess) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.055))
                .overlay { Image(systemName: "app").font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary) }
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(TaskManagerTheme.line) }
                .frame(width: 18, height: 18)
            Text(process.name).font(.system(size: 10)).foregroundStyle(TaskManagerTheme.ink).lineLimit(1)
        }
    }

    private func allocationRow(_ title: String, value: String) -> some View {
        let color: Color = switch title {
        case "Applications": TaskManagerTheme.ink.opacity(0.82)
        case "Wired": TaskManagerTheme.ink.opacity(0.58)
        case "Compressed": TaskManagerTheme.ink.opacity(0.35)
        default: TaskManagerTheme.line
        }
        return HStack {
            Rectangle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
            Spacer()
            Text(value).font(.system(size: 9, design: .monospaced))
        }
    }

    private func detailStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(title).font(.system(size: 8)).foregroundStyle(TaskManagerTheme.muted)
            Text(value).font(.system(size: 12, design: .monospaced))
        }
        .padding(.leading, 24)
    }

    private func settingRow<Content: View>(_ title: String, detail: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11))
                Text(detail).font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
            }
            Spacer(minLength: 20)
            control()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private var rowDivider: some View { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }

    @ViewBuilder
    private func monitorIcon(_ metric: SystemMonitorMenuMetric) -> some View {
        if metric == .gpu { GPUCardIcon() } else { Image(systemName: metric.symbol).font(.system(size: 11)) }
    }

    private var menuDisplayBinding: Binding<String> {
        Binding(
            get: {
                guard service.menuSettings.enabled else { return "off" }
                return service.menuSettings.enabledItems.allSatisfy { $0.placement == .separate } ? "separate" : "grouped"
            },
            set: { value in
                service.updateMenuSettings { settings in
                    if value == "off" { settings.enabled = false; return }
                    settings.enabled = true
                    if settings.enabledItems.isEmpty { settings.setPlacement(.combined, for: .memory) }
                    for index in settings.items.indices where settings.items[index].enabled {
                        settings.items[index].placement = value == "separate" ? .separate : .combined
                    }
                }
            }
        )
    }

    private var rememberPanelBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: "systemMonitor.rememberTrayPage") as? Bool ?? true },
            set: { UserDefaults.standard.set($0, forKey: "systemMonitor.rememberTrayPage") }
        )
    }

    private var menuIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { service.menuSettings.interval },
            set: { value in service.updateMenuSettings { $0.interval = value } }
        )
    }

    private var memoryDetail: String {
        guard let used = service.snapshot?.memoryUsed, let total = service.snapshot?.memoryTotal else { return "Physical memory" }
        return "\(Self.bytes(used)) / \(Self.bytes(total))"
    }

    private var memoryAvailable: String {
        guard let used = service.snapshot?.memoryUsed, let total = service.snapshot?.memoryTotal else { return "..." }
        return Self.bytes(max(total - used, 0))
    }

    private var diskAvailable: String {
        guard let used = service.snapshot?.diskUsed, let total = service.snapshot?.diskTotal else { return "..." }
        return Self.bytes(max(total - used, 0))
    }

    private var batteryDetail: String {
        guard service.snapshot?.batteryPercent != nil else { return "No internal battery detected" }
        return service.snapshot?.batteryCharging == true ? "Connected to power" : "On battery"
    }

    private var loadValue: String { service.snapshot?.loadAverage.map { Self.decimal($0.0) } ?? "..." }
    private var loadExplanation: String {
        "Load is the average number of processes running or waiting for a CPU. Compare it with \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs. It is not a percentage."
    }
    private var loadRange: ClosedRange<Double> {
        0...Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    }
    private var networkRange: ClosedRange<Double> {
        let maximum = recentHistory.flatMap { [$0.networkDownload, $0.networkUpload] }.compactMap { $0 }.max() ?? 1
        return 0...max(maximum * 1.15, 1)
    }

    private var diskRateRange: ClosedRange<Double> {
        let maximum = recentHistory.flatMap {
            [$0.diskDetails?.readPerSecond, $0.diskDetails?.writePerSecond]
        }.compactMap { $0 }.max() ?? 1
        return 0...max(maximum * 1.15, 1)
    }

    private var coreLayoutDescription: String {
        guard let layout = TaskManagerHardwareSummary.coreLayout else {
            return "\(ProcessInfo.processInfo.activeProcessorCount) logical cores"
        }
        return "\(layout.performance) performance · \(layout.efficiency) efficiency"
    }

    private func coreLabel(_ index: Int) -> String {
        guard let layout = TaskManagerHardwareSummary.coreLayout else { return "C\(index + 1)" }
        return index < layout.performance ? "P\(index + 1)" : "E\(index - layout.performance + 1)"
    }

    private var powerSourceDetail: String {
        guard service.snapshot?.batteryPercent != nil,
              let charging = service.snapshot?.batteryCharging else { return "Unavailable" }
        return charging ? "AC adapter" : "Battery"
    }

    private func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "..." }

    private func sampleOverviewProcesses() async {
        guard page == .overview else { return }
        while !Task.isCancelled {
            overviewProcesses = await overviewSampler.sample()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    nonisolated private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 2 : 1)))
    }
    nonisolated private static func rate(_ value: Double) -> String {
        SystemMonitorDisplayFormat.byteRate(value)
    }
    nonisolated private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(value, 0), countStyle: .memory)
    }
    nonisolated private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .memory)
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

    nonisolated private static func powerDraw(_ sample: SystemMonitorSample) -> Double? {
        guard let voltage = sample.batteryDetails?.voltageMillivolts,
              let amperage = sample.batteryDetails?.amperageMilliamps else { return nil }
        return Double(voltage) * Double(abs(amperage)) / 1_000_000
    }
}

struct SystemMonitorMenuSettingsView: View {
    @State private var service = SystemMonitorService.shared
    let showsContainerScroll: Bool
    let showsDisplaySection: Bool

    init(showsContainerScroll: Bool = true, showsDisplaySection: Bool = true) {
        self.showsContainerScroll = showsContainerScroll
        self.showsDisplaySection = showsDisplaySection
    }

    @ViewBuilder
    var body: some View {
        if showsContainerScroll {
            ScrollView {
                settingsContent
                    .padding(.horizontal, UtilityLayout.horizontalInset)
                    .padding(.vertical, 12)
            }
            .thinScrollIndicators()
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsDisplaySection { displaySection }
            itemsSection
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISPLAY").utilitySectionHeader()
            Toggle("Show Task Manager in Menu Bar", isOn: menuSetting(
                get: { $0.enabled },
                set: { $0.enabled = $1 }
            ))
            .accessibilityIdentifier("system-monitor.menu.enabled")
            globalIntervalControl
                .disabled(!service.menuSettings.enabled)
        }
        .utilitySectionCard()
    }

    private var globalIntervalControl: some View {
        settingControl("GLOBAL INTERVAL", width: 112) {
            Picker("Global interval", selection: menuSetting(
                get: { $0.interval },
                set: { $0.interval = $1 }
            )) {
                ForEach(SystemMonitorMenuInterval.allowedSeconds, id: \.self) { seconds in
                    Text(Self.intervalTitle(seconds)).tag(seconds)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityIdentifier("system-monitor.menu.global-interval")
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("MENU BAR ITEMS").utilitySectionHeader()
                Text("Drag to reorder")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            LazyVStack(spacing: 0) {
                ForEach(service.menuSettings.items) { item in
                    itemRow(item)
                    if item.metric != service.menuSettings.items.last?.metric {
                        QuietDivider()
                    }
                }
            }
            .background(TaskManagerTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius))
            .overlay {
                RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius)
                    .strokeBorder(TaskManagerTheme.line)
            }
        }
    }

    private func itemRow(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                itemIdentity(item)
                Spacer(minLength: 12)
                itemControls(item)
            }

            VStack(alignment: .leading, spacing: 8) {
                itemIdentity(item)
                itemControls(item)
                    .padding(.leading, 50)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .draggable(item.metric.rawValue)
        .dropDestination(for: String.self) { values, _ in
            guard let rawValue = values.first,
                  let source = SystemMonitorMenuMetric(rawValue: rawValue) else { return false }
            move(source, to: item.metric)
            return true
        }
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue)")
    }

    private func itemIdentity(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        HStack(spacing: 8) {
            reorderMenu(item.metric)

            Picker(item.metric.title, selection: Binding<SystemMonitorMenuPlacement>(
                get: {
                    guard let current = service.menuSettings.items.first(where: { $0.metric == item.metric }),
                          current.enabled else { return .off }
                    return current.placement
                },
                set: { placement in
                    service.updateMenuSettings { $0.setPlacement(placement, for: item.metric) }
                }
            )) {
                ForEach(SystemMonitorMenuPlacement.allCases) { placement in
                    Text(placement.title).tag(placement)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 120, height: UtilityLayout.workspaceActionHeight)
            .accessibilityLabel("\(item.metric.title) menu bar placement")
            .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).placement")

            Label(item.metric.title, systemImage: item.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 104, alignment: .leading)
                .lineLimit(1)
        }
    }

    private func itemControls(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                primaryItemControls(item)
                itemSpecificControl(item)
            }

            VStack(alignment: .leading, spacing: 6) {
                primaryItemControls(item)
                itemSpecificControl(item)
            }
        }
    }

    private func primaryItemControls(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            settingControl("STYLE", width: 92) {
                Picker("Style", selection: itemSetting(
                    item,
                    get: { $0.style },
                    set: { $0.style = $1 }
                )) {
                    ForEach(SystemMonitorMenuItemStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("\(item.metric.title) style")
                .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).style")
            }

            settingControl("ICON", width: 82) {
                Picker("Icon", selection: itemSetting(
                    item,
                    get: { $0.symbol },
                    set: { $0.symbol = $1 }
                )) {
                    ForEach(item.metric.symbols, id: \.self) { symbol in
                        Label(Self.iconTitle(symbol, for: item.metric), systemImage: symbol).tag(symbol)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("\(item.metric.title) icon")
                .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).icon")
            }

            settingControl("INTERVAL", width: 94) {
                Picker("Interval", selection: itemSetting(
                    item,
                    get: { $0.interval },
                    set: { $0.interval = $1 }
                )) {
                    ForEach(
                        item.metric.supportedIntervals(global: service.menuSettings.interval)
                    ) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("\(item.metric.title) interval")
                .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).interval")
            }
        }
    }

    @ViewBuilder
    private func itemSpecificControl(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        switch item.metric {
        case .memory:
            settingControl("UNIT", width: 88) {
                Picker("Unit", selection: itemSetting(
                    item,
                    get: { $0.memoryUnit },
                    set: { $0.memoryUnit = $1 }
                )) {
                    ForEach(SystemMonitorMemoryUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Memory unit")
                .accessibilityIdentifier("system-monitor.menu.item.memory.unit")
            }
        case .disk:
            settingControl("UNIT", width: 88) {
                Picker("Unit", selection: itemSetting(
                    item,
                    get: { $0.diskUnit },
                    set: { $0.diskUnit = $1 }
                )) {
                    ForEach(SystemMonitorDiskUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Disk unit")
                .accessibilityIdentifier("system-monitor.menu.item.disk.unit")
            }
        case .network:
            HStack(alignment: .bottom, spacing: 10) {
                settingControl("DIRECTION", width: 100) {
                    Picker("Direction", selection: itemSetting(
                        item,
                        get: { $0.networkDirection },
                        set: { $0.networkDirection = $1 }
                    )) {
                        ForEach(SystemMonitorNetworkDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Network direction")
                    .accessibilityIdentifier("system-monitor.menu.item.network.direction")
                }

                settingControl("UNIT", width: 130) {
                    Picker("Unit", selection: itemSetting(
                        item,
                        get: { $0.networkUnit },
                        set: { $0.networkUnit = $1 }
                    )) {
                        ForEach(SystemMonitorNetworkUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Network unit")
                    .accessibilityIdentifier("system-monitor.menu.item.network.unit")
                }
            }
        case .battery:
            settingControl("DISPLAY", width: 150) {
                Picker("Display", selection: itemSetting(
                    item,
                    get: { $0.batteryDisplay },
                    set: { $0.batteryDisplay = $1 }
                )) {
                    ForEach(SystemMonitorBatteryDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Battery display")
                .accessibilityIdentifier("system-monitor.menu.item.battery.display")
            }
        case .thermal:
            settingControl("DISPLAY", width: 100) {
                Picker("Display", selection: itemSetting(
                    item,
                    get: { $0.thermalDisplay },
                    set: { $0.thermalDisplay = $1 }
                )) {
                    ForEach(SystemMonitorThermalDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Thermal display")
                .accessibilityIdentifier("system-monitor.menu.item.thermal.display")
            }
        default:
            EmptyView()
        }
    }

    private func reorderMenu(_ metric: SystemMonitorMenuMetric) -> some View {
        let index = service.menuSettings.items.firstIndex { $0.metric == metric }
        return Menu {
            Button("Move Up") { move(metric, by: -1) }
                .disabled(index == service.menuSettings.items.startIndex)
            Button("Move Down") { move(metric, by: 1) }
                .disabled(index == service.menuSettings.items.indices.last)
        } label: {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .help("Reorder \(metric.title)")
        .accessibilityLabel("Reorder \(metric.title)")
        .accessibilityIdentifier("system-monitor.menu.item.\(metric.rawValue).reorder")
    }

    private func settingControl<Content: View>(
        _ label: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }

    private func menuSetting<Value>(
        get: @escaping (SystemMonitorMenuSettings) -> Value,
        set: @escaping (inout SystemMonitorMenuSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(service.menuSettings) },
            set: { value in service.updateMenuSettings { set(&$0, value) } }
        )
    }

    private func itemSetting<Value>(
        _ item: SystemMonitorMenuItemConfiguration,
        get: @escaping (SystemMonitorMenuItemConfiguration) -> Value,
        set: @escaping (inout SystemMonitorMenuItemConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: {
                service.menuSettings.items.first { $0.metric == item.metric }.map(get) ?? get(item)
            },
            set: { value in
                service.updateMenuSettings { settings in
                    guard let index = settings.items.firstIndex(where: { $0.metric == item.metric }) else { return }
                    set(&settings.items[index], value)
                }
            }
        )
    }

    private func move(_ metric: SystemMonitorMenuMetric, by offset: Int) {
        service.updateMenuSettings { settings in
            guard let source = settings.items.firstIndex(where: { $0.metric == metric }) else { return }
            let destination = source + offset
            guard settings.items.indices.contains(destination) else { return }
            settings.items.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: offset > 0 ? destination + 1 : destination
            )
        }
    }

    private func move(_ sourceMetric: SystemMonitorMenuMetric, to destinationMetric: SystemMonitorMenuMetric) {
        guard sourceMetric != destinationMetric else { return }
        service.updateMenuSettings { settings in
            guard let source = settings.items.firstIndex(where: { $0.metric == sourceMetric }),
                  let destination = settings.items.firstIndex(where: { $0.metric == destinationMetric }) else { return }
            settings.items.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: destination > source ? destination + 1 : destination
            )
        }
    }

    private static func intervalTitle(_ seconds: TimeInterval) -> String {
        "\(Int(seconds)) \(seconds == 1 ? "second" : "seconds")"
    }

    private static func iconTitle(_ symbol: String, for metric: SystemMonitorMenuMetric) -> String {
        guard let index = metric.symbols.firstIndex(of: symbol), index > 0 else { return metric.title }
        return "Alternate \(index)"
    }
}

struct SystemMonitorDitherSparkline: View {
    let values: [Double]
    var color: Color = TaskManagerTheme.ink
    var showsGuide = false

    var body: some View {
        let maximum = max(values.filter(\.isFinite).max() ?? 1, 1)
        TaskManagerHistoryChart(values: values, range: 0...maximum, unit: "", compact: true)
    }
}

private extension Optional where Wrapped == Double {
    var percent: String { map { "\(Int($0.rounded()))%" } ?? "..." }
}

private extension Text {
    func taskManagerSectionTitle() -> some View {
        font(.system(size: 8, design: .monospaced))
            .tracking(1)
            .foregroundStyle(TaskManagerTheme.secondary)
    }
}

#Preview {
    SystemMonitorWindowView().frame(width: 1_070, height: 654)
}
