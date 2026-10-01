import SwiftUI

private struct OnePlusTimingWindowKey: EnvironmentKey { static let defaultValue = "" }

extension EnvironmentValues {
    var onePlusTimingWindow: String {
        get { self[OnePlusTimingWindowKey.self] }
        set { self[OnePlusTimingWindowKey.self] = newValue }
    }
}

public extension View {
    // ponytail: display submission covers layout; add readiness signals if captured content fills late.
    func onePlusWindowTimings(_ tool: String) -> some View {
        environment(\.onePlusTimingWindow, "page.\(tool)")
            .onePlusPanelTimings(panel: "window.\(tool)", tab: nil)
            .onePlusPanelTimings(panel: "page.\(tool)", tab: nil)
    }
}
