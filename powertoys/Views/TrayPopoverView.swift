//
//  TrayPopoverView.swift
//  powertoys
//

import SwiftUI
import SwiftData

struct TrayPopoverView: View {
    @AppStorage("tray.selectedTab") private var selectedTab = "rclone"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.openWindow) private var openWindow
    @State private var slideForward = true
    @State private var settings = SettingsManager.shared

    private var trayTools: [any Tool] {
        ToolRegistry.allTools.filter { $0.hasTrayTab && settings.isToolEnabled($0.id) }
    }

    private var trayToolIDs: [String] { trayTools.map(\.id) }

    var body: some View {
        VStack(spacing: 0) {
            if trayTools.isEmpty {
                EmptyStateView(icon: "switch.2", message: "No enabled tray tools")
                    .frame(height: 160)
            } else {
                TrayTabStrip(tools: trayTools, selected: tabSelection)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                (colorScheme == .dark ? Color.white : Color.black)
                                    .opacity(contrast == .increased ? 0.16 : 0.08),
                                lineWidth: 1
                            )
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                ZStack {
                    tabContent
                        .id(selectedTab)
                        .transition(.asymmetric(
                            insertion: .move(edge: slideForward ? .trailing : .leading),
                            removal: .move(edge: slideForward ? .leading : .trailing)
                        ))
                }
                .clipped()
                .frame(maxWidth: .infinity)
            }

            QuietDivider()

            footer
        }
        .frame(width: 340)
        .background {
            Color.black
                .opacity(colorScheme == .dark ? 0.2 : 0.04)
                .ignoresSafeArea()
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: trayToolIDs) { normalizeSelection() }
    }

    private func normalizeSelection() {
        if !trayTools.contains(where: { $0.id == selectedTab }), let first = trayTools.first {
            selectedTab = first.id
        }
    }

    private var tabSelection: Binding<String> {
        Binding(
            get: { selectedTab },
            set: { nextTab in
                guard nextTab != selectedTab else { return }
                let oldIndex = trayTools.firstIndex { $0.id == selectedTab } ?? 0
                let newIndex = trayTools.firstIndex { $0.id == nextTab } ?? 0
                slideForward = newIndex > oldIndex
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = nextTab
                }
            }
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "rclone":
            RSyncTrayTab()
        case "awake":
            AwakeTrayTab()
        default:
            EmptyStateView(icon: "wrench.adjustable", message: "No tray view")
                .frame(height: 160)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TrayFooterButton(title: "Open MacPowerToys", systemImage: AppDelegate.openMainWindowSymbol) {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Spacer()

            TrayFooterButton(title: "Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
    }
}

private struct AwakeTrayTab: View {
    @State private var service = AwakeService.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(service.isActive ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                    .frame(width: 18)
                Text(service.statusText).font(.system(size: 11)).monospacedDigit().lineLimit(1)
                Spacer()
                TrayActionButton(title: "Open", isPrimary: false) {
                    openWindow(id: "awake")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .frame(minHeight: 24)

            Picker("Awake mode", selection: quickMode) {
                Text("Off").tag(AwakeQuickMode.off)
                Text("Indefinite").tag(AwakeQuickMode.indefinite)
                Text("30 min").tag(AwakeQuickMode.thirtyMinutes)
                Text("1 hour").tag(AwakeQuickMode.oneHour)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            HStack(spacing: 8) {
                Text("Keep Display On")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { service.configuration.keepDisplayOn },
                    set: service.setKeepDisplayOn
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Applies while Awake is active")
                .accessibilityLabel("Keep Display On")
            }
            .frame(minHeight: 24)

            if let error = service.assertionError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var quickMode: Binding<AwakeQuickMode> {
        Binding(
            get: { AwakeQuickMode(configuration: service.configuration) },
            set: { mode in
                switch mode {
                case .off:
                    service.setMode(.passive)
                case .indefinite:
                    service.setMode(.indefinite)
                case .thirtyMinutes:
                    service.setMode(.timed, duration: 1_800)
                case .oneHour:
                    service.setMode(.timed, duration: 3_600)
                case .custom:
                    break
                }
            }
        )
    }
}

// MARK: - Tab Strip (chrome-style)

private struct TrayTabStrip: View {
    let tools: [any Tool]
    @Binding var selected: String

    private let maxTabWidth: CGFloat = 150
    private let minTabWidth: CGFloat = 30
    private let labelThreshold: CGFloat = 84
    private let tabSpacing: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let count = max(1, tools.count)
            let perTab = min(maxTabWidth, max(minTabWidth, (geo.size.width - CGFloat(count - 1) * tabSpacing) / CGFloat(count)))
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
        HStack(spacing: tabSpacing) {
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
                ToolIconView(tool: tool, size: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if showsLabel {
                    Text(tool.name)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(
                            isSelected
                                ? Color(nsColor: .alternateSelectedControlTextColor)
                                : (isHovering ? Color.primary : Color.secondary)
                        )
                        .lineLimit(1)
                }
            }
            .frame(width: width, height: 28)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? Color(nsColor: .controlAccentColor)
                            : (isHovering ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - RSync Tray Tab

private struct RSyncTrayTab: View {
    @State private var manager = RcloneJobManager.shared
    @State private var contentHeight: CGFloat = 60
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TransferRecord.createdAt, order: .reverse) private var records: [TransferRecord]

    private var recentRecords: [TransferRecord] {
        Array(records.prefix(3))
    }

    private var maxContentHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) * 0.7 - 130
    }

    var body: some View {
        VStack(spacing: 0) {
            statusRow
                .padding(.horizontal, 12)
                .padding(.top, 10)

            ScrollView(showsIndicators: false) {
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
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    contentHeight = newHeight
                }
            }
            .frame(height: min(max(contentHeight, 44), maxContentHeight))
            .padding(.bottom, 2)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if manager.daemonIsHealthy {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .frame(width: 18, height: 18)
            } else {
                TrayRetryButton {
                    Task { await manager.start() }
                }
            }

            Text(manager.isDaemonRunning ? manager.daemonStatusText : "Engine not running")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            TrayActionButton(title: "Open Cloud Sync", isPrimary: false) {
                openWindow(id: "rclone")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .frame(minHeight: 24)
    }

    private var engineOffState: some View {
        Text("The engine is not running. Select Retry to start it.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
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
                    HStack(spacing: 8) {
                        Image(systemName: record.state.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(record.state.tint)
                            .frame(width: 18)

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
                    .frame(minHeight: 24)
                }
            }
        }
    }

    private var activeTransfers: some View {
        VStack(spacing: 12) {
            ForEach(manager.activeJobs.prefix(8)) { job in
                TrayTransferRow(job: job)
            }

            if manager.activeJobs.count > 8 {
                Text("+\(manager.activeJobs.count - 8) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

}

// MARK: - Retry Button

private struct TrayRetryButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovering ? 0.1 : 0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .help("Restart the engine")
    }
}

// MARK: - Tray Transfer Row

private struct TrayTransferRow: View {
    let job: TransferJob
    @State private var manager = RcloneJobManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: job.operation.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)

                Text("\(job.sourceDisplay) → \(job.destinationDisplay)")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(job.state == .paused ? "Paused" : RcloneFormat.speed(job.stats.speed))
                    .font(.system(size: 10))
                    .foregroundStyle(job.state == .paused ? Color.orange : Color.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if job.canPause {
                    transferControl(title: "Pause transfer", systemImage: "pause.fill") {
                        manager.pause(job)
                    }
                } else if job.canResume {
                    transferControl(title: "Resume transfer", systemImage: "play.fill") {
                        manager.resume(job)
                    }
                }
            }
            .frame(minHeight: 22)

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
            .padding(.leading, 26)

            ForEach(job.stats.transferring.prefix(3)) { file in
                HStack(spacing: 8) {
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
                .padding(.leading, 26)
            }
        }
    }

    private func transferControl(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(title)
        .accessibilityLabel(title)
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
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}
