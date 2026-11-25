//
//  DemoMenuPanel.swift
//  powertoys
//
//  Fake system readings for the demo build. SystemMonitorService and MenuPanelTopProcesses take these
//  instead of sampling the Mac. Tick 0 matches the site panel; later ticks drift a little.
//

#if MPT_DEMO
import Foundation

nonisolated enum DemoMenuPanelData {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var tick = 0
    private static let gibibyte = 1_073_741_824.0
    private static let coreShape: [Double] = [62, 55, 48, 51, 44, 40, 38, 35, 30, 28, 22, 18, 15, 12]

    private static func wave(_ step: Int, period: Double) -> Double {
        sin(Double(step) / period * 2 * .pi)
    }

    static func sample() -> SystemMonitorSample {
        let step = lock.withLock {
            defer { tick += 1 }
            return tick
        }
        let user = 23 + 2.5 * wave(step, period: 7)
        let system = 14 + 1.5 * wave(step, period: 5)
        let cpu = user + system
        let shapeAverage = coreShape.reduce(0, +) / Double(coreShape.count)
        let seconds = UInt64(step)
        return SystemMonitorSample(
            timestamp: Date(),
            cpuUsage: cpu,
            memoryUsed: Int64((14.19 + 0.04 * wave(step, period: 11)) * gibibyte),
            memoryTotal: Int64(24 * gibibyte),
            gpuUsage: 11 + 2 * wave(step, period: 6),
            networkDownload: 550_600 * (1 + 0.25 * wave(step, period: 4)),
            networkUpload: 66_100 * (1 + 0.3 * wave(step, period: 5)),
            diskUsed: 512_000_000_000,
            diskTotal: 994_000_000_000,
            batteryPercent: 82,
            batteryCharging: false,
            thermalState: "Nominal",
            loadAverage: (3.42, 3.18, 2.96),
            unavailableMetrics: [],
            cpuDetails: SystemMonitorCPUDetails(user: user, system: system, idle: 100 - cpu,
                                                cores: coreShape.map { min(100, $0 * cpu / shapeAverage) }),
            memoryDetails: SystemMonitorMemoryDetails(wired: Int64(3.1 * gibibyte), compressed: Int64(1.2 * gibibyte),
                                                      cached: Int64(5.4 * gibibyte), swapUsed: 0,
                                                      pageIns: 4_812_330 + seconds * 40, pageOuts: 12_408),
            networkDetails: SystemMonitorNetworkDetails(receivedTotal: 18_400_000_000 + seconds * 550_600,
                                                        sentTotal: 2_100_000_000 + seconds * 66_100),
            diskDetails: SystemMonitorDiskDetails(readPerSecond: 1_240_000, writePerSecond: 386_000,
                                                  readTotal: 96_000_000_000 + seconds * 1_240_000,
                                                  writeTotal: 41_000_000_000 + seconds * 386_000),
            batteryDetails: SystemMonitorBatteryDetails(cycleCount: 112, health: "96%", currentCapacity: 82,
                                                        maximumCapacity: 100, voltageMillivolts: 12_410,
                                                        amperageMilliamps: -1_160, timeRemaining: 6 * 3600 + 25 * 60)
        )
    }

    static func processes() -> [SystemMonitorProcess] {
        let step = lock.withLock { tick }
        let rows: [(pid: Int32, name: String, cpu: Double, megabytes: UInt64, path: String)] = [
            (812, "Xcode", 18.4, 2_960, "/Applications/Xcode.app/Contents/MacOS/Xcode"),
            (433, "Safari", 9.7, 1_420, "/Applications/Safari.app/Contents/MacOS/Safari"),
            (391, "WindowServer", 6.2, 610,
             "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer"),
            (1204, "Music", 3.1, 410, "/System/Applications/Music.app/Contents/MacOS/Music"),
            (522, "Finder", 1.2, 290, "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
        ]
        return rows.map { row in
            SystemMonitorProcess(pid: row.pid, started: 1, name: row.name,
                                 cpuPercent: row.cpu * (1 + 0.08 * wave(step + Int(row.pid), period: 6)),
                                 residentBytes: row.megabytes * 1_048_576, virtualBytes: row.megabytes * 4_194_304,
                                 threads: 24, parentPID: 1, userID: 501, executablePath: row.path)
        }
    }
}

@MainActor
enum DemoMenuPanel {
    static func seed() {}

    /// The main panel opens and its readings tick once a second from the fake sampler.
    static var scene: DemoScene {
        DemoScene(open: { DiagnosticsMenuPanels.shared.open(.main, tab: TrayTab.home.panelID) }, steps: [], tail: 7)
    }
}
#endif
