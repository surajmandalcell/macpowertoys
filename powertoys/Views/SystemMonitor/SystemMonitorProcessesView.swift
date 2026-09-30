import AppKit
import OnePlusUI
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
        let symbol: String
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
            let bundleName = URL(fileURLWithPath: process.executablePath).pathComponents
                .first { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }
            let owner = bundleName ?? parentName
            displayName = isVersion ? owner.map { "\($0) (\(process.name))" } ?? process.name : process.name
            symbol = bundleName != nil ? "app" : process.started == 0 ? "lock"
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
    @State private var rows: [SystemMonitorProcessHierarchy.Row] = []

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
                                    Image(systemName: row.symbol)
                                        .font(.system(size: 13))
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
        .task { await sample() }
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
            try? await Task.sleep(for: .seconds(3))
        }
    }
}

struct SystemMonitorProcessesView: View {
    @AppStorage("systemMonitor.processSortColumn") private var sortColumn = ProcessSortColumn.cpu.rawValue
    @AppStorage("systemMonitor.processSortDescending") private var descending = true
    @AppStorage("systemMonitor.processHierarchy") private var storedHierarchy = false
    @State private var sampler = SystemMonitorProcessSampler()
    @State private var processes: [SystemMonitorProcess] = []
    @State private var visibleRows: [SystemMonitorProcessHierarchy.Row] = []
    @State private var matchingCount = 0
    @State private var processGeneration = 0
    @State private var internalSearch = ""
    @State private var didLoad = false
    @State private var selectedID: String?
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
    private var selected: SystemMonitorProcess? { processes.first { $0.id == selectedID } }
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
        .task { await sampleProcesses() }
        .task(id: rowsRequest) { await prepareVisibleRows(rowsRequest) }
        .task(id: selectedID) { await sampleEndpoints() }
        .sheet(isPresented: Binding(
            get: { selectedID != nil },
            set: { if !$0 { selectedID = nil } }
        )) {
            if let selected {
                ProcessDetailSheet(
                    process: selected,
                    parentName: parentName(for: selected),
                    childCount: processes.lazy.filter { $0.parentPID == selected.pid && $0.pid != selected.pid }.count,
                    endpoints: networkEndpoints,
                    endpointsLoaded: endpointsLoaded,
                    lastUpdated: lastUpdated,
                    onQuit: { confirm(selected, force: false) },
                    onForceQuit: { confirm(selected, force: true) },
                    onDone: { selectedID = nil }
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
            Text(pendingForce ? "This process will stop immediately." : "The process can save its work before it exits.")
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
        return TaskManagerPanel {
            VStack(spacing: 0) {
                tableHeader
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleRows) { row in
                            SystemMonitorProcessRow(
                                row: row,
                                selected: selectedID == row.id,
                                inspect: { selectedID = $0.id },
                                copyPath: copy,
                                confirm: confirm
                            )
                            .equatable()
                        }
                        if !didLoad {
                            ProgressView().controlSize(.small)
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else if matchingCount == 0 {
                            VStack(spacing: 8) {
                                Text("No matching processes").font(.system(size: 12, weight: .medium))
                                Text("Search for a process name, path, or PID.")
                                    .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
                                if !search.isEmpty {
                                    Button("Clear search") { searchBinding.wrappedValue = "" }
                                        .taskManagerControl()
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }
                }
                .thinScrollIndicators()
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            header(.name).padding(.leading, 26).frame(maxWidth: .infinity, alignment: .leading)
            header(.cpu).frame(width: 72, alignment: .trailing)
            header(.memory).frame(width: 90, alignment: .trailing)
            header(.pid).frame(width: 64, alignment: .trailing)
            Color.clear.frame(width: 24)
        }
        .onePlusTableHeader()
    }

    private func header(_ column: ProcessSortColumn) -> some View {
        Button {
            if activeColumn == column {
                descending.toggle()
            } else {
                sortColumn = column.rawValue
                descending = column != .name
            }
        } label: {
            HStack(spacing: 5) {
                Text(column.title.uppercased())
                if activeColumn == column {
                    Image(systemName: descending ? "chevron.down" : "chevron.up")
                        .font(.system(size: 7, weight: .semibold))
                }
            }
            .font(.system(size: 8))
            .tracking(0.5)
            .foregroundStyle(activeColumn == column ? TaskManagerTheme.secondary : TaskManagerTheme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(column.title), \(activeColumn == column ? (descending ? "descending" : "ascending") : "inactive")")
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
            didLoad = true
            if let selectedID, !result.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
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
        visibleRows = result.rows
        matchingCount = result.matchingCount
    }

    private func sampleEndpoints() async {
        networkEndpoints = []
        endpointsLoaded = false
        guard let selectedID, let pid = processes.first(where: { $0.id == selectedID })?.pid else { return }
        while !Task.isCancelled {
            guard processes.contains(where: { $0.id == selectedID }) else { return }
            let endpoints = await SystemMonitorProcessPorts.endpoints(pid: pid)
            guard !Task.isCancelled else { return }
            networkEndpoints = endpoints
            endpointsLoaded = true
            try? await Task.sleep(for: .seconds(10))
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

private struct SystemMonitorProcessRow: View, Equatable {
    let row: SystemMonitorProcessHierarchy.Row
    let selected: Bool
    let inspect: (SystemMonitorProcess) -> Void
    let copyPath: (String) -> Void
    let confirm: (SystemMonitorProcess, Bool) -> Void

    static func == (left: Self, right: Self) -> Bool {
        left.row == right.row && left.selected == right.selected
    }

    var body: some View {
        let process = row.process
        HStack(spacing: 8) {
            Button { inspect(process) } label: {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(TaskManagerTheme.secondary)
                            .frame(width: 18, height: 18)
                        Text(row.displayName).lineLimit(1)
                    }
                    .padding(.leading, CGFloat(row.depth) * 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.cpuText).frame(width: 72, alignment: .trailing)
                    Text(row.memoryText).frame(width: 90, alignment: .trailing)
                    Text(row.pidText).frame(width: 64, alignment: .trailing)
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inspect \(process.name), PID \(process.pid)")
            .accessibilityIdentifier("task-manager.process.row.\(process.pid)")

            Menu {
                Button("Inspect") { inspect(process) }
                if process.executablePath != "Unavailable" && process.executablePath != "Protected process" {
                    Button("Copy Executable Path") { copyPath(process.executablePath) }
                }
                Divider()
                Button("Quit") { confirm(process, false) }
                    .disabled(process.started == 0)
                Button("Force Quit", role: .destructive) { confirm(process, true) }
                    .disabled(process.started == 0)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(TaskManagerTheme.secondary)
                    .frame(width: 24, height: 23)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 24)
            .accessibilityIdentifier("task-manager.process.actions.\(process.pid)")
        }
        .onePlusTableRow(selected: selected)
    }
}

struct ProcessDetailSheet: View {
    let process: SystemMonitorProcess
    let parentName: String
    let childCount: Int
    let endpoints: [String]
    let endpointsLoaded: Bool
    let lastUpdated: Date?
    let onQuit: () -> Void
    let onForceQuit: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Process Information")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 23, height: 23)
                }
                .taskManagerControl(.quiet, minWidth: 23, minHeight: 23, horizontalPadding: 0)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(TaskManagerTheme.window)
            .overlay(alignment: .bottom) { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identity
                    stats
                    properties
                    executable
                    endpointsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .thinScrollIndicators()

            HStack(spacing: 8) {
                Button("Quit") { onQuit() }
                    .taskManagerControl(.destructive)
                    .disabled(process.started == 0)
                TaskManagerProcessActionMenu(
                    isEnabled: process.started != 0,
                    onForceQuit: onForceQuit
                )
                .frame(width: 68, height: 27)
                .background(
                    Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: TaskManagerTheme.controlRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: TaskManagerTheme.controlRadius)
                        .strokeBorder(TaskManagerTheme.line)
                }
                Spacer()
                Button("Copy details") { copyDetails() }
                    .taskManagerControl()
                Button("Done", action: onDone)
                    .taskManagerControl(.primary, minWidth: 58)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(TaskManagerTheme.window)
            .overlay(alignment: .top) { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }
        }
        .frame(width: 450, height: 520)
        .background(TaskManagerTheme.window)
        .foregroundStyle(TaskManagerTheme.ink)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.06))
                .overlay { Image(systemName: "gearshape").font(.system(size: 22)).foregroundStyle(TaskManagerTheme.secondary) }
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(TaskManagerTheme.line) }
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(process.name).font(.system(size: 17, weight: .medium)).lineLimit(1)
                Text("PID \(process.pid) · \(childCount) \(childCount == 1 ? "child" : "children")")
                    .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
                if let lastUpdated {
                    Text("Updated \(lastUpdated, style: .time)")
                        .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.muted)
                }
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
        }
        .frame(height: 68)
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
        .overlay(alignment: .bottom) { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }
    }

    private var executable: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("EXECUTABLE").font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                Spacer()
                if process.executablePath != "Unavailable" && process.executablePath != "Protected process" {
                    Button { copy(process.executablePath) } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11)).frame(width: 23, height: 22)
                    }
                    .taskManagerControl(.quiet, minWidth: 23, minHeight: 22, horizontalPadding: 0)
                    .help("Copy executable path")
                }
            }
            Text(executablePathDisplay)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(TaskManagerTheme.secondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(TaskManagerTheme.lineSoft) }
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

private struct TaskManagerProcessActionMenu: NSViewRepresentable {
    let isEnabled: Bool
    let onForceQuit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: onForceQuit)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: 10.5, weight: .medium)
        button.contentTintColor = NSColor(calibratedWhite: 0.929, alpha: 0.88)
        button.alignment = .left
        button.addItem(withTitle: "More")

        let forceQuit = NSMenuItem(
            title: "Force Quit",
            action: #selector(Coordinator.forceQuit),
            keyEquivalent: ""
        )
        forceQuit.target = context.coordinator
        button.menu?.addItem(forceQuit)
        button.setAccessibilityLabel("More")
        button.setAccessibilityIdentifier("task-manager.process.more")
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.action = onForceQuit
        button.item(withTitle: "Force Quit")?.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func forceQuit() {
            action()
        }
    }
}
