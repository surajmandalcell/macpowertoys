//
//  DemoRSync.swift
//  powertoys
//

#if MPT_DEMO
import Foundation

@MainActor
enum DemoRSync {
    private struct Plan {
        let source: String
        let remote: String
        let destination: String
        let totalBytes: Int64
        let startBytes: Int64
        let files: Int
        let speed: Double
        let fileName: String
        let fileSize: Int64
    }

    private static let gigabyte: Int64 = 1_000_000_000
    private static let tick = 0.25

    private static let plans = [
        Plan(source: "Raw 2025", remote: "backblaze", destination: "photos/Raw 2025",
             totalBytes: 88_100_000_000, startBytes: 31 * gigabyte, files: 2_412, speed: 118_000_000,
             fileName: "DSC_4821.NEF", fileSize: 48_200_000),
        Plan(source: "Camera Roll", remote: "gdrive", destination: "Camera Roll",
             totalBytes: 18_400_000_000, startBytes: 12 * gigabyte, files: 1_836, speed: 42_000_000,
             fileName: "IMG_7304.HEIC", fileSize: 3_600_000),
    ]

    /// Finished earlier today, so the window and panel also show completed rows.
    private static let done: [(Plan, Double)] = [
        (Plan(source: "Documents/Taxes 2025", remote: "wasabi", destination: "archive/Taxes 2025",
              totalBytes: 1_240_000_000, startBytes: 0, files: 318, speed: 64_000_000,
              fileName: "", fileSize: 1), 1.5),
        (Plan(source: "Movies/Iceland Trip", remote: "backblaze", destination: "video/Iceland Trip",
              totalBytes: 42_600_000_000, startBytes: 0, files: 96, speed: 121_000_000,
              fileName: "", fileSize: 1), 3.2),
        (Plan(source: "Projects/storefront", remote: "gdrive", destination: "Backups/storefront",
              totalBytes: 860_000_000, startBytes: 0, files: 4_812, speed: 38_000_000,
              fileName: "", fileSize: 1), 5.8),
    ]

    private static var jobs: [(TransferJob, Plan)] = []

    static func seed() {
        jobs = plans.map { plan in
            let job = TransferJob(
                operation: .copy,
                sourceFs: "/Users/sam/Pictures/\(plan.source)",
                destinationFs: "\(plan.remote):\(plan.destination)",
                sourceDisplay: "Pictures/\(plan.source)",
                destinationDisplay: "\(plan.remote):\(plan.destination)",
                excludePatterns: [],
                maxRetries: 3
            )
            job.state = .running
            job.startedAt = Date().addingTimeInterval(-Double(plan.startBytes) / plan.speed)
            job.stats = stats(for: plan, bytes: plan.startBytes)
            job.refreshDisplayEta()
            return (job, plan)
        }
        let finished = done.map { plan, hoursAgo in
            let job = TransferJob(
                operation: .copy,
                sourceFs: "/Users/sam/\(plan.source)",
                destinationFs: "\(plan.remote):\(plan.destination)",
                sourceDisplay: plan.source,
                destinationDisplay: "\(plan.remote):\(plan.destination)",
                excludePatterns: [],
                maxRetries: 3
            )
            job.state = .completed
            job.finishedAt = Date().addingTimeInterval(-hoursAgo * 3600)
            job.startedAt = job.finishedAt?.addingTimeInterval(-Double(plan.totalBytes) / plan.speed)
            var stats = stats(for: plan, bytes: plan.totalBytes)
            stats.transferring = []
            stats.eta = 0
            job.stats = stats
            return job
        }
        RcloneJobManager.shared.applyDemo(
            remotes: [
                RcloneRemote(name: "backblaze", type: "b2"),
                RcloneRemote(name: "gdrive", type: "drive"),
                RcloneRemote(name: "wasabi", type: "s3"),
            ],
            jobs: jobs.map(\.0) + finished
        )
        // A still holds the numbers, so no digit is caught mid-roll.
        guard DemoStill.directory == nil else { return }
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(tick))
                advance()
            }
        }
    }

    private static func advance() {
        for (job, plan) in jobs where job.state == .running {
            job.stats = stats(for: plan, bytes: min(plan.totalBytes, job.stats.bytes + Int64(plan.speed * tick)))
            job.refreshDisplayEta()
        }
    }

    private static func stats(for plan: Plan, bytes: Int64) -> TransferStats {
        let fileBytes = bytes % plan.fileSize
        var stats = TransferStats()
        stats.bytes = bytes
        stats.totalBytes = plan.totalBytes
        stats.speed = plan.speed
        stats.eta = Double(plan.totalBytes - bytes) / plan.speed
        stats.transfers = Int(Double(plan.files) * Double(bytes) / Double(plan.totalBytes))
        stats.totalTransfers = plan.files
        stats.elapsedTime = Double(bytes) / plan.speed
        stats.transferring = [FileProgress(
            name: plan.fileName, size: plan.fileSize, bytes: fileBytes,
            percentage: Int(100 * fileBytes / plan.fileSize), speed: plan.speed, speedAvg: plan.speed,
            eta: Double(plan.fileSize - fileBytes) / plan.speed
        )]
        return stats
    }

    static var scene: DemoScene {
        DemoScene(
            open: { ToolActionRouter.shared.open(toolID: "rclone", activateApp: false) },
            steps: [
                DemoStep(at: 1.5) { if let job = jobs.first?.0 { RcloneJobManager.shared.pause(job) } },
                DemoStep(at: 4.0) { if let job = jobs.first?.0 { RcloneJobManager.shared.resume(job) } },
            ],
            tail: 2.0
        )
    }

    /// The menu bar panel on its RSync UI tab, with the same two transfers running.
    static var menuScene: DemoScene {
        DemoScene(open: { DiagnosticsMenuPanels.shared.open(.main, tab: "cloud-sync") }, steps: [], tail: 3.0)
    }
}
#endif
