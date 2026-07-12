//
//  RcloneTransferListView.swift
//  powertoys
//

import SwiftUI

struct RcloneTransferListView: View {
    @Environment(RcloneJobManager.self) private var manager

    private var hasTerminalJobs: Bool {
        manager.jobs.contains { $0.state.isTerminal }
    }

    private var emptyMessage: String {
        switch manager.filter {
        case .all: return "No transfers yet"
        case .active: return "No active transfers"
        case .completed: return "No completed transfers"
        case .failed: return "No failed transfers"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let banner = manager.errorBanner {
                errorBanner(banner)
            }

            if manager.filteredJobs.isEmpty {
                emptyState
            } else {
                transferList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(manager.activeJobs.count) active")
                .font(.system(size: 13, weight: .medium))

            if manager.aggregateSpeed > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)
                Label(RcloneFormat.speed(manager.aggregateSpeed), systemImage: "speedometer")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer()

            if hasTerminalJobs {
                Button {
                    manager.clearFinished()
                } label: {
                    Label("Clear finished", systemImage: "xmark.bin")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .padding(.top, 52)
    }

    // MARK: Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red.opacity(0.9))
                .textSelection(.enabled)
            Spacer()
            Button {
                manager.errorBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }

    // MARK: List

    private var transferList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(manager.filteredJobs) { job in
                    TransferJobRow(job: job)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            EmptyStateView(icon: "tray", message: emptyMessage)
            if manager.filter == .all || manager.filter == .active {
                Button {
                    manager.isPresentingNewTransfer = true
                } label: {
                    Label("New Transfer", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
