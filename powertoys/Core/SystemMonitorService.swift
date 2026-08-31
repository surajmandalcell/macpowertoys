import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps

nonisolated enum SystemMonitorMenuMode: String, Codable, CaseIterable, Identifiable {
    case grouped, direct
    var id: String { rawValue }
    var title: String { self == .grouped ? "Grouped" : "Individual" }
}

nonisolated enum SystemMonitorMenuMetric: String, Codable, CaseIterable, Identifiable, Hashable {
    case cpu, memory, gpu, disk, network, battery, thermal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .disk: "Disk"
        case .network: "Network"
        case .battery: "Battery"
        case .thermal: "Thermal"
        }
    }
    var symbol: String { symbols[0] }
    var symbols: [String] {
        switch self {
        case .cpu: ["cpu", "gauge.with.dots.needle.50percent", "waveform.path.ecg"]
        case .memory: ["memorychip", "square.stack.3d.up", "chart.bar.fill"]
        case .gpu: ["display", "rectangle.3.group", "sparkles.rectangle.stack"]
        case .disk: ["internaldrive", "externaldrive", "chart.pie.fill"]
        case .network: ["arrow.up.arrow.down", "network", "antenna.radiowaves.left.and.right"]
        case .battery: ["battery.75percent", "bolt.fill", "battery.100percent"]
        case .thermal: ["thermometer.medium", "thermometer.high", "flame.fill"]
        }
    }
    var defaultInterval: SystemMonitorMenuInterval {
        switch self {
        case .gpu: .seconds5
        case .disk, .battery, .thermal: .seconds30
        case .cpu, .memory, .network: .global
        }
    }

    var minimumInterval: TimeInterval {
        switch self {
        case .disk: 15
        case .battery, .thermal: 10
        case .cpu, .memory, .gpu, .network: 1
        }
    }

    func supportedIntervals(global: TimeInterval) -> [SystemMonitorMenuInterval] {
        switch self {
        case .cpu, .memory, .gpu, .network:
            return SystemMonitorMenuInterval.allCases
        case .disk:
            return (global >= minimumInterval ? [.global] : []) + [.seconds30, .seconds60]
        case .battery, .thermal:
            return (global >= minimumInterval ? [.global] : []) + [.seconds10, .seconds30, .seconds60]
        }
    }

    func normalizedInterval(_ selected: SystemMonitorMenuInterval, global: TimeInterval) -> SystemMonitorMenuInterval {
        let supported = supportedIntervals(global: global)
        guard !supported.contains(selected) else { return selected }
        let target = selected.seconds(global: global)
        return supported.min {
            let left = abs($0.seconds(global: global) - target)
            let right = abs($1.seconds(global: global) - target)
            return left == right ? $0.seconds(global: global) < $1.seconds(global: global) : left < right
        } ?? defaultInterval
    }
}

nonisolated enum SystemMonitorMenuItemStyle: String, Codable, CaseIterable, Identifiable {
    case iconAndValue, iconOnly, valueOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconAndValue: "Icon and Value"
        case .iconOnly: "Icon Only"
        case .valueOnly: "Value Only"
        }
    }
}

nonisolated enum SystemMonitorMenuInterval: String, Codable, CaseIterable, Identifiable {
    case global, seconds1, seconds2, seconds3, seconds5, seconds10, seconds30, seconds60
    var id: String { rawValue }
    var title: String {
        switch self {
        case .global: "Global"
        case .seconds1: "1 second"
        case .seconds2: "2 seconds"
        case .seconds3: "3 seconds"
        case .seconds5: "5 seconds"
        case .seconds10: "10 seconds"
        case .seconds30: "30 seconds"
        case .seconds60: "60 seconds"
        }
    }
    func seconds(global: TimeInterval) -> TimeInterval {
        switch self {
        case .global: Self.allowedSeconds.contains(global) ? global : 2
        case .seconds1: 1
        case .seconds2: 2
        case .seconds3: 3
        case .seconds5: 5
        case .seconds10: 10
        case .seconds30: 30
        case .seconds60: 60
        }
    }
    static let allowedSeconds: [TimeInterval] = [1, 2, 3, 5, 10, 30, 60]
}

nonisolated enum SystemMonitorMemoryUnit: String, Codable, CaseIterable, Identifiable {
    case percentage, used, available
    var id: String { rawValue }
    var title: String {
        switch self {
        case .percentage: "Percentage"
        case .used: "Used"
        case .available: "Available"
        }
    }
}

nonisolated enum SystemMonitorNetworkDirection: String, Codable, CaseIterable, Identifiable {
    case both, download, upload
    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: "Download and Upload"
        case .download: "Download"
        case .upload: "Upload"
        }
    }
}

nonisolated enum SystemMonitorDiskUnit: String, Codable, CaseIterable, Identifiable {
    case percentage, used, available
    var id: String { rawValue }
    var title: String {
        switch self {
        case .percentage: "Percentage"
        case .used: "Used"
        case .available: "Available"
        }
    }
}

nonisolated enum SystemMonitorNetworkUnit: String, Codable, CaseIterable, Identifiable {
    case bytes, bits
    var id: String { rawValue }
    var title: String { self == .bytes ? "Bytes per Second" : "Bits per Second" }
}

nonisolated enum SystemMonitorBatteryDisplay: String, Codable, CaseIterable, Identifiable {
    case percentage, status, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .percentage: "Percentage"
        case .status: "Status"
        case .both: "Percentage and Status"
        }
    }
}

nonisolated enum SystemMonitorThermalDisplay: String, Codable, CaseIterable, Identifiable {
    case compact, full
    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Full" }
}

nonisolated struct SystemMonitorMenuItemConfiguration: Codable, Equatable, Identifiable {
    var metric: SystemMonitorMenuMetric
    var enabled: Bool
    var style: SystemMonitorMenuItemStyle
    var symbol: String
    var interval: SystemMonitorMenuInterval
    var memoryUnit: SystemMonitorMemoryUnit
    var networkDirection: SystemMonitorNetworkDirection
    var diskUnit: SystemMonitorDiskUnit
    var networkUnit: SystemMonitorNetworkUnit
    var batteryDisplay: SystemMonitorBatteryDisplay
    var thermalDisplay: SystemMonitorThermalDisplay
    var id: SystemMonitorMenuMetric { metric }

    init(
        metric: SystemMonitorMenuMetric,
        enabled: Bool = false,
        style: SystemMonitorMenuItemStyle = .iconAndValue,
        symbol: String? = nil,
        interval: SystemMonitorMenuInterval? = nil,
        memoryUnit: SystemMonitorMemoryUnit = .percentage,
        networkDirection: SystemMonitorNetworkDirection = .both,
        diskUnit: SystemMonitorDiskUnit = .percentage,
        networkUnit: SystemMonitorNetworkUnit = .bytes,
        batteryDisplay: SystemMonitorBatteryDisplay = .percentage,
        thermalDisplay: SystemMonitorThermalDisplay = .compact
    ) {
        self.metric = metric
        self.enabled = enabled
        self.style = style
        self.symbol = symbol ?? metric.symbol
        self.interval = interval ?? metric.defaultInterval
        self.memoryUnit = memoryUnit
        self.networkDirection = networkDirection
        self.diskUnit = diskUnit
        self.networkUnit = networkUnit
        self.batteryDisplay = batteryDisplay
        self.thermalDisplay = thermalDisplay
    }

    func effectiveInterval(global: TimeInterval) -> TimeInterval {
        max(interval.seconds(global: global), metric.minimumInterval)
    }

    private enum CodingKeys: String, CodingKey {
        case metric, enabled, style, symbol, interval, memoryUnit, networkDirection
        case diskUnit, networkUnit, batteryDisplay, thermalDisplay
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        metric = try values.decode(SystemMonitorMenuMetric.self, forKey: .metric)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        style = try values.decodeIfPresent(SystemMonitorMenuItemStyle.self, forKey: .style) ?? .iconAndValue
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? metric.symbol
        interval = try values.decodeIfPresent(SystemMonitorMenuInterval.self, forKey: .interval) ?? metric.defaultInterval
        memoryUnit = try values.decodeIfPresent(SystemMonitorMemoryUnit.self, forKey: .memoryUnit) ?? .percentage
        networkDirection = try values.decodeIfPresent(SystemMonitorNetworkDirection.self, forKey: .networkDirection) ?? .both
        diskUnit = try values.decodeIfPresent(SystemMonitorDiskUnit.self, forKey: .diskUnit) ?? .percentage
        networkUnit = try values.decodeIfPresent(SystemMonitorNetworkUnit.self, forKey: .networkUnit) ?? .bytes
        batteryDisplay = try values.decodeIfPresent(SystemMonitorBatteryDisplay.self, forKey: .batteryDisplay) ?? .percentage
        thermalDisplay = try values.decodeIfPresent(SystemMonitorThermalDisplay.self, forKey: .thermalDisplay) ?? .compact
    }
}

nonisolated struct SystemMonitorMenuSettings: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var enabled: Bool
    var mode: SystemMonitorMenuMode
    var interval: TimeInterval
    var items: [SystemMonitorMenuItemConfiguration]

    init(schemaVersion: Int = Self.currentSchemaVersion,
         enabled: Bool = false, mode: SystemMonitorMenuMode = .grouped, interval: TimeInterval = 2,
         items: [SystemMonitorMenuItemConfiguration] = Self.defaultItems) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.mode = mode
        self.interval = interval
        self.items = items
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(mode, forKey: .mode)
        try values.encode(interval, forKey: .interval)
        try values.encode(items, forKey: .items)
    }

    init(enabled: Bool, mode: SystemMonitorMenuMode, interval: TimeInterval,
         metrics: Set<SystemMonitorMenuMetric>) {
        schemaVersion = Self.currentSchemaVersion
        self.enabled = enabled
        self.mode = mode
        self.interval = interval
        items = Self.migratedItems(from: metrics)
        normalize()
    }

    var enabledItems: [SystemMonitorMenuItemConfiguration] { items.filter(\.enabled) }

    mutating func normalize() {
        interval = SystemMonitorMenuInterval.allowedSeconds.contains(interval) ? interval : 2
        var seen = Set<SystemMonitorMenuMetric>()
        items = items.filter { seen.insert($0.metric).inserted }
        for metric in SystemMonitorMenuMetric.allCases where !seen.contains(metric) {
            items.append(SystemMonitorMenuItemConfiguration(metric: metric))
        }
        for index in items.indices where !items[index].metric.symbols.contains(items[index].symbol) {
            items[index].symbol = items[index].metric.symbol
        }
        for index in items.indices {
            items[index].interval = items[index].metric.normalizedInterval(items[index].interval, global: interval)
        }
    }

    func applying(_ change: (inout SystemMonitorMenuSettings) -> Void) -> SystemMonitorMenuSettings? {
        var updated = self
        change(&updated)
        updated.normalize()
        return updated == self ? nil : updated
    }

    static let defaultItems = SystemMonitorMenuMetric.allCases.map {
        SystemMonitorMenuItemConfiguration(metric: $0, enabled: $0 == .cpu || $0 == .memory)
    }

    private static func migratedItems(from metrics: Set<SystemMonitorMenuMetric>) -> [SystemMonitorMenuItemConfiguration] {
        SystemMonitorMenuMetric.allCases.map {
            SystemMonitorMenuItemConfiguration(metric: $0, enabled: metrics.contains($0),
                                               interval: metrics.contains($0) ? .global : nil)
        }
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, enabled, mode, interval, items, metrics }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        _ = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = Self.currentSchemaVersion
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try values.decodeIfPresent(SystemMonitorMenuMode.self, forKey: .mode) ?? .grouped
        interval = try values.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 2
        if let decoded = try values.decodeIfPresent([SystemMonitorMenuItemConfiguration].self, forKey: .items) {
            items = decoded
        } else {
            items = Self.migratedItems(from: try values.decodeIfPresent(Set<SystemMonitorMenuMetric>.self, forKey: .metrics)
                                       ?? [.cpu, .memory])
        }
        normalize()
    }
}

nonisolated struct SystemMonitorSample: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let cpuUsage: Double?
    let memoryUsed: Int64?
    let memoryTotal: Int64?
    let gpuUsage: Double?
    let networkDownload: Double?
    let networkUpload: Double?
    let diskUsed: Int64?
    let diskTotal: Int64?
    let batteryPercent: Int?
    let batteryCharging: Bool?
    let thermalState: String?
    let loadAverage: (Double, Double, Double)?
    let unavailableMetrics: Set<SystemMonitorMenuMetric>

    var memoryUsage: Double? {
        guard let memoryUsed, let memoryTotal, memoryTotal > 0 else { return nil }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }
    var diskUsage: Double? {
        guard let diskUsed, let diskTotal, diskTotal > 0 else { return nil }
        return Double(diskUsed) / Double(diskTotal) * 100
    }
}

nonisolated enum SystemMonitorDelta {
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

nonisolated enum SystemMonitorMenuSchedule {
    static func timerInterval(
        settings: SystemMonitorMenuSettings,
        detailed: Bool,
        unavailableMetrics: Set<SystemMonitorMenuMetric> = []
    ) -> TimeInterval? {
        if detailed { return 1 }
        let intervals = settings.enabled
            ? settings.enabledItems
                .filter { !unavailableMetrics.contains($0.metric) }
                .map { $0.effectiveInterval(global: settings.interval) }
            : []
        return intervals.min()
    }
    static func dueMetrics(
        settings: SystemMonitorMenuSettings,
        lastSampled: [SystemMonitorMenuMetric: Date],
        unavailableMetrics: Set<SystemMonitorMenuMetric> = [],
        now: Date
    ) -> Set<SystemMonitorMenuMetric> {
        guard settings.enabled else { return [] }
        return Set(settings.enabledItems.compactMap { item in
            guard !unavailableMetrics.contains(item.metric) else { return nil }
            guard let last = lastSampled[item.metric] else { return item.metric }
            return now.timeIntervalSince(last) >= item.effectiveInterval(global: settings.interval) ? item.metric : nil
        })
    }

    static func nextInterval(
        settings: SystemMonitorMenuSettings,
        lastSampled: [SystemMonitorMenuMetric: Date],
        unavailableMetrics: Set<SystemMonitorMenuMetric> = [],
        detailed: Bool,
        now: Date
    ) -> TimeInterval? {
        if detailed { return 1 }
        guard settings.enabled else { return nil }
        return settings.enabledItems
            .filter { !unavailableMetrics.contains($0.metric) }
            .map { item in
                guard let last = lastSampled[item.metric] else { return 0 }
                return max(item.effectiveInterval(global: settings.interval) - now.timeIntervalSince(last), 0)
            }
            .min()
    }
}

nonisolated enum SystemMonitorStatusItemOrder {
    static let groupedAutosaveName = "system-monitor.grouped"

    static func autosaveName(for metric: SystemMonitorMenuMetric) -> String {
        "system-monitor.\(metric.rawValue)"
    }

    static func preferredPositionKeys(
        previous: [SystemMonitorMenuMetric]?,
        current: [SystemMonitorMenuMetric],
        mode: SystemMonitorMenuMode
    ) -> [String] {
        guard mode == .direct, let previous, previous != current else { return [] }
        return current.map { "NSStatusItem Preferred Position \(autosaveName(for: $0))" }
    }
}

nonisolated struct SystemMonitorRenderedItem: Equatable {
    let metric: SystemMonitorMenuMetric
    let style: SystemMonitorMenuItemStyle
    let symbol: String
    let value: String
}

nonisolated enum SystemMonitorLifecycle {
    static func changesState(from current: Bool, to requested: Bool) -> Bool {
        current != requested
    }
}

nonisolated enum SystemMonitorMenuRenderer {
    static func render(item: SystemMonitorMenuItemConfiguration, sample: SystemMonitorSample?) -> SystemMonitorRenderedItem {
        SystemMonitorRenderedItem(metric: item.metric, style: item.style,
                                  symbol: item.metric.symbols.contains(item.symbol) ? item.symbol : item.metric.symbol,
                                  value: value(item: item, sample: sample))
    }
    private static func value(item: SystemMonitorMenuItemConfiguration, sample: SystemMonitorSample?) -> String {
        if sample?.unavailableMetrics.contains(item.metric) == true { return "Unavailable" }
        switch item.metric {
        case .cpu: return sample?.cpuUsage.map(percent) ?? "Waiting"
        case .memory:
            switch item.memoryUnit {
            case .percentage: return sample?.memoryUsage.map(percent) ?? "Waiting"
            case .used: return sample?.memoryUsed.map(bytes) ?? "Waiting"
            case .available:
                guard let used = sample?.memoryUsed, let total = sample?.memoryTotal else { return "Waiting" }
                return bytes(max(total - used, 0))
            }
        case .gpu: return sample?.gpuUsage.map(percent) ?? "Unavailable"
        case .disk:
            switch item.diskUnit {
            case .percentage: return sample?.diskUsage.map(percent) ?? "Waiting"
            case .used: return sample?.diskUsed.map(bytes) ?? "Waiting"
            case .available:
                guard let used = sample?.diskUsed, let total = sample?.diskTotal else { return "Waiting" }
                return bytes(max(total - used, 0))
            }
        case .network:
            let formatter = item.networkUnit == .bytes ? rate : bitRate
            let down = sample?.networkDownload.map(formatter) ?? "Waiting"
            let up = sample?.networkUpload.map(formatter) ?? "Waiting"
            switch item.networkDirection {
            case .both: return "↓\(down) ↑\(up)"
            case .download: return "↓\(down)"
            case .upload: return "↑\(up)"
            }
        case .battery:
            let percentage = sample?.batteryPercent.map { "\($0)%" }
            let status = sample?.batteryCharging.map { $0 ? "Charging" : "On Battery" }
            switch item.batteryDisplay {
            case .percentage: return percentage ?? "Unavailable"
            case .status: return status ?? "Unavailable"
            case .both:
                guard let percentage, let status else { return "Unavailable" }
                return "\(percentage) · \(status)"
            }
        case .thermal:
            guard let state = sample?.thermalState else { return "Waiting" }
            guard item.thermalDisplay == .compact else { return state }
            switch state {
            case "Nominal": return "OK"
            case "Fair": return "Warm"
            case "Serious": return "Hot"
            default: return state
            }
        }
    }
    private static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(value, 0), countStyle: .memory)
    }
    private static func rate(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(value, 0)), countStyle: .file) + "/s"
    }
    private static func bitRate(_ byteRate: Double) -> String {
        let bits = max(byteRate, 0) * 8
        let scales: [(Double, String)] = [(1_000_000_000, "Gb/s"), (1_000_000, "Mb/s"), (1_000, "kb/s")]
        guard let scale = scales.first(where: { bits >= $0.0 }) else { return "\(Int(bits.rounded())) b/s" }
        let value = bits / scale.0
        return value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))) + " " + scale.1
    }
}

nonisolated struct SystemMonitorRenderedStateCache {
    private var states: [String: [SystemMonitorRenderedItem]] = [:]
    mutating func shouldApply(_ state: [SystemMonitorRenderedItem], for key: String) -> Bool {
        guard states[key] != state else { return false }
        states[key] = state
        return true
    }
    mutating func removeAll() { states.removeAll() }
}

nonisolated private final class SystemMonitorDueTracker: @unchecked Sendable {
    private var lastSampled: [SystemMonitorMenuMetric: Date] = [:]
    func dueMetrics(
        settings: SystemMonitorMenuSettings,
        unavailableMetrics: Set<SystemMonitorMenuMetric>,
        now: Date
    ) -> Set<SystemMonitorMenuMetric> {
        let due = SystemMonitorMenuSchedule.dueMetrics(
            settings: settings,
            lastSampled: lastSampled,
            unavailableMetrics: unavailableMetrics,
            now: now
        )
        for metric in due { lastSampled[metric] = now }
        return due
    }

    func nextInterval(
        settings: SystemMonitorMenuSettings,
        unavailableMetrics: Set<SystemMonitorMenuMetric>,
        detailed: Bool,
        now: Date
    ) -> TimeInterval? {
        SystemMonitorMenuSchedule.nextInterval(
            settings: settings,
            lastSampled: lastSampled,
            unavailableMetrics: unavailableMetrics,
            detailed: detailed,
            now: now
        )
    }
}

nonisolated private final class SystemMonitorGPUReader: @unchecked Sendable {
    private var service: io_service_t = 0
    deinit { if service != 0 { IOObjectRelease(service) } }

    func usage() -> Double? {
        if service == 0 {
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        }
        guard service != 0 else { return nil }
        guard let values = IORegistryEntryCreateCFProperty(
            service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any] else {
            IOObjectRelease(service)
            service = 0
            return nil
        }
        let keys = ["Device Utilization %", "GPU Core Utilization", "GPU Activity(%)", "GPU Busy"]
        guard let number = keys.compactMap({ values[$0] as? NSNumber }).first else { return nil }
        let raw = number.doubleValue
        return min(max(raw <= 1 ? raw * 100 : raw, 0), 100)
    }
}

nonisolated private final class SystemMonitorSampler: @unchecked Sendable {
    private var previousCPU: (timestamp: Date, total: UInt64, idle: UInt64)?
    private var previousNetwork: (timestamp: Date, received: UInt64, sent: UInt64)?
    private let gpuReader = SystemMonitorGPUReader()

    func reset() {
        previousCPU = nil
        previousNetwork = nil
    }

    func sample(detailed: Bool, metrics: Set<SystemMonitorMenuMetric>) -> SystemMonitorSample {
        let now = Date()
        let needsCPU = detailed || metrics.contains(.cpu)
        let needsMemory = detailed || metrics.contains(.memory)
        let needsNetwork = detailed || metrics.contains(.network)
        let needsGPU = detailed || metrics.contains(.gpu)
        let needsDisk = detailed || metrics.contains(.disk)
        let needsBattery = detailed || metrics.contains(.battery)
        var unavailableMetrics = Set<SystemMonitorMenuMetric>()

        var cpuUsage: Double?
        if needsCPU {
            if let current = Self.cpuCounters() {
                if let previousCPU {
                    cpuUsage = SystemMonitorDelta.cpuUsage(previous: (previousCPU.total, previousCPU.idle), current: current)
                }
                previousCPU = (now, current.total, current.idle)
            } else {
                unavailableMetrics.insert(.cpu)
            }
        }

        var download: Double?
        var upload: Double?
        if needsNetwork {
            if let current = Self.networkCounters() {
                if let previousNetwork {
                    let elapsed = now.timeIntervalSince(previousNetwork.timestamp)
                    download = SystemMonitorDelta.rate(
                        previous: previousNetwork.received,
                        current: current.received,
                        seconds: elapsed
                    )
                    upload = SystemMonitorDelta.rate(previous: previousNetwork.sent, current: current.sent, seconds: elapsed)
                }
                previousNetwork = (now, current.received, current.sent)
            } else {
                unavailableMetrics.insert(.network)
            }
        }

        let memory = needsMemory ? Self.memoryUsage() : nil
        if needsMemory && memory == nil { unavailableMetrics.insert(.memory) }
        let gpu = needsGPU ? gpuReader.usage() : nil
        if needsGPU && gpu == nil { unavailableMetrics.insert(.gpu) }
        let disk = needsDisk ? Self.diskUsage() : nil
        if needsDisk && disk == nil { unavailableMetrics.insert(.disk) }
        let battery = needsBattery ? Self.battery() : nil
        if needsBattery && battery == nil { unavailableMetrics.insert(.battery) }
        var loads = [Double](repeating: 0, count: 3)
        let loadCount = detailed ? getloadavg(&loads, 3) : 0

        return SystemMonitorSample(
            timestamp: now,
            cpuUsage: cpuUsage,
            memoryUsed: memory?.used,
            memoryTotal: memory?.total,
            gpuUsage: gpu,
            networkDownload: download,
            networkUpload: upload,
            diskUsed: disk?.used,
            diskTotal: disk?.total,
            batteryPercent: battery?.percent,
            batteryCharging: battery?.charging,
            thermalState: detailed || metrics.contains(.thermal) ? Self.thermalState() : nil,
            loadAverage: loadCount == 3 ? (loads[0], loads[1], loads[2]) : nil,
            unavailableMetrics: unavailableMetrics
        )
    }

    private static func cpuCounters() -> (total: UInt64, idle: UInt64)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = withUnsafeBytes(of: info.cpu_ticks) { Array($0.bindMemory(to: UInt32.self)) }
        guard ticks.count > Int(CPU_STATE_IDLE) else { return nil }
        return (ticks.reduce(UInt64(0)) { $0 + UInt64($1) }, UInt64(ticks[Int(CPU_STATE_IDLE)]))
    }

    private static func memoryUsage() -> (used: Int64, total: Int64)? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let pages = UInt64(info.active_count) + UInt64(info.inactive_count)
            + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let total = min(ProcessInfo.processInfo.physicalMemory, UInt64(Int64.max))
        return (Int64(min(pages * UInt64(pageSize), total)), Int64(total))
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
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let total = values?.volumeTotalCapacity, let available = values?.volumeAvailableCapacity else { return nil }
        return (max(Int64(total) - Int64(available), 0), Int64(total))
    }

    private static func battery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = values[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = values[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return (Int((Double(current) / Double(maximum) * 100).rounded()),
                    values[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
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
final class SystemMonitorService {
    static let shared = SystemMonitorService()
    static let settingsKey = "systemMonitor.menuSettings"
    static let legacySettingsKey = "powerStats.menuSettings"
    nonisolated static let maximumHistoryCount = 120

    private(set) var snapshot: SystemMonitorSample?
    private(set) var history: [SystemMonitorSample] = []
    private(set) var detailedActive = false
    private(set) var menuSettings: SystemMonitorMenuSettings

    private let sampler = SystemMonitorSampler()
    private let samplingQueue = DispatchQueue(label: "com.surajmandal.macpowertoys.system-monitor", qos: .utility)
    private let menuController: SystemMonitorMenuController
    private let defaults: UserDefaults
    private var timer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private var unavailableMenuMetrics = Set<SystemMonitorMenuMetric>()
    private var toolEnabled = true
    private var generation = 0

    private convenience init() {
        self.init(menuSettings: Self.storedMenuSettings(in: .standard))
    }

    init(
        menuSettings: SystemMonitorMenuSettings,
        toolEnabled: Bool = true,
        observesWake: Bool = true,
        defaults: UserDefaults = .standard
    ) {
        self.menuSettings = menuSettings
        self.toolEnabled = toolEnabled
        self.defaults = defaults
        menuController = SystemMonitorMenuController(defaults: defaults)
        if observesWake {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.retryUnavailableMetrics() }
            }
        }
    }

    var timerOwnerCount: Int { timer == nil ? 0 : 1 }
    var statusItemOwnerCount: Int { menuController.statusItemCount }
    var statusItemIdentities: Set<ObjectIdentifier> { menuController.statusItemIdentities }
    var statusItemAutosaveNames: Set<String> { menuController.statusItemAutosaveNames }
    var wakeObserverOwnerCount: Int { wakeObserver == nil ? 0 : 1 }

    static func storedMenuSettings(in defaults: UserDefaults) -> SystemMonitorMenuSettings {
        let data = defaults.data(forKey: settingsKey) ?? defaults.data(forKey: legacySettingsKey)
        return data.flatMap { try? JSONDecoder().decode(SystemMonitorMenuSettings.self, from: $0) }
            ?? SystemMonitorMenuSettings()
    }

    isolated deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        stopTimer()
    }

    func startFromStoredSettings() {
        toolEnabled = SettingsManager.shared.isToolEnabled("system-monitor")
        reconfigure()
    }
    func startDetailed() {
        guard SystemMonitorLifecycle.changesState(from: detailedActive, to: true) else { return }
        detailedActive = true
        unavailableMenuMetrics.removeAll()
        reconfigure()
    }
    func stopDetailed() {
        guard SystemMonitorLifecycle.changesState(from: detailedActive, to: false) else { return }
        detailedActive = false
        reconfigure()
    }
    func updateMenuSettings(_ change: (inout SystemMonitorMenuSettings) -> Void) {
        guard let updated = menuSettings.applying(change) else { return }
        menuSettings = updated
        if let data = try? JSONEncoder().encode(menuSettings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
        unavailableMenuMetrics.removeAll()
        reconfigure()
    }
    func setToolEnabled(_ enabled: Bool) {
        guard SystemMonitorLifecycle.changesState(from: toolEnabled, to: enabled) else { return }
        toolEnabled = enabled
        if !enabled { detailedActive = false }
        if enabled { unavailableMenuMetrics.removeAll() }
        reconfigure()
    }

    private func reconfigure() {
        stopTimer()
        generation += 1
        let menuActive = toolEnabled && menuSettings.enabled
        var settings = menuSettings
        settings.enabled = menuActive
        menuController.configure(settings: settings)
        guard toolEnabled,
              SystemMonitorMenuSchedule.timerInterval(
                settings: settings,
                detailed: detailedActive,
                unavailableMetrics: unavailableMenuMetrics
              ) != nil else { return }

        let detailed = detailedActive
        let unavailableMetrics = unavailableMenuMetrics
        let dueTracker = SystemMonitorDueTracker()
        let currentGeneration = generation
        samplingQueue.sync { sampler.reset() }
        let source = DispatchSource.makeTimerSource(queue: samplingQueue)
        source.schedule(deadline: .now())
        source.setEventHandler { [weak self, sampler] in
            let now = Date()
            let due = dueTracker.dueMetrics(
                settings: settings,
                unavailableMetrics: unavailableMetrics,
                now: now
            )
            if detailed || !due.isEmpty {
                let sample = sampler.sample(detailed: detailed, metrics: due)
                Task { @MainActor [weak self] in
                    self?.receive(sample, detailed: detailed, dueMetrics: due, generation: currentGeneration)
                }
            }
            if let interval = dueTracker.nextInterval(
                settings: settings,
                unavailableMetrics: unavailableMetrics,
                detailed: detailed,
                now: now
            ) {
                let delay = max(interval - Date().timeIntervalSince(now), 0.001)
                source.schedule(
                    deadline: .now() + delay,
                    leeway: .milliseconds(min(Int(interval * 150), 150))
                )
            }
        }
        timer = source
        source.resume()
    }

    private func receive(_ sample: SystemMonitorSample, detailed: Bool,
                         dueMetrics: Set<SystemMonitorMenuMetric>, generation: Int) {
        guard generation == self.generation else { return }
        snapshot = sample
        if detailed {
            history.append(sample)
            if history.count > Self.maximumHistoryCount {
                history.removeFirst(history.count - Self.maximumHistoryCount)
            }
        }
        if toolEnabled && menuSettings.enabled && !dueMetrics.isEmpty {
            menuController.update(sample: sample, dueMetrics: dueMetrics)
        }
        let enabledMetrics = Set(menuSettings.enabledItems.map(\.metric))
        let newlyUnavailable = sample.unavailableMetrics.intersection(enabledMetrics)
            .subtracting(unavailableMenuMetrics)
        guard !newlyUnavailable.isEmpty else { return }
        unavailableMenuMetrics.formUnion(newlyUnavailable)
        if !detailed { reconfigure() }
    }

    private func retryUnavailableMetrics() {
        guard !unavailableMenuMetrics.isEmpty else { return }
        unavailableMenuMetrics.removeAll()
        reconfigure()
    }

    private func stopTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}

@MainActor
private final class SystemMonitorMenuController: NSObject {
    private var statusItems: [String: NSStatusItem] = [:]
    private var latestValues: [SystemMonitorMenuMetric: String] = [:]
    private var renderedStateCache = SystemMonitorRenderedStateCache()
    private var settings = SystemMonitorMenuSettings()
    private var lastDirectOrder: [SystemMonitorMenuMetric]?
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var statusItemCount: Int { statusItems.count }
    var statusItemIdentities: Set<ObjectIdentifier> {
        Set(statusItems.values.map(ObjectIdentifier.init))
    }
    var statusItemAutosaveNames: Set<String> { Set(statusItems.values.map(\.autosaveName)) }

    func configure(settings: SystemMonitorMenuSettings) {
        guard settings != self.settings else { return }
        let order = settings.items.map(\.metric)
        let positionKeys = SystemMonitorStatusItemOrder.preferredPositionKeys(
            previous: lastDirectOrder,
            current: order,
            mode: settings.mode
        )
        positionKeys.forEach { defaults.removeObject(forKey: $0) }
        if settings.mode == .direct || lastDirectOrder == nil { lastDirectOrder = order }
        let oldLayout = layoutSignature(for: self.settings)
        self.settings = settings
        renderedStateCache.removeAll()
        latestValues.removeAll()
        guard oldLayout != layoutSignature(for: settings) else {
            update(sample: nil, dueMetrics: Set(settings.enabledItems.map(\.metric)))
            return
        }

        statusItems.values.forEach(NSStatusBar.system.removeStatusItem)
        statusItems.removeAll()
        guard settings.enabled, !settings.enabledItems.isEmpty else { return }
        if settings.mode == .grouped {
            statusItems["group"] = makeStatusItem(
                autosaveName: SystemMonitorStatusItemOrder.groupedAutosaveName
            )
        } else {
            for item in settings.enabledItems.reversed() {
                statusItems[item.metric.rawValue] = makeStatusItem(
                    autosaveName: SystemMonitorStatusItemOrder.autosaveName(for: item.metric)
                )
            }
        }
        update(sample: nil, dueMetrics: Set(settings.enabledItems.map(\.metric)))
    }

    func update(sample: SystemMonitorSample?, dueMetrics: Set<SystemMonitorMenuMetric>) {
        guard settings.enabled else { return }
        for item in settings.enabledItems where dueMetrics.contains(item.metric) {
            latestValues[item.metric] = SystemMonitorMenuRenderer.render(item: item, sample: sample).value
        }
        if settings.mode == .grouped {
            let state = settings.enabledItems.map(renderedItem)
            guard renderedStateCache.shouldApply(state, for: "group"),
                  let button = statusItems["group"]?.button else { return }
            button.image = nil
            button.attributedTitle = attributedTitle(for: state)
            button.setAccessibilityLabel(accessibilityLabel(for: state))
        } else {
            for item in settings.enabledItems where dueMetrics.contains(item.metric) || sample == nil {
                let state = [renderedItem(item)]
                let key = item.metric.rawValue
                guard renderedStateCache.shouldApply(state, for: key),
                      let button = statusItems[key]?.button else { continue }
                apply(state[0], to: button)
            }
        }
    }

    private func renderedItem(_ item: SystemMonitorMenuItemConfiguration) -> SystemMonitorRenderedItem {
        SystemMonitorRenderedItem(metric: item.metric, style: item.style,
                                  symbol: item.metric.symbols.contains(item.symbol) ? item.symbol : item.metric.symbol,
                                  value: latestValues[item.metric] ?? "Waiting")
    }

    private func apply(_ state: SystemMonitorRenderedItem, to button: NSStatusBarButton) {
        button.attributedTitle = NSAttributedString(string: "")
        switch state.style {
        case .iconAndValue:
            button.image = image(symbol: state.symbol, description: state.metric.title)
            button.title = state.value
        case .iconOnly:
            button.image = image(symbol: state.symbol, description: state.metric.title)
            button.title = ""
        case .valueOnly:
            button.image = nil
            button.title = state.value
        }
        button.setAccessibilityLabel("\(state.metric.title), \(state.value)")
    }

    private func attributedTitle(for state: [SystemMonitorRenderedItem]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, item) in state.enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "  ")) }
            if item.style != .valueOnly, let symbol = image(symbol: item.symbol, description: item.metric.title) {
                let attachment = NSTextAttachment()
                attachment.image = symbol
                output.append(NSAttributedString(attachment: attachment))
                if item.style == .iconAndValue { output.append(NSAttributedString(string: " ")) }
            }
            if item.style != .iconOnly { output.append(NSAttributedString(string: item.value)) }
        }
        return output
    }

    private func accessibilityLabel(for state: [SystemMonitorRenderedItem]) -> String {
        state.map { "\($0.metric.title), \($0.value)" }.joined(separator: "; ")
    }
    private func image(symbol: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: description)
    }
    private func makeStatusItem(autosaveName: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        item.button?.target = self
        item.button?.action = #selector(openSystemMonitor)
        item.button?.sendAction(on: [.leftMouseUp])
        item.button?.toolTip = "Open System Monitor"
        return item
    }
    private func layoutSignature(for settings: SystemMonitorMenuSettings) -> String {
        "\(settings.enabled)|\(settings.mode.rawValue)|\(settings.enabledItems.map(\.metric.rawValue).joined(separator: ","))"
    }
    @objc private func openSystemMonitor() { ToolActionRouter.shared.open(toolID: "system-monitor") }
}
