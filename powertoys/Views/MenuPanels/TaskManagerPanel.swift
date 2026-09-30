import Observation
import OnePlusUI
import SwiftUI

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
                            Text("MB/s").onePlusText(.caption)
                        }
                        menuChart
                    }
                }
            }
            if page != .sensors { detailRows }
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
        case .disk: diskUsedCaption
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

    private var diskUsedCaption: String {
        guard let used = sample?.diskUsed, let total = sample?.diskTotal else { return "—" }
        return "\(TrayPopoverLayout.diskBytes(used)) of \(TrayPopoverLayout.diskBytes(total)) used"
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
        let scaleLabels = [chartScale(ceiling), chartScale(ceiling / 2), page == .sensors ? "Nominal" : "0"]
        return VStack(spacing: OnePlusMetrics.navRowGap) {
            if page == .network {
                Text("MB/s").onePlusText(.caption)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                GeometryReader { proxy in
                    ForEach(scaleLabels.indices, id: \.self) { index in
                        let fraction = CGFloat(index) / CGFloat(scaleLabels.count - 1)
                        let y = min((fraction * proxy.size.height).rounded(.down), (proxy.size.height - 1).rounded(.down)) + 0.5
                        Text(scaleLabels[index])
                            .frame(width: proxy.size.width, alignment: .trailing)
                            .position(x: proxy.size.width / 2, y: y)
                    }
                }.onePlusText(.tableHeader).lineLimit(1)
                .frame(width: [.sensors, .network, .disk].contains(page)
                    ? OnePlusMetrics.titleRow : OnePlusMetrics.compactControlHeight)
                .allowsHitTesting(false)
                TaskManagerHistoryChart(values: primary, secondary: secondary, range: 0...ceiling,
                                        unit: page == .memory ? "GB" : page == .network || page == .disk ? "B/s" : page == .sensors ? "" : "%",
                                        compact: true, stepped: page == .sensors,
                                        primaryColor: page == .memory ? OnePlusColor.accent : OnePlusColor.chartLine)
            }.frame(height: OnePlusMetrics.searchHeight * 2)
                .padding(.vertical, 6)
            HStack { Text("−2 min"); Spacer(); Text("Now") }.onePlusText(.tableHeader)
            if page == .network || page == .disk {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Label(page == .network ? "Download" : "Read", systemImage: "minus")
                        .foregroundStyle(OnePlusColor.chartLine)
                    Label(page == .network ? "Upload" : "Write", systemImage: "minus")
                        .foregroundStyle(OnePlusColor.accent)
                }.onePlusText(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                ("Used", sample?.diskUsed.map(TrayPopoverLayout.diskBytes) ?? "—"),
                ("Available", diskAvailable),
                ("Capacity", sample?.diskTotal.map(TrayPopoverLayout.diskBytes) ?? "—"),
                ("Read", sample?.diskDetails?.readPerSecond.map(Self.rate) ?? "—"),
                ("Write", sample?.diskDetails?.writePerSecond.map(Self.rate) ?? "—"),
            ]
        case .battery:
            batteryPanelRows
        case .sensors, .home, .processes:
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
        return TrayPopoverLayout.diskBytes(max(total - used, 0)) + " free"
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
