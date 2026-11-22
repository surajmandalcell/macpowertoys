//
//  DemoAwake.swift
//  powertoys
//
//  Awake in the demo build: AwakeService shows the active state with a fake assertion ID and never
//  creates a real power assertion.
//

#if MPT_DEMO
import Foundation

@MainActor
enum DemoAwake {
    static func seed() {
        AwakeService.shared.setMode(.passive)
    }

    /// The Awake page opens off, then Awake turns on for 1 hour.
    static var scene: DemoScene {
        DemoScene(open: { ToolActionRouter.shared.openMainPage(toolID: "awake", activateApp: false) },
                  steps: [DemoStep(at: 1.6) { AwakeService.shared.setMode(.timed, duration: 3_600) }],
                  tail: 3)
    }
}
#endif
