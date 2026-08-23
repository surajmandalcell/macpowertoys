import SwiftUI

private enum PowerStatsPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processor = "Processor"
    case memory = "Memory"
    case network = "Network & Disk"
    case menuBar = "Menu Bar"
    case about = "About"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .processor: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .menuBar: "menubar.rectangle"
        case .about: "info.circle"
        }
    }
}

struct PowerStatsWindowView: View {
    @State private var service = PowerStatsService.shared
    @State private var page = PowerStatsPage.overview

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 240)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "power-stats"))
        .onAppear { service.startDetailed() }
        .onDisappear { service.stopDetailed() }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar)
            SidebarTitle(text: "Power Stats")
            VStack(spacing: 4) {
                ForEach(PowerStatsPage.allCases) { item in
                    SidebarRow(icon: item.icon, title: item.rawValue, isSelected: page == item) {
                        page = item
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(service.detailedActive ? Color.green : Color.secondary).frame(width: 7, height: 7)
                    Text(service.detailedActive ? "Detailed sampling active" : "Sampling stopped")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
            }
            .padding(.horizontal, 12)
            .padding(.top, 52)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .overview: overviewPage
        case .processor: processorPage
        case .memory: memoryPage
        case .network: networkPage
        case .menuBar: menuBarPage
        case .about: ToolAboutView(toolId: "power-stats")
        }
    }

    private var overviewPage: some View {
        pageView(title: "Power Stats", subtitle: "Live detail while this window is open") {
            metricGrid
            VStack(alignment: .leading, spacing: 10) {
                Text("LAST TWO MINUTES").utilitySectionHeader()
                HStack(spacing: 12) {
                    chartCard(title: "CPU", suffix: "%", values: service.history.compactMap(\.cpuUsage))
                    chartCard(title: "Memory", suffix: "%", values: service.history.compactMap(\.memoryUsage))
                    chartCard(
                        title: "Download",
                        suffix: "/s",
                        values: service.history.compactMap(\.networkDownload),
                        formatter: Self.rate
                    )
                }
            }
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            metricCard(
                icon: "cpu",
                title: "CPU",
                value: service.snapshot?.cpuUsage.percent ?? "Priming…",
                detail: loadDetail
            )
            metricCard(
                icon: "memorychip",
                title: "Memory",
                value: service.snapshot?.memoryUsage.percent ?? "—",
                detail: memoryDetail
            )
            metricCard(
                icon: "internaldrive",
                title: "Disk",
                value: service.snapshot?.diskUsage.percent ?? "—",
                detail: diskDetail
            )
            metricCard(
                icon: "arrow.down.circle",
                title: "Network",
                value: service.snapshot?.networkDownload.map(Self.rate) ?? "Priming…",
                detail: "Upload \(service.snapshot?.networkUpload.map(Self.rate) ?? "—")"
            )
            metricCard(
                icon: "thermometer.medium",
                title: "Thermal",
                value: service.snapshot?.thermalState ?? "—",
                detail: "Public macOS thermal state"
            )
            metricCard(
                icon: "battery.75percent",
                title: "Battery",
                value: service.snapshot?.batteryPercent.map { "\($0)%" } ?? "Not available",
                detail: batteryDetail
            )
        }
    }

    private func metricCard(icon: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chartCard(
        title: String,
        suffix: String,
        values: [Double],
        formatter: (Double) -> String = { "\(Int($0.rounded()))" }
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(values.last.map { formatter($0) + suffix } ?? "—")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            StatsSparkline(values: values)
                .frame(height: 100)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var processorPage: some View {
        pageView(title: "Processor", subtitle: "Aggregate public Mach host counters") {
            HStack(spacing: 12) {
                metricCard(icon: "cpu", title: "Usage", value: service.snapshot?.cpuUsage.percent ?? "Priming…", detail: "User + system + nice")
                metricCard(icon: "chart.bar", title: "Load Average", value: loadAverage, detail: "1, 5, and 15 minute run queue")
                metricCard(icon: "thermometer.medium", title: "Thermal", value: service.snapshot?.thermalState ?? "—", detail: "System thermal pressure")
            }
            chartCard(title: "CPU Usage", suffix: "%", values: service.history.compactMap(\.cpuUsage))
            unavailableNote("Per-process and GPU polling are omitted from the one-second sampler because macOS has no stable low-cost public aggregate GPU API.")
        }
    }

    private var memoryPage: some View {
        pageView(title: "Memory", subtitle: "Active, inactive, wired, and compressed host pages") {
            HStack(spacing: 12) {
                metricCard(icon: "memorychip", title: "Used", value: service.snapshot?.memoryUsed.map(\.bytes) ?? "—", detail: memoryDetail)
                metricCard(icon: "square.stack.3d.up", title: "Physical", value: service.snapshot?.memoryTotal.map(\.bytes) ?? "—", detail: "Installed unified memory")
                metricCard(icon: "gauge.with.dots.needle.50percent", title: "Utilization", value: service.snapshot?.memoryUsage.percent ?? "—", detail: "Free memory alone is not a health score")
            }
            chartCard(title: "Memory Utilization", suffix: "%", values: service.history.compactMap(\.memoryUsage))
        }
    }

    private var networkPage: some View {
        pageView(title: "Network & Disk", subtitle: "Delta network counters and local startup-volume capacity") {
            HStack(spacing: 12) {
                metricCard(icon: "arrow.down", title: "Download", value: service.snapshot?.networkDownload.map(Self.rate) ?? "Priming…", detail: "All active non-loopback interfaces")
                metricCard(icon: "arrow.up", title: "Upload", value: service.snapshot?.networkUpload.map(Self.rate) ?? "Priming…", detail: "All active non-loopback interfaces")
                metricCard(icon: "internaldrive", title: "Disk Used", value: service.snapshot?.diskUsed.map(\.bytes) ?? "—", detail: diskDetail)
            }
            HStack(spacing: 12) {
                chartCard(title: "Download", suffix: "/s", values: service.history.compactMap(\.networkDownload), formatter: Self.rate)
                chartCard(title: "Upload", suffix: "/s", values: service.history.compactMap(\.networkUpload), formatter: Self.rate)
            }
            unavailableNote("Disk throughput, fan speed, and sensor temperatures are not shown without a stable public macOS source.")
        }
    }

    private var menuBarPage: some View {
        pageView(title: "Menu Bar", subtitle: "A separate lightweight sampler only when you enable it") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Show Power Stats in the menu bar", isOn: menuSetting(
                    get: { $0.enabled },
                    set: { $0.enabled = $1 }
                ))
                .font(.system(size: 13, weight: .medium))

                Picker("Layout", selection: menuSetting(
                    get: { $0.mode },
                    set: { $0.mode = $1 }
                )) {
                    ForEach(PowerMenuMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Picker("Update every", selection: menuSetting(
                    get: { $0.interval },
                    set: { $0.interval = $1 }
                )) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                .frame(maxWidth: 260)

                Text("METRICS").utilitySectionHeader()
                HStack(spacing: 18) {
                    ForEach(PowerMenuMetric.allCases) { metric in
                        Toggle(metric.title, isOn: metricBinding(metric)).toggleStyle(.checkbox)
                    }
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Grouped uses one status item. Individual creates one item per selected metric. The menu sampler never collects disk, battery, thermal, process, or history data.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func unavailableNote(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var loadDetail: String {
        service.snapshot?.loadAverage.map { "Load \($0.0.formatted(.number.precision(.fractionLength(2))))" } ?? "Waiting for first delta"
    }

    private var loadAverage: String {
        service.snapshot?.loadAverage.map {
            [$0.0, $0.1, $0.2].map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: " · ")
        } ?? "—"
    }

    private var memoryDetail: String {
        guard let used = service.snapshot?.memoryUsed, let total = service.snapshot?.memoryTotal else { return "Host memory counters" }
        return "\(used.bytes) of \(total.bytes)"
    }

    private var diskDetail: String {
        guard let used = service.snapshot?.diskUsed, let total = service.snapshot?.diskTotal else { return "Startup volume" }
        return "\(used.bytes) of \(total.bytes)"
    }

    private var batteryDetail: String {
        guard service.snapshot?.batteryPercent != nil else { return "No internal battery detected" }
        return service.snapshot?.batteryCharging == true ? "Connected to power" : "On battery"
    }

    private func pageView<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 22, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                content()
            }
            .padding(20)
            .padding(.top, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .thinScrollIndicators()
    }

    private func menuSetting<Value>(
        get: @escaping (PowerStatsMenuSettings) -> Value,
        set: @escaping (inout PowerStatsMenuSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(service.menuSettings) },
            set: { value in service.updateMenuSettings { set(&$0, value) } }
        )
    }

    private func metricBinding(_ metric: PowerMenuMetric) -> Binding<Bool> {
        Binding(
            get: { service.menuSettings.metrics.contains(metric) },
            set: { enabled in
                service.updateMenuSettings {
                    if enabled { $0.metrics.insert(metric) }
                    else { $0.metrics.remove(metric) }
                }
            }
        )
    }

    nonisolated private static func rate(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 0)), countStyle: .file)
    }
}

private struct StatsSparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maximum = values.max(), let minimum = values.min() else { return }
            let range = max(maximum - minimum, 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
                    y: size.height - CGFloat((value - minimum) / range) * size.height
                )
                if index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Recent \(values.last?.formatted() ?? "unavailable")")
    }
}

private extension Optional where Wrapped == Double {
    var percent: String { map { "\(Int($0.rounded()))%" } ?? "—" }
}

private extension Int64 {
    var bytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .memory) }
}

#Preview {
    PowerStatsWindowView().frame(width: 1080, height: 720)
}
