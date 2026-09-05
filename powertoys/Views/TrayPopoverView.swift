//
//  TrayPopoverView.swift
//  powertoys
//

import SwiftUI
import SwiftData

enum TrayPopoverLayout {
    static let width: CGFloat = 340
    static let horizontalInset: CGFloat = 12
    static let tabGroupInset: CGFloat = 4
    static let tabGroupOuterInset: CGFloat = 8
    static let tabHeight: CGFloat = 28
    static let tabSpacing: CGFloat = 4
    static let minimumTabWidth: CGFloat = 30
    static let tabTransitionDuration = UtilityMotion.standardDuration
    static let bodyTopInset: CGFloat = 0
    static let settingsTopInset: CGFloat = 10
    static let bodyBottomInset: CGFloat = 14
    static let rowSpacing: CGFloat = 10
    static let minimumBodyHeight: CGFloat = 44
    static let footerHorizontalInset: CGFloat = 10
    static let footerTopInset: CGFloat = 8
    static let footerBottomInset: CGFloat = 10
    static let heightFraction: CGFloat = 0.7

    static var chromeHeight: CGFloat {
        tabGroupOuterInset * 2 + tabGroupInset * 2 + tabHeight
            + footerTopInset + footerBottomInset + 24
    }

    static func maximumBodyHeight(screenHeight: CGFloat) -> CGFloat {
        max(minimumBodyHeight, screenHeight * heightFraction - chromeHeight)
    }

    static func tabWidth(availableWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return availableWidth }
        let totalSpacing = CGFloat(count - 1) * tabSpacing
        return max(minimumTabWidth, (availableWidth - totalSpacing) / CGFloat(count))
    }

    static func showsTabLabels(count: Int) -> Bool { count <= 2 }

    static func normalizedSelection(_ selection: String, availableIDs: [String]) -> String? {
        availableIDs.contains(selection) ? selection : availableIDs.first
    }
}

struct TrayPopoverView: View {
    @AppStorage("tray.selectedTab") private var selectedTab = "rclone"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.openWindow) private var openWindow
    @State private var slideForward = true
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

    private var trayTools: [any Tool] {
        trayToolIDs.compactMap(ToolRegistry.tool(for:))
    }

    var body: some View {
        VStack(spacing: 0) {
            if trayTools.isEmpty {
                EmptyStateView(icon: "switch.2", message: "No enabled tray tools")
                    .frame(height: 160)
            } else {
                TrayTabStrip(tools: trayTools, selected: tabSelection)
                    .padding(TrayPopoverLayout.tabGroupInset)
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
                    .padding(.horizontal, TrayPopoverLayout.horizontalInset)
                    .padding(.vertical, TrayPopoverLayout.tabGroupOuterInset)

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
        .frame(width: TrayPopoverLayout.width)
        .background {
            Color.black
                .opacity(colorScheme == .dark ? 0.2 : 0.04)
                .ignoresSafeArea()
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: trayToolIDs) { normalizeSelection() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let current = Self.combinedTrayToolIDs()
            if current != trayToolIDs { trayToolIDs = current }
        }
    }

    private func normalizeSelection() {
        if let normalized = TrayPopoverLayout.normalizedSelection(
            selectedTab,
            availableIDs: trayToolIDs
        ), normalized != selectedTab {
            selectedTab = normalized
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
                withAnimation(.easeInOut(duration: TrayPopoverLayout.tabTransitionDuration)) {
                    selectedTab = nextTab
                }
            }
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "rclone":
            TrayToolTab(toolID: selectedTab) { RSyncTraySummary() }
        case "awake":
            TrayToolTab(toolID: selectedTab) { AwakeTraySummary() }
        default:
            if let tool = ToolRegistry.tool(for: selectedTab) {
                TrayToolTab(toolID: tool.id) { QuickToolTraySummary(tool: tool) }
            } else {
                EmptyStateView(icon: "wrench.adjustable", message: "No tray view")
                    .frame(height: 160)
            }
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

private struct TrayToolTab<Summary: View>: View {
    let toolID: String
    @ViewBuilder let summary: Summary

    @State private var contentHeight: CGFloat = TrayPopoverLayout.minimumBodyHeight

    private var maximumHeight: CGFloat {
        TrayPopoverLayout.maximumBodyHeight(
            screenHeight: NSScreen.main?.visibleFrame.height ?? 900
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                summary

                QuietDivider()

                ToolSettingsContent(toolID: toolID)
                    .environment(\.compactSettingsLayout, true)
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
}

private struct QuickToolTraySummary: View {
    let tool: any Tool

    private var menuBarTool: IndividualMenuBarTool? {
        IndividualMenuBarTool(rawValue: tool.id)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let action = menuBarTool?.quickAction {
                TrayActionButton(title: menuBarTool?.actionTitle ?? tool.name, isPrimary: true, toolID: tool.id) {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: action))
                }
            }
            TrayActionButton(title: "Open", isPrimary: menuBarTool?.quickAction == nil, toolID: tool.id) {
                ToolActionRouter.shared.open(toolID: tool.id)
            }
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.top, TrayPopoverLayout.bodyTopInset)
        .padding(.bottom, TrayPopoverLayout.rowSpacing)
    }
}

private struct AwakeTraySummary: View {
    @State private var service = AwakeService.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: TrayPopoverLayout.rowSpacing) {
            HStack(spacing: 8) {
                Circle()
                    .fill(service.isActive ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                    .frame(width: 18)
                Text(service.statusText).font(.system(size: 11)).monospacedDigit().lineLimit(1)
                Spacer()
                TrayActionButton(title: "Open", isPrimary: false, toolID: "awake") {
                    openWindow(id: "awake")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .frame(minHeight: 24)

            if let error = service.assertionError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.top, TrayPopoverLayout.bodyTopInset)
        .padding(.bottom, TrayPopoverLayout.rowSpacing)
    }
}

// MARK: - Tab Strip (chrome-style)

private struct TrayTabStrip: View {
    let tools: [any Tool]
    @Binding var selected: String

    var body: some View {
        GeometryReader { geo in
            let count = max(1, tools.count)
            let perTab = TrayPopoverLayout.tabWidth(availableWidth: geo.size.width, count: count)
            let overflow = CGFloat(count) * TrayPopoverLayout.minimumTabWidth
                + CGFloat(count - 1) * TrayPopoverLayout.tabSpacing > geo.size.width

            Group {
                if overflow {
                    ScrollView(.horizontal) {
                        strip(perTab: TrayPopoverLayout.minimumTabWidth)
                    }
                    .thinScrollIndicators()
                } else {
                    strip(perTab: perTab)
                }
            }
        }
        .frame(height: TrayPopoverLayout.tabHeight)
    }

    private func strip(perTab: CGFloat) -> some View {
        HStack(spacing: TrayPopoverLayout.tabSpacing) {
            ForEach(tools, id: \.id) { tool in
                TrayTabItem(
                    tool: tool,
                    width: perTab,
                    showsLabel: TrayPopoverLayout.showsTabLabels(count: tools.count),
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
            .frame(width: width, height: TrayPopoverLayout.tabHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrayTabButtonStyle(isSelected: isSelected, isHovering: isHovering))
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(tool.name)
        .onHover { isHovering = $0 }
        .help(tool.name)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

struct TrayTabButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovering: Bool

    static func backgroundOpacity(
        isSelected: Bool,
        isHovering: Bool,
        isPressed: Bool
    ) -> Double {
        if isSelected { return 1 }
        return UtilityInteractionButtonStyle.highlightOpacity(
            isEnabled: true,
            isHovering: isHovering,
            isPressed: isPressed
        )
    }

    static func interactionOpacity(
        isSelected: Bool,
        isHovering: Bool,
        isPressed: Bool
    ) -> Double {
        guard isSelected else { return 0 }
        if isPressed { return 0.18 }
        return isHovering ? 0.1 : 0
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? Color(nsColor: .controlAccentColor)
                            : Color.primary.opacity(opacity(configuration))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(interactionOpacity(configuration)))
            )
    }

    private func opacity(_ configuration: Configuration) -> Double {
        Self.backgroundOpacity(
            isSelected: isSelected,
            isHovering: isHovering,
            isPressed: configuration.isPressed
        )
    }

    private func interactionOpacity(_ configuration: Configuration) -> Double {
        Self.interactionOpacity(
            isSelected: isSelected,
            isHovering: isHovering,
            isPressed: configuration.isPressed
        )
    }
}

// MARK: - RSync Tray Tab

private struct RSyncTraySummary: View {
    @State private var manager = RcloneJobManager.shared
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TransferRecord.createdAt, order: .reverse) private var records: [TransferRecord]

    private var recentRecords: [TransferRecord] {
        Array(records.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusRow

            Group {
                if !manager.isDaemonRunning {
                    engineOffState
                } else if manager.activeJobs.isEmpty {
                    idleState
                } else {
                    activeTransfers
                }
            }
            .padding(.top, TrayPopoverLayout.rowSpacing)
        }
        .padding(.horizontal, TrayPopoverLayout.horizontalInset)
        .padding(.top, TrayPopoverLayout.bodyTopInset)
        .padding(.bottom, TrayPopoverLayout.rowSpacing)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if !manager.daemonIsHealthy {
                TrayRetryButton {
                    Task { await manager.start() }
                }
            }

            Text(manager.isDaemonRunning ? manager.daemonStatusText : "Engine not running")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            TrayActionButton(title: "Open Cloud Sync", isPrimary: false, toolID: "rclone") {
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
    let isPrimary: Bool
    var toolID: String = ""
    let action: () -> Void

    private var tint: NSColor {
        if !toolID.isEmpty, let color = ToolIconColor.major(asset: ToolRegistry.tool(for: toolID)?.logoAsset ?? "") { return color }
        return .controlAccentColor
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPrimary ? ToolIconColor.label(on: tint) : .primary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 26)
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
        .focusEffectDisabled()
        .background(
            isPrimary ? Color(nsColor: tint) : Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 6)
        )
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

