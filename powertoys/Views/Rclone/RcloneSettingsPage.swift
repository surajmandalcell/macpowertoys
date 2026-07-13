//
//  RcloneSettingsPage.swift
//  powertoys
//

import SwiftUI

struct RcloneSettingsPage: View {
    @AppStorage("tool.rclone.startAtLaunch") private var startAtLaunch = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section {
                    Toggle("Start Cloud Sync at launch", isOn: $startAtLaunch)
                } header: {
                    Text("General")
                } footer: {
                    Text("Opens Cloud Sync and starts the transfer engine when MacPowerToys launches, so transfers show up in the tray right away.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                TraySettingSection()
                RcloneSettingsView()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
