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

    /// The tab row's own inset, so each tab's groups line up under the tabs.
    private static let gutter = OnePlusLinearSpace.section

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
        OnePlusLinearSheet("Transfer Info", width: .large, close: { dismiss() }) {
            OnePlusLinearAppletTabRow(tabs: infoTabs, selection: $selectedTab) { EmptyView() }
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
            .frame(minHeight: OnePlusLinearSpace.page * 18)
        } footer: {
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnePlusLinearButtonStyle(.push))
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
            VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletSectionGap) {
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
            VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletSectionGap) {
                if let job {
                    OnePlusLinearAppletSection("Performance") {
                        StepperField(label: "Parallel file transfers", value: settingBinding(job, \.transfersOverride), range: 0...64, format: .number)
                            .help("0 inherits the remote or global setting.")
                        StepperField(label: "Checkers", value: settingBinding(job, \.checkersOverride), range: 0...128, format: .number)
                            .help("Parallel comparisons while scanning for changes.")
                        OnePlusLinearAppletRow("Transfer order") {
                            OnePlusLinearSelect(
                                choices: TransferOrder.allCases.map { ($0, $0.displayName) },
                                selection: settingBinding(job, \.transferOrder),
                                accessibilityLabel: "Transfer order",
                                width: OnePlusLinearControlWidth.regular
                            )
                        }
                    }

                    OnePlusLinearAppletSection("Comparison") {
                        RSyncSwitchRow("Only update older files",
                                       detail: "Skip files whose copy on the destination is newer.",
                                       isOn: settingBinding(job, \.updateOlderOnly))
                        RSyncSwitchRow("Skip files that already exist",
                                       detail: "Never touch a file the destination already has, even if it changed.",
                                       isOn: settingBinding(job, \.ignoreExisting))
                        RSyncSwitchRow("Compare by checksum",
                                       detail: "Use checksums instead of size and modification time. Slower but exact.",
                                       isOn: settingBinding(job, \.compareChecksums))
                    }

                    LinearCaption("Changes apply to queued work at once. A running transfer restarts after a short delay.")
                        .help("Changes apply to queued work immediately. A running transfer restarts after a short delay. Completed files stay complete. The active file can restart if its cloud backend cannot resume it.")
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

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        OnePlusLinearAppletSection(title) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(OnePlusLinearMetrics.appletRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .linearText(color: OnePlusLinearColor.secondary)
            Spacer(minLength: 12)
            Text(value)
                .linearText()
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func monoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .linearText(color: OnePlusLinearColor.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: OnePlusLinearMetrics.control, design: .monospaced))
                .foregroundStyle(OnePlusLinearColor.secondary)
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
                .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.muted)
            Text(details.destinationDisplay)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .linearText()

        row("Kind", value: details.kind == .directory ? "Folder" : "Single file")
        monoRow("Source", value: details.sourceFs)
        monoRow("Destination", value: details.destinationFs)
    }

    @ViewBuilder
    private var resultRows: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("State")
                .linearText(color: OnePlusLinearColor.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                Image(systemName: details.state.icon)
                    .font(.system(size: OnePlusLinearMetrics.control))
                Text(details.state.displayName)
                    .font(.system(size: OnePlusLinearMetrics.body))
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
                        .linearText(color: OnePlusLinearColor.secondary)

                    Button {
                        showTransferPlanInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                    }
                    .buttonStyle(OnePlusLinearButtonStyle())
                    .accessibilityLabel("About transfer plan")
                    .help("About the transfer plan")
                    .popover(isPresented: $showTransferPlanInfo) {
                        Text("Runs an rclone dry comparison. The total only grows when new work is found.")
                            .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                            .frame(width: 220, alignment: .leading)
                            .padding(12)
                            .onePlusFocusPolicy().onePlusOpaquePopover()
                    }
                }
                Spacer(minLength: 12)
                if job.isRecalculating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Comparing")
                            .linearText(color: OnePlusLinearColor.secondary)
                    }
                    .fixedSize()
                } else {
                    Button("Recalculate") { manager.recalculate(job) }
                        .buttonStyle(OnePlusLinearButtonStyle(.soft))
                        .disabled(!manager.daemonIsHealthy)
                }
            }
            if let error = job.recalculationError {
                Text(error)
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.destructiveText)
                    .textSelection(.enabled)
            }
        }

        if details.attempts > 0 {
            row("Attempts", value: "\(details.attempts)")
        }

        if let message = details.errorMessage {
            Text(message)
                .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.destructiveText)
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
                .linearText(color: OnePlusLinearColor.muted)
        } else {
            ForEach(details.excludePatterns, id: \.self) { pattern in
                Text(pattern)
                    .font(.system(size: OnePlusLinearMetrics.control, design: .monospaced))
                    .foregroundStyle(OnePlusLinearColor.secondary)
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
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.muted)
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
                .linearText(weight: .semibold, color: changeTint(entry.kind))
                .frame(width: 24, height: 24)
                .background(changeTint(entry.kind).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.relativePath)
                    .font(.system(size: OnePlusLinearMetrics.control, design: .monospaced))
                    .foregroundStyle(OnePlusLinearColor.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text("\(entry.kind.displayName) · \(entry.operation.displayName) · \(entry.sourceDisplay)")
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.muted)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(10)
        .background(OnePlusLinearColor.barTrack)
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
