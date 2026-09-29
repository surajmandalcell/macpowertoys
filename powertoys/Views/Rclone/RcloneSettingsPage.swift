import OnePlusUI
import SwiftUI

struct RcloneSettingsPage: View {
    var showsHeader = true

    var body: some View {
        Group {
            if showsHeader {
                OnePlusPage {
                    OnePlusPageHeader(title: "Settings", subtitle: "Cloud Sync engine and transfer preferences")
                } content: { RcloneSettingsView() }
            } else {
                RcloneSettingsView()
            }
        }
        .accessibilityIdentifier("rclone.settings")
    }
}
