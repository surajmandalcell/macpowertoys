import OnePlusUI
import SwiftUI

struct TransferJobRow: View {
    @Environment(RcloneJobManager.self) private var manager
    let job: TransferJob

    @State private var showInfo = false

    private var hasFiles: Bool { !job.stats.transferring.isEmpty }
    private var stateColor: Color {
        switch job.state {
        case .completed: OnePlusLinearColor.success
        case .retrying, .paused: OnePlusLinearColor.warning
        case .failed: OnePlusLinearColor.destructiveText
        case .cancelled: OnePlusLinearColor.muted
        default: OnePlusLinearColor.cpu
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearSpace.row) {
            identityRow
            OnePlusLinearUsageBar(job.progressFraction, color: stateColor)
                .frame(height: OnePlusLinearMetrics.usageBar)
                .accessibilityLabel("Transfer progress")

            if let message = job.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.destructiveText)
                    .textSelection(.enabled)
            }

            if job.isExpanded { fileDetails }
        }
        .padding(.horizontal, OnePlusLinearMetrics.appletRowPadding)
        .padding(.vertical, OnePlusLinearSpace.group)
        .linearGroupRowHover()
        .contextMenu { contextMenu }
        .sheet(isPresented: $showInfo) { TransferInfoSheet(job: job) }
        .accessibilityIdentifier("rclone.transfer.\(job.id)")
    }

    private var identityRow: some View {
        HStack(spacing: OnePlusLinearSpace.group) {
            Image(systemName: job.operation.icon)
                .font(.system(size: OnePlusLinearEditorialMetrics.rowGlyphSize))
                .foregroundStyle(OnePlusLinearColor.secondary)
                .frame(width: OnePlusLinearEditorialMetrics.rowGlyph)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OnePlusLinearSpace.hair) {
                pathChip(job.sourceDisplay, color: OnePlusLinearColor.ink)
                pathChip(job.destinationDisplay, color: OnePlusLinearColor.secondary)
            }
            Spacer(minLength: OnePlusLinearSpace.small)
            // Left of the size text, so the size, status, and key columns stay at one x in every row.
            if job.kind == .file { priorityMenu }
            Text("\(RcloneFormat.bytes(job.progressBytes)) / \(RcloneFormat.bytes(job.effectiveTotalBytes))\(job.isSizing ? "~" : "") · \(job.progressFiles)/\(job.effectiveTotalFiles) files")
                .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary).monospacedDigit().lineLimit(1)
            statusColumn
            actionButtons
                .frame(width: Self.keySlot * 3 + OnePlusLinearSpace.tight * 2, alignment: .trailing)
            disclosureButton
                .opacity(hasFiles || job.isExpanded ? 1 : 0)
                .disabled(!(hasFiles || job.isExpanded))
                .accessibilityHidden(!(hasFiles || job.isExpanded))
        }
    }

    private static let keySlot = OnePlusLinearMetrics.toolbarButton

    /// Fixed-width status column (state, then speed while running), so every row's text lines up.
    private var statusColumn: some View {
        HStack(spacing: OnePlusLinearSpace.small) {
            if job.state == .retrying { retryHint } else { stateBadge }
            Spacer(minLength: 0)
            if job.state == .running, job.stats.speed > 0 {
                Text(RcloneFormat.speed(job.stats.speed))
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                    .monospacedDigit().lineLimit(1)
            }
        }
        .frame(width: OnePlusLinearControlWidth.wide)
    }

    private func pathChip(_ value: String, color: Color) -> some View {
        Text(value)
            .linearText(color: color)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(value)
    }

    private var stateBadge: some View {
        HStack(spacing: OnePlusLinearSpace.tight) {
            Image(systemName: job.state.icon).accessibilityHidden(true)
            Text(job.state == .running ? RcloneFormat.knownETA(job.displayEta).map { "ETA \($0)" } ?? job.state.displayName
                                       : job.state.displayName)
                .monospacedDigit()
        }
        .font(.system(size: OnePlusLinearMetrics.control, weight: .medium))
        .foregroundStyle(stateColor)
        .help("Attempt \(job.attempt)/\(job.maxRetries)")
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var retryHint: some View {
        if let nextRetryAt = job.nextRetryAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Retrying in \(max(0, Int(nextRetryAt.timeIntervalSince(context.date).rounded())))s")
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.warning).monospacedDigit()
            }
        } else {
            Text("Retrying…").linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.warning)
        }
    }

    private var priorityMenu: some View {
        OnePlusLinearSelect(
            choices: TransferPriority.allCases.reversed().map { ($0, $0.displayName) },
            selection: Binding(
                get: { job.priority },
                set: { manager.setPriority($0, for: job) }
            ),
            accessibilityLabel: "File priority",
            width: OnePlusLinearControlWidth.regular
        )
    }

    private var actionButtons: some View {
        HStack(spacing: OnePlusLinearSpace.tight) {
            if job.canPause { iconButton("pause", "Pause") { manager.pause(job) } }
            if job.canResume { iconButton("play", "Resume") { manager.resume(job) } }
            if job.canRetry { iconButton("arrow.clockwise", "Retry") { manager.retry(job) } }
            iconButton("info.circle", "Transfer info") { showInfo = true }
            if job.canCancel { iconButton("xmark", "Cancel") { manager.cancel(job) } }
            if job.state.isTerminal { iconButton("trash", "Remove") { manager.remove(job) } }
        }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        OnePlusLinearIconButton(systemImage: symbol, help: label, size: OnePlusLinearMetrics.toolbarButton, action: action)
    }

    private var disclosureButton: some View {
        OnePlusLinearIconButton(
            systemImage: job.isExpanded ? "chevron.down" : "chevron.right",
            help: job.isExpanded ? "Hide files" : "Show files",
            size: OnePlusLinearMetrics.toolbarButton
        ) {
            manager.setExpanded(!job.isExpanded, for: job)
        }
    }

    private var fileDetails: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            OnePlusLinearColor.lineSoft.frame(height: 1)
            if job.stats.transferring.isEmpty {
                Text("No files transferring")
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                    .padding(.top, OnePlusLinearSpace.row)
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
            HStack(spacing: OnePlusLinearSpace.row) {
                Text(file.name)
                    .font(.system(size: OnePlusLinearMetrics.control, design: .monospaced))
                    .foregroundStyle(OnePlusLinearColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RcloneFormat.bytes(file.size))
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary).monospacedDigit()
                OnePlusLinearUsageBar(file.fraction, color: OnePlusLinearColor.cpu)
                    .frame(width: OnePlusLinearSpace.page * 3, height: OnePlusLinearMetrics.usageBar)
                Text("\(file.percentage)%").linearText(OnePlusLinearMetrics.control).monospacedDigit()
                Text(RcloneFormat.speed(file.speed))
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary).monospacedDigit()
                OnePlusMenuButton("Ignore this file", systemImage: "nosign", variant: .borderedIcon, items: [
                    .item(.init("Ignore This Time") { ignore(false) }),
                    .item(.init("Ignore and Add to Ignore List") { ignore(true) })
                ])
            }
            .frame(minHeight: OnePlusTable.rowHeight(.regular))
            OnePlusLinearColor.lineSoft.frame(height: 1)
        }
    }
}
