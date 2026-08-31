//
//  RcloneSettingsPage.swift
//  powertoys
//

import SwiftUI

struct RcloneSettingsPage: View {
    var showsHeader = true
    @AppStorage("tool.rclone.startAtLaunch") private var startAtLaunch = false

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                QuietDivider()
            }

            Form {
                Section {
                    Toggle("Start sync engine at launch", isOn: $startAtLaunch)
                } header: {
                    Text("General")
                } footer: {
                    Text("Starts the transfer engine in the background when MacPowerToys launches. The Cloud Sync window stays closed until you open it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                TraySettingSection()
                RcloneSettingsView()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .thinScrollIndicators()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: startAtLaunch) { _, enabled in
            Task { await RcloneJobManager.shared.backgroundPreferenceDidChange(enabled: enabled) }
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .padding(.top, 12)
    }
}
