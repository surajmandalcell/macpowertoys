import OnePlusUI
import SwiftUI

struct CloudSyncTrayView: View {
    @State private var manager = RcloneJobManager.shared
    @State private var remoteTransfers: [String: TransferJob] = [:]
    @Environment(\.onePlusIsVisible) private var isVisible
    @Binding var jobs: [TransferJob]
    var showsHeader = true

    private var activeJobs: [TransferJob] { jobs.filter { $0.state.isActive } }
    private var recentJobs: [TransferJob] { jobs.filter { $0.state.isTerminal } }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            if showsHeader { TrayToolHeader(tab: .cloudSync) }
            if !manager.daemonIsHealthy {
                HStack {
                    Text("The engine is not responding.").onePlusText(.caption, color: OnePlusColor.warn)
                    Spacer()
                    TrayQuietActionButton(title: "Retry", symbol: "arrow.clockwise") {
                        Task { await manager.start() }
                    }
                }
            }
            OnePlusMenuSectionHeader("Remotes", actionTitle: "New Transfer") {
                ToolActionRouter.shared.open(toolID: "rclone", page: "new-transfer")
            }
            if manager.remotes.isEmpty {
                OnePlusMenuCard {
                    Text(manager.daemonIsHealthy ? "No remotes loaded" : "Open Cloud Sync to load remotes")
                        .onePlusText(.caption)
                }
            } else {
                ForEach(manager.remotes) { remote in remoteCard(remote) }
            }
            if jobs.isEmpty {
                if manager.remotes.isEmpty {
                    OnePlusMenuCard { Text("No transfers yet").onePlusText(.caption) }
                }
            } else {
                HStack(spacing: OnePlusMenuMetrics.tileGap) {
                    OnePlusMenuTile(span: 2) {
                        VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                            Label("Active transfers", systemImage: "cloud").onePlusText(.caption)
                            Text(String(activeJobs.count)).onePlusText(.metric, color: OnePlusColor.dataBlue)
                            Text(RcloneFormat.speed(activeJobs.reduce(0) { $0 + $1.stats.speed }))
                                .onePlusText(.caption).monospacedDigit()
                        }
                    }
                    OnePlusMenuTile {
                        VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                            Text("Recent").onePlusText(.caption)
                            Text(String(recentJobs.count)).onePlusText(.metric)
                        }
                    }
                }
                jobSection("Active", jobs: activeJobs)
                jobSection("Recent", jobs: recentJobs)
            }
        }
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

    private func remoteCard(_ remote: RcloneRemote) -> some View {
        let lastTransfer = remoteTransfers[remote.name]
        return OnePlusMenuCard {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: remote.icon).onePlusText(.row)
                    Text(remote.displayName).onePlusText(.row, color: OnePlusColor.dataBlue)
                        .lineLimit(1).help(remote.displayName)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    Text(lastTransfer?.state.displayName ?? "Configured").onePlusText(.caption)
                }
                if let lastTransfer {
                    Text("\(lastTransfer.finishedAt == nil ? "Started" : "Last transfer") · \((lastTransfer.finishedAt ?? lastTransfer.createdAt).formatted(date: .abbreviated, time: .shortened))")
                        .onePlusText(.caption)
                } else {
                    Text("No transfers yet · \(remote.typeLabel)").onePlusText(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func jobSection(_ title: String, jobs: [TransferJob]) -> some View {
        if !jobs.isEmpty {
            OnePlusMenuSectionHeader(title)
            ForEach(jobs) { job in
                TrayTransferRow(job: job)
            }
        }
    }
}

private struct TrayTransferOrderKey: Equatable {
    let id: UUID
    let state: TransferState
}

private struct TrayTransferRow: View {
    let job: TransferJob
    @State private var manager = RcloneJobManager.shared
    @State private var showsError = false

    var body: some View {
        OnePlusMenuCard {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack(spacing: OnePlusMenuMetrics.tileGap) {
                    Button {
                        manager.setExpanded(!job.isExpanded, for: job)
                    } label: {
                        Image(systemName: job.isExpanded ? "chevron.down" : "chevron.right")
                            .onePlusText(.caption)
                            .frame(width: OnePlusMetrics.compactControlHeight, height: OnePlusMetrics.compactControlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.iconButtonRadius))
                    .accessibilityLabel(job.isExpanded ? "Hide transfer files" : "Show transfer files")
                    .help(job.isExpanded ? "Hide transfer files" : "Show transfer files")
                    Image(systemName: job.operation.icon).onePlusText(.caption)
                    Text("\(job.sourceDisplay) → \(job.destinationDisplay)")
                        .onePlusText(.row).lineLimit(1).truncationMode(.middle)
                        .help("\(job.sourceDisplay) → \(job.destinationDisplay)")
                    Spacer(minLength: 4)
                    if job.state == .failed, job.errorMessage?.isEmpty == false {
                        Button { showsError.toggle() } label: { stateBadge }
                            .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.iconButtonRadius))
                            .accessibilityLabel(showsError ? "Hide transfer error" : "Show transfer error")
                    } else {
                        stateBadge
                    }
                    if job.canPause {
                        transferButton("Pause transfer", symbol: "pause.fill") { manager.pause(job) }
                    } else if job.canResume {
                        transferButton("Resume transfer", symbol: "play.fill") { manager.resume(job) }
                    } else if job.canRetry {
                        transferButton("Retry transfer", symbol: "arrow.clockwise") { manager.retry(job) }
                    }
                }

                if job.effectiveTotalBytes > 0 || job.state.isActive {
                    OnePlusUsageBar(value: job.progressFraction, color: stateColor)
                    HStack(spacing: OnePlusMenuMetrics.tileGap) {
                        Text("\(RcloneFormat.bytes(job.displayBytes)) of \(RcloneFormat.bytes(job.effectiveTotalBytes))")
                        if job.effectiveTotalFiles > 0 {
                            Text("· \(job.displayFiles) of \(job.effectiveTotalFiles) files")
                        }
                        Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    }
                    .onePlusText(.caption)
                    .lineLimit(1).monospacedDigit()
                    if job.stats.speed > 0 || job.displayEta != nil {
                        HStack {
                            if job.stats.speed > 0 { Text(RcloneFormat.speed(job.stats.speed)) }
                            Spacer()
                            if job.displayEta != nil { Text("ETA \(RcloneFormat.eta(job.displayEta))") }
                        }.onePlusText(.caption).monospacedDigit()
                    }
                }

                if showsError, let error = job.errorMessage, !error.isEmpty {
                    Text(error)
                        .onePlusText(.caption, color: OnePlusColor.danger)
                        .lineLimit(2).help(error)
                }

                if job.isExpanded {
                    VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                        if job.stats.transferring.isEmpty {
                            Text(job.state.isTerminal ? "No in-flight files" : "Waiting for file activity")
                                .onePlusText(.caption)
                        } else {
                            ForEach(Array(job.stats.transferring.prefix(4))) { file in
                                TrayTransferFileRow(file: file)
                            }
                            if job.stats.transferring.count > 4 {
                                Text("\(job.stats.transferring.count - 4) more in-flight files")
                                    .onePlusText(.caption)
                            }
                        }
                    }
                    .padding(.leading, OnePlusMetrics.compactControlHeight + OnePlusMenuMetrics.tileGap)
                }
            }
        }
    }

    private var stateBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: job.state.icon)
            Text(job.state.displayName)
        }
        .onePlusText(.caption, color: stateColor)
        .lineLimit(1)
    }

    private var stateColor: Color {
        switch job.state {
        case .running: OnePlusColor.dataBlue
        case .retrying, .paused: OnePlusColor.warn
        case .completed: OnePlusColor.ok
        case .failed: OnePlusColor.danger
        case .queued, .cancelled: OnePlusColor.secondary
        }
    }

    private func transferButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct TrayTransferFileRow: View {
    let file: FileProgress

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            HStack(spacing: 6) {
                Image(systemName: "doc").onePlusText(.caption)
                Text(file.name).onePlusText(.caption, color: OnePlusColor.ink)
                    .lineLimit(1).truncationMode(.middle).help(file.name)
                Spacer(minLength: 4)
                Text("\(file.percentage)%")
                    .onePlusText(.mono)
            }
            OnePlusUsageBar(value: file.fraction, color: OnePlusColor.dataBlue)
            HStack {
                Text("\(RcloneFormat.bytes(file.bytes)) of \(RcloneFormat.bytes(file.size))")
                Spacer()
                if file.speed > 0 { Text(RcloneFormat.speed(file.speed)) }
                if file.eta != nil { Text("ETA \(RcloneFormat.eta(file.eta))") }
            }
            .onePlusText(.caption)
            .monospacedDigit()
        }
    }
}
