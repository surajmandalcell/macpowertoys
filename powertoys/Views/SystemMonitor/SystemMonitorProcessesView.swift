import AppKit
import SwiftUI

nonisolated enum ProcessSortColumn: String, CaseIterable {
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
    static func sorted(_ processes: [SystemMonitorProcess], by column: ProcessSortColumn,
                       descending: Bool) -> [SystemMonitorProcess] {
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
    struct Row: Identifiable {
        let process: SystemMonitorProcess
        let depth: Int
        var id: String { process.id }
    }

    static func rows(_ processes: [SystemMonitorProcess], by column: ProcessSortColumn,
                     descending: Bool) -> [Row] {
        let sorted = SystemMonitorProcessSorting.sorted(processes, by: column, descending: descending)
        let ids = Set(sorted.map(\.pid))
        let children = Dictionary(grouping: sorted.filter { ids.contains($0.parentPID) && $0.parentPID != $0.pid },
                                  by: \.parentPID)
        var rows: [Row] = []
        var visited = Set<Int32>()
        func append(_ process: SystemMonitorProcess, depth: Int) {
            guard visited.insert(process.pid).inserted else { return }
            rows.append(Row(process: process, depth: min(depth, 6)))
            for child in children[process.pid] ?? [] { append(child, depth: depth + 1) }
        }
        for process in sorted where !ids.contains(process.parentPID) || process.parentPID == process.pid {
            append(process, depth: 0)
        }
        for process in sorted { append(process, depth: 0) }
        return rows
    }
}

struct SystemMonitorProcessesView: View {
    @AppStorage("systemMonitor.processSortColumn") private var sortColumn = ProcessSortColumn.cpu.rawValue
    @AppStorage("systemMonitor.processSortDescending") private var descending = true
    @AppStorage("systemMonitor.processHierarchy") private var hierarchy = false
    @State private var sampler = SystemMonitorProcessSampler()
    @State private var processes: [SystemMonitorProcess] = []
    @State private var didLoad = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedID: String?
    @State private var pendingProcess: SystemMonitorProcess?
    @State private var pendingForce = false
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    @State private var networkEndpoints: [String] = []
    @State private var endpointsLoaded = false

    private var selected: SystemMonitorProcess? { processes.first { $0.id == selectedID } }
    private var activeColumn: ProcessSortColumn { ProcessSortColumn(rawValue: sortColumn) ?? .cpu }
    private var filteredProcesses: [SystemMonitorProcess] {
        processes.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || String($0.pid).contains(search)
                || $0.executablePath.localizedCaseInsensitiveContains(search)
        }
    }
    private var visibleRows: [SystemMonitorProcessHierarchy.Row] {
        hierarchy
            ? SystemMonitorProcessHierarchy.rows(filteredProcesses, by: activeColumn, descending: descending)
            : SystemMonitorProcessSorting.sorted(filteredProcesses, by: activeColumn, descending: descending)
                .map { .init(process: $0, depth: 0) }
    }

    var body: some View {
        WorkspacePage("Processes") {} content: {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search name, path or PID", text: $search)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: 400, minHeight: 34)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(searchFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: searchFocused ? 2 : 1)
                }
                Spacer(minLength: 0)
                Toggle("Hierarchy", isOn: $hierarchy)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Keep child processes below their parents; column headers sort each group")
                Text("\(processes.count) processes")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let selected {
                let children = processes.lazy.filter { $0.parentPID == selected.pid && $0.pid != selected.pid }.count
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selected.name).font(.system(size: 15, weight: .semibold))
                            Text("PID \(selected.pid) · Parent \(parentName(for: selected)) · \(children) \(children == 1 ? "child" : "children") · User \(selected.userID == UInt32.max ? "Unavailable" : String(selected.userID))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            if let lastUpdated {
                                Text("Updated \(lastUpdated, style: .time)")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Button { confirm(selected, force: false) } label: {
                            Text("Quit").utilityActionLabel()
                        }
                            .disabled(selected.started == 0)
                        Button(role: .destructive) { confirm(selected, force: true) } label: {
                            Text("Force Quit").utilityActionLabel()
                        }
                            .disabled(selected.started == 0)
                    }
                    .controlSize(.large)
                    QuietDivider()
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            detail("CPU", selected.cpuPercent.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "Measuring")
                            detail("Memory", selected.residentBytes == 0 && selected.started == 0 ? "Unavailable" : bytes(selected.residentBytes))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text("Virtual address space")
                                    Image(systemName: "info.circle")
                                        .accessibilityLabel("About virtual address space")
                                        .help("Address space reserved or mapped by this process, including shared files and unused ranges. It is not physical RAM in use; compare Memory for that.")
                                }
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(selected.virtualBytes == 0 && selected.started == 0 ? "Unavailable" : bytes(selected.virtualBytes))
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        GridRow {
                            detail("Threads", selected.threads == 0 ? "Unavailable" : "\(selected.threads)")
                            detail("Started", selected.started == 0 ? "Unavailable" :
                                Date(timeIntervalSince1970: TimeInterval(selected.started / 1_000_000))
                                    .formatted(date: .abbreviated, time: .standard))
                            detail("Process ID", "\(selected.pid)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("EXECUTABLE").utilitySectionHeader()
                            Spacer()
                            if selected.executablePath != "Unavailable" && selected.executablePath != "Protected process" {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(selected.executablePath, forType: .string)
                                } label: {
                                    Label("Copy Path", systemImage: "doc.on.doc")
                                        .utilityActionLabel()
                                }
                                .controlSize(.large)
                            }
                        }
                        Text(selected.executablePath)
                            .font(.system(size: 11)).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NETWORK ENDPOINTS").utilitySectionHeader()
                        if networkEndpoints.isEmpty {
                            Text(endpointsLoaded ? "No visible endpoints" : "Checking…")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            ForEach(networkEndpoints, id: \.self) { endpoint in
                                Text(endpoint).font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if selected.started == 0 {
                        Text("Quit is unavailable because macOS did not provide a verifiable process identity.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.system(size: 12))
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    header(.name).frame(maxWidth: .infinity, alignment: .leading)
                    header(.cpu).frame(width: 72, alignment: .trailing)
                    header(.memory).frame(width: 90, alignment: .trailing)
                    header(.pid).frame(width: 64, alignment: .trailing)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                LazyVStack(spacing: 0) {
                    ForEach(visibleRows) { row in
                        let process = row.process
                        Button { selectedID = process.id } label: {
                            HStack(spacing: 8) {
                                Text(process.name).lineLimit(1)
                                    .padding(.leading, CGFloat(row.depth) * 14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(process.cpuPercent.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—")
                                    .frame(width: 72, alignment: .trailing)
                                Text(process.residentBytes == 0 && process.started == 0 ? "—" : bytes(process.residentBytes))
                                    .frame(width: 90, alignment: .trailing)
                                Text("\(process.pid)").frame(width: 64, alignment: .trailing)
                            }
                            .font(.system(size: 12)).monospacedDigit()
                            .padding(.horizontal, 12).frame(minHeight: 30)
                            .contentShape(Rectangle())
                            .background(selectedID == process.id ? Color.accentColor.opacity(0.1) : .clear)
                        }
                        .buttonStyle(UtilityInteractionButtonStyle())
                        .focusEffectDisabled()
                        .accessibilityLabel("\(process.name), PID \(process.pid)")
                        QuietDivider()
                    }
                }
                if !didLoad {
                    ProgressView("Loading processes…").frame(maxWidth: .infinity).padding(30)
                } else if processes.isEmpty {
                    Text("No processes are available")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30)
                } else if filteredProcesses.isEmpty {
                    Text("No matching processes")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30)
                }
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .task {
            while !Task.isCancelled {
                let result = await sampler.sample()
                guard !Task.isCancelled else { break }
                processes = result
                lastUpdated = Date()
                didLoad = true
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task(id: selectedID) {
            networkEndpoints = []
            endpointsLoaded = false
            guard let selectedID, let pid = processes.first(where: { $0.id == selectedID })?.pid else { return }
            while !Task.isCancelled {
                guard processes.contains(where: { $0.id == selectedID }) else { return }
                let endpoints = await SystemMonitorProcessPorts.endpoints(pid: pid)
                guard !Task.isCancelled else { return }
                networkEndpoints = endpoints
                endpointsLoaded = true
                try? await Task.sleep(for: .seconds(30))
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

    private func header(_ column: ProcessSortColumn) -> some View {
        Button {
            if activeColumn == column { descending.toggle() }
            else { sortColumn = column.rawValue; descending = column != .name }
        } label: {
            HStack(spacing: 3) {
                Text(column.title.uppercased())
                if activeColumn == column {
                    Image(systemName: descending ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .utilitySectionHeader()
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel("Sort by \(column.title), \(activeColumn == column ? (descending ? "descending" : "ascending") : "inactive")")
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .memory)
    }
    private func parentName(for process: SystemMonitorProcess) -> String {
        guard process.parentPID > 0 else { return "Unavailable" }
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
}
