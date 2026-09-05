//
//  TraySettingSection.swift
//  powertoys
//

import SwiftUI

struct TraySettingSection: View {
    @AppStorage("app.showTray") private var showTray = true

    var body: some View {
        Section {
            Toggle("Show MacPowerToys in the menu bar", isOn: $showTray)
        } header: {
            Text("Tray")
        }
    }
}
