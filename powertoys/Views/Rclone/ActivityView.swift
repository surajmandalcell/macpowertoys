//
//  ActivityView.swift
//  powertoys
//

import SwiftUI
import SwiftData

struct ActivityView: View {
    @Query(sort: \TransferRecord.createdAt, order: .reverse) private var records: [TransferRecord]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var dayGroups: [(day: Date, records: [TransferRecord])] {
        Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.createdAt) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, records: $0.value) }
    }

    private var totalBytes: Int64 {
        records.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            QuietDivider()

            if records.isEmpty {
                emptyState
            } else {
                ledger
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Activity")
                .font(.system(size: 13, weight: .medium))

            Spacer()

            if !records.isEmpty {
                Text("\(records.count) transfer\(records.count == 1 ? "" : "s") · \(RcloneFormat.bytes(totalBytes)) moved")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .padding(.top, 12)
    }

    // MARK: Ledger

    private var ledger: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(dayGroups, id: \.day) { group in
                    dayHeader(group.day)
                    ForEach(group.records) { record in
                        ActivityRow(record: record)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        Text(dayLabel(day).uppercased())
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return Self.dayFormatter.string(from: day)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(icon: "clock.arrow.circlepath", message: "No activity yet")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Activity Row

private struct ActivityRow: View {
    let record: TransferRecord

    @State private var isHovering = false
    @State private var isHoveringInfo = false
    @State private var showInfo = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var caption: String {
        [
            Self.timeFormatter.string(from: record.createdAt),
            RcloneFormat.bytes(record.bytes),
            "\(record.filesTransferred) file\(record.filesTransferred == 1 ? "" : "s")",
            RcloneFormat.duration(record.duration)
        ].joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.state.icon)
                .font(.system(size: 13))
                .foregroundStyle(record.state.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.operation.displayName) · \(record.sourceDisplay) → \(record.destinationDisplay)")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(isHoveringInfo ? 0.06 : 0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .animation(.easeInOut(duration: 0.15), value: isHoveringInfo)
            .onHover { isHoveringInfo = $0 }
            .help("Details")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
        .sheet(isPresented: $showInfo) {
            TransferInfoSheet(details: TransferDetails(record: record))
        }
    }
}
