import OnePlusUI
import SwiftUI

struct TraySettingSection: View {
    @AppStorage("app.showTray") private var showTray = true
    var body: some View {
        OnePlusCard {
            OnePlusCardHeader("Menu bar")
            OnePlusSettingRow("Show MacPowerToys in the menu bar", separator: false) {
                Toggle("Show MacPowerToys in the menu bar", isOn: $showTray)
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
        }
    }
}
