import Foundation
import Observation

nonisolated struct TaskManagerMenuChartData: Equatable, Sendable {
    var primary: [Double] = []
    var secondary: [Double] = []
    var ceiling: Double = 100
    var labels = ["100", "50", "0"]
}

nonisolated struct TaskManagerMenuReading: Equatable, Sendable {
    let title: String
    let value: String
}

nonisolated struct TaskManagerMenuPageData: Equatable, Sendable {
    var value = "—"
    var caption = "—"
    var homeValue = "—"
    var homeCaption = "—"
    var homeCaptionHelp: String?
    var upload = "—"
    var charging = false
    var usage: Double = 0
    var accessories: [TaskManagerMenuReading] = []
    var rows: [TaskManagerMenuReading] = []
    var chart = TaskManagerMenuChartData()
}

nonisolated enum TaskManagerMenuProjection {
    static func prepare(sample: SystemMonitorSample?, history: SystemMonitorHistory, staleMetrics: Set<SystemMonitorMenuMetric> = []) -> [SystemMonitorTrayPage: TaskManagerMenuPageData] {
        var pages: [SystemMonitorTrayPage: TaskManagerMenuPageData] = [:]
        let load = sample?.loadAverage.map { decimal($0.0) } ?? "—"
        let used = sample?.memoryUsed.map(bytes) ?? "—"
        let total = sample?.memoryTotal.map(bytes) ?? "—"
        let available = sample.flatMap { s in s.memoryTotal.flatMap { t in s.memoryUsed.map { bytes(max(t - $0, 0)) } } } ?? "—"
        let diskFree = sample.flatMap { s in s.diskTotal.flatMap { t in s.diskUsed.map { TrayPopoverLayout.diskBytes(max(t - $0, 0)) + " free" } } } ?? "—"
        let batteryStatus = sample?.batteryCharging.map { $0 ? "Connected to power" : "On battery" } ?? "—"
        for page in SystemMonitorTrayPage.allCases where page != .home && page != .processes {
            var data = TaskManagerMenuPageData()
            switch page {
            case .cpu:
                data.value = percent(sample?.cpuUsage)
                data.homeCaption = "Load \(load)"
                data.caption = "Across \(ProcessInfo.processInfo.activeProcessorCount) cores"
                data.accessories = [reading("User", percent(sample?.cpuDetails?.user)), reading("System", percent(sample?.cpuDetails?.system))]
                data.rows = [reading("Load · 1 minute", load),
                             reading("Load · 5 minutes", sample?.loadAverage.map { decimal($0.1) } ?? "—"),
                             reading("Load · 15 minutes", sample?.loadAverage.map { decimal($0.2) } ?? "—"),
                             reading("Logical CPUs", String(ProcessInfo.processInfo.activeProcessorCount)),
                             reading("Thermal pressure", sample?.thermalState ?? "—")]
                data.chart.primary = history.samples(for: .cpu).compactMap(\.cpuUsage)
            case .gpu:
                data.value = percent(sample?.gpuUsage)
                data.homeCaption = "Graphics utilization"
                data.caption = "Integrated graphics"
                data.rows = [reading("Graphics utilization", data.value), reading("Memory", "Unified"), reading("Thermal pressure", sample?.thermalState ?? "—")]
                data.chart.primary = history.samples(for: .gpu).compactMap(\.gpuUsage)
            case .memory:
                let allocation = SystemMonitorMemoryAllocation(used: sample?.memoryUsed, total: sample?.memoryTotal, details: sample?.memoryDetails)
                data.value = used
                data.homeValue = percent(sample?.memoryUsage)
                data.homeCaption = memoryPair(used: sample?.memoryUsed, total: sample?.memoryTotal)
                data.homeCaptionHelp = sample?.memoryUsed != nil && sample?.memoryTotal != nil ? "\(used) / \(total)" : "—"
                data.caption = sample?.memoryTotal != nil ? "\(total) unified memory" : "—"
                data.accessories = [reading("Used", data.homeValue)]
                data.rows = [reading("Applications", allocation.map { bytes($0.applications) } ?? "—"), reading("Wired", allocation.map { bytes($0.wired) } ?? "—"),
                             reading("Available", available), reading("Total", total),
                             reading("Compressed", allocation.map { bytes($0.compressed) } ?? "—"),
                             reading("Swap used", sample?.memoryDetails?.swapUsed.map(bytes) ?? "—")]
                data.chart.primary = history.samples(for: .memory).compactMap { $0.memoryUsed.map { Double($0) / 1_073_741_824 } }
                data.chart.ceiling = max(sample?.memoryTotal.map { Double($0) / 1_073_741_824 } ?? 1, 1)
            case .network:
                data.value = sample?.networkDownload.map(rate) ?? "—"
                data.upload = sample?.networkUpload.map(rate) ?? "—"
                data.caption = SystemMonitorNetworkDetails.rateScope
                data.accessories = [reading("Upload", data.upload)]
                data.rows = [reading("Download", data.value), reading("Upload", data.upload), reading("Current interface", sample?.networkDetails?.interfaceName ?? "—"),
                             reading("Local address", sample?.networkDetails?.localAddress ?? "—")]
                data.chart.primary = history.samples(for: .network).compactMap(\.networkDownload)
                data.chart.secondary = history.samples(for: .network).compactMap(\.networkUpload)
            case .disk:
                data.value = percent(sample?.diskUsage)
                data.homeCaption = diskFree
                data.usage = (sample?.diskUsage ?? 0) / 100
                if let used = sample?.diskUsed, let total = sample?.diskTotal {
                    data.caption = "\(TrayPopoverLayout.diskBytes(used)) of \(TrayPopoverLayout.diskBytes(total)) used"
                }
                data.accessories = [reading("Available", diskFree)]
                data.rows = [reading("Used", sample?.diskUsed.map(TrayPopoverLayout.diskBytes) ?? "—"), reading("Available", diskFree),
                             reading("Capacity", sample?.diskTotal.map(TrayPopoverLayout.diskBytes) ?? "—"),
                             reading("Read", sample?.diskDetails?.readPerSecond.map(rate) ?? "—"), reading("Write", sample?.diskDetails?.writePerSecond.map(rate) ?? "—")]
                data.chart.primary = history.samples(for: .disk).compactMap { $0.diskDetails?.readPerSecond }
                data.chart.secondary = history.samples(for: .disk).compactMap { $0.diskDetails?.writePerSecond }
            case .battery:
                data.value = sample?.batteryPercent.map { "\($0)%" } ?? "—"
                data.caption = batteryStatus
                data.charging = sample?.batteryCharging == true
                data.accessories = [reading("Health", sample?.batteryDetails?.health ?? "—")]
                data.rows = [reading("Status", batteryStatus)]
                if let health = sample?.batteryDetails?.health { data.rows.append(reading("Health", health)) }
                if let cycles = sample?.batteryDetails?.cycleCount { data.rows.append(reading("Cycle count", String(cycles))) }
                if let voltage = sample?.batteryDetails?.voltageMillivolts, let amperage = sample?.batteryDetails?.amperageMilliamps {
                    data.rows.append(reading("Power draw", "\(decimal(Double(voltage) * Double(amperage).magnitude / 1_000_000)) W"))
                }
                data.chart.primary = history.samples(for: .battery).compactMap { $0.batteryPercent.map(Double.init) }
            case .sensors:
                data.value = sample?.thermalState ?? "—"
                data.caption = "System-reported state"
                data.chart.primary = history.samples(for: .thermal).compactMap { thermalLevel($0.thermalState) }
            case .home, .processes: break
            }
            if let metric = SystemMonitorMenuMetric(rawValue: page == .sensors ? "thermal" : page.rawValue), staleMetrics.contains(metric) {
                data.rows.append(reading("Reading", "Stale"))
                data.caption = SystemMonitorFreshness.staleHelp
                data.homeCaption = "Stale reading"
                data.homeCaptionHelp = SystemMonitorFreshness.staleHelp
            }
            if page != .memory { data.homeValue = data.value }
            data.chart.primary = data.chart.primary.filter(\.isFinite)
            data.chart.secondary = data.chart.secondary.filter(\.isFinite)
            if page == .network || page == .disk {
                data.chart.ceiling = max((data.chart.primary + data.chart.secondary).max() ?? 1, 1)
            }
            data.chart.labels = [scale(data.chart.ceiling, page: page), scale(data.chart.ceiling / 2, page: page), page == .sensors ? "Nominal" : "0"]
            pages[page] = data
        }
        return pages
    }

    static func homeHistory(_ page: SystemMonitorTrayPage, history: SystemMonitorHistory) -> [Double] {
        switch page {
        case .cpu: history.samples(for: .cpu).compactMap(\.cpuUsage).filter(\.isFinite)
        case .gpu: history.samples(for: .gpu).compactMap(\.gpuUsage).filter(\.isFinite)
        case .memory: history.samples(for: .memory).compactMap(\.memoryUsage).filter(\.isFinite)
        default: []
        }
    }

    private static func reading(_ title: String, _ value: String) -> TaskManagerMenuReading { .init(title: title, value: value) }
    private static func percent(_ value: Double?) -> String { value.flatMap { $0.isFinite ? "\(Int(min(max($0.rounded(), 0), 100)))%" : nil } ?? "—" }
    private static func decimal(_ value: Double) -> String { value.isFinite ? value.formatted(.number.precision(.fractionLength(2))) : "—" }
    private static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: max(value, 0), countStyle: .memory) }
    private static func memoryPair(used: Int64?, total: Int64?) -> String {
        guard let used, let total, total > 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        let index = units.indices.last { Double(total) >= pow(1024, Double($0)) } ?? 0
        let divisor = pow(1024, Double(index))
        let format = FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.significantDigits(1...3))
        return "\((Double(max(used, 0)) / divisor).formatted(format))/\((Double(total) / divisor).formatted(format)) \(units[index])"
    }
    private static func rate(_ value: Double) -> String {
        value.isFinite ? SystemMonitorDisplayFormat.byteRate(min(max(value, 0), Double(Int64.max).nextDown)) : "—"
    }
    private static func scale(_ value: Double, page: SystemMonitorTrayPage) -> String {
        switch page {
        case .network, .disk: (value / 1_000_000).formatted(.number.grouping(.never).precision(.significantDigits(1...3)))
        case .sensors: value == 100 ? "Critical" : ""
        default: value.formatted(.number.precision(.fractionLength(0)))
        }
    }
    private static func thermalLevel(_ state: String?) -> Double? {
        switch state { case "Nominal": 0; case "Fair": 33; case "Serious": 66; case "Critical": 100; default: nil }
    }
}

struct TaskManagerMenuValue: Equatable {
    let value: String
    let unit: String
    init(_ text: String) {
        let parts = TaskManagerMetricText.parts(text)
        value = parts.value
        unit = parts.unit
    }
}

struct TaskManagerMenuHomeData: Equatable {
    let value: TaskManagerMenuValue
    let caption: String
    let captionHelp: String
    let upload: TaskManagerMenuValue
    let charging: Bool
    let history: [Double]
}

struct TaskManagerMenuHeroData: Equatable {
    let value: TaskManagerMenuValue
    let caption: String
    let usage: Double
    let accessories: [TaskManagerMenuReading]
}

@Observable @MainActor
final class TaskManagerMenuPageState {
    var home: TaskManagerMenuHomeData
    var hero: TaskManagerMenuHeroData
    var chart: TaskManagerMenuChartData
    var rows: [TaskManagerMenuReading]

    init(_ data: TaskManagerMenuPageData, history: [Double]) {
        home = Self.home(data, history: history)
        hero = Self.hero(data)
        chart = data.chart
        rows = data.rows
    }

    func apply(_ data: TaskManagerMenuPageData, history: [Double]) {
        let nextHome = Self.home(data, history: history)
        let nextHero = Self.hero(data)
        if home != nextHome { home = nextHome }
        if hero != nextHero { hero = nextHero }
        if chart != data.chart { chart = data.chart }
        if rows != data.rows { rows = data.rows }
    }

    private static func home(_ data: TaskManagerMenuPageData, history: [Double]) -> TaskManagerMenuHomeData {
        .init(value: .init(data.homeValue), caption: data.homeCaption, captionHelp: data.homeCaptionHelp ?? data.homeCaption,
              upload: .init(data.upload), charging: data.charging, history: history)
    }
    private static func hero(_ data: TaskManagerMenuPageData) -> TaskManagerMenuHeroData {
        .init(value: .init(data.value), caption: data.caption, usage: data.usage, accessories: data.accessories)
    }
}

@MainActor
final class TaskManagerMenuPresentation {
    static let minimumUpdateInterval: Duration = .milliseconds(250)
    let pages: [SystemMonitorTrayPage: TaskManagerMenuPageState]
    private let service: SystemMonitorService
    private var active = false
    private var isObserving = false
    private var generation = 0
    private var pending: (sample: SystemMonitorSample?, history: SystemMonitorHistory, stale: Set<SystemMonitorMenuMetric>)?
    private var preparation: Task<Void, Never>?
    private var lastPublication: ContinuousClock.Instant?

    init(service: SystemMonitorService = .shared) {
        self.service = service
        let history = service.history
        pages = TaskManagerMenuProjection.prepare(sample: service.snapshot, history: history, staleMetrics: service.staleMetrics).mapValues { data in
            TaskManagerMenuPageState(data, history: [])
        }
        for (page, state) in pages {
            state.home = .init(value: state.home.value, caption: state.home.caption, captionHelp: state.home.captionHelp, upload: state.home.upload,
                               charging: state.home.charging, history: TaskManagerMenuProjection.homeHistory(page, history: history))
        }
    }

    func start() {
        guard !active else { return }
        active = true
        generation &+= 1
        observe()
        schedule()
    }

    func stop() {
        active = false
        generation &+= 1
        preparation?.cancel()
        preparation = nil
        pending = nil
    }

    private func observe() {
        guard active else { return }
        pending = (service.snapshot, service.history, service.staleMetrics)
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = service.snapshot
            _ = service.history
            _ = service.staleMetrics
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                guard self.active else { return }
                self.observe()
                self.schedule()
            }
        }
    }

    private func schedule() {
        guard active, preparation == nil else { return }
        let generation = generation
        preparation = Task { [weak self] in
            guard let self else { return }
            if let lastPublication {
                try? await Task.sleep(until: lastPublication.advanced(by: Self.minimumUpdateInterval), clock: .continuous)
            }
            guard !Task.isCancelled, let input = pending else { return }
            pending = nil
            let result = await Task.detached(priority: .userInitiated) {
                TaskManagerMenuProjection.prepare(sample: input.sample, history: input.history, staleMetrics: input.stale)
            }.value
            guard !Task.isCancelled, active, self.generation == generation else { return }
            for (page, data) in result {
                pages[page]?.apply(data, history: TaskManagerMenuProjection.homeHistory(page, history: input.history))
            }
            lastPublication = .now
            preparation = nil
            if pending != nil { schedule() }
        }
    }
}
