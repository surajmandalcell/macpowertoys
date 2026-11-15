import AppKit
import NetToysCore
import Darwin
import Foundation
import Network
import IOKit
import IOKit.ps
import Observation

nonisolated enum SystemMonitorMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
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
}

nonisolated struct SystemMonitorCPUDetails: Sendable {
    let user: Double
    let system: Double
    let idle: Double
    let cores: [Double]
}

nonisolated struct SystemMonitorMemoryDetails: Sendable {
    let wired: Int64
    let compressed: Int64
    let cached: Int64
    let swapUsed: Int64?
    let pageIns: UInt64
    let pageOuts: UInt64
}

nonisolated struct SystemMonitorNetworkDetails: Sendable {
    static let rateScope = "All interfaces"
    let interfaceName: String?
    let localAddress: String?
    let receivedTotal: UInt64
    let sentTotal: UInt64
}

nonisolated struct SystemMonitorDiskDetails: Sendable {
    let readPerSecond: Double?
    let writePerSecond: Double?
    let readTotal: UInt64
    let writeTotal: UInt64

    func retainingRates(from previous: Self?) -> Self {
        Self(readPerSecond: readPerSecond ?? previous?.readPerSecond,
             writePerSecond: writePerSecond ?? previous?.writePerSecond,
             readTotal: readTotal, writeTotal: writeTotal)
    }
}

nonisolated struct SystemMonitorNetworkIdentity: Sendable {
    let interfaceName: String?
    let localAddress: String?

    init(route: DefaultRoute?, network: LocalIPv4Network?) {
        interfaceName = route?.interfaceName
        localAddress = route.flatMap { route in
            network?.interfaceName == route.interfaceName ? network?.address.description : nil
        }
    }
}

nonisolated struct SystemMonitorBatteryDetails: Sendable {
    let cycleCount: Int?
    let health: String?
    let currentCapacity: Int?
    let maximumCapacity: Int?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
}

nonisolated enum SystemMonitorBatteryProperties {
    static func details(from properties: [String: Any]) -> SystemMonitorBatteryDetails {
        let batteryData = properties["BatteryData"] as? [String: Any] ?? [:]
        let nominalCapacity = integer("NominalChargeCapacity", in: properties, fallback: batteryData)
        let designCapacity = integer("DesignCapacity", in: properties, fallback: batteryData)
        let health = string("BatteryHealth", in: properties, fallback: batteryData)
            ?? string("Health", in: properties, fallback: batteryData)
            ?? healthPercent(nominalCapacity: nominalCapacity, designCapacity: designCapacity)
        return SystemMonitorBatteryDetails(
            cycleCount: integer("CycleCount", in: properties, fallback: batteryData),
            health: health,
            currentCapacity: integer("CurrentCapacity", in: properties, fallback: batteryData),
            maximumCapacity: integer("MaxCapacity", in: properties, fallback: batteryData),
            voltageMillivolts: integer("Voltage", in: properties, fallback: batteryData)
                ?? integer("AppleRawBatteryVoltage", in: properties, fallback: batteryData),
            amperageMilliamps: integer("Amperage", in: properties, fallback: batteryData)
                ?? integer("InstantAmperage", in: properties, fallback: batteryData)
        )
    }

    private static func integer(
        _ key: String,
        in properties: [String: Any],
        fallback: [String: Any]
    ) -> Int? {
        (properties[key] as? NSNumber)?.intValue ?? (fallback[key] as? NSNumber)?.intValue
    }

    private static func string(
        _ key: String,
        in properties: [String: Any],
        fallback: [String: Any]
    ) -> String? {
        (properties[key] as? String) ?? (fallback[key] as? String)
    }

    private static func healthPercent(nominalCapacity: Int?, designCapacity: Int?) -> String? {
        guard let nominalCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return "\(Int(Double(nominalCapacity) / Double(designCapacity) * 100))%"
    }
}

nonisolated struct SystemMonitorSample: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let lastSuccessfulReads: [SystemMonitorMetric: Date]
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
    let unavailableMetrics: Set<SystemMonitorMetric>
    let cpuDetails: SystemMonitorCPUDetails?
    let memoryDetails: SystemMonitorMemoryDetails?
    let networkDetails: SystemMonitorNetworkDetails?
    let diskDetails: SystemMonitorDiskDetails?
    let batteryDetails: SystemMonitorBatteryDetails?

    init(
        timestamp: Date,
        cpuUsage: Double?,
        memoryUsed: Int64?,
        memoryTotal: Int64?,
        gpuUsage: Double?,
        networkDownload: Double?,
        networkUpload: Double?,
        diskUsed: Int64?,
        diskTotal: Int64?,
        batteryPercent: Int?,
        batteryCharging: Bool?,
        thermalState: String?,
        loadAverage: (Double, Double, Double)?,
        unavailableMetrics: Set<SystemMonitorMetric>,
        cpuDetails: SystemMonitorCPUDetails? = nil,
        memoryDetails: SystemMonitorMemoryDetails? = nil,
        networkDetails: SystemMonitorNetworkDetails? = nil,
        diskDetails: SystemMonitorDiskDetails? = nil,
        batteryDetails: SystemMonitorBatteryDetails? = nil,
        lastSuccessfulReads: [SystemMonitorMetric: Date]? = nil
    ) {
        let present: [(SystemMonitorMetric, Bool)] = [
            (.cpu, cpuUsage?.isFinite == true),
            (.memory, memoryUsed != nil && (memoryTotal ?? 0) > 0),
            (.gpu, gpuUsage?.isFinite == true),
            (.network, networkDownload?.isFinite == true && networkUpload?.isFinite == true),
            (.disk, diskUsed != nil && (diskTotal ?? 0) > 0),
            (.battery, batteryPercent != nil && batteryCharging != nil),
            (.thermal, thermalState != nil),
        ]
        self.lastSuccessfulReads = lastSuccessfulReads ?? Dictionary(uniqueKeysWithValues:
            present.filter { $0.1 && !unavailableMetrics.contains($0.0) }.map { ($0.0, timestamp) })
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.gpuUsage = gpuUsage
        self.networkDownload = networkDownload
        self.networkUpload = networkUpload
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.batteryPercent = batteryPercent
        self.batteryCharging = batteryCharging
        self.thermalState = thermalState
        self.loadAverage = loadAverage
        self.unavailableMetrics = unavailableMetrics
        self.cpuDetails = cpuDetails
        self.memoryDetails = memoryDetails
        self.networkDetails = networkDetails
        self.diskDetails = diskDetails
        self.batteryDetails = batteryDetails
    }

    var memoryUsage: Double? {
        guard let memoryUsed, let memoryTotal, memoryTotal > 0 else { return nil }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }
    var diskUsage: Double? {
        guard let diskUsed, let diskTotal, diskTotal > 0 else { return nil }
        return Double(diskUsed) / Double(diskTotal) * 100
    }

    func preservingAvailableValues(from previous: Self?) -> Self {
        guard let previous else { return self }
        func retained<Value>(_ value: Value?, _ oldValue: Value?) -> Value? {
            value ?? oldValue
        }
        return Self(
            timestamp: timestamp,
            cpuUsage: retained(cpuUsage, previous.cpuUsage),
            memoryUsed: retained(memoryUsed, previous.memoryUsed),
            memoryTotal: retained(memoryTotal, previous.memoryTotal),
            gpuUsage: retained(gpuUsage, previous.gpuUsage),
            networkDownload: retained(networkDownload, previous.networkDownload),
            networkUpload: retained(networkUpload, previous.networkUpload),
            diskUsed: retained(diskUsed, previous.diskUsed),
            diskTotal: retained(diskTotal, previous.diskTotal),
            batteryPercent: retained(batteryPercent, previous.batteryPercent),
            batteryCharging: retained(batteryCharging, previous.batteryCharging),
            thermalState: retained(thermalState, previous.thermalState),
            loadAverage: retained(loadAverage, previous.loadAverage),
            unavailableMetrics: unavailableMetrics,
            cpuDetails: retained(cpuDetails, previous.cpuDetails),
            memoryDetails: retained(memoryDetails, previous.memoryDetails),
            networkDetails: retained(networkDetails, previous.networkDetails),
            diskDetails: diskDetails.map { $0.retainingRates(from: previous.diskDetails) } ?? previous.diskDetails,
            batteryDetails: retained(batteryDetails, previous.batteryDetails),
            lastSuccessfulReads: previous.lastSuccessfulReads.merging(lastSuccessfulReads) { _, fresh in fresh }
        )
    }
}

nonisolated enum SystemMonitorDelta {
    /// Mach tick counters are unsigned 32-bit values exposed as `integer_t`; a wrap makes the next delta nil.
    static func tickCounter(_ value: integer_t) -> UInt64 {
        UInt64(UInt32(bitPattern: value))
    }

    static func cpuUsage(previous: (total: UInt64, idle: UInt64), current: (total: UInt64, idle: UInt64)) -> Double? {
        guard current.total >= previous.total, current.idle >= previous.idle else { return nil }
        let total = current.total - previous.total
        guard total > 0 else { return nil }
        let idle = current.idle - previous.idle
        return min(max(Double(total - min(idle, total)) / Double(total) * 100, 0), 100)
    }
    static func elapsedSeconds(previous: UInt64, current: UInt64) -> TimeInterval {
        guard current > previous else { return 0 }
        return Double(current - previous) / 1_000_000_000
    }

    static func rate(previous: UInt64, current: UInt64, seconds: TimeInterval) -> Double? {
        guard seconds > 0, current >= previous else { return nil }
        return Double(current - previous) / seconds
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
    private struct CPUCounters {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
        var total: UInt64 { user + system + idle + nice }
    }

    private struct MemorySnapshot {
        let used: Int64
        let total: Int64
        let details: SystemMonitorMemoryDetails
    }

    private struct NetworkSnapshot {
        let received: UInt64
        let sent: UInt64
        let details: SystemMonitorNetworkDetails
    }

    private struct BatterySnapshot {
        let percent: Int
        let charging: Bool
        let details: SystemMonitorBatteryDetails
    }

    private var previousCPU: (timestamp: Date, aggregate: CPUCounters, cores: [CPUCounters])?
    private var previousNetwork: (timestamp: UInt64, received: UInt64, sent: UInt64)?
    private var previousDisk: (timestamp: UInt64, read: UInt64, write: UInt64)?
    var networkIdentity: SystemMonitorNetworkIdentity?
    private let gpuReader = SystemMonitorGPUReader()

    func reset() {
        previousCPU = nil
        previousNetwork = nil
        previousDisk = nil
    }

    func sample(detailedMetrics: Set<SystemMonitorMetric>, metrics: Set<SystemMonitorMetric>) -> SystemMonitorSample {
        let now = Date()
        let uptime = DispatchTime.now().uptimeNanoseconds
        let requested = detailedMetrics.union(metrics)
        let needsCPU = requested.contains(.cpu)
        let needsMemory = requested.contains(.memory)
        let needsNetwork = requested.contains(.network)
        let needsGPU = requested.contains(.gpu)
        let needsDisk = requested.contains(.disk)
        let needsBattery = requested.contains(.battery)
        var unavailableMetrics = Set<SystemMonitorMetric>()

        var cpuUsage: Double?
        var cpuDetails: SystemMonitorCPUDetails?
        if needsCPU {
            if let current = Self.cpuCounters() {
                if let previousCPU {
                    cpuUsage = SystemMonitorDelta.cpuUsage(
                        previous: (previousCPU.aggregate.total, previousCPU.aggregate.idle),
                        current: (current.aggregate.total, current.aggregate.idle)
                    )
                    cpuDetails = Self.cpuDetails(previous: previousCPU, current: current)
                }
                previousCPU = (now, current.aggregate, current.cores)
            } else {
                unavailableMetrics.insert(.cpu)
            }
        }

        var download: Double?
        var upload: Double?
        var networkDetails: SystemMonitorNetworkDetails?
        if needsNetwork {
            if let current = Self.networkCounters(identity: networkIdentity) {
                networkDetails = current.details
                if let previousNetwork {
                    let elapsed = SystemMonitorDelta.elapsedSeconds(previous: previousNetwork.timestamp, current: uptime)
                    download = SystemMonitorDelta.rate(
                        previous: previousNetwork.received,
                        current: current.received,
                        seconds: elapsed
                    )
                    upload = SystemMonitorDelta.rate(previous: previousNetwork.sent, current: current.sent, seconds: elapsed)
                }
                previousNetwork = (uptime, current.received, current.sent)
            } else {
                unavailableMetrics.insert(.network)
            }
        }

        let memory = needsMemory ? Self.memoryUsage() : nil
        if needsMemory && memory == nil { unavailableMetrics.insert(.memory) }
        let gpu = needsGPU ? gpuReader.usage() : nil
        if needsGPU && gpu == nil { unavailableMetrics.insert(.gpu) }
        let disk = needsDisk ? Self.diskUsage() : nil
        var diskDetails: SystemMonitorDiskDetails?
        if needsDisk, let counters = Self.diskCounters() {
            let elapsed = previousDisk.map { SystemMonitorDelta.elapsedSeconds(previous: $0.timestamp, current: uptime) }
            diskDetails = SystemMonitorDiskDetails(
                readPerSecond: previousDisk.flatMap {
                    SystemMonitorDelta.rate(previous: $0.read, current: counters.read, seconds: elapsed ?? 0)
                },
                writePerSecond: previousDisk.flatMap {
                    SystemMonitorDelta.rate(previous: $0.write, current: counters.write, seconds: elapsed ?? 0)
                },
                readTotal: counters.read,
                writeTotal: counters.write
            )
            previousDisk = (uptime, counters.read, counters.write)
        }
        if needsDisk && disk == nil { unavailableMetrics.insert(.disk) }
        let battery = needsBattery ? Self.battery() : nil
        if needsBattery && battery == nil { unavailableMetrics.insert(.battery) }
        var loads = [Double](repeating: 0, count: 3)
        let loadCount = detailedMetrics.contains(.cpu) ? getloadavg(&loads, 3) : 0

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
            thermalState: requested.contains(.thermal) ? Self.thermalState() : nil,
            loadAverage: loadCount == 3 ? (loads[0], loads[1], loads[2]) : nil,
            unavailableMetrics: unavailableMetrics,
            cpuDetails: cpuDetails,
            memoryDetails: memory?.details,
            networkDetails: networkDetails,
            diskDetails: diskDetails,
            batteryDetails: battery?.details
        )
    }

    private static func cpuCounters() -> (aggregate: CPUCounters, cores: [CPUCounters])? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = withUnsafeBytes(of: info.cpu_ticks) { Array($0.bindMemory(to: UInt32.self)) }
        guard ticks.count >= Int(CPU_STATE_MAX) else { return nil }
        let aggregate = CPUCounters(
            user: UInt64(ticks[Int(CPU_STATE_USER)]),
            system: UInt64(ticks[Int(CPU_STATE_SYSTEM)]),
            idle: UInt64(ticks[Int(CPU_STATE_IDLE)]),
            nice: UInt64(ticks[Int(CPU_STATE_NICE)])
        )
        return (aggregate, perCoreCounters())
    }

    private static func perCoreCounters() -> [CPUCounters] {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
            &cpuCount, &cpuInfo, &infoCount
        ) == KERN_SUCCESS, let cpuInfo else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { index in
            let offset = index * stride
            return CPUCounters(
                user: SystemMonitorDelta.tickCounter(cpuInfo[offset + Int(CPU_STATE_USER)]),
                system: SystemMonitorDelta.tickCounter(cpuInfo[offset + Int(CPU_STATE_SYSTEM)]),
                idle: SystemMonitorDelta.tickCounter(cpuInfo[offset + Int(CPU_STATE_IDLE)]),
                nice: SystemMonitorDelta.tickCounter(cpuInfo[offset + Int(CPU_STATE_NICE)])
            )
        }
    }

    private static func cpuDetails(
        previous: (timestamp: Date, aggregate: CPUCounters, cores: [CPUCounters]),
        current: (aggregate: CPUCounters, cores: [CPUCounters])
    ) -> SystemMonitorCPUDetails? {
        let previousTotal = previous.aggregate.total
        let currentTotal = current.aggregate.total
        guard currentTotal > previousTotal,
              current.aggregate.user >= previous.aggregate.user,
              current.aggregate.system >= previous.aggregate.system,
              current.aggregate.nice >= previous.aggregate.nice else { return nil }
        let delta = Double(currentTotal - previousTotal)
        let user = Double(current.aggregate.user - previous.aggregate.user
            + current.aggregate.nice - previous.aggregate.nice) / delta * 100
        let system = Double(current.aggregate.system - previous.aggregate.system) / delta * 100
        let cores = zip(previous.cores, current.cores).compactMap { old, new in
            SystemMonitorDelta.cpuUsage(
                previous: (old.total, old.idle),
                current: (new.total, new.idle)
            )
        }
        return SystemMonitorCPUDetails(
            user: min(max(user, 0), 100),
            system: min(max(system, 0), 100),
            idle: min(max(100 - user - system, 0), 100),
            cores: cores
        )
    }

    private static func memoryUsage() -> MemorySnapshot? {
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
        let pageBytes = UInt64(pageSize)
        let bytes: (UInt64) -> Int64 = { count in
            let result = count.multipliedReportingOverflow(by: pageBytes)
            return Int64(min(result.overflow ? total : result.partialValue, total))
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
            ? Int64(min(swap.xsu_used, UInt64(Int64.max))) : nil
        return MemorySnapshot(
            used: Int64(min(pages * pageBytes, total)),
            total: Int64(total),
            details: SystemMonitorMemoryDetails(
                wired: bytes(UInt64(info.wire_count)),
                compressed: bytes(UInt64(info.compressor_page_count)),
                cached: bytes(UInt64(info.inactive_count) + UInt64(info.speculative_count)),
                swapUsed: swapUsed,
                pageIns: UInt64(info.pageins),
                pageOuts: UInt64(info.pageouts)
            )
        )
    }

    private static func networkCounters(identity: SystemMonitorNetworkIdentity?) -> NetworkSnapshot? {
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
        return NetworkSnapshot(
            received: received, sent: sent,
            details: SystemMonitorNetworkDetails(interfaceName: identity?.interfaceName,
                                                  localAddress: identity?.localAddress,
                                                  receivedTotal: received, sentTotal: sent)
        )
    }

    private static func diskUsage() -> (used: Int64, total: Int64)? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let total = values?.volumeTotalCapacity, let available = values?.volumeAvailableCapacity else { return nil }
        return (max(Int64(total) - Int64(available), 0), Int64(total))
    }

    private static func diskCounters() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var found = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(
                service, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
            let readValue = property["Bytes (Read)"] as? NSNumber,
            let writeValue = property["Bytes (Write)"] as? NSNumber else { continue }
            let nextRead = read.addingReportingOverflow(readValue.uint64Value)
            let nextWrite = write.addingReportingOverflow(writeValue.uint64Value)
            read = nextRead.overflow ? .max : nextRead.partialValue
            write = nextWrite.overflow ? .max : nextWrite.partialValue
            found = true
        }
        return found ? (read, write) : nil
    }

    private static func battery() -> BatterySnapshot? {
        let smartDetails = smartBatteryDetails()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = values[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = values[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatterySnapshot(
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                charging: values[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                details: SystemMonitorBatteryDetails(
                    cycleCount: smartDetails?.cycleCount ?? (values["Cycle Count"] as? NSNumber)?.intValue,
                    health: smartDetails?.health ?? values["BatteryHealth"] as? String,
                    currentCapacity: current,
                    maximumCapacity: maximum,
                    voltageMillivolts: smartDetails?.voltageMillivolts
                        ?? (values["Voltage"] as? NSNumber)?.intValue,
                    amperageMilliamps: smartDetails?.amperageMilliamps
                        ?? (values["Amperage"] as? NSNumber)?.intValue
                )
            )
        }
        return nil
    }

    private static func smartBatteryDetails() -> SystemMonitorBatteryDetails? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var rawProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &rawProperties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let properties = rawProperties?.takeRetainedValue() as? [String: Any] else { return nil }
        return SystemMonitorBatteryProperties.details(from: properties)
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

nonisolated struct SystemMonitorHistory {
    static let capacity = 120
    private var samplesByMetric: [SystemMonitorMetric: [SystemMonitorSample]] = [:]

    var isEmpty: Bool { samplesByMetric.isEmpty }

    func samples(for metric: SystemMonitorMetric) -> [SystemMonitorSample] {
        samplesByMetric[metric] ?? []
    }

    mutating func append(_ sample: SystemMonitorSample, metrics: Set<SystemMonitorMetric>) {
        for metric in metrics {
            samplesByMetric[metric, default: []].append(sample)
            if samplesByMetric[metric, default: []].count > Self.capacity {
                samplesByMetric[metric]?.removeFirst()
            }
        }
    }
}

/// Samples system metrics on a utility queue only while a visible owner, such as the combined panel Home, needs them.
@Observable
@MainActor
final class SystemMonitorService {
    static let shared = SystemMonitorService()
    static weak var current: SystemMonitorService?
    nonisolated static let maximumHistoryCount = SystemMonitorHistory.capacity

    private(set) var snapshot: SystemMonitorSample?
    private(set) var history = SystemMonitorHistory()

    private let sampler = SystemMonitorSampler()
    private let samplingQueue = DispatchQueue(label: "com.surajmandal.macpowertoys.system-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var networkMonitor: NWPathMonitor?
    private var networkIdentityTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var detailedOwners: [String: Set<SystemMonitorMetric>] = [:]
    private var generation = 0

    init(observesWake: Bool = true) {
        if observesWake {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAfterWake() }
            }
        }
        Self.current = self
    }

    var timerOwnerCount: Int { timer == nil ? 0 : 1 }
    var wakeObserverOwnerCount: Int { wakeObserver == nil ? 0 : 1 }

    isolated deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        stopTimer()
    }

    func startDetailed(owner: String, metrics: Set<SystemMonitorMetric> = Set(SystemMonitorMetric.allCases)) {
        guard detailedOwners[owner] == nil else { return }
        detailedOwners[owner] = metrics
        reconfigure()
    }
    func updateDetailed(owner: String, metrics: Set<SystemMonitorMetric>) {
        guard detailedOwners[owner] != nil, detailedOwners[owner] != metrics else { return }
        detailedOwners[owner] = metrics
        reconfigure()
    }
    func stopDetailed(owner: String) {
        guard detailedOwners.removeValue(forKey: owner) != nil else { return }
        reconfigure()
    }

    private func reconfigure() {
        stopTimer()
        generation += 1
        let detailedMetrics = detailedOwners.values.reduce(into: Set<SystemMonitorMetric>()) { $0.formUnion($1) }
        guard !detailedMetrics.isEmpty else { return }
        let currentGeneration = generation
        if detailedMetrics.contains(.network) {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.refreshNetworkIdentity(generation: currentGeneration)
                }
            }
            networkMonitor = monitor
            monitor.start(queue: samplingQueue)
        }
        samplingQueue.async { [sampler] in sampler.reset() }
        let source = DispatchSource.makeTimerSource(queue: samplingQueue)
        source.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(150))
        source.setEventHandler { @Sendable [weak self, sampler] in autoreleasepool {
            let sample = sampler.sample(detailedMetrics: detailedMetrics, metrics: [])
            Task { @MainActor [weak self] in
                self?.receive(sample, metrics: detailedMetrics, generation: currentGeneration)
            }
        } }
        timer = source
        source.resume()
    }

    private func receive(_ sample: SystemMonitorSample, metrics: Set<SystemMonitorMetric>, generation: Int) {
        guard generation == self.generation else { return }
        // Record only fresh readings, never values retained from an earlier sample.
        history.append(sample, metrics: metrics)
        snapshot = sample.preservingAvailableValues(from: snapshot)
    }

    func refreshAfterWake() {
        reconfigure()
    }

    private func refreshNetworkIdentity(generation: Int) {
        networkIdentityTask?.cancel()
        networkIdentityTask = Task { [weak self] in
            let data = try? await TailscalePeerCatalog.runStatusCommand(
                executableURL: URL(fileURLWithPath: "/sbin/route"), arguments: ["-n", "get", "default"],
                maximumOutputBytes: 8_192, timeout: 2
            )
            guard !Task.isCancelled else { return }
            let route = data.flatMap { DefaultRoute.parse(String(decoding: $0, as: UTF8.self)) }
            let identity = await Task.detached(priority: .utility) {
                SystemMonitorNetworkIdentity(route: route, network: route.flatMap {
                    LocalIPv4Network.active(preferredInterfaceName: $0.interfaceName)
                })
            }.value
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.samplingQueue.async { [sampler = self.sampler] in sampler.networkIdentity = identity }
            self.networkIdentityTask = nil
        }
    }

    private func stopTimer() {
        networkMonitor?.cancel()
        networkMonitor = nil
        networkIdentityTask?.cancel()
        networkIdentityTask = nil
        samplingQueue.async { [sampler] in sampler.networkIdentity = nil }
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}
