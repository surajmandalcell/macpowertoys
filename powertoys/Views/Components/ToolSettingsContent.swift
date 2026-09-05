//
//  ToolSettingsContent.swift
//  powertoys
//

import SwiftUI

struct ToolSettingsContent: View {
    let toolID: String

    @Environment(\.compactSettingsLayout) private var compact

    @ViewBuilder
    var body: some View {
        switch toolID {
        case "cc-history":
            CCHistorySettingsPage(showsHeader: false)
        case "rclone":
            RcloneSettingsPage(showsHeader: false)
        case "ruler":
            RulerLauncherSettingsView()
        case "awake":
            AwakeSettingsView(showsStatus: !compact)
                .settingsPageInsets(horizontal: 24, top: 24, bottom: 24)
                .settingsScrollContainer()
        case "color-picker":
            ColorPickerSettingsView()
        case "text-extractor":
            TextExtractorSettingsView()
        case "nettoys":
            NetToysSettingsView()
        case "input-devices":
            InputDevicesSettingsView()
        case "system-monitor":
            SystemMonitorMenuSettingsView()
        case "logs":
            LogsSettingsView()
        default:
            EmptyStateView(icon: "slider.horizontal.3", message: "No settings available")
        }
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

// MARK: - Compact (tray) layout

private struct CompactSettingsLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactSettingsLayout: Bool {
        get { self[CompactSettingsLayoutKey.self] }
        set { self[CompactSettingsLayoutKey.self] = newValue }
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
    @Environment(\.compactSettingsLayout) private var compact

    @ViewBuilder
    func body(content: Content) -> some View {
        if compact {
            content
        } else {
            ScrollView { content }
                .thinScrollIndicators()
        }
    }
}

private struct SettingsPageInsets: ViewModifier {
    @Environment(\.compactSettingsLayout) private var compact

    let horizontal: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, compact ? TrayPopoverLayout.horizontalInset : horizontal)
            .padding(.top, compact ? TrayPopoverLayout.settingsTopInset : top)
            .padding(.bottom, compact ? TrayPopoverLayout.bodyBottomInset : bottom)
    }
}
