//
//  TransferInfoSheet.swift
//  powertoys
//

import SwiftUI

struct TransferInfoSheet: View {
    private let job: TransferJob?
    private let recordDetails: TransferDetails?

    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cloudsync.details.selectedTab") private var selectedTab: InfoTab = .overview
    @State private var showTransferPlanInfo = false
    @State private var isHoveringTransferPlanInfo = false

    private static let gutter: CGFloat = 20
    private static let cardPadding: CGFloat = 14

    init(details: TransferDetails) {
        self.recordDetails = details
        self.job = nil
    }

    init(job: TransferJob) {
        self.job = job
        self.recordDetails = nil
    }

    private var details: TransferDetails {
        job.map { TransferDetails(job: $0) } ?? recordDetails!
    }

    private enum InfoTab: String, Hashable {
        case overview
        case files
        case changes
        case settings
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var duration: TimeInterval? {
        guard let startedAt = details.startedAt, let finishedAt = details.finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    private var visibleTab: InfoTab {
        if job == nil && (selectedTab == .changes || selectedTab == .settings) {
            return .overview
        }
        return selectedTab
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            switch visibleTab {
            case .overview:
                overviewContent
            case .files:
                TransferFileTreeView(sourceFs: details.sourceFs, destinationFs: details.destinationFs)
                    .padding(.top, 12)
            case .changes:
                if let job {
                    TransferChangesTab(jobID: job.id)
                }
            case .settings:
                settingsContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 640, height: 620)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Transfer Details")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Self.gutter)
        .padding(.vertical, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton("Overview", .overview)
            tabButton("Files", .files)
            if job != nil {
                tabButton("Changes", .changes)
                tabButton("Settings", .settings)
            }
            Spacer()
        }
        .padding(.leading, Self.gutter)
        .padding(.trailing, Self.gutter)
        .padding(.bottom, 12)
    }

    private func tabButton(_ title: String, _ tab: InfoTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(title)
                .font(.system(size: 12, weight: visibleTab == tab ? .medium : .regular))
                .foregroundStyle(visibleTab == tab ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(visibleTab == tab ? Color.primary.opacity(0.06) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    // MARK: Overview

    private var overviewContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                section("Route") { routeRows }
                section("Result") { resultRows }
                section("Timing") { timingRows }
                section("Ignore Rules") { ignoreRuleRows }
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    // MARK: Settings

    private var settingsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if let job {
                    section("Performance") {
                        VStack(alignment: .leading, spacing: 2) {
                            StepperField(label: "Parallel file transfers", value: settingBinding(job, \.transfersOverride), range: 0...64, format: .number)
                                .font(.system(size: 13))
                            Text("0 inherits the remote or global setting.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            StepperField(label: "Checkers", value: settingBinding(job, \.checkersOverride), range: 0...128, format: .number)
                                .font(.system(size: 13))
                            Text("Parallel comparisons while scanning for changes.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    section("Upload Order") {
                        HStack {
                            Text("Transfer order")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Picker("Transfer order", selection: settingBinding(job, \.transferOrder)) {
                                ForEach(TransferOrder.allCases, id: \.self) { order in
                                    Text(order.displayName).tag(order)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }

                    section("Comparison") {
                        settingToggle("Only update older files",
                                      caption: "Skip files whose copy on the destination is newer.",
                                      isOn: settingBinding(job, \.updateOlderOnly))
                        settingToggle("Skip files that already exist",
                                      caption: "Never touch a file the destination already has, even if it changed.",
                                      isOn: settingBinding(job, \.ignoreExisting))
                        settingToggle("Compare by checksum",
                                      caption: "Use checksums instead of size and modification time. Slower but exact.",
                                      isOn: settingBinding(job, \.compareChecksums))
                    }

                    Text("Changes apply to queued work immediately. A running transfer restarts after a short delay; completed files are skipped, while the active file may restart if its cloud backend cannot resume it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    private func settingBinding<Value>(_ job: TransferJob, _ keyPath: ReferenceWritableKeyPath<TransferJob, Value>) -> Binding<Value> {
        Binding(
            get: { job[keyPath: keyPath] },
            set: { newValue in
                job[keyPath: keyPath] = newValue
                manager.applyTransferSettingsChange(job)
            }
        )
    }

    private func settingToggle(_ title: String, caption: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func monoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var routeRows: some View {
        HStack(spacing: 8) {
            Text(details.sourceDisplay)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(details.destinationDisplay)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))

        row("Kind", value: details.kind == .directory ? "Folder" : "Single file")
        monoRow("Source", value: details.sourceFs)
        monoRow("Destination", value: details.destinationFs)
    }

    @ViewBuilder
    private var resultRows: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("State")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                Image(systemName: details.state.icon)
                    .font(.system(size: 11))
                Text(details.state.displayName)
                    .font(.system(size: 13))
            }
            .foregroundStyle(details.state.tint)
        }

        row("Data moved", value: "\(RcloneFormat.bytes(details.bytes)) of \(RcloneFormat.bytes(details.totalBytes))")
        if let job, job.networkBytes > job.displayBytes {
            row("Network attempted", value: RcloneFormat.bytes(job.networkBytes))
            Text("Network attempts include retried bytes. They do not increase the planned transfer total.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        row("Files", value: "\(details.filesTransferred) of \(details.totalFiles)")
        row("Average speed", value: RcloneFormat.speed(details.averageSpeed))

        if let job, job.kind == .directory {
            HStack {
                HStack(spacing: 2) {
                    Text("Transfer plan")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Button {
                        showTransferPlanInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(isHoveringTransferPlanInfo ? 0.06 : 0))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .accessibilityLabel("About transfer plan")
                    .onHover { isHoveringTransferPlanInfo = $0 }
                    .help("About the transfer plan")
                    .popover(isPresented: $showTransferPlanInfo) {
                        Text("Runs an rclone dry comparison. The total only grows when new work is found.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 220, alignment: .leading)
                            .padding(12)
                    }
                }
                Spacer(minLength: 12)
                if job.isRecalculating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Comparing")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                } else {
                    Button("Recalculate") { manager.recalculate(job) }
                        .disabled(!manager.daemonIsHealthy)
                }
            }
            if let error = job.recalculationError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }

        if details.attempts > 0 {
            row("Attempts", value: "\(details.attempts)")
        }

        if let message = details.errorMessage {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }

    }

    @ViewBuilder
    private var timingRows: some View {
        row("Created", value: Self.dateFormatter.string(from: details.createdAt))
        row("Started", value: details.startedAt.map(Self.dateFormatter.string(from:)) ?? "—")
        row("Finished", value: details.finishedAt.map(Self.dateFormatter.string(from:)) ?? "—")
        row("Duration", value: RcloneFormat.duration(duration))
    }

    @ViewBuilder
    private var ignoreRuleRows: some View {
        if details.excludePatterns.isEmpty {
            Text("None")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        } else {
            ForEach(details.excludePatterns, id: \.self) { pattern in
                Text(pattern)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}

private struct TransferChangesTab: View {
    let jobID: UUID

    @State private var history = LocalChangeHistory.shared

    private var entries: [LocalChangeRecord] {
        history.entries.filter { $0.jobID == jobID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHANGED FILES AUDIT")
                        .utilitySectionHeader()
                    Text("The latest source-folder changes observed after this transfer was added.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entries.count) / 100")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "No Local Changes",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Changes appear here while this local source is being watched.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(entries) { entry in
                            changeRow(entry)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private func changeRow(_ entry: LocalChangeRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(changeTint(entry.kind))
                .frame(width: 24, height: 24)
                .background(changeTint(entry.kind).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.relativePath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text("\(entry.kind.displayName) · \(entry.operation.displayName) · \(entry.sourceDisplay)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func changeTint(_ kind: FileChangeKind) -> Color {
        switch kind {
        case .created: return .green
        case .modified: return .blue
        case .removed: return .red
        case .renamed: return .orange
        }
    }
}

struct TransferDetails {
    let operation: RcloneOperation
    let kind: TransferKind
    let state: TransferState
    let sourceFs: String
    let destinationFs: String
    let sourceDisplay: String
    let destinationDisplay: String
    let excludePatterns: [String]
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let bytes: Int64
    let totalBytes: Int64
    let filesTransferred: Int
    let totalFiles: Int
    let attempts: Int
    let averageSpeed: Double
    let errorMessage: String?

    init(job: TransferJob) {
        operation = job.operation
        kind = job.kind
        state = job.state
        sourceFs = job.sourceFs
        destinationFs = job.destinationFs
        sourceDisplay = job.sourceDisplay
        destinationDisplay = job.destinationDisplay
        excludePatterns = job.excludePatterns
        createdAt = job.createdAt
        startedAt = job.startedAt
        finishedAt = job.finishedAt
        bytes = job.displayBytes
        totalBytes = job.effectiveTotalBytes
        filesTransferred = job.displayFiles
        totalFiles = job.effectiveTotalFiles
        attempts = job.attempt
        if let duration = job.duration, duration > 0 {
            averageSpeed = Double(job.stats.bytes) / duration
        } else {
            averageSpeed = job.stats.speed
        }
        errorMessage = job.errorMessage
    }

    init(record: TransferRecord) {
        operation = record.operation
        kind = record.kind
        state = record.state
        sourceFs = record.sourceFs
        destinationFs = record.destinationFs
        sourceDisplay = record.sourceDisplay
        destinationDisplay = record.destinationDisplay
        excludePatterns = record.excludePatterns.split(whereSeparator: \.isNewline).map(String.init)
        createdAt = record.createdAt
        startedAt = record.startedAt
        finishedAt = record.finishedAt
        bytes = record.bytes
        totalBytes = record.totalBytes
        filesTransferred = record.filesTransferred
        totalFiles = record.totalFiles
        attempts = record.attempts
        averageSpeed = record.averageSpeed
        errorMessage = record.errorMessage
    }
}
