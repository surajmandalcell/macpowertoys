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
        case .retrying: OnePlusColor.warn
        case .failed: OnePlusColor.danger
        case .cancelled: OnePlusColor.muted
        default: OnePlusColor.accent
        }
    }

    var body: some View {
        OnePlusCard {
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[3]) {
                identityRow
                OnePlusUsageBar(value: job.progressFraction, color: stateColor)
                    .accessibilityLabel("Transfer progress")
                metricsRow

                if let message = job.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .onePlusText(.caption)
                        .foregroundStyle(OnePlusColor.danger)
                        .textSelection(.enabled)
                }

                if job.isExpanded { fileDetails }
            }
            .padding(OnePlusMetrics.cardPadding)
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
            pathChip(job.sourceDisplay)
            Image(systemName: "arrow.right")
                .foregroundStyle(OnePlusColor.muted)
                .accessibilityHidden(true)
            pathChip(job.destinationDisplay)
            Spacer(minLength: OnePlusMetrics.spacing[2])
            stateBadge
        }
    }

    private func pathChip(_ value: String) -> some View {
        Text(value)
            .onePlusText(.mono)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(value)
            .padding(.horizontal, OnePlusMetrics.spacing[3])
            .frame(height: OnePlusMetrics.compactControlHeight)
            .background(OnePlusColor.track, in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
    }

    private var stateBadge: some View {
        HStack(spacing: OnePlusMetrics.spacing[1]) {
            Image(systemName: job.state.icon).accessibilityHidden(true)
            Text(job.state == .running ? "ETA \(RcloneFormat.eta(job.displayEta))" : job.state.displayName)
                .monospacedDigit()
        }
        .onePlusText(.caption)
        .foregroundStyle(stateColor)
        .padding(.horizontal, OnePlusMetrics.spacing[3])
        .frame(height: OnePlusMetrics.compactControlHeight)
        .background(OnePlusColor.raised, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var metricsRow: some View {
        HStack(spacing: OnePlusMetrics.spacing[4]) {
            metric("internaldrive", "\(RcloneFormat.bytes(job.displayBytes)) / \(RcloneFormat.bytes(job.effectiveTotalBytes))\(job.isSizing ? "~" : "")")
            metric("speedometer", RcloneFormat.speed(job.stats.speed))
            metric("doc.on.doc", "\(job.displayFiles)/\(job.effectiveTotalFiles) files")

            if job.state == .retrying { retryHint }
            if job.attempt > 0 {
                Text("Attempt \(job.attempt)/\(job.maxRetries)")
                    .onePlusText(.mono)
                    .foregroundStyle(OnePlusColor.warn)
            }

            Spacer(minLength: OnePlusMetrics.spacing[2])
            if job.kind == .file { priorityMenu }
            actionButtons
            if hasFiles || job.isExpanded { disclosureButton }
        }
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        Label(value, systemImage: icon)
            .onePlusText(.mono)
            .foregroundStyle(OnePlusColor.secondary)
            .fixedSize()
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
        Menu {
            ForEach(TransferPriority.allCases.reversed(), id: \.self) { priority in
                Button {
                    manager.setPriority(priority, for: job)
                } label: {
                    if job.priority == priority { Label(priority.displayName, systemImage: "checkmark") }
                    else { Text(priority.displayName) }
                }
            }
        } label: {
            Image(systemName: job.priority.icon)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Priority: \(job.priority.displayName)")
        .accessibilityLabel("File priority")
        .accessibilityValue(job.priority.displayName)
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
            .help(label)
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
        .help(job.isExpanded ? "Hide files" : "Show files")
        .accessibilityLabel(job.isExpanded ? "Hide files" : "Show files")
    }

    private var fileDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        HStack(spacing: OnePlusMetrics.spacing[3]) {
            Text(file.name)
                .onePlusText(.mono)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(file.name)
            Text(RcloneFormat.bytes(file.size)).onePlusText(.mono).foregroundStyle(OnePlusColor.secondary)
            OnePlusUsageBar(value: file.fraction).frame(width: OnePlusMetrics.spacing[8] * 3)
            Text("\(file.percentage)%").onePlusText(.mono).monospacedDigit()
            Text(RcloneFormat.speed(file.speed)).onePlusText(.mono).foregroundStyle(OnePlusColor.secondary)
            Menu {
                Button("Ignore This Time") { ignore(false) }
                Button("Ignore and Add to Ignore List") { ignore(true) }
            } label: { Image(systemName: "nosign") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Ignore this file")
        }
        .frame(minHeight: OnePlusTable.rowHeight(.regular))
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
    }
}
