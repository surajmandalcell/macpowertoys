import OnePlusUI
import SwiftUI

struct RcloneSettingsPage: View {
    var body: some View {
        OnePlusLinearEditorialBody { RcloneSettingsView() }
            .accessibilityIdentifier("rclone.settings")
    }
}
