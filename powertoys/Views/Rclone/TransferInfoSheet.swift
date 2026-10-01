//
//  TransferInfoSheet.swift
//  powertoys
//

import SwiftUI
import OnePlusUI

struct TransferInfoSheet: View {
    private let job: TransferJob?
    private let recordDetails: TransferDetails?

    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cloudsync.details.selectedTab") private var selectedTab: InfoTab = .overview
    @State private var showTransferPlanInfo = false

    private static let gutter = OnePlusMetrics.spacing[7]
    private static let cardPadding = OnePlusMetrics.cardPadding

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
        OnePlusSheet("Transfer Info", width: .large, close: { dismiss() }) {
            OnePlusTabStrip(tabs: infoTabs, selection: $selectedTab)
            Group {
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
            .frame(minHeight: OnePlusMetrics.spacing[8] * 18)
        } footer: {
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnePlusButtonStyle(.primary))
        }
    }

    private var infoTabs: [OnePlusTab<InfoTab>] {
        var tabs = [OnePlusTab<InfoTab>(.overview, "Overview"), OnePlusTab<InfoTab>(.files, "Files")]
        if job != nil {
            tabs.append(OnePlusTab<InfoTab>(.changes, "Changes"))
            tabs.append(OnePlusTab<InfoTab>(.settings, "Settings"))
        }
        return tabs
    }

    // MARK: Overview

    private var overviewContent: some View {
        ScrollView {
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
        .thinScrollIndicators()
    }

    // MARK: Settings

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let job {
                    section("Performance") {
                        VStack(alignment: .leading, spacing: 2) {
                            StepperField(label: "Parallel file transfers", value: settingBinding(job, \.transfersOverride), range: 0...64, format: .number)
                                .onePlusText(.row)
                                .help("0 inherits the remote or global setting.")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            StepperField(label: "Checkers", value: settingBinding(job, \.checkersOverride), range: 0...128, format: .number)
                                .onePlusText(.row)
                                .help("Parallel comparisons while scanning for changes.")
                        }
                    }

                    VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[2]) {
                        HStack {
                            Text("Transfer order")
                                .onePlusText(.row)
                                .foregroundStyle(OnePlusColor.secondary)
                            Spacer(minLength: 12)
                            OnePlusSelect(
                                choices: TransferOrder.allCases.map { ($0, $0.displayName) },
                                selection: settingBinding(job, \.transferOrder),
                                width: OnePlusMetrics.controlColumn,
                                accessibilityLabel: "Transfer order"
                            )
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

                    Image(systemName: "info.circle")
                        .foregroundStyle(OnePlusColor.secondary)
                        .help("Changes apply to queued work immediately. A running transfer restarts after a short delay. Completed files stay complete. The active file can restart if its cloud backend cannot resume it.")
                        .accessibilityLabel("About applying transfer settings")
                }
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .thinScrollIndicators()
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
        HStack {
            Text(title).onePlusText(.row)
            Image(systemName: "info.circle")
                .foregroundStyle(OnePlusColor.secondary)
                .help(caption)
                .accessibilityLabel(caption)
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn)
                .toggleStyle(OnePlusSwitchStyle())
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnePlusColor.track)
            .clipShape(RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius))
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .onePlusText(.row)
                .foregroundStyle(OnePlusColor.secondary)
            Spacer(minLength: 12)
            Text(value)
                .onePlusText(.row)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func monoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .onePlusText(.row)
                .foregroundStyle(OnePlusColor.secondary)
            Spacer(minLength: 12)
            Text(value)
                .onePlusText(.mono)
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
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.muted)
            Text(details.destinationDisplay)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .onePlusText(.row)

        row("Kind", value: details.kind == .directory ? "Folder" : "Single file")
        monoRow("Source", value: details.sourceFs)
        monoRow("Destination", value: details.destinationFs)
    }

    @ViewBuilder
    private var resultRows: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("State")
                .onePlusText(.row)
                .foregroundStyle(OnePlusColor.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                Image(systemName: details.state.icon)
                    .onePlusText(.caption)
                Text(details.state.displayName)
                    .onePlusText(.row)
            }
            .foregroundStyle(details.state.tint)
        }

        row("Data moved", value: "\(RcloneFormat.bytes(details.bytes)) of \(RcloneFormat.bytes(details.totalBytes))")
        if let job, job.networkBytes > job.displayBytes {
            row("Network attempted", value: RcloneFormat.bytes(job.networkBytes))
                .help("Network attempts include retried bytes. They do not increase the planned total.")
        }
        row("Files", value: "\(details.filesTransferred) of \(details.totalFiles)")
        row("Average speed", value: RcloneFormat.speed(details.averageSpeed))

        if let job, job.kind == .directory {
            HStack {
                HStack(spacing: 2) {
                    Text("Transfer plan")
                        .onePlusText(.row)
                        .foregroundStyle(OnePlusColor.secondary)

                    Button {
                        showTransferPlanInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .onePlusText(.caption)
                            .foregroundStyle(OnePlusColor.secondary)
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .accessibilityLabel("About transfer plan")
                    .help("About the transfer plan")
                    .popover(isPresented: $showTransferPlanInfo) {
                        Text("Runs an rclone dry comparison. The total only grows when new work is found.")
                            .onePlusText(.caption)
                            .foregroundStyle(OnePlusColor.secondary)
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
                            .onePlusText(.row)
                            .foregroundStyle(OnePlusColor.secondary)
                    }
                    .fixedSize()
                } else {
                    Button("Recalculate") { manager.recalculate(job) }
                        .disabled(!manager.daemonIsHealthy)
                }
            }
            if let error = job.recalculationError {
                Text(error)
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.danger)
            }
        }

        if details.attempts > 0 {
            row("Attempts", value: "\(details.attempts)")
        }

        if let message = details.errorMessage {
            Text(message)
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.danger)
                .textSelection(.enabled)
        }

    }

    @ViewBuilder
    private var timingRows: some View {
        row("Created", value: Self.dateFormatter.string(from: details.createdAt))
        row("Started", value: details.startedAt.map(Self.dateFormatter.string(from:)) ?? "Not started")
        row("Finished", value: details.finishedAt.map(Self.dateFormatter.string(from:)) ?? "Not finished")
        row("Duration", value: RcloneFormat.duration(duration))
    }

    @ViewBuilder
    private var ignoreRuleRows: some View {
        if details.excludePatterns.isEmpty {
            Text("None")
                .onePlusText(.row)
                .foregroundStyle(OnePlusColor.muted)
        } else {
            ForEach(details.excludePatterns, id: \.self) { pattern in
                Text(pattern)
                    .onePlusText(.mono)
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
                        .help("The latest source-folder changes observed after this transfer was added.")

                }
                Spacer()
                Text("\(entries.count) / 100")
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.muted)
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
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(entries) { entry in
                            changeRow(entry)
                        }
                    }
                }
                .thinScrollIndicators()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private func changeRow(_ entry: LocalChangeRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind.icon)
                .onePlusText(.cardTitle)
                .foregroundStyle(changeTint(entry.kind))
                .frame(width: 24, height: 24)
                .background(changeTint(entry.kind).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.relativePath)
                    .onePlusText(.mono)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text("\(entry.kind.displayName) · \(entry.operation.displayName) · \(entry.sourceDisplay)")
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.muted)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(10)
        .background(OnePlusColor.track)
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
            averageSpeed = Double(job.displayBytes) / duration
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
