//
//  TrayPopoverView.swift
//  powertoys
//

import SwiftUI
import SwiftData

struct TrayPopoverView: View {
    @AppStorage("tray.selectedTab") private var selectedTab = "rclone"
    @Environment(\.openWindow) private var openWindow

    private var trayTools: [any Tool] {
        ToolRegistry.allTools.filter { $0.hasTrayTab }
    }

    var body: some View {
        VStack(spacing: 0) {
            TrayTabStrip(tools: trayTools, selected: $selectedTab)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()

            tabContent
                .frame(maxWidth: .infinity)

            Divider()

            footer
        }
        .frame(width: 340)
        .onAppear {
            if !trayTools.contains(where: { $0.id == selectedTab }), let first = trayTools.first {
                selectedTab = first.id
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "rclone":
            RSyncTrayTab()
        default:
            EmptyStateView(icon: "wrench.adjustable", message: "No tray view")
                .frame(height: 160)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TrayFooterButton(title: "Open PowerToys") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Spacer()

            TrayFooterButton(title: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Tab Strip (chrome-style)

private struct TrayTabStrip: View {
    let tools: [any Tool]
    @Binding var selected: String

    private let maxTabWidth: CGFloat = 150
    private let minTabWidth: CGFloat = 30
    private let labelThreshold: CGFloat = 84

    var body: some View {
        GeometryReader { geo in
            let count = max(1, tools.count)
            let perTab = min(maxTabWidth, max(minTabWidth, (geo.size.width - CGFloat(count - 1) * 4) / CGFloat(count)))
            let overflow = CGFloat(count) * minTabWidth > geo.size.width

            Group {
                if overflow {
                    ScrollView(.horizontal, showsIndicators: false) {
                        strip(perTab: minTabWidth)
                    }
                } else {
                    strip(perTab: perTab)
                }
            }
        }
        .frame(height: 30)
    }

    private func strip(perTab: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(tools, id: \.id) { tool in
                TrayTabItem(
                    tool: tool,
                    width: perTab,
                    showsLabel: perTab > labelThreshold,
                    isSelected: selected == tool.id
                ) {
                    selected = tool.id
                }
            }
        }
    }
}

private struct TrayTabItem: View {
    let tool: any Tool
    let width: CGFloat
    let showsLabel: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(tool.logoAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if showsLabel {
                    Text(tool.name)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, height: 26)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.08) : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - RSync Tray Tab

private struct RSyncTrayTab: View {
    @State private var manager = RcloneJobManager.shared
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TransferRecord.createdAt, order: .reverse) private var records: [TransferRecord]

    private var recentRecords: [TransferRecord] {
        Array(records.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusRow
                .padding(.horizontal, 12)
                .padding(.top, 10)

            Group {
                if !manager.isDaemonRunning {
                    engineOffState
                } else if manager.activeJobs.isEmpty {
                    idleState
                } else {
                    activeTransfers
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            actionRow
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(manager.daemonIsHealthy ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)

            Text(manager.isDaemonRunning ? manager.daemonStatusText : "Engine not running")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if manager.aggregateSpeed > 0 {
                Text(RcloneFormat.speed(manager.aggregateSpeed))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    private var engineOffState: some View {
        VStack(spacing: 8) {
            Text("Start the engine to queue and monitor transfers from here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await manager.start() }
            } label: {
                Text("Start Engine")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 6) {
            if recentRecords.isEmpty {
                Text("No transfers yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                Text("RECENT")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(recentRecords) { record in
                    HStack(spacing: 6) {
                        Image(systemName: record.state.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(record.state.tint)

                        Text("\(record.sourceDisplay) → \(record.destinationDisplay)")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 4)

                        Text(RcloneFormat.bytes(record.bytes))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var activeTransfers: some View {
        VStack(spacing: 8) {
            ForEach(manager.activeJobs.prefix(4)) { job in
                TrayTransferRow(job: job)
            }

            if manager.activeJobs.count > 4 {
                Text("+\(manager.activeJobs.count - 4) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            TrayActionButton(title: "New Transfer", isPrimary: true) {
                openWindow(id: "rclone")
                NSApplication.shared.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: .newTransferRequested, object: nil)
                }
            }

            TrayActionButton(title: "Open RSync", isPrimary: false) {
                openWindow(id: "rclone")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Spacer()
        }
    }
}

// MARK: - Tray Transfer Row

private struct TrayTransferRow: View {
    let job: TransferJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: job.operation.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)

                Text("\(job.sourceDisplay) → \(job.destinationDisplay)")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(RcloneFormat.speed(job.stats.speed))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, min(1, job.progressFraction)) * geo.size.width)
                        .animation(.easeInOut(duration: 0.3), value: job.progressFraction)
                }
            }
            .frame(height: 4)

            ForEach(job.stats.transferring.prefix(3)) { file in
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    Text("\(file.percentage)%")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Buttons

private struct TrayActionButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isPrimary ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(isPrimary ? Color.accentColor.opacity(isHovering ? 0.85 : 1.0) : Color.primary.opacity(isHovering ? 0.1 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

private struct TrayFooterButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}
