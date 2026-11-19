import IOKit
import IOKit.ps
import OnePlusUI
import SwiftUI

/// The first Home open after launch counts numbers up, grows bars, and draws charts in; later opens show values as is.
enum MainPanelEntrance {
    @MainActor static var pending = true
}

/// The combined panel's Home (DESIGN.md v15): the metric bento, the Fan and Awake card, the top processes,
/// and the joined action bar. 1 s sampling and the process refresh run only while Home is visible.
struct TrayHomeView: View {
    static let owner = "main-tray-home"
    let toolIDs: [String]
    @State private var taskManager: MainPanelTaskManager?
    @State private var reveal: Double = MainPanelEntrance.pending && !OnePlusMotion.reducesMotion ? 0 : 1
    @Environment(\.onePlusIsVisible) private var isVisible

    var body: some View {
        MainPanelHomeContent(readings: MainPanelReadingsModel.shared.readings,
                             processes: MainPanelProcessDisplay.rows(MenuPanelTopProcesses.shared),
                             actions: actions, taskManager: taskManager) {
            MainPanelControlCard(showsAwake: toolIDs.contains("awake"))
        }
        .environment(\.onePlusLinearReveal, reveal)
        .background { MainPanelReadingsFeed(model: .shared) }
        .task(id: isVisible) { if isVisible { taskManager = .installed() } }
        .onChange(of: isVisible, initial: true) {
            guard isVisible, reveal < 1 else { return }
            MainPanelEntrance.pending = false
            withAnimation(OnePlusMotion.animation(OnePlusMotion.panelReveal)) { reveal = 1 }
        }
        .modifier(MenuPanelProcessRefresh())
        .modifier(MenuPanelMetricSampling(owner: Self.owner))
    }

    private var actions: [OnePlusLinearAction] {
        let items: [(id: String, title: String, action: ToolActionID)] = [
            ("color-picker", "Pick Color", .colorPickerPick),
            ("text-extractor", "Extract Text", .textExtractorCapture),
            ("ruler", "Ruler", .rulerOpen),
        ]
        return items.filter { toolIDs.contains($0.id) }.map { item in
            OnePlusLinearAction(item.title, systemImage: ToolGlyph(rawValue: item.id)?.symbol ?? "circle",
                                id: "tray.action.\(item.id)") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: item.action))
            }
        }
    }
}

/// The Home layout from prepared values only, so tests can render it with fixed data.
struct MainPanelHomeContent<Controls: View>: View {
    let readings: MainPanelReadings
    let processes: [MainPanelProcessDisplay]
    let actions: [OnePlusLinearAction]
    var taskManager: MainPanelTaskManager?
    @ViewBuilder let controls: Controls
    /// Tracked by PID: rows reorder on every refresh.
    @State private var selectedPID: Int32?
    @Environment(\.onePlusIsVisible) private var isVisible

    var body: some View {
        VStack(alignment: .leading, spacing: TrayPopoverLayout.style.blockGap) {
            MainPanelBento(readings: readings)
            controls
            VStack(spacing: 0) {
                OnePlusLinearPanelHeader.processes()
                OnePlusLinearList(style: .panel) {
                    ForEach(0..<MainPanelProcessDisplay.rowCount, id: \.self) { index in
                        if index < processes.count {
                            processRow(processes[index])
                        } else {
                            Color.clear.frame(height: OnePlusLinearMetrics.processRow)
                        }
                    }
                }
            }
            if !actions.isEmpty { OnePlusLinearActionBar(actions) }
        }
        .onChange(of: processes.map(\.pid)) { _, pids in
            if let selectedPID, !pids.contains(selectedPID) { self.selectedPID = nil }
        }
        .onChange(of: isVisible) { _, visible in if !visible { selectedPID = nil } }
    }

    private func processRow(_ row: MainPanelProcessDisplay) -> some View {
        Button { selectedPID = row.pid } label: {
            OnePlusLinearProcessRow(row.name, icon: row.icon, cpu: row.cpu, memory: row.memory, selected: row.pid == selectedPID)
        }
        .buttonStyle(MainPanelRowButtonStyle())
        .contextMenu {
            Button("Quit Process…") { MainPanelProcessQuit.confirm(name: row.name, pid: row.pid, started: row.started) }
            if let taskManager {
                Button(taskManager.menuTitle) {
                    MainMenuBarController.shared.closePanel()
                    taskManager.open()
                }
            } else {
                Menu(AppsBySamView.title) {
                    ForEach(["Task Manager Pro", "Task Manager Classic"], id: \.self) { name in
                        Button(name) {
                            MainMenuBarController.shared.closePanel()
                            ToolActionRouter.shared.open(toolID: AppsBySamView.pageID)
                        }
                    }
                }
            }
        }
    }
}

/// The row draws its own hover and selected fill, so the button adds no press look.
private struct MainPanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// One top-process row as the panel draws it. Rows hold their slot while the first reading loads.
struct MainPanelProcessDisplay {
    static let rowCount = 5
    let name: String
    let icon: Image?
    let cpu: String
    let memory: String
    var pid: Int32 = 0
    var started: UInt64 = 0

    static func rows(_ model: MenuPanelTopProcesses) -> [Self] {
        model.rows.prefix(rowCount).map { row in
            Self(name: row.displayName, icon: row.appBundlePath.flatMap { model.icons.images[$0] }.map(Image.init(nsImage:)),
                 cpu: row.cpuValueText, memory: row.memoryText, pid: row.process.pid, started: row.process.started)
        }
    }
}

/// Home samples every second while visible. While the panel exists but Home is hidden, a background owner
/// samples every 5 seconds, so the charts open with up to 5 minutes of history.
struct MenuPanelMetricSampling: ViewModifier {
    static let metrics: Set<SystemMonitorMetric> = {
        let hardware = MainPanelHardware.current
        return Set<SystemMonitorMetric>([.cpu, .memory, .disk, .network])
            .union(hardware.hasGPU ? [.gpu] : []).union(hardware.hasBattery ? [.battery] : [])
    }()
    static let backgroundOwner = "main-panel-background"
    static let backgroundInterval: TimeInterval = 5

    static func setBackground(_ enabled: Bool) {
        if enabled {
            SystemMonitorService.shared.startDetailed(owner: backgroundOwner, metrics: metrics, interval: backgroundInterval)
        } else {
            SystemMonitorService.shared.stopDetailed(owner: backgroundOwner)
        }
    }

    let owner: String
    @Environment(\.onePlusIsVisible) private var isVisible

    func body(content: Content) -> some View {
        content
            .onChange(of: isVisible, initial: true) {
                if isVisible {
                    SystemMonitorService.shared.startDetailed(owner: owner, metrics: Self.metrics)
                } else {
                    SystemMonitorService.shared.stopDetailed(owner: owner)
                }
            }
            .onDisappear { SystemMonitorService.shared.stopDetailed(owner: owner) }
    }
}

/// Formats each new sample off the main thread. Samples arrive once a second, under the 4 per second UI limit.
/// Hidden Home reads no sample, so background samples never wake the view.
private struct MainPanelReadingsFeed: View {
    let model: MainPanelReadingsModel
    @Environment(\.onePlusIsVisible) private var isVisible

    var body: some View {
        let service = SystemMonitorService.shared
        Color.clear.task(id: isVisible ? service.snapshot?.id : nil) {
            guard isVisible, let sample = service.snapshot else { return }
            let history = service.history
            let hardware = MainPanelHardware.current
            let previous = model.readings
            let prepared = await Task.detached(priority: .userInitiated) {
                MainPanelReadings(sample: sample, history: history, hardware: hardware, previous: previous)
            }.value
            guard !Task.isCancelled, prepared != model.readings else { return }
            model.readings = prepared
        }
    }
}

/// Home's readings outlive the view tree, so the opener formats the newest background sample before the first
/// frame. Without this, a panel closed for minutes showed its old values, then jumped (or empty tiles, then filled).
@Observable
final class MainPanelReadingsModel {
    static let shared = MainPanelReadingsModel()
    var readings = MainPanelReadings(hardware: .current)

    func prepareForOpening() {
        let service = SystemMonitorService.shared
        guard let sample = service.snapshot else { return }
        let prepared = MainPanelReadings(sample: sample, history: service.history, hardware: .current, previous: readings)
        if prepared != readings { readings = prepared }
    }
}

/// Hardware the Home tiles need, probed once per launch so the layout never changes after the first frame.
nonisolated struct MainPanelHardware: Equatable, Sendable {
    var hasBattery: Bool
    var hasGPU: Bool
    var cores: Int
    var chip: String?

    static let current = MainPanelHardware(hasBattery: probeBattery(), hasGPU: probeGPU(),
                                           cores: ProcessInfo.processInfo.activeProcessorCount, chip: probeChip())

    private static func probeBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return sources.contains { source in
            let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return values?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    private static func probeGPU() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        return ["Device Utilization %", "GPU Core Utilization", "GPU Activity(%)", "GPU Busy"]
            .contains { statistics?[$0] is NSNumber }
    }

    private static func probeChip() -> String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return nil }
        let name = String(cString: bytes)
        return name.hasPrefix("Apple") ? name : nil
    }
}

/// Every Home text and chart value, prepared off the main thread. A missing reading shows a dash.
nonisolated struct MainPanelReadings: Equatable, Sendable {
    static let historySeconds = 60
    static let dash = "—"

    var hasBattery: Bool
    var hasGPU: Bool
    var cores: String
    var cpu = MainPanelReadings.dash, cpuUser = MainPanelReadings.dash, cpuSystem = MainPanelReadings.dash
    var cpuHistory: [Double] = [], cpuRange: ClosedRange<Double> = 0...10
    var gpu = MainPanelReadings.dash, gpuName: String
    var gpuHistory: [Double] = [], gpuRange: ClosedRange<Double> = 0...10
    var memory = MainPanelReadings.dash, memoryUsed = "", memoryTotal = "", memoryFraction = 0.0
    var diskFree = MainPanelReadings.dash, diskFreeUnit = "GB free", diskUsed = "", diskFraction = 0.0
    var battery = MainPanelReadings.dash, batteryCaption = "", batteryFraction = 0.0, batterySymbol = "battery.100percent"
    var down = MainPanelReadings.dash, downUnit = "KB/s", up = MainPanelReadings.dash
    var downHistory: [Double] = [], upHistory: [Double] = [], networkRange: ClosedRange<Double> = 0...1_024

    init(hardware: MainPanelHardware) {
        hasBattery = hardware.hasBattery
        hasGPU = hardware.hasGPU
        cores = "\(hardware.cores) cores"
        gpuName = hardware.chip ?? ""
    }

    /// Charts draw eased samples on a ceiling that eases from `previous`; the text shows the raw current reading.
    init(sample: SystemMonitorSample, history: SystemMonitorHistory, hardware: MainPanelHardware, previous: Self? = nil) {
        self.init(hardware: hardware)
        cpu = Self.percent(sample.cpuUsage)
        cpuUser = Self.percent(sample.cpuDetails?.user)
        cpuSystem = Self.percent(sample.cpuDetails?.system)
        cpuHistory = Self.recent(history, .cpu, \.cpuUsage)
        cpuRange = Self.percentRange(cpuHistory, previous: previous?.cpuRange)
        gpu = Self.percent(sample.gpuUsage)
        gpuHistory = Self.recent(history, .gpu, \.gpuUsage)
        gpuRange = Self.percentRange(gpuHistory, previous: previous?.gpuRange)
        if let used = sample.memoryUsed, let total = sample.memoryTotal, total > 0 {
            memory = Self.percent(sample.memoryUsage)
            memoryUsed = ByteCountFormatter.string(fromByteCount: used, countStyle: .memory) + " used"
            memoryTotal = ByteCountFormatter.string(fromByteCount: total, countStyle: .memory)
            memoryFraction = Double(used) / Double(total)
        }
        if let used = sample.diskUsed, let total = sample.diskTotal, total > 0 {
            (diskFree, diskFreeUnit) = Self.split(TrayPopoverLayout.compactDiskBytes(max(0, total - used), fractionLength: 0))
            diskFreeUnit += " free"
            diskUsed = TrayPopoverLayout.compactDiskBytes(used, fractionLength: 0) + " used"
            diskFraction = Double(used) / Double(total)
        }
        if let percent = sample.batteryPercent {
            battery = "\(percent)"
            batteryFraction = Double(percent) / 100
            let onPower = sample.batteryCharging == true
            batteryCaption = onPower ? (percent >= 100 ? "Charged" : "Charging")
                : sample.batteryDetails?.timeRemaining.map(Self.timeLeft) ?? "Estimating"
            batterySymbol = onPower ? "battery.100percent.bolt"
                : "battery.\([0, 25, 50, 75, 100].min { abs($0 - percent) < abs($1 - percent) } ?? 100)percent"
        }
        if let download = sample.networkDownload { (down, downUnit) = Self.rate(download) }
        if let upload = sample.networkUpload { up = Self.rate(upload).0 + " " + Self.rate(upload).1 }
        downHistory = Self.recent(history, .network, \.networkDownload)
        upHistory = Self.recent(history, .network, \.networkUpload)
        networkRange = 0...OnePlusChartSmoothing.ceiling(peak: Self.peak(downHistory + upHistory),
                                                         previous: previous?.networkRange.upperBound, minimum: 10_000)
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return dash }
        return "\(Int(min(max(value, 0), 100).rounded()))"
    }

    /// Bytes per second as a decimal value and unit, such as `2.4` and `MB/s`.
    static func rate(_ bytesPerSecond: Double) -> (String, String) {
        let (value, unit) = split(TrayPopoverLayout.compactDiskBytes(Int64(max(0, bytesPerSecond).rounded())))
        return (value, unit + "/s")
    }

    static func timeLeft(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return String(format: "%d:%02d left", minutes / 60, minutes % 60)
    }

    /// A stable 5, 10, 20, 25, 50, or 100 percent top that never clips a sample and settles down slowly.
    static func percentRange(_ values: [Double], previous: ClosedRange<Double>? = nil) -> ClosedRange<Double> {
        0...OnePlusChartSmoothing.ceiling(peak: peak(values), previous: previous?.upperBound, minimum: 5, maximum: 100)
    }

    private static func peak(_ values: [Double]) -> Double { values.filter(\.isFinite).max() ?? 0 }

    private static func split(_ text: String) -> (String, String) {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        return (parts.first ?? dash, parts.count > 1 ? parts[1] : "")
    }

    /// The last 60 samples, eased over the whole kept history so a drawn point never changes. A missing reading
    /// stays a gap in its own slot instead of shifting later points left.
    private static func recent(_ history: SystemMonitorHistory, _ metric: SystemMonitorMetric,
                               _ value: KeyPath<SystemMonitorSample, Double?>) -> [Double] {
        let raw = history.samples(for: metric).map { $0[keyPath: value] ?? .nan }
        return Array(OnePlusChartSmoothing.eased(raw).suffix(historySeconds))
    }
}

/// Fixed tile heights that keep both bento columns equal. A missing Battery or GPU tile gives its height to
/// the column's chart tile (CPU on the left, Network on the right), so the two columns still end on one line.
nonisolated struct MainPanelBentoLayout: Equatable {
    let cpu: CGFloat, cpuChart: CGFloat, network: CGFloat, networkChart: CGFloat, height: CGFloat

    init(hasBattery: Bool, hasGPU: Bool) {
        let style = TrayPopoverLayout.style
        let gap = style.bentoGap
        let left = style.tallTile + gap + OnePlusLinearMetrics.shortTile
            + (hasBattery ? gap + OnePlusLinearMetrics.shortTile : 0)
        let right = (hasGPU ? style.tile + gap : 0) + 2 * style.tile + gap
        height = max(left, right)
        cpu = style.tallTile + height - left
        cpuChart = OnePlusLinearMetrics.tallChart + height - left
        network = style.tile + height - right
        networkChart = OnePlusLinearMetrics.chart + height - right
    }
}

struct MainPanelBento: View {
    let readings: MainPanelReadings

    var body: some View {
        let layout = MainPanelBentoLayout(hasBattery: readings.hasBattery, hasGPU: readings.hasGPU)
        OnePlusLinearBento(style: .instrument) {
            OnePlusLinearTile(height: layout.cpu, chart: OnePlusLinearChart(
                [OnePlusLinearSeries(readings.cpuHistory, color: OnePlusLinearColor.cpu)], range: readings.cpuRange,
                height: layout.cpuChart, slots: MainPanelReadings.historySeconds), tint: OnePlusLinearColor.cpu) {
                OnePlusLinearTileLabel("CPU", systemImage: "cpu", color: OnePlusLinearColor.cpu, meta: readings.cores)
                OnePlusLinearTileValue(readings.cpu, unit: "%", color: OnePlusLinearColor.cpuText, pace: .cpu)
                OnePlusLinearTileSplit([("User", readings.cpuUser, "%"), ("System", readings.cpuSystem, "%")])
            }
            OnePlusLinearTile(height: OnePlusLinearMetrics.shortTile, usage: OnePlusLinearUsage(
                readings.diskFraction, color: OnePlusLinearColor.disk, caption: readings.diskUsed, pace: .disk), tint: OnePlusLinearColor.disk) {
                OnePlusLinearTileLabel("Disk", systemImage: "internaldrive", color: OnePlusLinearColor.disk) {
                    OnePlusLinearInlineValue(readings.diskFree, unit: readings.diskFreeUnit, color: OnePlusLinearColor.disk, pace: .disk)
                }
            }
            if readings.hasBattery {
                OnePlusLinearTile(height: OnePlusLinearMetrics.shortTile, usage: OnePlusLinearUsage(
                    readings.batteryFraction, color: OnePlusLinearColor.battery, caption: readings.batteryCaption, pace: .battery),
                    tint: OnePlusLinearColor.battery) {
                    OnePlusLinearTileLabel("Battery", systemImage: readings.batterySymbol, color: OnePlusLinearColor.battery) {
                        OnePlusLinearInlineValue(readings.battery, unit: "%", color: OnePlusLinearColor.battery, pace: .battery)
                    }
                }
            }
        } trailing: {
            if readings.hasGPU {
                OnePlusLinearTile(chart: OnePlusLinearChart(
                    [OnePlusLinearSeries(readings.gpuHistory, color: OnePlusLinearColor.gpu)], range: readings.gpuRange,
                    slots: MainPanelReadings.historySeconds, order: 1), tint: OnePlusLinearColor.gpu) {
                    OnePlusLinearTileLabel("GPU", systemImage: "display", color: OnePlusLinearColor.gpu, meta: readings.gpuName)
                    OnePlusLinearTileValue(readings.gpu, unit: "%", color: OnePlusLinearColor.gpu, pace: .gpu)
                }
            }
            OnePlusLinearTile(usage: OnePlusLinearUsage(readings.memoryFraction, color: OnePlusLinearColor.memory),
                              tint: OnePlusLinearColor.memory) {
                OnePlusLinearTileLabel("Memory", systemImage: "memorychip", color: OnePlusLinearColor.memory,
                                       meta: readings.memoryTotal)
                OnePlusLinearTileValue(readings.memory, unit: "%", note: readings.memoryUsed, color: OnePlusLinearColor.memory, pace: .memory)
            }
            OnePlusLinearTile(height: layout.network, chart: OnePlusLinearChart(
                [OnePlusLinearSeries(readings.downHistory, color: OnePlusLinearColor.networkDown),
                 OnePlusLinearSeries(readings.upHistory, color: OnePlusLinearColor.networkUp, filled: false)],
                range: readings.networkRange, height: layout.networkChart, slots: MainPanelReadings.historySeconds, order: 2),
                tint: OnePlusLinearColor.networkDown) {
                OnePlusLinearTileLabel("Network", systemImage: "network", color: OnePlusLinearColor.networkDown) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up").font(.system(size: 9, weight: .medium))
                            .foregroundStyle(OnePlusLinearColor.secondary).accessibilityHidden(true)
                        OnePlusLinearNumberText(readings.up, pace: .network).font(.system(size: OnePlusLinearMetrics.caption)).monospacedDigit()
                            .foregroundStyle(OnePlusLinearColor.networkUp)
                    }
                    .accessibilityLabel("Upload \(readings.up)")
                }
                OnePlusLinearTileValue(readings.down, unit: readings.downUnit,
                                       glyph: ("arrow.down", OnePlusLinearColor.networkDown), color: OnePlusLinearColor.networkDown, pace: .network)
            }
        }
    }
}

/// One card with the Fan row and the Awake row. A Mac without fans shows only Awake; with neither, no card.
private struct MainPanelControlCard: View {
    let showsAwake: Bool

    var body: some View {
        let showsFan = !FanControlService.shared.display.hasNoFans
        if showsFan || showsAwake {
            OnePlusLinearList(style: .panel) {
                if showsFan { FanControlView(owner: TrayHomeView.owner) }
                if showsAwake { MainPanelAwakeControl() }
            }
        }
    }
}

/// The Awake switch row. On keeps the Mac awake with no end time; the Awake applet sets timed modes.
struct MainPanelAwakeRow: View {
    @Binding var isOn: Bool
    let status: String

    var body: some View {
        OnePlusLinearControlRow("Awake", systemImage: ToolGlyph.awake.symbol, status: status) {
            Toggle("Awake", isOn: $isOn)
                .toggleStyle(OnePlusLinearSwitchStyle())
                .accessibilityIdentifier("awake.toggle")
        }
    }
}

/// Set by the Awake page tile; the Awake row shows its mark once after the panel opens.
@MainActor @Observable
final class MainPanelAwakeMark {
    static let shared = MainPanelAwakeMark()
    var pending = false
}

private struct MainPanelAwakeControl: View {
    @Bindable private var mark = MainPanelAwakeMark.shared

    var body: some View {
        let service = AwakeService.shared
        MainPanelAwakeRow(isOn: Binding(get: { service.configuration.mode != .passive },
                                        set: { service.setMode($0 ? .indefinite : .passive) }),
                          status: Self.status(service))
            .onePlusLinearRowMark(pending: $mark.pending)
    }

    static func status(_ service: AwakeService) -> String {
        if let error = service.assertionError { return error }
        guard service.configuration.mode != .passive else { return "Off" }
        guard let remaining = service.remaining else { return service.configuration.mode.title }
        let seconds = max(Int(remaining), 0)
        return String(format: "%d:%02d:%02d left", seconds / 3_600, seconds / 60 % 60, seconds % 60)
    }
}

/// Top processes refresh only while Home is visible: a CPU baseline, a first reading 0.5 s later, then every 2 s.
enum MainPanelProcessCadence {
    static let baseline: Duration = .milliseconds(500)
    static let interval: Duration = .seconds(2)

    static func run(refresh: () async -> Void, sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async {
        await refresh()
        var delay = baseline
        while !Task.isCancelled {
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            await refresh()
            delay = interval
        }
    }
}

/// Runs the top-process cadence while Home is visible; hiding, closing, or a tab change cancels it.
private struct MenuPanelProcessRefresh: ViewModifier {
    @Environment(\.onePlusIsVisible) private var isVisible

    func body(content: Content) -> some View {
        content.task(id: isVisible) {
            guard isVisible else { return }
            await MainPanelProcessCadence.run {
                await MenuPanelTopProcesses.shared.refresh(limit: MainPanelProcessDisplay.rowCount)
            }
        }
    }
}

struct AwakeTrayRow: View {
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
        VStack(alignment: .leading, spacing: 2) {
            OnePlusMenuControlRow("Awake",systemImage: ToolGlyph.awake.symbol, status: status) {
                OnePlusSegmented(
                    choices: [
                        (AwakeQuickMode?.some(.off), "Off"),
                        (AwakeQuickMode?.some(.thirtyMinutes), "30m"),
                        (AwakeQuickMode?.some(.oneHour), "1h"),
                        (AwakeQuickMode?.some(.indefinite), "∞"),
                    ],
                    selection: quickMode
                )
                .accessibilityLabel("Awake duration")
            }
            OnePlusMenuControlRow("Keep display on", systemImage: "display") {
                Toggle("Keep display on", isOn: Binding(
                    get: { service.configuration.keepDisplayOn },
                    set: service.setKeepDisplayOn
                ))
                .labelsHidden()
                .toggleStyle(OnePlusSwitchStyle())
                .accessibilityIdentifier("awake.keep-display-on")
            }
            if let assertionError = service.assertionError {
                Text(assertionError)
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.danger)
                    .lineLimit(2)
            }
        }
    }

    private var status: String {
        guard service.configuration.mode != .passive else { return "Off" }
        guard let remaining = service.remaining else { return "On" }
        let seconds = max(Int(remaining), 0)
        return String(format: "%d:%02d:%02d left", seconds / 3_600, seconds / 60 % 60, seconds % 60)
    }
}
