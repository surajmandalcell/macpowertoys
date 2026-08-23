//
//  RcloneJobRowView.swift
//  powertoys
//

import SwiftUI

struct TransferJobRow: View {
    @Environment(RcloneJobManager.self) private var manager

    let job: TransferJob

    @State private var isHovering = false
    @State private var showInfo = false
    @State private var isHoveringDisclosure = false

    private var progressTint: Color {
        switch job.state {
        case .completed: return .green
        case .retrying: return .orange
        case .failed: return .red
        case .cancelled: return .secondary
        default: return .accentColor
        }
    }

    private var hasTransferringFiles: Bool {
        !job.stats.transferring.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            progressSection
            metricsRow

            if let message = job.errorMessage {
                errorStrip(message)
            }

            if hasTransferringFiles || job.isExpanded {
                perFileSection
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0.03))
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.18), value: job.state)
        .animation(.easeInOut(duration: 0.18), value: hasTransferringFiles)
        .animation(.easeInOut(duration: 0.18), value: job.errorMessage != nil)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Details…") { showInfo = true }
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
            if job.canPause {
                Button("Pause") { manager.pause(job) }
            }
            if job.canResume {
                Button("Resume") { manager.resume(job) }
            }
            if job.canRetry {
                Button("Retry") { manager.retry(job) }
            }
            if job.canCancel {
                Button("Cancel") { manager.cancel(job) }
            }
            if RcloneJobManager.supportsContinuousSync(job), job.state == .completed || job.continuousSync {
                Button(job.continuousSync ? "Turn Off Continuous Sync" : "Turn On Continuous Sync") {
                    manager.setContinuousSync(!job.continuousSync, for: job)
                }
            }
            if job.state.isTerminal {
                Button("Remove") { manager.remove(job) }
            }
        }
        .sheet(isPresented: $showInfo) {
            TransferInfoSheet(job: job)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            operationChip
            pathChip(job.sourceDisplay)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            pathChip(job.destinationDisplay)
            Spacer(minLength: 8)
            stateBadge
        }
    }

    private var operationChip: some View {
        Image(systemName: job.operation.icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
            )
    }

    private func pathChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.75))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
            )
    }

    private var stateBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: job.state.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(job.state == .running ? "ETA \(RcloneFormat.eta(job.displayEta))" : job.state.displayName)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(job.state.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(job.state.tint.opacity(0.12))
        )
        .fixedSize()
    }

    // MARK: Progress

    private var progressSection: some View {
        CapsuleProgressBar(fraction: job.progressFraction, tint: progressTint, indeterminate: job.state == .queued)
            .frame(height: 6)
    }

    @ViewBuilder
    private var retryHint: some View {
        if let nextRetryAt = job.nextRetryAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, nextRetryAt.timeIntervalSince(context.date))
                Text(remaining > 0 ? "Retrying in \(Int(remaining.rounded()))s" : "Retrying…")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        } else {
            Text("Retrying…")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        }
    }

    // MARK: Metrics

    private var metricsRow: some View {
        HStack(spacing: 14) {
            metric(icon: "internaldrive",
                   text: "\(RcloneFormat.bytes(job.displayBytes)) / \(RcloneFormat.bytes(job.effectiveTotalBytes))\(job.isSizing ? "~" : "")")
            metric(icon: "speedometer", text: RcloneFormat.speed(job.stats.speed))
            metric(icon: "arrow.up.arrow.down", text: "\(job.displayFiles)/\(job.effectiveTotalFiles)")

            if job.isSizing && job.state == .running {
                sizingChip
            }

            Spacer(minLength: 8)

            if job.state == .retrying {
                retryHint
            }

            if job.attempt > 0 {
                Text("Attempt \(job.attempt)/\(job.maxRetries)")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }

            if job.kind == .file {
                priorityMenu
            }

            controls

            if hasTransferringFiles || job.isExpanded {
                disclosureButton
            }
        }
    }

    private var sizingChip: some View {
        progressChip("Comparing")
    }

    private func progressChip(_ text: String) -> some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .fixedSize()
    }

    // MARK: Controls

    private var priorityMenu: some View {
        Menu {
            ForEach(TransferPriority.allCases.reversed(), id: \.self) { priority in
                Button {
                    manager.setPriority(priority, for: job)
                } label: {
                    if job.priority == priority {
                        Label(priority.displayName, systemImage: "checkmark")
                    } else {
                        Text(priority.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: job.priority.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(job.priority == .normal ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusEffectDisabled()
        .help(priorityHelp)
        .accessibilityLabel("File priority")
        .accessibilityValue(job.priority.displayName)
    }

    private var priorityHelp: String {
        if job.state == .running {
            return "Priority: \(job.priority.displayName). The running file continues. The new priority applies if the file enters the queue again."
        }
        return "Priority: \(job.priority.displayName). Higher-priority files start first."
    }

    private var controls: some View {
        HStack(spacing: 6) {
            ControlIconButton(icon: "gearshape", label: "Details & settings", tint: .secondary) {
                showInfo = true
            }
            if job.canPause {
                ControlIconButton(icon: "pause.circle", label: "Pause", tint: .secondary) {
                    manager.pause(job)
                }
            }
            if job.canResume {
                ControlIconButton(icon: "play.circle", label: "Resume", tint: .accentColor) {
                    manager.resume(job)
                }
            }
            if job.canCancel {
                ControlIconButton(icon: "xmark.circle", label: "Cancel", tint: .secondary) {
                    manager.cancel(job)
                }
            }
            if job.canRetry {
                ControlIconButton(icon: "arrow.clockwise", label: "Retry", tint: .accentColor) {
                    manager.retry(job)
                }
            }
            if RcloneJobManager.supportsContinuousSync(job), job.state == .completed || job.continuousSync {
                ControlIconButton(
                    icon: "arrow.triangle.2.circlepath",
                    label: job.continuousSync ? "Turn off Continuous Sync" : "Turn on Continuous Sync",
                    tint: job.continuousSync ? .accentColor : .secondary
                ) {
                    manager.setContinuousSync(!job.continuousSync, for: job)
                }
            }
            if job.state.isTerminal {
                ControlIconButton(icon: "trash", label: "Remove", tint: .secondary) {
                    manager.remove(job)
                }
            }
        }
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                manager.setExpanded(!job.isExpanded, for: job)
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(job.isExpanded ? 90 : 0))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHoveringDisclosure ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.easeInOut(duration: 0.15), value: isHoveringDisclosure)
        .onHover { isHoveringDisclosure = $0 }
        .onDisappear { isHoveringDisclosure = false }
        .help(job.isExpanded ? "Hide files" : "Show files")
    }

    // MARK: Error strip

    private func errorStrip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red.opacity(0.9))
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.08))
        )
    }

    // MARK: Per-file section

    @ViewBuilder
    private var perFileSection: some View {
        if job.isExpanded {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                if job.stats.transferring.isEmpty {
                    Text("No files transferring")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(job.stats.transferring) { file in
                        FileProgressRow(file: file) { addToGlobalList in
                            manager.ignoreFile(job, path: file.name, addToGlobalList: addToGlobalList)
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Control Icon Button

private struct ControlIconButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .help(label)
    }
}

// MARK: - Capsule Progress Bar

private struct CapsuleProgressBar: View {
    let fraction: Double
    let tint: Color
    var indeterminate: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                if !indeterminate {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                        .animation(.easeInOut(duration: 0.3), value: fraction)
                }
            }
        }
    }
}

// MARK: - Per-file Row

private struct FileProgressRow: View {
    let file: FileProgress
    var onIgnore: ((_ addToGlobalList: Bool) -> Void)?

    @State private var isHoveringIgnore = false

    var body: some View {
        HStack(spacing: 8) {
            Text(file.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(RcloneFormat.bytes(file.size))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)

            CapsuleProgressBar(fraction: file.fraction, tint: .accentColor)
                .frame(width: 80, height: 4)

            Text("\(file.percentage)%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 34, alignment: .trailing)

            Text(RcloneFormat.speed(file.speed))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)

            if let onIgnore {
                ignoreMenu(onIgnore)
            }
        }
    }

    private func ignoreMenu(_ onIgnore: @escaping (_ addToGlobalList: Bool) -> Void) -> some View {
        Menu {
            Button("Ignore This Time") { onIgnore(false) }
            Button("Ignore and Add to Ignore List") { onIgnore(true) }
        } label: {
            Image(systemName: "nosign")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHoveringIgnore ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusEffectDisabled()
        .animation(.easeInOut(duration: 0.15), value: isHoveringIgnore)
        .onHover { isHoveringIgnore = $0 }
        .help("Ignore this file")
        .contextMenu {
            Button("Ignore This Time") { onIgnore(false) }
            Button("Ignore and Add to Ignore List") { onIgnore(true) }
        }
    }
}
