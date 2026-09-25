//
//  ToolSettingsContent.swift
//  powertoys
//

import SwiftUI

struct ToolSettingsContent: View {
    let toolID: String
    @State private var isReady: Bool

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("tool.\(toolID).settings-loading")
            }
        }
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
            RcloneSettingsPage(showsHeader: false)
        case "ruler":
            RulerLauncherSettingsView()
        case "awake":
            AwakeSettingsView()
                .settingsPageInsets(horizontal: 24, top: 24, bottom: 24)
                .settingsScrollContainer()
        case "color-picker":
            ColorPickerSettingsView()
        case "text-extractor":
            TextExtractorSettingsView()
        case "nettoys":
            NetToysSettingsView()
        case "switch":
            SwitchLauncherSettingsView()
        case "input-devices":
            InputDevicesSettingsView()
        case "system-monitor":
            SystemMonitorMenuSettingsView()
        case "disk-explorer":
            DiskExplorerSettingsView()
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
            Text("Switch and MacPowerToys use the same account store. Open Switch to manage accounts, usage, and recovery.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .utilitySectionCard()
            Spacer()
        }
        .settingsPageInsets(horizontal: 24, top: 24, bottom: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RulerLauncherSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RULER SETTINGS").utilitySectionHeader()

            VStack(alignment: .leading, spacing: 12) {
                Text("Ruler settings stay in the native panels used by the Ruler window.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

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
        .settingsPageInsets(horizontal: 24, top: 24, bottom: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    func settingsScrollContainer() -> some View {
        modifier(SettingsScrollContainer())
    }

    func settingsPageInsets(
        horizontal: CGFloat,
        top: CGFloat = 0,
        bottom: CGFloat
    ) -> some View {
        modifier(SettingsPageInsets(horizontal: horizontal, top: top, bottom: bottom))
    }
}

private struct SettingsScrollContainer: ViewModifier {
    func body(content: Content) -> some View {
        ScrollView { content }
            .thinScrollIndicators()
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
