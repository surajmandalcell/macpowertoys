//
//  ToolSettingsContent.swift
//  powertoys
//

import SwiftUI
import OnePlusUI

struct ToolSettingsContent: View {
    let toolID: String
    @State private var isReady: Bool
    @AppStorage("systemCare.defaultMode") private var systemCareMode = SystemCareMode.quick.rawValue

    init(toolID: String) {
        self.toolID = toolID
        _isReady = State(initialValue: !Self.defersInitialLoad(for: toolID))
    }

    static func defersInitialLoad(for toolID: String) -> Bool {
        toolID == "nettoys" || toolID == "system-monitor"
    }

    var body: some View {
        Group {
            if isReady {
                settingsContent
            } else {
                ProgressView("Loading settings…")
                    .controlSize(.small)
                    .onePlusText(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("tool.\(toolID).settings-loading")
            }
        }
        .buttonStyle(OnePlusButtonStyle())
        .toggleStyle(OnePlusSwitchStyle())
        .task(id: toolID) {
            guard Self.defersInitialLoad(for: toolID) else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            isReady = true
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch toolID {
        case "rclone":
            OnePlusPage(header: { EmptyView() }) { RcloneSettingsPage(showsHeader: false) }
        case "ruler":
            RulerLauncherSettingsView()
        case "awake":
            OnePlusPage(header: { EmptyView() }) { AwakePreferencesView() }
        case "color-picker":
            ColorPickerSettingsView()
        case "text-extractor":
            TextExtractorSettingsView()
        case "nettoys":
            OnePlusPage(header: { EmptyView() }) { NetToysSettingsView() }
        case "switch":
            SwitchLauncherSettingsView()
        case "mac-tweaks":
            VStack(alignment: .leading, spacing: 12) {
                Text("Mic Lock and other small Mac settings live in the Mac Tweaks window.")
                    .onePlusText(.row)
                Button("Open Mac Tweaks") { ToolActionRouter.shared.open(toolID: "mac-tweaks") }
                    .controlSize(.small)
                Spacer()
            }
            .settingsPageInsets(horizontal: OnePlusMetrics.gutter, top: OnePlusMetrics.contentTop, bottom: OnePlusMetrics.gutter)
        case "input-devices":
            InputDevicesSettingsView()
        case "system-monitor":
            OnePlusPage(header: { EmptyView() }) { SystemMonitorMenuSettingsView(showsContainerScroll: false) }
        case "system-care":
            OnePlusPage(header: { EmptyView() }) {
                SystemCareSettingsContent(mode: Binding(
                    get: { SystemCareMode(rawValue: systemCareMode) ?? .quick },
                    set: { systemCareMode = $0.rawValue }
                ))
            }
        case "portman":
            OnePlusPage(header: { EmptyView() }) { PortmanSettingsView() }
        case "disk-explorer":
            OnePlusPage(header: { EmptyView() }) { DiskExplorerSettingsView() }
        case "logs":
            LogsSettingsView()
        default:
            EmptyStateView(icon: "slider.horizontal.3", message: "No settings available")
        }
    }
}

private struct SwitchLauncherSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNTS").utilitySectionHeader()
            Text("Manage accounts, usage, and recovery in the Switch applet. The standalone Switch app is optional and shares the same accounts.")
                .onePlusText(.row)
                .utilitySectionCard()
            Spacer()
        }
        .settingsPageInsets(horizontal: OnePlusMetrics.gutter, top: OnePlusMetrics.contentTop, bottom: OnePlusMetrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RulerLauncherSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RULER SETTINGS").utilitySectionHeader()

            VStack(alignment: .leading, spacing: 12) {
                Text("Ruler settings stay in the native panels used by the Ruler window.")
                    .onePlusText(.row)

                HStack(spacing: 8) {
                    Button("Open Ruler Settings") {
                        ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
                    }
                    Button("Open Defaults") {
                        AppDelegate.current?.openPreferences(self)
                    }
                }
                .controlSize(.small)
            }
            .utilitySectionCard()

            Spacer()
        }
        .settingsPageInsets(horizontal: OnePlusMetrics.gutter, top: OnePlusMetrics.contentTop, bottom: OnePlusMetrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    func settingsPageInsets(
        horizontal: CGFloat,
        top: CGFloat = 0,
        bottom: CGFloat
    ) -> some View {
        modifier(SettingsPageInsets(horizontal: horizontal, top: top, bottom: bottom))
    }
}

private struct SettingsPageInsets: ViewModifier {
    let horizontal: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.top, top)
            .padding(.bottom, bottom)
    }
}
