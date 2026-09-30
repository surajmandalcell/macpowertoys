import OnePlusUI
import SwiftUI

enum TrayPopoverLayout {
    static let width = OnePlusMenuMetrics.width
    static let horizontalInset = OnePlusMenuMetrics.bodyInset
    static let tabHeight = OnePlusMenuMetrics.tab
    static let tabSpacing = OnePlusMenuMetrics.tabGap
    static let netToysDisclosureHorizontalPadding: CGFloat = 6
    static let netToysDisclosureVerticalPadding: CGFloat = 6
    static let minimumBodyHeight: CGFloat = 54
    static let topChromeHeight = OnePlusMenuMetrics.topBar
    static let heightFraction = OnePlusMenuMetrics.heightFraction
    static let homeToolIDs = ["color-picker", "text-extractor", "awake", "ruler"]
    static let defaultComplexTabs: [TrayTab] = [
        .cloudSync, .inputDevices, .systemCare, .netToys,
        .switchAccounts,
    ]

    static func maximumBodyHeight(screenHeight: CGFloat) -> CGFloat {
        max(minimumBodyHeight, screenHeight * heightFraction - topChromeHeight)
    }

    nonisolated static func diskBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func orderedComplexTabs(available: [TrayTab], savedIDs: [String]) -> [TrayTab] {
        let availableSet = Set(available)
        var seen = Set<TrayTab>()
        let saved = savedIDs.compactMap(TrayTab.init(rawValue:)).filter {
            $0 != .home && availableSet.contains($0) && seen.insert($0).inserted
        }
        return saved + defaultComplexTabs.filter { availableSet.contains($0) && !seen.contains($0) }
    }

    static func visibleTransferJobs(
        _ jobs: [TransferJob],
        activeLimit: Int = 5,
        recentLimit: Int = 3
    ) -> [TransferJob] {
        let active = jobs
            .filter { $0.state.isActive }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(activeLimit)
        let recent = jobs
            .filter { $0.state.isTerminal }
            .sorted { ($0.finishedAt ?? $0.createdAt) > ($1.finishedAt ?? $1.createdAt) }
            .prefix(recentLimit)
        return Array(active) + Array(recent)
    }

    static func latestTransfersByRemote(_ jobs: [TransferJob]) -> [String: TransferJob] {
        var latest: [String: TransferJob] = [:]
        for job in jobs {
            for endpoint in [job.sourceFs, job.destinationFs] {
                guard let colon = endpoint.firstIndex(of: ":") else { continue }
                let name = String(endpoint[..<colon])
                let date = job.finishedAt ?? job.createdAt
                if let previous = latest[name], date < (previous.finishedAt ?? previous.createdAt) { continue }
                latest[name] = job
            }
        }
        return latest
    }

    nonisolated static func recentAnchors(
        _ anchors: [SSHAnchorConfiguration],
        statuses: [SSHAnchorStatus],
        limit: Int = 5
    ) -> [SSHAnchorConfiguration] {
        let checkedAt = Dictionary(
            statuses.map { ($0.anchorID, $0.lastCheck) },
            uniquingKeysWith: { max($0, $1) }
        )
        return Array(anchors.enumerated().sorted {
            let left = checkedAt[$0.element.id] ?? .distantPast
            let right = checkedAt[$1.element.id] ?? .distantPast
            return left == right ? $0.offset < $1.offset : left > right
        }.prefix(limit).map(\.element))
    }

    nonisolated static func recentNetworkIssues(
        _ events: [NetworkTransitionEvent],
        limit: Int = 5
    ) -> [NetworkTransitionEvent] {
        Array(events.reversed().filter { event in
            event.changes.contains { change in
                switch change {
                case .network(_, let to): to == "disconnected"
                case .gateway(_, let to), .internet(_, let to): to == .unreachable
                }
            }
        }.prefix(limit))
    }
}

struct TrayQuietActionButton: View {
    let title: String
    let symbol: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
        .disabled(disabled)
    }
}

struct TrayToolHeader: View {
    let tab: TrayTab

    var body: some View {
        OnePlusMenuControlRow(tab.title, systemImage: tab.symbol) {
            Button {
                ToolActionRouter.shared.open(toolID: tab.rawValue)
            } label: {
                Image(systemName: "arrow.up.right")
            }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .accessibilityLabel("Open \(tab.title)")
            .help("Open \(tab.title)")
        }
    }
}
