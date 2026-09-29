import OnePlusUI
import SwiftUI

struct FloatingSettingsButton: View {
    let isActive: Bool
    let helpText: String
    let action: () -> Void
    var body: some View { OnePlusFloatingSettingsButton(isActive: isActive, help: helpText, action: action) }
}
