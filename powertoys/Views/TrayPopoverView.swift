//
//  TrayPopoverView.swift
//  powertoys
//

import SwiftUI

enum TrayDashboardSection: String, CaseIterable, Identifiable {
    case quickActions
    case awake
    case cloudSync
    case inputDevices

    var id: String { rawValue }
}

enum TrayPopoverLayout {
    static let width: CGFloat = 340
    static let horizontalInset: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static let minimumBodyHeight: CGFloat = 44
    static let footerHorizontalInset: CGFloat = 10
    static let footerTopInset: CGFloat = 8
    static let footerBottomInset: CGFloat = 10
    static let heightFraction: CGFloat = 0.7

    static var chromeHeight: CGFloat {
        footerTopInset + footerBottomInset + 24
    }

    static func maximumBodyHeight(screenHeight: CGFloat) -> CGFloat {
        max(minimumBodyHeight, screenHeight * heightFraction - chromeHeight)
    }

    static func dashboardSections(for availableIDs: [String]) -> [TrayDashboardSection] {
        let available = Set(availableIDs)
        return TrayDashboardSection.allCases.filter { section in
            switch section {
            case .quickActions:
                available.contains("color-picker") || available.contains("text-extractor")
            case .awake:
                available.contains("awake")
            case .cloudSync:
                available.contains("rclone")
            case .inputDevices:
                available.contains("input-devices")
            }
        }
    }
}

struct TrayPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @State private var trayToolIDs = TrayPopoverView.combinedTrayToolIDs()

    static func combinedTrayToolIDs() -> [String] {
        ToolRegistry.allTools.filter { tool in
            tool.hasTrayTab
                && IndividualMenuBarTool(rawValue: tool.id)?.usesMenuBarMode(
                    .combined,
                    enabled: SettingsManager.shared.isToolEnabled(tool.id)
                ) == true
        }
        .map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if trayToolIDs.isEmpty {
                EmptyStateView(icon: "switch.2", message: "No enabled tray tools")
                    .frame(height: 160)
            } else {
                TrayDashboardView(toolIDs: trayToolIDs)
            }

            QuietDivider()

            footer
        }
        .frame(width: TrayPopoverLayout.width)
        .background {
            Color.black
                .opacity(colorScheme == .dark ? 0.2 : 0.04)
                .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let current = Self.combinedTrayToolIDs()
            if current != trayToolIDs { trayToolIDs = current }
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
        .padding(.horizontal, TrayPopoverLayout.footerHorizontalInset)
        .padding(.top, TrayPopoverLayout.footerTopInset)
        .padding(.bottom, TrayPopoverLayout.footerBottomInset)
        .background(Color.primary.opacity(0.03))
    }
}

@MainActor
private struct TrayDashboardView: View {
    let toolIDs: [String]
    @State private var contentHeight: CGFloat = TrayPopoverLayout.minimumBodyHeight

    private var sections: [TrayDashboardSection] {
        TrayPopoverLayout.dashboardSections(for: toolIDs)
    }

    private var quickActionTools: [any Tool] {
        toolIDs.compactMap(ToolRegistry.tool(for:)).filter {
            IndividualMenuBarTool(rawValue: $0.id)?.quickAction != nil
        }
    }

    private var maximumHeight: CGFloat {
        TrayPopoverLayout.maximumBodyHeight(
            screenHeight: NSScreen.main?.visibleFrame.height ?? 900
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sections) { section in
                    if sections.first != section {
                        QuietDivider()
                            .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                    }
                    sectionView(section)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                contentHeight = newHeight
            }
        }
        .thinScrollIndicators()
        .frame(
            height: min(
                max(contentHeight, TrayPopoverLayout.minimumBodyHeight),
                maximumHeight
            )
        )
    }

    @ViewBuilder
    private func sectionView(_ section: TrayDashboardSection) -> some View {
        switch section {
        case .quickActions:
            QuickActionsTraySection(tools: quickActionTools)
        case .awake:
            AwakeTraySection()
        case .cloudSync:
            CloudSyncTraySection()
        case .inputDevices:
            OpenToolTraySection(
                title: "INPUT DEVICES",
                systemImage: "computermouse",
                detail: "Mouse and trackpad controls",
                toolID: "input-devices"
            )
        }
    }
}

private struct TraySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .utilitySectionHeader()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct QuickActionsTraySection: View {
    let tools: [any Tool]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TraySectionHeader(title: "QUICK ACTIONS")
            HStack(spacing: 8) {
                ForEach(tools, id: \.id) { tool in
                    if let menuBarTool = IndividualMenuBarTool(rawValue: tool.id),
                       let action = menuBarTool.quickAction {
                        TrayActionButton(
                            title: menuBarTool.actionTitle ?? tool.name,
                            systemImage: menuBarTool.symbol,
                            toolID: tool.id
                        ) {
                            ToolActionRouter.shared.execute(ToolActionRequest(action: action))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 12)
    }
}

private struct AwakeTraySection: View {
    @State private var service = AwakeService.shared

    private var quickMode: Binding<AwakeQuickMode?> {
        Binding(
            get: {
                let mode = AwakeQuickMode(configuration: service.configuration)
                return mode == .custom ? nil : mode
            },
            set: { mode in
                guard let mode else { return }
                switch mode {
                case .off: service.setMode(.passive)
                case .thirtyMinutes: service.setMode(.timed, duration: 30 * 60)
                case .oneHour: service.setMode(.timed, duration: 60 * 60)
                case .indefinite: service.setMode(.indefinite)
                case .custom: break
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TrayPopoverLayout.rowSpacing) {
            TraySectionHeader(title: "AWAKE")

            HStack(spacing: 8) {
                Image(systemName: service.isActive ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 12))
                    .foregroundStyle(service.isActive ? Color.primary : Color.secondary)
                    .frame(width: 18)
                Text(service.statusText).font(.system(size: 11)).monospacedDigit().lineLimit(1)
                Spacer()
                TrayOpenButton(toolID: "awake", title: "Awake")
            }
            .frame(minHeight: 24)

            Picker("Awake duration", selection: quickMode) {
                Text("Off").tag(AwakeQuickMode?.some(.off))
                Text("30 min").tag(AwakeQuickMode?.some(.thirtyMinutes))
                Text("1 h").tag(AwakeQuickMode?.some(.oneHour))
                Text("∞")
                    .accessibilityLabel("Indefinite")
                    .tag(AwakeQuickMode?.some(.indefinite))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Awake duration")

            if let error = service.assertionError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 12)
    }
}

private struct CloudSyncTraySection: View {
    @State private var manager = RcloneJobManager.shared

    private var statusText: String {
        guard manager.isDaemonRunning else { return "Engine not running" }
        let count = manager.activeJobs.count
        return count == 0 ? "Ready · No active transfers" : "\(count) active transfer\(count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TrayPopoverLayout.rowSpacing) {
            TraySectionHeader(title: "CLOUD SYNC")
            statusRow

            if !manager.activeJobs.isEmpty {
                activeTransfers
            }
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 12)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            if !manager.daemonIsHealthy {
                TrayRetryButton {
                    Task { await manager.start() }
                }
            }

            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
            TrayOpenButton(toolID: "rclone", title: "Cloud Sync")
        }
        .frame(minHeight: 24)
    }

    private var activeTransfers: some View {
        VStack(spacing: 12) {
            ForEach(manager.activeJobs.prefix(3)) { job in
                TrayTransferRow(job: job)
            }

            if manager.activeJobs.count > 3 {
                Text("+\(manager.activeJobs.count - 3) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct OpenToolTraySection: View {
    let title: String
    let systemImage: String
    let detail: String
    let toolID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TraySectionHeader(title: title)
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                TrayOpenButton(toolID: toolID, title: title.capitalized)
            }
            .frame(minHeight: 24)
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.vertical, 12)
    }
}

private struct TrayOpenButton: View {
    let toolID: String
    let title: String

    var body: some View {
        Button("Open") {
            ToolActionRouter.shared.open(toolID: toolID)
        }
        .controlSize(.small)
        .contentShape(Rectangle())
        .help("Open \(title)")
    }
}

// MARK: - Retry Button

private struct TrayRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .focusEffectDisabled()
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .focusEffectDisabled()
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .help(title)
        .accessibilityLabel(title)
    }
}

// MARK: - Buttons

private struct TrayActionButton: View {
    let title: String
    let systemImage: String
    let toolID: String
    let action: () -> Void

    private var tint: NSColor {
        if let color = ToolIconColor.major(asset: ToolRegistry.tool(for: toolID)?.logoAsset ?? "") { return color }
        return .controlAccentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ToolIconColor.label(on: tint))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .focusEffectDisabled()
        .background(Color(nsColor: tint), in: RoundedRectangle(cornerRadius: 6))
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
                .foregroundStyle(Color.primary.opacity(isHovering ? 1 : 0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}
