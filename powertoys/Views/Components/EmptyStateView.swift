import OnePlusUI
import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let message: String
    var body: some View { OnePlusEmptyState(message, systemImage: icon) }
}
