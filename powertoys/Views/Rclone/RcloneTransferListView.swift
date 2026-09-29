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
                OnePlusEmptyState(emptyTitle, systemImage: "tray", caption: emptyCaption) {
                    Button("New Transfer") { manager.isPresentingNewTransfer = true }
                        .buttonStyle(OnePlusButtonStyle(.neutral))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        manager.filter == .all || manager.filter == .active
            ? "Create a transfer between a local folder and a remote."
            : "Completed transfers stay here until you clear them."
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
        let active = "\(manager.activeJobs.count) active"
        return manager.aggregateSpeed > 0 ? "\(active) · \(RcloneFormat.speed(manager.aggregateSpeed))" : active
    }

    var body: some View {
        OnePlusPageHeader(title: title, subtitle: subtitle) {
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
