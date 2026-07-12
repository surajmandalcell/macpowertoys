//
//  RcloneJobRowView.swift
//  powertoys
//

import SwiftUI

struct TransferJobRow: View {
    @Environment(RcloneJobManager.self) private var manager

    let job: TransferJob

    @State private var isHovering = false
    @State private var isExpanded = false
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

            if hasTransferringFiles || isExpanded {
                perFileSection
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0.03))
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .sheet(isPresented: $showInfo) {
            TransferInfoSheet(details: TransferDetails(job: job))
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
            Text(job.state.displayName)
                .font(.system(size: 11, weight: .medium))
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

    @ViewBuilder
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            CapsuleProgressBar(fraction: job.progressFraction, tint: progressTint, indeterminate: job.state == .queued)
                .frame(height: 6)

            if job.state == .queued {
                Text("Queued")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if job.state == .retrying {
                retryHint
            }
        }
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
                   text: "\(RcloneFormat.bytes(job.stats.bytes)) / \(RcloneFormat.bytes(job.effectiveTotalBytes))\(job.isSizing ? "~" : "")")
            metric(icon: "speedometer", text: RcloneFormat.speed(job.stats.speed))
            metric(icon: "clock", text: "ETA \(RcloneFormat.eta(job.displayEta))")
            metric(icon: "arrow.up.arrow.down", text: "\(job.stats.transfers)/\(job.effectiveTotalFiles)")

            if job.isSizing && job.state == .running {
                sizingChip
            }

            Spacer(minLength: 8)

            if job.attempt > 0 {
                Text("Attempt \(job.attempt)/\(job.maxRetries)")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }

            controls

            if hasTransferringFiles {
                disclosureButton
            }
        }
    }

    private var sizingChip: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
            Text("Calculating size…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
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
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 6) {
            ControlIconButton(icon: "info.circle", label: "Details", tint: .secondary) {
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
            if job.state.isTerminal {
                ControlIconButton(icon: "trash", label: "Remove", tint: .secondary) {
                    manager.remove(job)
                }
            }
        }
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
        .help(isExpanded ? "Hide files" : "Show files")
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
        if isExpanded {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                if job.stats.transferring.isEmpty {
                    Text("No files transferring")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(job.stats.transferring) { file in
                        FileProgressRow(file: file)
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

    var body: some View {
        HStack(spacing: 8) {
            Text(file.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        }
    }
}
