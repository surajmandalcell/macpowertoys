import OnePlusUI
import SwiftUI

struct RcloneSettingsPage: View {
    var body: some View {
        OnePlusLinearPaneBody { RcloneSettingsView() }
            .accessibilityIdentifier("rclone.settings")
    }
}
