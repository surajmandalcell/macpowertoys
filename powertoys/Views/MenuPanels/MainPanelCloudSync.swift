import OnePlusUI
import SwiftUI

/// The RSync UI tab in Home's language: a Transfers and Speed tile pair, the remotes group, the active and recent
/// transfer groups, and the New Transfer and Open keys. Rows use Home's row inset and hover fill step.
struct CloudSyncTrayView: View {
    @State private var manager = RcloneJobManager.shared
    @State private var remoteTransfers: [String: TransferJob] = [:]
    @Environment(\.onePlusIsVisible) private var isVisible
    @Binding var jobs: [TransferJob]
    var showsOpenKey = true

    private var activeJobs: [TransferJob] { jobs.filter { $0.state.isActive } }
    private var recentJobs: [TransferJob] { jobs.filter { $0.state.isTerminal } }

    var body: some View {
        VStack(alignment: .leading, spacing: TrayPopoverLayout.style.blockGap) {
            if !manager.daemonIsHealthy {
                OnePlusLinearBanner(.warning, title: "The engine is not responding.") {
                    Button("Retry") { Task { await manager.start() } }.buttonStyle(OnePlusLinearKeyButtonStyle.compact)
                }
            }
            CloudSyncTiles(active: activeJobs)
            VStack(spacing: 0) {
                OnePlusLinearPanelHeader("Remotes", note: manager.remotes.isEmpty ? nil : String(manager.remotes.count))
                OnePlusLinearList(style: .panel) {
                    if manager.remotes.isEmpty {
                        CloudSyncEmptyRow(text: manager.daemonIsHealthy ? "No remotes loaded" : "Open RSync UI to load remotes")
                    } else {
                        ForEach(manager.remotes) { remote in
                            CloudSyncRemoteRow(remote: remote, lastTransfer: remoteTransfers[remote.name])
                        }
                    }
                }
            }
            jobSection("Active", jobs: activeJobs)
            jobSection("Recent", jobs: recentJobs)
            OnePlusLinearActionBar(actions)
        }
        .modifier(MainPanelReveal(.cloudSync))
        .onChange(of: manager.jobs.map { TrayTransferOrderKey(id: $0.id, state: $0.state) }, initial: true) {
            guard isVisible else { return }
            jobs = TrayPopoverLayout.visibleTransferJobs(manager.jobs)
            remoteTransfers = TrayPopoverLayout.latestTransfersByRemote(manager.jobs)
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            jobs = TrayPopoverLayout.visibleTransferJobs(manager.jobs)
            remoteTransfers = TrayPopoverLayout.latestTransfersByRemote(manager.jobs)
            await manager.refreshRemotes()
        }
    }

    private var actions: [OnePlusLinearAction] {
        var actions = [OnePlusLinearAction("New Transfer", systemImage: "plus", id: "tray.action.new-transfer") {
            ToolActionRouter.shared.open(toolID: "rclone", page: "new-transfer")
        }]
        if showsOpenKey {
            actions.append(OnePlusLinearAction("Open RSync UI", systemImage: TrayTab.cloudSync.symbol, id: "tray.action.rclone") {
                ToolActionRouter.shared.open(toolID: "rclone")
            })
        }
        return actions
    }

    @ViewBuilder
    private func jobSection(_ title: String, jobs: [TransferJob]) -> some View {
        if !jobs.isEmpty {
            VStack(spacing: 0) {
                OnePlusLinearPanelHeader(title, note: String(jobs.count))
                OnePlusLinearList(style: .panel) {
                    ForEach(jobs) { job in TrayTransferRow(job: job) }
                }
            }
        }
    }
}

/// Home-style short tiles: bytes moved by the active transfers, and their summed speed with the file count.
private struct CloudSyncTiles: View {
    let active: [TransferJob]

    var body: some View {
        let total = active.reduce(Int64(0)) { $0 + $1.effectiveTotalBytes }
        let done = active.reduce(Int64(0)) { $0 + $1.displayBytes }
        let files = active.reduce(0) { $0 + $1.effectiveTotalFiles }
        let doneFiles = active.reduce(0) { $0 + $1.displayFiles }
        let speed = Self.split(RcloneFormat.speed(active.reduce(0) { $0 + $1.stats.speed }))
        OnePlusLinearBento(style: .instrument) {
            OnePlusLinearTile(height: OnePlusLinearMetrics.shortTile, usage: OnePlusLinearUsage(
                total > 0 ? Double(done) / Double(total) : 0, color: OnePlusLinearColor.cpu,
                caption: total > 0 ? "\(RcloneFormat.bytes(done)) of \(RcloneFormat.bytes(total))" : "Idle", pace: .network),
                tint: OnePlusLinearColor.cpu) {
                OnePlusLinearTileLabel("Transfers", systemImage: "arrow.left.arrow.right", color: OnePlusLinearColor.cpu) {
                    OnePlusLinearInlineValue(String(active.count), unit: "active", color: OnePlusLinearColor.cpu, pace: .process)
                }
            }
        } trailing: {
            OnePlusLinearTile(height: OnePlusLinearMetrics.shortTile, usage: OnePlusLinearUsage(
                files > 0 ? Double(doneFiles) / Double(files) : 0, color: OnePlusLinearColor.networkDown,
                caption: files > 0 ? "\(doneFiles) of \(files) files" : "No files moving", pace: .network),
                tint: OnePlusLinearColor.networkDown) {
                OnePlusLinearTileLabel("Speed", systemImage: "speedometer", color: OnePlusLinearColor.networkDown) {
                    OnePlusLinearInlineValue(speed.value, unit: speed.unit, color: OnePlusLinearColor.networkDown, pace: .network)
                }
            }
        }
    }

    /// `34.2 MB/s` becomes `34.2` and `MB/s`, so the number rolls on its own like Home's values.
    static func split(_ text: String) -> (value: String, unit: String) {
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
}

private struct CloudSyncEmptyRow: View {
    let text: String
    var body: some View {
        Text(text).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
            .frame(height: OnePlusLinearMetrics.controlRow)
    }
}

/// A 32 pt remote row: glyph, name, type, then the last transfer's state and time.
private struct CloudSyncRemoteRow: View {
    let remote: RcloneRemote
    let lastTransfer: TransferJob?
    @State private var hover = false
    @Environment(\.onePlusControlState) private var sample
    @Environment(\.onePlusLinearPanelStyle) private var panelStyle

    var body: some View {
        HStack(spacing: OnePlusLinearMetrics.rowGap) {
            Image(systemName: remote.icon).font(.system(size: 12)).foregroundStyle(OnePlusLinearColor.panelMuted)
                .frame(width: 14, height: 14).accessibilityHidden(true)
            Text(remote.displayName).linearText().lineLimit(1).help(remote.displayName)
            Text(remote.typeLabel).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted).lineLimit(1)
            Spacer(minLength: OnePlusLinearMetrics.rowGap)
            Group {
                Text(lastTransfer?.state.displayName ?? "No transfers")
                if let lastTransfer {
                    let date = lastTransfer.finishedAt ?? lastTransfer.createdAt
                    Text(date, format: .dateTime.hour().minute()).monospacedDigit()
                        .help(date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.secondary).lineLimit(1)
        }
        .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
        .frame(height: OnePlusLinearMetrics.controlRow)
        .linearRowHover($hover, sample: sample, enabled: true, panelStyle: panelStyle)
    }
}

private struct TrayTransferOrderKey: Equatable {
    let id: UUID
    let state: TransferState
}

/// A transfer row: chevron, operation glyph, source to destination, state, and the pause, resume, or retry
/// key, then the progress bar with bytes, speed, and time left. Open, it lists up to four files in flight.
private struct TrayTransferRow: View {
    let job: TransferJob
    @State private var manager = RcloneJobManager.shared
    @State private var showsError = false
    @State private var hover = false
    @Environment(\.onePlusControlState) private var sample
    @Environment(\.onePlusLinearPanelStyle) private var panelStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: OnePlusLinearMetrics.rowGap) {
                Button { manager.setExpanded(!job.isExpanded, for: job) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OnePlusLinearColor.panelMuted)
                        .rotationEffect(.degrees(job.isExpanded ? 90 : 0))
                        .frame(width: 14, height: 14).contentShape(Rectangle())
                }
                .buttonStyle(OnePlusLinearPlainRowStyle())
                .accessibilityLabel(job.isExpanded ? "Hide transfer files" : "Show transfer files")
                .help(job.isExpanded ? "Hide transfer files" : "Show transfer files")
                Image(systemName: job.operation.icon).font(.system(size: 12)).foregroundStyle(OnePlusLinearColor.panelMuted)
                Text("\(job.sourceDisplay) → \(job.destinationDisplay)")
                    .linearText().lineLimit(1).truncationMode(.middle)
                    .help("\(job.sourceDisplay) → \(job.destinationDisplay)")
                Spacer(minLength: 4)
                if job.state == .failed, job.errorMessage?.isEmpty == false {
                    Button { showsError.toggle() } label: { stateText }
                        .buttonStyle(OnePlusLinearPlainRowStyle())
                        .accessibilityLabel(showsError ? "Hide transfer error" : "Show transfer error")
                } else {
                    stateText
                }
                if job.canPause {
                    transferButton("Pause transfer", symbol: "pause.fill") { manager.pause(job) }
                } else if job.canResume {
                    transferButton("Resume transfer", symbol: "play.fill") { manager.resume(job) }
                } else if job.canRetry {
                    transferButton("Retry transfer", symbol: "arrow.clockwise") { manager.retry(job) }
                }
            }
            .frame(height: OnePlusLinearMetrics.panelAccessory)
            if job.effectiveTotalBytes > 0 || job.state.isActive { progress }
            if showsError, let error = job.errorMessage, !error.isEmpty {
                Text(error).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.destructiveText)
                    .lineLimit(2).help(error)
            }
            if job.isExpanded { files }
        }
        .padding(.horizontal, OnePlusLinearMetrics.panelRowInset).padding(.vertical, 6)
        .linearRowHover($hover, sample: sample, enabled: true, panelStyle: panelStyle)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            OnePlusLinearUsageBar(job.progressFraction, color: stateColor)
            HStack(spacing: OnePlusLinearMetrics.rowGap) {
                Text("\(RcloneFormat.bytes(job.progressBytes)) of \(RcloneFormat.bytes(job.effectiveTotalBytes))")
                Spacer(minLength: OnePlusLinearMetrics.rowGap)
                if job.stats.speed > 0 || job.displayEta != nil {
                    if job.stats.speed > 0 { Text(RcloneFormat.speed(job.stats.speed)) }
                    if job.displayEta != nil { Text("ETA \(RcloneFormat.eta(job.displayEta))") }
                } else if job.effectiveTotalFiles > 0 {
                    Text("\(job.progressFiles) of \(job.effectiveTotalFiles) files")
                }
            }
            .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
            .lineLimit(1).monospacedDigit()
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 6) {
            if job.stats.transferring.isEmpty {
                Text(job.state.isTerminal ? "No in-flight files" : "Waiting for file activity")
                    .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
            } else {
                ForEach(Array(job.stats.transferring.prefix(4))) { file in TrayTransferFileRow(file: file) }
                if job.stats.transferring.count > 4 {
                    Text("\(job.stats.transferring.count - 4) more in-flight files")
                        .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
                }
            }
        }
        .padding(.leading, 14 + OnePlusLinearMetrics.rowGap)
    }

    private var stateText: some View {
        Text(job.state.displayName)
            .linearText(OnePlusLinearMetrics.caption, weight: .medium, color: stateColor)
            .lineLimit(1)
    }

    private var stateColor: Color {
        switch job.state {
        case .running: OnePlusLinearColor.cpu
        case .retrying, .paused: OnePlusLinearColor.warning
        case .completed: OnePlusLinearColor.battery
        case .failed: OnePlusLinearColor.destructiveText
        case .queued, .cancelled: OnePlusLinearColor.panelMuted
        }
    }

    private func transferButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        OnePlusLinearIconButton(systemImage: symbol, help: title, size: OnePlusLinearMetrics.panelAccessory, action: action)
    }
}

private struct TrayTransferFileRow: View {
    let file: FileProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc").font(.system(size: 11)).foregroundStyle(OnePlusLinearColor.panelMuted)
                Text(file.name).linearText(OnePlusLinearMetrics.caption)
                    .lineLimit(1).truncationMode(.middle).help(file.name)
                Spacer(minLength: 4)
                Text("\(file.percentage)%").linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.secondary)
                    .monospacedDigit()
            }
            OnePlusLinearUsageBar(file.fraction, color: OnePlusLinearColor.cpu)
            HStack {
                Text("\(RcloneFormat.bytes(file.bytes)) of \(RcloneFormat.bytes(file.size))")
                Spacer()
                if file.speed > 0 { Text(RcloneFormat.speed(file.speed)) }
                if file.eta != nil { Text("ETA \(RcloneFormat.eta(file.eta))") }
            }
            .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
            .monospacedDigit()
        }
    }
}
