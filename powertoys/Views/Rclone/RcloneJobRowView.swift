import OnePlusUI
import SwiftUI

struct TransferJobRow: View {
    @Environment(RcloneJobManager.self) private var manager
    let job: TransferJob

    @State private var showInfo = false

    private var hasFiles: Bool { !job.stats.transferring.isEmpty }
    private var stateColor: Color {
        switch job.state {
        case .completed: OnePlusColor.ok
        case .retrying, .paused: OnePlusColor.warn
        case .failed: OnePlusColor.danger
        case .cancelled: OnePlusColor.muted
        default: OnePlusColor.dataBlue
        }
    }

    var body: some View {
        OnePlusCard {
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[3]) {
                identityRow
                OnePlusUsageBar(value: job.progressFraction, color: stateColor)
                    .accessibilityLabel("Transfer progress")

                if let message = job.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .onePlusText(.caption)
                        .foregroundStyle(OnePlusColor.danger)
                        .textSelection(.enabled)
                }

                if job.isExpanded { fileDetails }
            }
            .padding(OnePlusMetrics.cardPadding)
            .onePlusRowHover()
        }
        .contextMenu { contextMenu }
        .sheet(isPresented: $showInfo) { TransferInfoSheet(job: job) }
        .accessibilityIdentifier("rclone.transfer.\(job.id)")
    }

    private var identityRow: some View {
        HStack(spacing: OnePlusMetrics.spacing[2]) {
            Image(systemName: job.operation.icon)
                .foregroundStyle(OnePlusColor.secondary)
                .frame(width: OnePlusMetrics.controlHeight, height: OnePlusMetrics.controlHeight)
                .background(OnePlusColor.raised, in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                pathChip(job.sourceDisplay)
                pathChip(job.destinationDisplay).foregroundStyle(OnePlusColor.secondary)
            }
            Spacer(minLength: OnePlusMetrics.spacing[2])
            Text("\(RcloneFormat.bytes(job.displayBytes)) / \(RcloneFormat.bytes(job.effectiveTotalBytes))\(job.isSizing ? "~" : "") · \(job.displayFiles)/\(job.effectiveTotalFiles) files")
                .onePlusText(.mono).lineLimit(1)
            if job.state == .running {
                Text(RcloneFormat.speed(job.stats.speed)).onePlusText(.mono)
            }
            if job.state == .retrying { retryHint } else { stateBadge }
            if job.kind == .file { priorityMenu }
            actionButtons
            if hasFiles || job.isExpanded { disclosureButton }
        }
    }

    private func pathChip(_ value: String) -> some View {
        Text(value)
            .onePlusText(.mono)
            .lineLimit(1)
            .truncationMode(.middle)

    }

    private var stateBadge: some View {
        HStack(spacing: OnePlusMetrics.spacing[1]) {
            Image(systemName: job.state.icon).accessibilityHidden(true)
            Text(job.state == .running ? "ETA \(RcloneFormat.eta(job.displayEta))" : job.state.displayName)
                .monospacedDigit()
        }
        .onePlusText(.caption)
        .foregroundStyle(stateColor)
        .help("Attempt \(job.attempt)/\(job.maxRetries)")
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var retryHint: some View {
        if let nextRetryAt = job.nextRetryAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Retrying in \(max(0, Int(nextRetryAt.timeIntervalSince(context.date).rounded())))s")
                    .onePlusText(.mono)
                    .foregroundStyle(OnePlusColor.warn)
            }
        } else {
            Text("Retrying…").onePlusText(.caption).foregroundStyle(OnePlusColor.warn)
        }
    }

    private var priorityMenu: some View {
        OnePlusSelect(
            choices: TransferPriority.allCases.reversed().map { ($0, $0.displayName) },
            selection: Binding(
                get: { job.priority },
                set: { manager.setPriority($0, for: job) }
            ),
            width: OnePlusMetrics.controlColumn,
            accessibilityLabel: "File priority"
        )
    }

    private var actionButtons: some View {
        HStack(spacing: OnePlusMetrics.spacing[1]) {
            if job.canPause { iconButton("pause", "Pause") { manager.pause(job) } }
            if job.canResume { iconButton("play", "Resume") { manager.resume(job) } }
            if job.canRetry { iconButton("arrow.clockwise", "Retry") { manager.retry(job) } }
            iconButton("info.circle", "Transfer info") { showInfo = true }
            if job.canCancel { iconButton("xmark", "Cancel") { manager.cancel(job) } }
            if job.state.isTerminal { iconButton("trash", "Remove") { manager.remove(job) } }
        }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .accessibilityLabel(label)
    }

    private var disclosureButton: some View {
        Button {
            manager.setExpanded(!job.isExpanded, for: job)
        } label: {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(job.isExpanded ? 90 : 0))
        }
        .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
        .accessibilityLabel(job.isExpanded ? "Hide files" : "Show files")
    }

    private var fileDetails: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            OnePlusColor.lineSoft.frame(height: 1)
            if job.stats.transferring.isEmpty {
                Text("No files transferring")
                    .onePlusText(.caption)
                    .padding(.top, OnePlusMetrics.spacing[3])
            } else {
                ForEach(job.stats.transferring) { file in
                    TransferFileProgressRow(file: file) { global in
                        manager.ignoreFile(job, path: file.name, addToGlobalList: global)
                    }
                }
            }
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Transfer Info…") { showInfo = true }
        Divider()
        if let provider = manager.websiteName(for: job.sourceFs) {
            Button("Open Source in \(provider)") {
                manager.openFolderInWebsite(fs: job.sourceFs, transferKind: job.kind)
            }
            .disabled(!manager.daemonIsHealthy)
        }
        if let provider = manager.websiteName(for: job.destinationFs) {
            Button("Open Destination in \(provider)") {
                manager.openFolderInWebsite(fs: job.destinationFs, transferKind: job.kind)
            }
            .disabled(!manager.daemonIsHealthy)
        }
        if manager.websiteName(for: job.sourceFs) != nil || manager.websiteName(for: job.destinationFs) != nil {
            Divider()
        }
        if job.canPause { Button("Pause") { manager.pause(job) } }
        if job.canResume { Button("Resume") { manager.resume(job) } }
        if job.canRetry { Button("Retry") { manager.retry(job) } }
        if job.canCancel { Button("Cancel") { manager.cancel(job) } }
        if RcloneJobManager.supportsContinuousSync(job), job.state == .completed || job.continuousSync {
            Button(job.continuousSync ? "Turn Off Continuous Sync" : "Turn On Continuous Sync") {
                manager.setContinuousSync(!job.continuousSync, for: job)
            }
        }
        if job.state.isTerminal { Button("Remove", role: .destructive) { manager.remove(job) } }
    }
}

private struct TransferFileProgressRow: View {
    let file: FileProgress
    let ignore: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OnePlusMetrics.spacing[3]) {
                Text(file.name)
                    .onePlusText(.mono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RcloneFormat.bytes(file.size)).onePlusText(.mono).foregroundStyle(OnePlusColor.secondary)
                OnePlusUsageBar(value: file.fraction).frame(width: OnePlusMetrics.spacing[8] * 3)
                Text("\(file.percentage)%").onePlusText(.mono).monospacedDigit()
                Text(RcloneFormat.speed(file.speed)).onePlusText(.mono).foregroundStyle(OnePlusColor.secondary)
                OnePlusMenuButton("Ignore this file", systemImage: "nosign", variant: .borderedIcon, items: [
                    .item(.init("Ignore This Time") { ignore(false) }),
                    .item(.init("Ignore and Add to Ignore List") { ignore(true) })
                ])
            }
            .frame(minHeight: OnePlusTable.rowHeight(.regular))
            OnePlusColor.lineSoft.frame(height: 1)
        }
    }
}
