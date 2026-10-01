import SwiftUI
import OnePlusUI

/// The host owns the page, scrolling, and gutters. Each tool supplies only cards.
struct ToolSettingsContent: View {
    let toolID: String
    var changed: (() -> Void)? = nil
    @State private var preferenceObserver: ToolSettingsPreferenceObserver?
    @AppStorage("systemCare.defaultMode") private var systemCareMode = SystemCareMode.quick.rawValue

    var body: some View {
        settingsContent
            .onChange(of: toolID, initial: true) { _, _ in
                preferenceObserver?.stop()
                guard let changed else { preferenceObserver = nil; return }
                let keys = Set(SettingsRegistry.entries.filter {
                    $0.toolID == toolID || (toolID == "rclone" && $0.key == "app.showTray")
                }.map(\.key))
                preferenceObserver = ToolSettingsPreferenceObserver(keys: keys, changed: changed)
            }
            .onDisappear {
                preferenceObserver?.stop()
                preferenceObserver = nil
            }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch toolID {
        case "rclone": RcloneSettingsView()
        case "ruler": RulerLauncherSettingsView()
        case "awake": AwakeSettingsView()
        case "color-picker": ColorPickerSettingsView()
        case "text-extractor": TextExtractorSettingsView()
        case "nettoys": NetToysSettingsView()
        case "switch": SwitchSettingsContent()
        case "mac-tweaks": MacTweaksSettingsContent()
        case "input-devices": InputDevicesSettingsContent()
        case "system-monitor": SystemMonitorSettingsContent()
        case "system-care":
            SystemCareSettingsCards(mode: Binding(
                get: { SystemCareMode(rawValue: systemCareMode) ?? .quick },
                set: { systemCareMode = $0.rawValue }
            ))
        case "portman": PortmanSettingsView()
        case "disk-explorer": DiskExplorerSettingsView()
        case "logs": LogsSettingsView()
        default: OnePlusEmptyState("No settings available", systemImage: "slider.horizontal.3")
        }
    }
}

struct RulerLauncherSettingsView: View {
    var body: some View {
        HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusCardHeader("Ruler", systemImage: ToolGlyph.ruler.symbol, iconRotation: ToolGlyph.ruler.rotation)
                OnePlusSettingRow("Active rulers", separator: false) {
                    Button("Open Ruler Settings") {
                        ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerSettings))
                    }.buttonStyle(OnePlusButtonStyle())
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Defaults", systemImage: "slider.horizontal.3")
                OnePlusSettingRow("New rulers", separator: false) {
                    Button("Open Defaults") { AppDelegate.current?.openPreferences(self) }
                        .buttonStyle(OnePlusButtonStyle())
                }
            }
        }
    }
}
