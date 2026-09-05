//
//  RcloneSettingsPage.swift
//  powertoys
//

import SwiftUI

struct RcloneSettingsPage: View {
    var showsHeader = true
    @AppStorage("tool.rclone.startAtLaunch") private var startAtLaunch = false
    @AppStorage("app.showTray") private var showTray = true
    @Environment(\.compactSettingsLayout) private var compact

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                QuietDivider()
            }

            VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
                generalSection
                traySection
                RcloneSettingsView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsPageInsets(horizontal: UtilityLayout.horizontalInset, top: 16, bottom: 20)
            .settingsScrollContainer()
        }
        .background(compact ? Color.clear : Color(nsColor: .windowBackgroundColor))
        .onChange(of: startAtLaunch) { _, enabled in
            Task { await RcloneJobManager.shared.backgroundPreferenceDidChange(enabled: enabled) }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GENERAL").utilitySectionHeader()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Start sync engine at launch")
                    Spacer()
                    Toggle("Start sync engine at launch", isOn: $startAtLaunch)
                        .labelsHidden()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 12))
            .controlSize(.small)
            .utilitySectionCard()
        }
    }

    private var traySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRAY").utilitySectionHeader()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Show MacPowerToys in the menu bar")
                    Spacer()
                    Toggle("Show MacPowerToys in the menu bar", isOn: $showTray)
                        .labelsHidden()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 12))
            .controlSize(.small)
            .utilitySectionCard()
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
