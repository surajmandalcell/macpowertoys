import AppKit
import Darwin
import Foundation
import IOKit.ps

nonisolated enum PowerMenuMode: String, Codable, CaseIterable, Identifiable {
    case grouped
    case direct

    var id: String { rawValue }
    var title: String { self == .grouped ? "Grouped" : "Individual" }
}

nonisolated enum PowerMenuMetric: String, Codable, CaseIterable, Identifiable, Hashable {
    case cpu
    case memory
    case network

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        }
    }
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        }
    }
}

nonisolated struct PowerStatsMenuSettings: Codable, Equatable {
    var enabled = false
    var mode = PowerMenuMode.grouped
    var interval = 2.0
    var metrics: Set<PowerMenuMetric> = [.cpu, .memory]
}

nonisolated struct PowerStatsSample: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let cpuUsage: Double?
    let memoryUsed: Int64?
    let memoryTotal: Int64?
    let networkDownload: Double?
    let networkUpload: Double?
    let diskUsed: Int64?
    let diskTotal: Int64?
    let batteryPercent: Int?
    let batteryCharging: Bool?
    let thermalState: String?
    let loadAverage: (Double, Double, Double)?

    var memoryUsage: Double? {
        guard let memoryUsed, let memoryTotal, memoryTotal > 0 else { return nil }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }

    var diskUsage: Double? {
        guard let diskUsed, let diskTotal, diskTotal > 0 else { return nil }
        return Double(diskUsed) / Double(diskTotal) * 100
    }
}

nonisolated enum PowerStatsDelta {
    static func cpuUsage(previous: (total: UInt64, idle: UInt64), current: (total: UInt64, idle: UInt64)) -> Double? {
        guard current.total >= previous.total, current.idle >= previous.idle else { return nil }
        let total = current.total - previous.total
        guard total > 0 else { return nil }
        let idle = current.idle - previous.idle
        return min(max(Double(total - min(idle, total)) / Double(total) * 100, 0), 100)
    }

    static func rate(previous: UInt64, current: UInt64, seconds: TimeInterval) -> Double? {
        guard seconds > 0, current >= previous else { return nil }
        return Double(current - previous) / seconds
    }
}

nonisolated private struct PowerRawSample {
    let timestamp: Date
    let cpu: (total: UInt64, idle: UInt64)?
    let network: (received: UInt64, sent: UInt64)?
}

nonisolated private final class PowerStatsSampler: @unchecked Sendable {
    private var previous: PowerRawSample?

    func reset() {
        previous = nil
    }

    func sample(detailed: Bool, metrics: Set<PowerMenuMetric>) -> PowerStatsSample {
        let now = Date()
        let needsCPU = detailed || metrics.contains(.cpu)
        let needsMemory = detailed || metrics.contains(.memory)
        let needsNetwork = detailed || metrics.contains(.network)
        let cpu = needsCPU ? Self.cpuCounters() : nil
        let network = needsNetwork ? Self.networkCounters() : nil
        let raw = PowerRawSample(timestamp: now, cpu: cpu, network: network)
        let elapsed = previous.map { now.timeIntervalSince($0.timestamp) } ?? 0
        let cpuUsage = previous?.cpu.flatMap { prior in
            cpu.flatMap { PowerStatsDelta.cpuUsage(previous: prior, current: $0) }
        }
        let download = previous?.network.flatMap { prior in
            network.flatMap { PowerStatsDelta.rate(previous: prior.received, current: $0.received, seconds: elapsed) }
        }
        let upload = previous?.network.flatMap { prior in
            network.flatMap { PowerStatsDelta.rate(previous: prior.sent, current: $0.sent, seconds: elapsed) }
        }
        previous = raw

        let memory = needsMemory ? Self.memoryUsage() : nil
        let disk = detailed ? Self.diskUsage() : nil
        let battery = detailed ? Self.battery() : nil
        var loads = [Double](repeating: 0, count: 3)
        let loadCount = detailed ? getloadavg(&loads, 3) : 0

        return PowerStatsSample(
            timestamp: now,
            cpuUsage: cpuUsage,
            memoryUsed: memory?.used,
            memoryTotal: memory?.total,
            networkDownload: download,
            networkUpload: upload,
            diskUsed: disk?.used,
            diskTotal: disk?.total,
            batteryPercent: battery?.percent,
            batteryCharging: battery?.charging,
            thermalState: detailed ? Self.thermalState() : nil,
            loadAverage: loadCount == 3 ? (loads[0], loads[1], loads[2]) : nil
        )
    }

    private static func cpuCounters() -> (total: UInt64, idle: UInt64)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = withUnsafeBytes(of: info.cpu_ticks) { Array($0.bindMemory(to: UInt32.self)) }
        guard ticks.count > Int(CPU_STATE_IDLE) else { return nil }
        let total = ticks.reduce(UInt64(0)) { $0 + UInt64($1) }
        return (total, UInt64(ticks[Int(CPU_STATE_IDLE)]))
    }

    private static func memoryUsage() -> (used: Int64, total: Int64)? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let usedPages = UInt64(info.active_count) + UInt64(info.inactive_count)
            + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let total = min(ProcessInfo.processInfo.physicalMemory, UInt64(Int64.max))
        return (Int64(min(usedPages * UInt64(pageSize), total)), Int64(total))
    }

    private static func networkCounters() -> (received: UInt64, sent: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var address: UnsafeMutablePointer<ifaddrs>? = first
        while let current = address {
            let interface = current.pointee
            if interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                received += UInt64(data.pointee.ifi_ibytes)
                sent += UInt64(data.pointee.ifi_obytes)
            }
            address = interface.ifa_next
        }
        return (received, sent)
    }

    private static func diskUsage() -> (used: Int64, total: Int64)? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ])
        guard let totalValue = values?.volumeTotalCapacity,
              let availableValue = values?.volumeAvailableCapacity else { return nil }
        let total = Int64(totalValue)
        return (max(total - Int64(availableValue), 0), total)
    }

    private static func battery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            return (Int((Double(current) / Double(maximum) * 100).rounded()), state == kIOPSACPowerValue)
        }
        return nil
    }

    private static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

@Observable
@MainActor
final class PowerStatsService {
    static let shared = PowerStatsService()

    private static let settingsKey = "powerStats.menuSettings"
    nonisolated static let maximumHistoryCount = 120

    private(set) var snapshot: PowerStatsSample?
    private(set) var history: [PowerStatsSample] = []
    private(set) var detailedActive = false
    private(set) var menuSettings: PowerStatsMenuSettings

    private let sampler = PowerStatsSampler()
    private let samplingQueue = DispatchQueue(label: "com.surajmandal.macpowertoys.power-stats", qos: .utility)
    private let menuController = PowerStatsMenuController()
    private var timer: DispatchSourceTimer?
    private var toolEnabled = true
    private var generation = 0
    private var lastMenuUpdate: Date?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(PowerStatsMenuSettings.self, from: data) {
            menuSettings = decoded
        } else {
            menuSettings = PowerStatsMenuSettings()
        }
    }

    deinit {
        MainActor.assumeIsolated { stopTimer() }
    }

    func startFromStoredSettings() {
        toolEnabled = SettingsManager.shared.isToolEnabled("power-stats")
        reconfigure()
    }

    func startDetailed() {
        detailedActive = true
        reconfigure()
    }

    func stopDetailed() {
        detailedActive = false
        reconfigure()
    }

    func updateMenuSettings(_ change: (inout PowerStatsMenuSettings) -> Void) {
        change(&menuSettings)
        if menuSettings.metrics.isEmpty { menuSettings.metrics = [.cpu] }
        if let data = try? JSONEncoder().encode(menuSettings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        reconfigure()
    }

    func setToolEnabled(_ enabled: Bool) {
        toolEnabled = enabled
        if !enabled { detailedActive = false }
        reconfigure()
    }

    private func reconfigure() {
        stopTimer()
        generation += 1
        lastMenuUpdate = nil
        let menuActive = toolEnabled && menuSettings.enabled
        menuController.configure(settings: menuActive ? menuSettings : PowerStatsMenuSettings())
        guard toolEnabled && (detailedActive || menuActive) else { return }

        let interval = detailedActive ? 1.0 : menuSettings.interval
        let detail = detailedActive
        let metrics = menuActive ? menuSettings.metrics : []
        let currentGeneration = generation
        samplingQueue.sync { sampler.reset() }
        let source = DispatchSource.makeTimerSource(queue: samplingQueue)
        source.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .milliseconds(Int(interval * 150))
        )
        source.setEventHandler { [weak self, sampler] in
            let sample = sampler.sample(detailed: detail, metrics: metrics)
            Task { @MainActor [weak self] in
                self?.receive(sample, detailed: detail, generation: currentGeneration)
            }
        }
        timer = source
        source.resume()
    }

    private func receive(_ sample: PowerStatsSample, detailed: Bool, generation: Int) {
        guard generation == self.generation else { return }
        snapshot = sample
        if detailed {
            history.append(sample)
            if history.count > Self.maximumHistoryCount {
                history.removeFirst(history.count - Self.maximumHistoryCount)
            }
        }
        if toolEnabled && menuSettings.enabled,
           lastMenuUpdate.map({ sample.timestamp.timeIntervalSince($0) >= menuSettings.interval * 0.9 }) ?? true {
            lastMenuUpdate = sample.timestamp
            menuController.update(sample: sample)
        }
    }

    private func stopTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}

@MainActor
private final class PowerStatsMenuController: NSObject {
    private var statusItems: [String: NSStatusItem] = [:]
    private var settings = PowerStatsMenuSettings()

    func configure(settings: PowerStatsMenuSettings) {
        guard settings != self.settings else { return }
        statusItems.values.forEach(NSStatusBar.system.removeStatusItem)
        statusItems.removeAll()
        self.settings = settings
        guard settings.enabled else { return }

        if settings.mode == .grouped {
            statusItems["group"] = makeStatusItem(symbol: "gauge.with.dots.needle.50percent")
        } else {
            for metric in settings.metrics.sorted(by: { $0.rawValue < $1.rawValue }) {
                statusItems[metric.rawValue] = makeStatusItem(symbol: metric.symbol)
            }
        }
        update(sample: nil)
    }

    func update(sample: PowerStatsSample?) {
        guard settings.enabled else { return }
        if settings.mode == .grouped {
            statusItems["group"]?.button?.title = settings.metrics
                .sorted(by: { $0.rawValue < $1.rawValue })
                .map { label(for: $0, sample: sample) }
                .joined(separator: " · ")
        } else {
            for metric in settings.metrics {
                statusItems[metric.rawValue]?.button?.title = value(for: metric, sample: sample)
            }
        }
    }

    private func makeStatusItem(symbol: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Power Stats")
        item.button?.target = self
        item.button?.action = #selector(openPowerStats)
        item.button?.sendAction(on: [.leftMouseUp])
        item.button?.toolTip = "Open Power Stats"
        return item
    }

    private func label(for metric: PowerMenuMetric, sample: PowerStatsSample?) -> String {
        "\(metric.title) \(value(for: metric, sample: sample))"
    }

    private func value(for metric: PowerMenuMetric, sample: PowerStatsSample?) -> String {
        switch metric {
        case .cpu:
            sample?.cpuUsage.map { "\(Int($0.rounded()))%" } ?? "Waiting"
        case .memory:
            sample?.memoryUsage.map { "\(Int($0.rounded()))%" } ?? "Waiting"
        case .network:
            sample?.networkDownload.map { "↓\(Self.rate($0))" } ?? "↓Waiting"
        }
    }

    nonisolated private static func rate(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 0)), countStyle: .file) + "/s"
    }

    @objc private func openPowerStats() {
        ToolActionRouter.shared.open(toolID: "power-stats")
    }
}
