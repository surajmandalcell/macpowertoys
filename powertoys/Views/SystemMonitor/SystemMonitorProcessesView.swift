import AppKit
import OnePlusUI
import Observation
import SwiftUI

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
        let depth: Int
        let cpuText: String
        let memoryText: String
        let pidText: String
        let displayName: String
        let tableName: String
        let symbol: String
        let appBundlePath: String?
        var id: String { process.id }

        init(process: SystemMonitorProcess, depth: Int, parentName: String? = nil) {
            self.process = process
            self.depth = depth
            cpuText = process.cpuPercent.map {
                "\($0.formatted(.number.precision(.fractionLength(1))))%"
            } ?? "—"
            memoryText = process.residentBytes == 0 && process.started == 0
                ? "—"
                : ByteCountFormatter.string(
                    fromByteCount: Int64(min(process.residentBytes, UInt64(Int64.max))),
                    countStyle: .memory
                )
            pidText = String(process.pid)
            let parts = process.name.split(separator: ".")
            let isVersion = parts.count > 1 && parts.allSatisfy { Int($0) != nil }
            let components = URL(fileURLWithPath: process.executablePath).pathComponents
            appBundlePath = components.firstIndex(where: { $0.hasSuffix(".app") }).map {
                NSString.path(withComponents: Array(components[...$0]))
            }
            let bundleName = appBundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            let owner = bundleName ?? parentName
            displayName = isVersion ? owner.map { "\($0) (\(process.name))" } ?? process.name : process.name
            tableName = String(repeating: "    ", count: depth) + displayName
            symbol = process.started == 0 ? "lock"
                : process.executablePath.hasPrefix("/System/Library/") ? "gearshape" : "terminal"
        }
    }

    static func rows(
        _ processes: [SystemMonitorProcess],
        by column: ProcessSortColumn,
        descending: Bool
    ) -> [Row] {
        let sorted = SystemMonitorProcessSorting.sorted(processes, by: column, descending: descending)
        let ids = Set(sorted.map(\.pid))
        let names = Dictionary(sorted.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let children = Dictionary(
            grouping: sorted.filter { ids.contains($0.parentPID) && $0.parentPID != $0.pid },
            by: \.parentPID
        )
        var rows: [Row] = []
        var visited = Set<Int32>()

        func append(_ process: SystemMonitorProcess, depth: Int) {
            guard visited.insert(process.pid).inserted else { return }
            rows.append(Row(process: process, depth: min(depth, 6), parentName: names[process.parentPID]))
            for child in children[process.pid] ?? [] { append(child, depth: depth + 1) }
        }

        for process in sorted where !ids.contains(process.parentPID) || process.parentPID == process.pid {
            append(process, depth: 0)
        }
        for process in sorted { append(process, depth: 0) }
        return rows
    }
}

nonisolated enum SystemMonitorProcessRows {
    struct Result: Sendable {
        let rows: [SystemMonitorProcessHierarchy.Row]
        let matchingCount: Int
    }

    static func prepare(
        _ processes: [SystemMonitorProcess],
        search: String,
        hierarchy: Bool,
        column: ProcessSortColumn,
        descending: Bool,
        limit: Int? = nil
    ) -> Result {
        let names = Dictionary(processes.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let filtered = processes.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || String($0.pid).contains(search)
                || $0.executablePath.localizedCaseInsensitiveContains(search)
                || names[$0.parentPID]?.localizedCaseInsensitiveContains(search) == true
        }
        let prepared = hierarchy
            ? SystemMonitorProcessHierarchy.rows(filtered, by: column, descending: descending)
            : SystemMonitorProcessSorting.sorted(filtered, by: column, descending: descending)
                .map { SystemMonitorProcessHierarchy.Row(process: $0, depth: 0, parentName: names[$0.parentPID]) }
        return Result(
            rows: limit.map { Array(prepared.prefix($0)) } ?? prepared,
            matchingCount: filtered.count
        )
    }

    static func prepareOffMain(
        _ processes: [SystemMonitorProcess],
        search: String,
        hierarchy: Bool,
        column: ProcessSortColumn,
        descending: Bool,
        limit: Int? = nil
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            prepare(
                processes,
                search: search,
                hierarchy: hierarchy,
                column: column,
                descending: descending,
                limit: limit
            )
        }.value
    }
}

nonisolated enum SystemMonitorProcessActions {
    static func canTerminate(_ process: SystemMonitorProcess) -> Bool {
        process.started != 0 && process.pid > 1 && process.pid != ProcessInfo.processInfo.processIdentifier
    }

    static func canCopyPath(_ process: SystemMonitorProcess) -> Bool {
        process.executablePath.hasPrefix("/")
    }

    @MainActor
    static func tableActions(_ process: SystemMonitorProcess, inspect: @escaping () -> Void,
                             copyPath: @escaping (String) -> Void,
                             confirm: @escaping (SystemMonitorProcess, Bool) -> Void) -> [OnePlusTableAction] {
        var actions = [OnePlusTableAction("Inspect", action: inspect)]
        if canCopyPath(process) {
            actions.append(OnePlusTableAction("Copy executable path") { copyPath(process.executablePath) })
        }
        if canTerminate(process) {
            actions.append(OnePlusTableAction("Quit") { confirm(process, false) })
            actions.append(OnePlusTableAction("Force Quit") { confirm(process, true) })
        }
        return actions
    }

}

@MainActor @Observable
private final class SystemMonitorProcessIcons {
    private(set) var images: [String: NSImage] = [:]
    private var loaded = Set<String>()

    func load(for rows: [SystemMonitorProcessHierarchy.Row]) async {
        let paths = Set(rows.compactMap(\.appBundlePath))
        for path in images.keys where !paths.contains(path) { images[path] = nil }
        loaded.formIntersection(paths)
        let missing = paths.subtracting(loaded)
        guard !missing.isEmpty else { return }
        let worker = Task.detached(priority: .utility) {
            var data: [String: Data] = [:]
            for path in missing {
                guard !Task.isCancelled else { break }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    data[path] = NSWorkspace.shared.icon(forFile: path).tiffRepresentation
                }
            }
            return data
        }
        let data = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else { return }
        loaded.formUnion(missing)
        for (path, bytes) in data { images[path] = NSImage(data: bytes) }
    }
}

private struct SystemMonitorProcessRowsRequest: Hashable {
    let generation: Int
    let search: String
    let hierarchy: Bool
    let column: ProcessSortColumn
    let descending: Bool
}

struct SystemMonitorOverviewProcessesView: View {
    let onViewAll: () -> Void
    let onSelect: (SystemMonitorProcess) -> Void

    @State private var sampler = SystemMonitorProcessSampler()
    @State private var processIcons = SystemMonitorProcessIcons()
    @State private var rows: [SystemMonitorProcessHierarchy.Row] = []
    @Environment(\.onePlusIsVisible) private var isVisible

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Top processes").font(.system(size: 11, weight: .medium))
                Spacer()
                Button("View all", action: onViewAll)
                    .buttonStyle(OnePlusButtonStyle(.link, size: .small))
            }
            .frame(minHeight: 17)
            TaskManagerPanel {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                        Text("CPU").frame(width: 62, alignment: .trailing)
                        Text("MEMORY").frame(width: 82, alignment: .trailing)
                    }
                    .onePlusTableHeader()
                    ForEach(rows) { row in
                        Button { onSelect(row.process) } label: {
                            HStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Group {
                                        if let path = row.appBundlePath, let icon = processIcons.images[path] {
                                            Image(nsImage: icon).resizable().scaledToFit()
                                        } else { Image(systemName: row.symbol).font(.system(size: 13)) }
                                    }
                                    .foregroundStyle(TaskManagerTheme.secondary)
                                    .frame(width: 18, height: 18)
                                    Text(row.displayName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(TaskManagerTheme.ink)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.cpuText).frame(width: 62, alignment: .trailing)
                                Text(row.memoryText).frame(width: 82, alignment: .trailing)
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(TaskManagerTheme.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 0))
                        .onePlusTableRow()
                    }
                    if rows.isEmpty {
                        Text("—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(TaskManagerTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 165)
                    }
                }
                .frame(height: 203, alignment: .top)
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            await sample()
        }
    }

    private func sample() async {
        while !Task.isCancelled {
            let processes = await sampler.sample()
            let result = await SystemMonitorProcessRows.prepareOffMain(
                processes,
                search: "",
                hierarchy: false,
                column: .cpu,
                descending: true,
                limit: 5
            )
            guard !Task.isCancelled else { return }
            rows = result.rows
            await processIcons.load(for: result.rows)
            try? await Task.sleep(for: .seconds(3))
        }
    }
}

struct SystemMonitorProcessesView: View {
    @Environment(\.onePlusIsVisible) private var isVisible
    @AppStorage("systemMonitor.processSortColumn") private var sortColumn = ProcessSortColumn.cpu.rawValue
    @AppStorage("systemMonitor.processSortDescending") private var descending = true
    @AppStorage("systemMonitor.processHierarchy") private var storedHierarchy = false
    @State private var sampler = SystemMonitorProcessSampler()
    @State private var processIcons = SystemMonitorProcessIcons()
    @State private var processes: [SystemMonitorProcess] = []
    @State private var processGeneration = 0
    @State private var internalSearch = ""
    @State private var didLoad = false
    @State private var selectedProcessIDs = Set<String>()
    @State private var inspectedProcessID: String?
    @State private var tableRows: [OnePlusTableItem] = []
    @State private var pendingProcess: SystemMonitorProcess?
    @State private var pendingForce = false
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    @State private var networkEndpoints: [String] = []
    @State private var endpointsLoaded = false

    private let externalSearch: Binding<String>?
    private let externalHierarchy: Binding<Bool>?
    private let showsToolbar: Bool

    init(
        search: Binding<String>? = nil,
        hierarchy: Binding<Bool>? = nil,
        showsToolbar: Bool = true
    ) {
        externalSearch = search
        externalHierarchy = hierarchy
        self.showsToolbar = showsToolbar
    }

    private var search: String { externalSearch?.wrappedValue ?? internalSearch }
    private var hierarchy: Bool { externalHierarchy?.wrappedValue ?? storedHierarchy }
    private var inspected: SystemMonitorProcess? { processes.first { $0.id == inspectedProcessID } }
    private var selected: SystemMonitorProcess? {
        guard selectedProcessIDs.count == 1 else { return nil }
        return processes.first { selectedProcessIDs.contains($0.id) }
    }
    private var inspectAction: (() -> Void)? {
        guard isVisible, let selected else { return nil }
        return { inspectedProcessID = selected.id }
    }
    private var activeColumn: ProcessSortColumn { ProcessSortColumn(rawValue: sortColumn) ?? .cpu }
    private var rowsRequest: SystemMonitorProcessRowsRequest {
        SystemMonitorProcessRowsRequest(
            generation: processGeneration,
            search: search,
            hierarchy: hierarchy,
            column: activeColumn,
            descending: descending
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            if showsToolbar { toolbar }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(TaskManagerTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            processTable
        }
        .foregroundStyle(TaskManagerTheme.ink)
        .focusedSceneValue(\.appInspect, inspectAction)
        .task(id: isVisible) {
            guard isVisible else { return }
            await sampleProcesses()
        }
        .task(id: rowsRequest) {
            guard isVisible else { return }
            await prepareVisibleRows(rowsRequest)
        }
        .task(id: isVisible ? inspectedProcessID : nil) {
            guard isVisible else { return }
            await sampleEndpoints()
        }
        .sheet(isPresented: Binding(
            get: { inspectedProcessID != nil },
            set: { if !$0 { inspectedProcessID = nil } }
        )) {
            if let selected = inspected {
                ProcessDetailSheet(
                    process: selected,
                    parentName: parentName(for: selected),
                    childCount: processes.lazy.filter { $0.parentPID == selected.pid && $0.pid != selected.pid }.count,
                    endpoints: networkEndpoints,
                    endpointsLoaded: endpointsLoaded,
                    lastUpdated: lastUpdated,
                    errorMessage: errorMessage,
                    onQuit: { confirm(selected, force: false) },
                    onForceQuit: { confirm(selected, force: true) },
                    onDone: { inspectedProcessID = nil }
                )
            }
        }
        .confirmationDialog(
            pendingForce ? "Force quit \(pendingProcess?.name ?? "process")?" : "Quit \(pendingProcess?.name ?? "process")?",
            isPresented: $showingConfirmation
        ) {
            Button(pendingForce ? "Force Quit" : "Quit", role: .destructive) {
                guard let pendingProcess else { return }
                do {
                    try SystemMonitorProcessControl.terminate(pendingProcess, force: pendingForce)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text(pendingForce ? "This process will stop immediately." : "The process will be asked to stop. Unsaved work may be lost.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Text("Hierarchy").font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                Toggle("Hierarchy", isOn: hierarchyBinding)
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            Text("\(processes.count) processes")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(TaskManagerTheme.muted)
            Spacer()
            TaskManagerSearchField(prompt: "Search name, path, or PID", text: searchBinding)
        }
    }

    private var processTable: some View {
        TaskManagerPanel {
            OnePlusNativeTable(
                columns: [
                    OnePlusGridColumn("Process", width: 400),
                    OnePlusGridColumn("CPU", width: 84, trailing: true),
                    OnePlusGridColumn("Memory", width: 102, trailing: true),
                    OnePlusGridColumn("PID", width: 76, trailing: true),
                ],
                rows: tableRows,
                selection: $selectedProcessIDs,
                sortColumn: ProcessSortColumn.allCases.firstIndex(of: activeColumn) ?? 1,
                ascending: !descending,
                sort: { index, ascending in
                    guard ProcessSortColumn.allCases.indices.contains(index) else { return }
                    sortColumn = ProcessSortColumn.allCases[index].rawValue
                    descending = !ascending
                },
                open: { ids in
                    guard ids.count == 1, let process = processes.first(where: { ids.contains($0.id) }) else { return }
                    inspectedProcessID = process.id
                },
                actions: { ids in
                    guard ids.count == 1, let process = processes.first(where: { ids.contains($0.id) }) else { return [] }
                    return SystemMonitorProcessActions.tableActions(
                        process, inspect: { inspectedProcessID = process.id }, copyPath: copy, confirm: confirm
                    )
                }
            )
            .accessibilityIdentifier("task-manager.process.table")
            .overlay {
                if tableRows.isEmpty {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 28) // Native table header stays fixed.
                        ZStack {
                            if !didLoad { ProgressView().controlSize(.small) }
                            else {
                                OnePlusEmptyState("No matching processes", systemImage: "list.bullet.rectangle") {
                                    if !search.isEmpty {
                                        Button("Clear search") { searchBinding.wrappedValue = "" }
                                            .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .allowsHitTesting(didLoad)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchBinding: Binding<String> {
        externalSearch ?? Binding(get: { internalSearch }, set: { internalSearch = $0 })
    }

    private var hierarchyBinding: Binding<Bool> {
        externalHierarchy ?? Binding(get: { storedHierarchy }, set: { storedHierarchy = $0 })
    }

    private func sampleProcesses() async {
        while !Task.isCancelled {
            let result = await sampler.sample()
            guard !Task.isCancelled else { return }
            processes = result
            processGeneration &+= 1
            lastUpdated = Date()
            selectedProcessIDs.formIntersection(result.map(\.id))
            if let inspectedProcessID, !result.contains(where: { $0.id == inspectedProcessID }) {
                self.inspectedProcessID = nil
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func prepareVisibleRows(_ request: SystemMonitorProcessRowsRequest) async {
        let result = await SystemMonitorProcessRows.prepareOffMain(
            processes,
            search: request.search,
            hierarchy: request.hierarchy,
            column: request.column,
            descending: request.descending
        )
        guard !Task.isCancelled, rowsRequest == request else { return }
        updateTableRows(result.rows)
        selectedProcessIDs.formIntersection(result.rows.map(\.id))
        if request.generation > 0 { didLoad = true }
        await processIcons.load(for: result.rows)
        guard !Task.isCancelled, rowsRequest == request else { return }
        updateTableRows(result.rows)
    }

    private func updateTableRows(_ rows: [SystemMonitorProcessHierarchy.Row]) {
        let prepared = rows.map { row in
            OnePlusTableItem(id: row.id, cells: [row.tableName, row.cpuText, row.memoryText, row.pidText],
                             symbol: row.symbol, image: row.appBundlePath.flatMap { processIcons.images[$0] })
        }
        if tableRows != prepared { tableRows = prepared }
    }

    private func sampleEndpoints() async {
        networkEndpoints = []
        endpointsLoaded = false
        guard let inspectedProcessID, let pid = processes.first(where: { $0.id == inspectedProcessID })?.pid else { return }
        while !Task.isCancelled {
            guard processes.contains(where: { $0.id == inspectedProcessID }) else { return }
            let endpoints = await SystemMonitorProcessPorts.endpoints(pid: pid)
            guard !Task.isCancelled else { return }
            networkEndpoints = endpoints
            endpointsLoaded = true
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func parentName(for process: SystemMonitorProcess) -> String {
        guard process.parentPID > 0 else { return "—" }
        if let parent = processes.first(where: { $0.pid == process.parentPID }) {
            return "\(parent.name) (\(parent.pid))"
        }
        return String(process.parentPID)
    }

    private func confirm(_ process: SystemMonitorProcess, force: Bool) {
        pendingProcess = process
        pendingForce = force
        showingConfirmation = true
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

}

struct ProcessDetailSheet: View {
    let process: SystemMonitorProcess
    let parentName: String
    let childCount: Int
    let endpoints: [String]
    let endpointsLoaded: Bool
    let lastUpdated: Date?
    var errorMessage: String? = nil
    let onQuit: () -> Void
    let onForceQuit: () -> Void
    let onDone: () -> Void

    var body: some View {
        OnePlusSheet("Process Information", width: .small, close: onDone) {
            ScrollView {
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[6]) {
                    if let errorMessage { OnePlusBanner(errorMessage, tone: .error) }
                    identity
                    stats
                    properties
                    executable
                    endpointsSection
                }
            }
            .thinScrollIndicators()
        } footer: {
            Button("Quit", action: onQuit)
                .buttonStyle(OnePlusButtonStyle(.destructive))
                .disabled(!SystemMonitorProcessActions.canTerminate(process))
            OnePlusMenuButton("More", variant: .neutral, items: [
                .item(OnePlusPopupMenuItem("Force Quit", role: .destructive, isEnabled: SystemMonitorProcessActions.canTerminate(process), action: onForceQuit)),
            ])
            .accessibilityIdentifier("task-manager.process.more")
            Button("Copy details") { copyDetails() }
                .buttonStyle(OnePlusButtonStyle(.neutral))
            Button("Done", action: onDone)
                .buttonStyle(OnePlusButtonStyle(.primary))
        }
        .frame(height: 520)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius)
                .fill(OnePlusColor.raised)
                .overlay { Image(systemName: "gearshape").font(.system(size: 22)).foregroundStyle(TaskManagerTheme.secondary) }
                .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius).strokeBorder(TaskManagerTheme.line) }
                .frame(width: 44, height: 44)
            Text(process.name).font(.system(size: 17, weight: .medium)).lineLimit(1)
                .help(process.name)
            Spacer(minLength: OnePlusMetrics.spacing[2])
            if let lastUpdated {
                Text(lastUpdated, style: .time)
                    .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.muted)
                    .help("Last updated")
            }
        }
    }

    private var stats: some View {
        TaskManagerPanel {
            HStack(spacing: 0) {
                stat("CPU", process.cpuPercent.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—")
                Rectangle().fill(TaskManagerTheme.line).frame(width: 1)
                stat("Memory", process.residentBytes == 0 && process.started == 0 ? "—" : bytes(process.residentBytes))
                Rectangle().fill(TaskManagerTheme.line).frame(width: 1)
                stat("Threads", process.threads == 0 ? "—" : "\(process.threads)")
            }
            .frame(height: 68)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
            Text(value).font(.system(size: 18, weight: .medium)).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var properties: some View {
        VStack(spacing: 0) {
            property("PID", String(process.pid))
            property("Children", String(childCount))
            property("Parent", parentName)
            property("User ID", process.userID == UInt32.max ? "—" : String(process.userID))
            property("Started", process.started == 0 ? "—" : startedDate)
            property("Virtual address space", process.virtualBytes == 0 && process.started == 0 ? "—" : bytes(process.virtualBytes),
                     help: "Reserved or mapped address ranges, including shared files and unused regions. This is not physical RAM. Compare Memory for RAM in use.")
        }
    }

    private func property(_ title: String, _ value: String, help: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            HStack(spacing: 4) {
                Text(title)
                if let help {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .help(help)
                        .accessibilityLabel("About \(title)")
                }
            }
            .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 10.5))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 7)
        .onePlusRowHover()
        .overlay(alignment: .bottom) { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }
    }

    private var executable: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("EXECUTABLE").font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                Spacer()
                if SystemMonitorProcessActions.canCopyPath(process) {
                    Button { copy(process.executablePath) } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(OnePlusButtonStyle(.borderedIcon, size: .small))
                    .accessibilityLabel("Copy executable path")
                    .help("Copy executable path")
                }
            }
            Text(executablePathDisplay)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(TaskManagerTheme.secondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OnePlusColor.track, in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
                .overlay { RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius).strokeBorder(TaskManagerTheme.lineSoft) }
            if executablePathDisplay == "—" {
                Text("The executable path is not available for this process.")
                    .font(.system(size: 9))
                    .foregroundStyle(TaskManagerTheme.muted)
            }
        }
    }

    private var endpointsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NETWORK ENDPOINTS").font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
            if endpoints.isEmpty {
                Text(endpointsLoaded ? "No visible endpoints" : "—")
                    .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.muted)
            } else {
                ForEach(endpoints, id: \.self) { endpoint in
                    Text(endpoint).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
    }

    private var startedDate: String {
        Date(timeIntervalSince1970: TimeInterval(process.started / 1_000_000))
            .formatted(date: .abbreviated, time: .standard)
    }

    private var executablePathDisplay: String {
        process.executablePath == "Unavailable" || process.executablePath == "Protected process"
            ? "—" : process.executablePath
    }

    private func copyDetails() {
        let details = """
        \(process.name)
        PID: \(process.pid)
        Parent: \(parentName)
        CPU: \(process.cpuPercent.map { "\($0)%" } ?? "—")
        Memory: \(bytes(process.residentBytes))
        Virtual address space: \(bytes(process.virtualBytes))
        Threads: \(process.threads)
        Executable: \(process.executablePath)
        Network endpoints: \(endpoints.isEmpty ? "None visible" : endpoints.joined(separator: ", "))
        """
        copy(details)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .memory)
    }
}
