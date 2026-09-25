import AppKit
import SwiftUI

private enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case name = "Name"
    var id: String { rawValue }
}

struct SystemMonitorProcessesView: View {
    @AppStorage("systemMonitor.processLimit") private var rowLimit = 25
    @State private var sampler = SystemMonitorProcessSampler()
    @State private var processes: [SystemMonitorProcess] = []
    @State private var didLoad = false
    @State private var search = ""
    @State private var sort = ProcessSort.cpu
    @State private var selectedID: String?
    @State private var pendingProcess: SystemMonitorProcess?
    @State private var pendingForce = false
    @State private var showingConfirmation = false
    @State private var errorMessage: String?

    private var selected: SystemMonitorProcess? {
        processes.first { $0.id == selectedID }
    }

    private var visibleProcesses: [SystemMonitorProcess] {
        let filtered = processes.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || String($0.pid).contains(search)
        }
        let sorted = filtered.sorted { left, right in
            switch sort {
            case .cpu:
                if left.cpuPercent != right.cpuPercent {
                    return (left.cpuPercent ?? -1) > (right.cpuPercent ?? -1)
                }
                if left.cpuPercent == nil, left.residentBytes != right.residentBytes {
                    return left.residentBytes > right.residentBytes
                }
            case .memory:
                if left.residentBytes != right.residentBytes {
                    return left.residentBytes > right.residentBytes
                }
            case .name:
                let order = left.name.localizedStandardCompare(right.name)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return left.pid < right.pid
        }
        return Array(sorted.prefix(rowLimit))
    }

    var body: some View {
        WorkspacePage("Processes") {
            Button("Open Terminal", systemImage: "terminal") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
            }
            .help("Open Terminal")
        } content: {
            HStack(spacing: 12) {
                NativeSearchField(text: $search, placeholder: "Search name or PID")
                    .frame(maxWidth: 360)
                    .frame(height: 24)
                Picker("Sort", selection: $sort) {
                    ForEach(ProcessSort.allCases) { option in Text(option.rawValue).tag(option) }
                }
                .frame(width: 112)
                Picker("Show", selection: $rowLimit) {
                    ForEach([25, 50, 100, 500], id: \.self) { count in Text("\(count)").tag(count) }
                }
                .frame(width: 112)
                Spacer(minLength: 0)
                Text("\(processes.count) processes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)

            if let selected {
                HStack(spacing: 10) {
                    Text("\(selected.name) · PID \(selected.pid)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button("Quit") { confirm(selected, force: false) }
                    Button("Force Quit", role: .destructive) { confirm(selected, force: true) }
                }
                .controlSize(.small)
                .utilitySectionCard()
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
            }

            VStack(spacing: 0) {
                HStack {
                    Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: 72, alignment: .trailing)
                    Text("MEMORY").frame(width: 90, alignment: .trailing)
                    Text("PID").frame(width: 64, alignment: .trailing)
                }
                .utilitySectionHeader()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                LazyVStack(spacing: 0) {
                    ForEach(visibleProcesses) { process in
                        Button { selectedID = process.id } label: {
                            HStack(spacing: 8) {
                                Text(process.name)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(process.cpuPercent.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "…")
                                    .frame(width: 72, alignment: .trailing)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(process.residentBytes), countStyle: .memory))
                                    .frame(width: 90, alignment: .trailing)
                                Text("\(process.pid)").frame(width: 64, alignment: .trailing)
                            }
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
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
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                } else if visibleProcesses.isEmpty {
                    Text("No matching processes")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(30)
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
                didLoad = true
                try? await Task.sleep(for: .seconds(3))
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

    private func confirm(_ process: SystemMonitorProcess, force: Bool) {
        pendingProcess = process
        pendingForce = force
        showingConfirmation = true
    }
}
