import SwiftUI
import XCTest
@testable import powertoys

final class FocusEffectTests: XCTestCase {
    @MainActor
    func testSharedRootSuppressesDescendantFocusEffects() {
        var focusEffectEnabled = true
        let host = NSHostingView(rootView: FocusEffectProbe { focusEffectEnabled = $0 }
            .utilityMotionPolicy())
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(focusEffectEnabled)
    }
}

private struct FocusEffectProbe: View {
    @Environment(\.isFocusEffectEnabled) private var isFocusEffectEnabled
    let onAppear: (Bool) -> Void

    var body: some View {
        Button("Probe") {}
            .onAppear { onAppear(isFocusEffectEnabled) }
    }
}
