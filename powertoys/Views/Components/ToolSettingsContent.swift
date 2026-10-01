import SwiftUI
import OnePlusUI

/// The host owns the page, scrolling, and gutters. Each tool supplies only cards.
struct ToolSettingsContent: View {
    let toolID: String
    @AppStorage("systemCare.defaultMode") private var systemCareMode = SystemCareMode.quick.rawValue

    @ViewBuilder
    var body: some View {
        switch toolID {
        case "rclone": RcloneSettingsView()
        case "ruler": RulerLauncherSettingsView()
        case "awake": AwakeSettingsView()
        case "color-picker": ColorPickerSettingsView()
        case "text-extractor": TextExtractorSettingsView()
        case "nettoys": NetToysSettingsView()
        case "switch": SwitchSettingsContent(showsEnableControl: false)
        case "mac-tweaks": MacTweaksSettingsContent()
        case "input-devices": InputDevicesSettingsContent()
        case "system-monitor": SystemMonitorSettingsContent()
        case "system-care":
            SystemCareSettingsCards(mode: Binding(
                get: { SystemCareMode(rawValue: systemCareMode) ?? .quick },
                set: { systemCareMode = $0.rawValue }
            ))
        case "portman": PortmanSettingsView()
        case "disk-explorer": DiskExplorerSettingsView(showsEnableControl: false)
        case "logs": LogsSettingsView()
        default: OnePlusEmptyState("No settings available", systemImage: "slider.horizontal.3")
        }
    }
}

struct RulerLauncherSettingsView: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Button {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
            } label: {
                Label {
                    Text("Open Ruler Settings")
                } icon: {
                    Image(systemName: ToolGlyph.ruler.symbol).rotationEffect(.degrees(ToolGlyph.ruler.rotation))
                }
            }
            .buttonStyle(OnePlusButtonStyle())
            .help("Settings for the active rulers")
            Button("Open Defaults") { AppDelegate.current?.openPreferences(self) }
                .buttonStyle(OnePlusButtonStyle())
                .help("Defaults for new rulers")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!settings.isToolEnabled("ruler") || settings.isToolTransitioning("ruler"))
    }
}
