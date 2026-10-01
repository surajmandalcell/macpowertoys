import AppKit
import OnePlusUI
import QuickLook
import SwiftUI

struct SystemCareInfo: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Image(systemName: "info.circle").onePlusText(.caption)
            .help(text).accessibilityLabel(text)
    }
}

struct SystemCareDiskSummary: View {
    let disk: SystemCareStartupDiskSnapshot?
    let loaded: Bool
    @Environment(\.onePlusDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Text("Startup disk").onePlusText(.cardTitle)
                SystemCareInfo("Purgeable space is separate from free space. macOS can make it available when needed.")
                Spacer()
                Text(disk.map { "\(TrayPopoverLayout.diskBytes($0.capacity)) total" } ?? (loaded ? "Unavailable" : "—"))
                    .onePlusText(.caption)
            }
            HStack(spacing: OnePlusMetrics.cardGap) {
                value("Used", bytes: disk?.used)
                if disk?.purgeable != nil { value("Purgeable", bytes: disk?.purgeable) }
                value("Free", bytes: disk?.free)
                if density == .regular { Spacer(minLength: 0) }
            }
            OnePlusSegmentBar(values: disk.map { [Double($0.used), Double($0.purgeable ?? 0), Double($0.free)] } ?? [],
                              colors: [OnePlusColor.dataBlue, OnePlusColor.warn, OnePlusColor.ok])
        }
    }

    private func value(_ title: String, bytes: Int64?) -> some View {
        let metric = bytes.map(SystemCareByteMetric.init)
        return VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
            Text(title).onePlusText(.metricCaption)
            HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.navRowGap) {
                Text(metric?.value ?? "—").onePlusText(.metric).monospacedDigit().fixedSize()
                Text(metric?.unit ?? "").onePlusText(.unit).fixedSize()
            }
        }
        .frame(maxWidth: density == .compact ? .infinity : nil, alignment: .leading)
        .help(bytes.map { "\(title): \($0.formatted()) bytes" } ?? "\(title): Unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bytes.map { "\(title): \($0.formatted()) bytes" } ?? "\(title): Unavailable")
    }
}

struct SystemCareCandidateRow: View {
    let row: SystemCareCleanupRow
    let manager: SystemCareManager
    var rowIndex = 0
    @Environment(\.onePlusDensity) private var density
    @State private var previewURL: URL?

    var body: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Toggle("Select \(row.candidate.name)", isOn: Binding(
                get: { manager.selectedCandidateIDs.contains(row.id) },
                set: { manager.setCandidate(row.id, selected: $0) }
            ))
            .labelsHidden().toggleStyle(OnePlusCheckboxStyle()).disabled(manager.isWorking)
            Text(row.candidate.name).onePlusText(.row).lineLimit(1).truncationMode(.middle)
            Text(row.candidate.url.deletingLastPathComponent().path).onePlusText(.mono)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.size).onePlusText(.mono)
        }
        .padding(.horizontal, density == .regular ? OnePlusMetrics.cardPadding : OnePlusMenuMetrics.bodyInset)
        .frame(height: OnePlusTable.rowHeight(density))
        .onePlusRowHover()
        .background(OnePlusTable.rowBackground(rowIndex))
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
        .contextMenu { SystemCareFileActions(url: row.candidate.url, previewURL: $previewURL) }
        .quickLookPreview($previewURL)
        .draggable(row.candidate.url)
        .help(row.candidate.url.path)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.candidate.url.path)
    }
}

struct SystemCareFileActions: View {
    let url: URL
    @Binding var previewURL: URL?
    var body: some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Copy Path") { DiskEntryPresentation.copy([url.path]) }
        Button("Open") { NSWorkspace.shared.open(url) }
        Button("Open With…") { DiskEntryPresentation.openWith([url]) }
        Button("Quick Look") { previewURL = url }
    }
}

struct SystemCareScanCoverage: View {
    let manager: SystemCareManager
    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Text(title).onePlusText(.caption, color: manager.cleanupScanOutcome == .completed ? OnePlusColor.secondary : OnePlusColor.warn)
            SystemCareInfo("Scans examine up to 500 immediate children per location. Partial results do not prove a location is empty.")
            Spacer(minLength: 0)
            Button("Coverage") { showingDetails = true }
                .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                .popover(isPresented: $showingDetails) { details }
            if manager.cleanupScanOutcome != .completed {
                Button("Retry Scan") {
                    if manager.cleanupCoverage.contains(where: { !$0.isComplete }) { manager.retryCleanupScan() }
                    else { manager.scanCleanup(categories: Set(SystemCareCategoryID.allCases)) }
                }
                    .buttonStyle(OnePlusButtonStyle(.neutral, size: .small)).disabled(manager.isWorking)
            }
        }
    }

    private var title: String {
        switch manager.cleanupScanOutcome {
        case .completed: "Scan complete"
        case .partial: "Partial scan"
        case .canceled: "Scan canceled"
        case .failed: "Scan failed"
        case nil: "Scan coverage unavailable"
        }
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Text("Scan coverage").onePlusText(.sectionTitle)
                if manager.cleanupCoverage.isEmpty {
                    Text("Rescan to verify these locations.").onePlusText(.row)
                }
                ForEach(manager.cleanupCoverage, id: \.root.path) { coverage in
                    VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                        HStack {
                            Text(coverage.category.title).onePlusText(.row)
                            Spacer()
                            Text(coverage.isComplete ? "Complete" : "Incomplete").onePlusText(.caption)
                        }
                        Text(coverage.root.path).onePlusText(.mono)
                        Text("\(coverage.examinedCount) children examined\(coverage.isTruncated ? ", 500-child limit reached" : "")")
                            .onePlusText(.caption)
                        ForEach(coverage.issues, id: \.url.path) { issue in
                            Text("\(issue.url.path): \(issue.reason)").onePlusText(.caption, color: OnePlusColor.danger)
                        }
                    }
                }
            }.padding(OnePlusMetrics.cardPadding).textSelection(.enabled)
        }.frame(width: OnePlusMetrics.wideControlColumn * 2, height: OnePlusMetrics.controlColumn * 2)
    }
}

struct SystemCareTrashFailures: View {
    let failures: [CleanupTrashFailure]
    @State private var showingDetails = false
    var body: some View {
        Button("\(failures.count) failed") { showingDetails = true }
            .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
            .popover(isPresented: $showingDetails) {
                ScrollView {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                        ForEach(failures, id: \.id) { failure in
                            Text(failure.id).onePlusText(.mono)
                            Text(failure.reason).onePlusText(.caption, color: OnePlusColor.danger)
                        }
                    }.padding(OnePlusMetrics.cardPadding).textSelection(.enabled)
                }.frame(width: OnePlusMetrics.wideControlColumn * 2, height: OnePlusMetrics.controlColumn * 2)
            }
    }
}
