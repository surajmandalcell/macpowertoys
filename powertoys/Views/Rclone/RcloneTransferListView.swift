import OnePlusUI
import SwiftUI

struct RcloneTransferListView: View {
    @Environment(RcloneJobManager.self) private var manager

    private var emptyTitle: String {
        switch manager.filter {
        case .all: "No transfers yet"
        case .active: "No active transfers"
        case .completed: "No completed transfers"
        case .failed: "No failed transfers"
        }
    }

    var body: some View {
        let jobs = manager.filteredJobs
        OnePlusPage(scrolls: false) {
            RcloneTransferHeader()
        } content: {
            if let message = manager.errorBanner {
                OnePlusBanner(message, tone: .error) {
                    Button("Dismiss") { manager.errorBanner = nil }
                }
            }

            if jobs.isEmpty {
                if RcloneTransferPresentation.showsNewTransferAction(for: manager.filter) {
                    OnePlusEmptyState(emptyTitle, systemImage: "tray", caption: emptyCaption) {
                        Button("New Transfer") { manager.isPresentingNewTransfer = true }
                            .buttonStyle(OnePlusButtonStyle(.neutral))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    OnePlusEmptyState(emptyTitle, systemImage: "tray", caption: emptyCaption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: OnePlusMetrics.spacing[3]) {
                        ForEach(jobs) { TransferJobRow(job: $0) }
                    }
                }
                .onePlusScrollIndicators()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("rclone.transfers.\(manager.filter.rawValue)")
    }

    private var emptyCaption: String {
        RcloneTransferPresentation.emptyCaption(for: manager.filter)
    }
}

enum RcloneTransferPresentation {
    static func subtitle(
        for filter: JobFilter,
        activeCount: Int,
        filteredCount: Int,
        aggregateSpeed: Double
    ) -> String {
        switch filter {
        case .all, .active:
            let active = "\(activeCount) active"
            return aggregateSpeed > 0 ? "\(active) · \(RcloneFormat.speed(aggregateSpeed))" : active
        case .completed:
            return "\(filteredCount) completed"
        case .failed:
            return "\(filteredCount) failed"
        }
    }

    static func emptyCaption(for filter: JobFilter) -> String {
        switch filter {
        case .all, .active:
            return "Create a transfer between a local folder and a remote."
        case .completed:
            return "Completed transfers stay here until you clear them."
        case .failed:
            return "Failed and cancelled transfers stay here until you clear them."
        }
    }

    static func showsNewTransferAction(for filter: JobFilter) -> Bool {
        filter == .all || filter == .active
    }
}

private struct RcloneTransferHeader: View {
    @Environment(RcloneJobManager.self) private var manager

    private var title: String {
        switch manager.filter {
        case .all: "All transfers"
        case .active: "Active transfers"
        case .completed: "Completed transfers"
        case .failed: "Failed transfers"
        }
    }

    private var subtitle: String {
        RcloneTransferPresentation.subtitle(
            for: manager.filter,
            activeCount: manager.activeJobs.count,
            filteredCount: manager.filteredJobs.count,
            aggregateSpeed: manager.aggregateSpeed
        )
    }

    var body: some View {
        OnePlusPageHeader(title: title) {
            Text(subtitle).onePlusText(.caption).lineLimit(1)
            if manager.jobs.contains(where: { $0.state.isTerminal }) {
                Button("Clear finished") { manager.clearFinished() }
                    .buttonStyle(OnePlusButtonStyle(.ghost))
            }
            if manager.isGloballyPaused || !manager.activeJobs.isEmpty {
                Button(manager.isGloballyPaused ? "Resume all" : "Pause all") {
                    manager.isGloballyPaused ? manager.resumeAll() : manager.pauseAll()
                }
                .buttonStyle(OnePlusButtonStyle(.neutral))
            }
        }
    }
}
