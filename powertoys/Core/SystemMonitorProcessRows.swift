import AppKit
import OnePlusUI
import Observation

nonisolated enum ProcessSortColumn: String, CaseIterable, Hashable, Sendable {
    case name, cpu, memory, pid

    var title: String {
        switch self {
        case .name: "Process"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .pid: "PID"
        }
    }
}

nonisolated enum SystemMonitorProcessSorting {
    static func sorted(
        _ processes: [SystemMonitorProcess],
        by column: ProcessSortColumn,
        descending: Bool
    ) -> [SystemMonitorProcess] {
        processes.sorted { left, right in
            let unavailable: (Bool, Bool) = switch column {
            case .cpu: (left.cpuPercent == nil, right.cpuPercent == nil)
            case .memory: (left.started == 0 && left.residentBytes == 0,
                           right.started == 0 && right.residentBytes == 0)
            case .name, .pid: (false, false)
            }
            if unavailable.0 != unavailable.1 { return !unavailable.0 }
            let order: ComparisonResult
            switch column {
            case .name: order = left.name.localizedStandardCompare(right.name)
            case .cpu: order = compare(left.cpuPercent ?? -1, right.cpuPercent ?? -1)
            case .memory: order = compare(left.residentBytes, right.residentBytes)
            case .pid: order = compare(left.pid, right.pid)
            }
            if order == .orderedSame { return left.pid < right.pid }
            return descending ? order == .orderedDescending : order == .orderedAscending
        }
    }

    private static func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }
}

nonisolated enum SystemMonitorProcessHierarchy {
    struct Row: Equatable, Identifiable, Sendable {
        let process: SystemMonitorProcess
        let cpuText: String
        /// The CPU number without its percent sign, for rows that draw the sign separately.
        let cpuValueText: String
        let memoryText: String
        let displayName: String
        let symbol: String
        let appBundlePath: String?
        var id: String { process.id }

        init(process: SystemMonitorProcess, parentName: String? = nil) {
            self.process = process
            // Process CPU sums all cores and can pass 100%; from 100 on, whole percent ("101", "1250") keeps it short.
            cpuValueText = process.cpuPercent.map {
                $0.formatted(.number.grouping(.never).precision(.fractionLength($0 >= 99.95 ? 0 : 1)))
            } ?? "—"
            cpuText = process.cpuPercent == nil ? cpuValueText : cpuValueText + "%"
            memoryText = process.residentBytes == 0 && process.started == 0
                ? "—"
                : ByteCountFormatter.string(
                    fromByteCount: Int64(min(process.residentBytes, UInt64(Int64.max))),
                    countStyle: .memory
                )
            let parts = process.name.split(separator: ".")
            let isVersion = parts.count > 1 && parts.allSatisfy { Int($0) != nil }
            appBundlePath = SystemMonitorProcessHierarchy.appBundlePath(for: process.executablePath)
            let bundleName = appBundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            let owner = bundleName ?? parentName
            displayName = isVersion ? owner.map { "\($0) (\(process.name))" } ?? process.name : process.name
            symbol = appBundlePath == nil && process.executablePath.hasPrefix("/") ? "terminal" : ""
        }
    }

    static func appBundlePath(for executablePath: String) -> String? {
        guard executablePath.hasPrefix("/") else { return nil }
        let components = URL(fileURLWithPath: executablePath).pathComponents
        return components.firstIndex(where: { $0.hasSuffix(".app") }).map {
            NSString.path(withComponents: Array(components[...$0]))
        }
    }
}

nonisolated enum SystemMonitorProcessRows {
    static func prepare(
        _ processes: [SystemMonitorProcess],
        column: ProcessSortColumn,
        descending: Bool,
        limit: Int? = nil
    ) -> [SystemMonitorProcessHierarchy.Row] {
        let names = Dictionary(processes.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let sorted = SystemMonitorProcessSorting.sorted(processes, by: column, descending: descending)
        return (limit.map { Array(sorted.prefix($0)) } ?? sorted)
            .map { SystemMonitorProcessHierarchy.Row(process: $0, parentName: names[$0.parentPID]) }
    }
}

@MainActor @Observable
final class SystemMonitorProcessIcons {
    /// macOS 26 draws an app with only a legacy `.icns` icon inside a padded gray tile. Such apps get their own
    /// `.icns` art, so every row shows the real icon at the full slot. Apps with an asset-catalog icon keep the
    /// system image.
    nonisolated static func icon(forBundle path: String) -> NSImage {
        let bundle = Bundle(path: path)
        if bundle?.object(forInfoDictionaryKey: "CFBundleIconName") == nil,
           let name = bundle?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let file = bundle?.path(forResource: (name as NSString).deletingPathExtension, ofType: "icns"),
           let image = NSImage(contentsOfFile: file) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private(set) var images: [String: NSImage] = [:]
    private var loaded = Set<String>()

    /// With `live`, cached icons stay while any live process runs from their bundle, not only while shown.
    func load(for rows: [SystemMonitorProcessHierarchy.Row], live: [SystemMonitorProcess]? = nil) async {
        let paths = Set(rows.compactMap(\.appBundlePath))
        let retained = live.map { processes in
            paths.union(images.keys.filter { path in
                let prefix = path + "/"
                return processes.contains { $0.executablePath.hasPrefix(prefix) }
            })
        }
        await load(bundlePaths: paths, retaining: retained)
    }

    func load(bundlePaths paths: Set<String>, retaining retained: Set<String>? = nil) async {
        let kept = retained ?? paths
        for path in images.keys where !kept.contains(path) { images[path] = nil }
        loaded.formIntersection(kept)
        let missing = paths.subtracting(loaded)
        guard !missing.isEmpty else { return }
        let worker = Task.detached(priority: .utility) {
            var images: [String: CGImage] = [:]
            for path in missing {
                guard !Task.isCancelled else { break }
                autoreleasepool {
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return }
                    var pixels = NSRect(x: 0, y: 0, width: 64, height: 64)
                    let image = isDirectory.boolValue ? SystemMonitorProcessIcons.icon(forBundle: path)
                        : NSImage(contentsOfFile: path)
                    images[path] = image?.cgImage(forProposedRect: &pixels, context: nil, hints: nil)
                }
            }
            return images
        }
        let prepared = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else { return }
        loaded.formUnion(missing)
        for (path, image) in prepared {
            images[path] = NSImage(cgImage: image, size: NSSize(width: OnePlusMetrics.navIcon, height: OnePlusMetrics.navIcon))
        }
    }
}

/// The busiest processes by CPU for the combined menu panel, with app icons.
/// Samples off the main thread. Keeps its five rows while closed, so a reopen never starts with an empty list.
@Observable
final class MenuPanelTopProcesses {
    static let shared = MenuPanelTopProcesses()

    @ObservationIgnored let sampler = SystemMonitorProcessSampler()
    private(set) var icons = SystemMonitorProcessIcons()
    private(set) var rows: [SystemMonitorProcessHierarchy.Row] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// The first sample sets the CPU baseline, so CPU readings start with the second call.
    func refresh(limit: Int = 3) async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task {
            #if MPT_DEMO
            let processes = DemoMenuPanelData.processes()
            #else
            let processes = await sampler.sample()
            #endif
            let prepared = await Task.detached(priority: .userInitiated) {
                SystemMonitorProcessRows.prepare(processes, column: .cpu, descending: true, limit: limit)
            }.value
            await icons.load(for: prepared, live: processes)
            rows = prepared
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }
}
