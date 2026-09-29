import OnePlusUI
import SwiftUI

struct RcloneSettingsPage: View {
    var showsHeader = true
    @AppStorage("tool.rclone.startAtLaunch") private var startAtLaunch = false
    @AppStorage("app.showTray") private var showTray = true

    var body: some View {
        Group {
            if showsHeader {
                OnePlusPage {
                    OnePlusPageHeader(title: "Settings", subtitle: "Cloud Sync engine and transfer preferences")
                } content: { settingsContent }
            } else {
                VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) { settingsContent }
            }
        }
        .onChange(of: startAtLaunch) { _, enabled in
            Task { await RcloneJobManager.shared.backgroundPreferenceDidChange(enabled: enabled) }
        }
        .accessibilityIdentifier("rclone.settings")
    }

    @ViewBuilder private var settingsContent: some View {
        OnePlusSectionTitle("Sync engine")
        OnePlusCard {
            OnePlusSettingRow("Start at launch", caption: "Keep the sync engine ready after sign-in.") {
                Toggle("Start at launch", isOn: $startAtLaunch).labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("Show in menu bar", caption: "Show MacPowerToys transfer status in the menu bar.") {
                Toggle("Show in menu bar", isOn: $showTray).labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("Retry interrupted transfers", caption: "Queue unfinished transfers after the engine starts.", separator: false) {
                Toggle("Retry interrupted transfers", isOn: .constant(true))
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
                    .disabled(true)
                    .help("Cloud Sync always protects and resumes interrupted transfers.")
            }
        }

        RcloneSettingsView()
    }
}
