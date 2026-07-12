//
//  TraySettingSection.swift
//  powertoys
//

import SwiftUI

struct TraySettingSection: View {
    @AppStorage("app.showTray") private var showTray = true

    var body: some View {
        Section {
            Toggle("Show PowerToys in the menu bar", isOn: $showTray)
        } header: {
            Text("Tray")
        } footer: {
            Text("The tray icon gives quick access to PowerToys even when all windows are closed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
