//
//  DemoMacTweaks.swift
//  powertoys
//

#if MPT_DEMO
import Foundation

@MainActor
enum DemoMacTweaks {
    static let didChange = Notification.Name("MPTDemoMacTweaksDidChange")

    private static let revealDelay = TweakPreferences.fields(for: "dock.reveal-delay")[0]
    private static let animationDuration = TweakPreferences.fields(for: "dock.animation-duration")[0]

    static func seed() {
        TweakPreferenceStore.demoSelections = [
            revealDelay.identity: revealDelay.defaultSelection ?? -1,
            animationDuration.identity: animationDuration.defaultSelection ?? -1,
        ]
    }

    static var scene: DemoScene {
        DemoScene(
            open: { ToolActionRouter.shared.open(toolID: "mac-tweaks", activateApp: false) },
            steps: [
                DemoStep(at: 1.5) {
                    try? TweakPreferenceStore.shared.apply([revealDelay], selections: [revealDelay.identity: 0])
                    NotificationCenter.default.post(name: didChange, object: nil)
                },
            ],
            tail: 3.0
        )
    }
}
#endif
