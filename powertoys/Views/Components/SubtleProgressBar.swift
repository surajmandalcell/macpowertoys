import OnePlusUI
import SwiftUI

struct SubtleProgressBar: View {
    let progress: Double
    var body: some View { OnePlusUsageBar(value: progress) }
}
