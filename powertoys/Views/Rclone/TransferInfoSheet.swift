//
//  TransferInfoSheet.swift
//  powertoys
//

import SwiftUI

struct TransferInfoSheet: View {
    private let job: TransferJob?
    private let recordDetails: TransferDetails?

    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: InfoTab = .overview

    private static let textGutter: CGFloat = 34
    private static let cardMargin: CGFloat = 20
    private static let cardPadding: CGFloat = 14

    init(details: TransferDetails) {
        self.recordDetails = details
        self.job = nil
    }

    init(job: TransferJob) {
        self.job = job
        self.recordDetails = nil
    }

    private var details: TransferDetails {
        job.map { TransferDetails(job: $0) } ?? recordDetails!
    }

    private enum InfoTab: Hashable {
        case overview
        case files
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var duration: TimeInterval? {
        guard let startedAt = details.startedAt, let finishedAt = details.finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            switch selectedTab {
            case .overview:
                overviewContent
            case .files:
                TransferFileTreeView(rootFs: details.sourceFs)
                    .padding(.top, 12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 640, height: 620)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Transfer Details")
                .font(.system(size: 15, weight: .semibold))

            stateBadge

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.leading, Self.textGutter)
        .padding(.trailing, Self.cardMargin)
        .padding(.vertical, 16)
    }

    private var stateBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: details.state.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(details.state.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(details.state.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(details.state.tint.opacity(0.12))
        )
        .fixedSize()
    }

    private var tabBar: some View {
        HStack {
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(InfoTab.overview)
                Text("Files").tag(InfoTab.files)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Spacer()
        }
        .padding(.leading, Self.textGutter)
        .padding(.trailing, Self.cardMargin)
        .padding(.bottom, 12)
    }

    // MARK: Overview

    private var overviewContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                section("Route") { routeRows }
                section("Result") { resultRows }
                section("Timing") { timingRows }
                section("Ignore Rules") { ignoreRuleRows }
            }
            .padding(.horizontal, Self.cardMargin)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, Self.textGutter - Self.cardMargin)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func monoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var routeRows: some View {
        HStack(spacing: 8) {
            Text(details.sourceDisplay)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(details.destinationDisplay)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))

        row("Kind", value: details.kind == .directory ? "Folder" : "Single file")
        monoRow("Source", value: details.sourceFs)
        monoRow("Destination", value: details.destinationFs)
    }

    @ViewBuilder
    private var resultRows: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("State")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                Image(systemName: details.state.icon)
                    .font(.system(size: 11))
                Text(details.state.displayName)
                    .font(.system(size: 13))
            }
            .foregroundStyle(details.state.tint)
        }

        row("Data moved", value: "\(RcloneFormat.bytes(details.bytes)) of \(RcloneFormat.bytes(details.totalBytes))")
        row("Files", value: "\(details.filesTransferred) of \(details.totalFiles)")
        row("Average speed", value: RcloneFormat.speed(details.averageSpeed))

        if details.attempts > 0 {
            row("Attempts", value: "\(details.attempts)")
        }

        if let message = details.errorMessage {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }

        if let job, job.kind == .directory, !job.state.isTerminal {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Size & diff")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Re-scans source and destination so totals and remaining data are exact.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 12)
                if job.isRecalculating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning both sides…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Recalculate") { manager.recalculate(job) }
                        .disabled(!manager.daemonIsHealthy)
                }
            }
        }
    }

    @ViewBuilder
    private var timingRows: some View {
        row("Created", value: Self.dateFormatter.string(from: details.createdAt))
        row("Started", value: details.startedAt.map(Self.dateFormatter.string(from:)) ?? "—")
        row("Finished", value: details.finishedAt.map(Self.dateFormatter.string(from:)) ?? "—")
        row("Duration", value: RcloneFormat.duration(duration))
    }

    @ViewBuilder
    private var ignoreRuleRows: some View {
        if details.excludePatterns.isEmpty {
            Text("None")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        } else {
            ForEach(details.excludePatterns, id: \.self) { pattern in
                Text(pattern)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}

struct TransferDetails {
    let operation: RcloneOperation
    let kind: TransferKind
    let state: TransferState
    let sourceFs: String
    let destinationFs: String
    let sourceDisplay: String
    let destinationDisplay: String
    let excludePatterns: [String]
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let bytes: Int64
    let totalBytes: Int64
    let filesTransferred: Int
    let totalFiles: Int
    let attempts: Int
    let averageSpeed: Double
    let errorMessage: String?

    init(job: TransferJob) {
        operation = job.operation
        kind = job.kind
        state = job.state
        sourceFs = job.sourceFs
        destinationFs = job.destinationFs
        sourceDisplay = job.sourceDisplay
        destinationDisplay = job.destinationDisplay
        excludePatterns = job.excludePatterns
        createdAt = job.createdAt
        startedAt = job.startedAt
        finishedAt = job.finishedAt
        bytes = job.displayBytes
        totalBytes = job.effectiveTotalBytes
        filesTransferred = job.displayFiles
        totalFiles = job.effectiveTotalFiles
        attempts = job.attempt
        if let duration = job.duration, duration > 0 {
            averageSpeed = Double(job.stats.bytes) / duration
        } else {
            averageSpeed = job.stats.speed
        }
        errorMessage = job.errorMessage
    }

    init(record: TransferRecord) {
        operation = record.operation
        kind = record.kind
        state = record.state
        sourceFs = record.sourceFs
        destinationFs = record.destinationFs
        sourceDisplay = record.sourceDisplay
        destinationDisplay = record.destinationDisplay
        excludePatterns = record.excludePatterns.split(whereSeparator: \.isNewline).map(String.init)
        createdAt = record.createdAt
        startedAt = record.startedAt
        finishedAt = record.finishedAt
        bytes = record.bytes
        totalBytes = record.totalBytes
        filesTransferred = record.filesTransferred
        totalFiles = record.totalFiles
        attempts = record.attempts
        averageSpeed = record.averageSpeed
        errorMessage = record.errorMessage
    }
}
