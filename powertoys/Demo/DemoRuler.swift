//
//  DemoRuler.swift
//  powertoys
//

#if MPT_DEMO
import AppKit

@MainActor
enum DemoRuler {
    private static let target = NSSize(width: 640, height: 460)
    private static let start = NSSize(width: 280, height: 200)
    private static let growSteps = 24
    private static let growDuration = 1.6

    static func seed() {}

    private static func resize(to size: NSSize) {
        AppDelegate.current?.rulerManager.activeController?
            .updateDimensions(horizontalLength: size.width, verticalLength: size.height)
    }

    static var scene: DemoScene {
        let grow = (1...growSteps).map { index in
            let progress = Double(index) / Double(growSteps)
            let eased = 1 - pow(1 - progress, 3)
            let size = NSSize(width: start.width + (target.width - start.width) * eased,
                              height: start.height + (target.height - start.height) * eased)
            return DemoStep(at: 1.0 + growDuration * progress) { resize(to: size) }
        }
        return DemoScene(
            open: {
                ToolActionRouter.shared.open(toolID: "ruler", activateApp: false)
                resize(to: start)
            },
            steps: grow,
            tail: 2.5
        )
    }
}
#endif
