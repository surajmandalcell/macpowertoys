//
//  DemoColorPicker.swift
//  powertoys
//

#if MPT_DEMO
import Foundation

@MainActor
enum DemoColorPicker {
    private static func sample(_ hex: UInt32, minutesAgo: Double) -> ColorSample {
        ColorSample(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1,
            createdAt: Date(timeIntervalSinceNow: -minutesAgo * 60)
        )
    }

    static func seed() {
        ColorPickerService.shared.demoSeed([
            sample(0xF2B544, minutesAgo: 4),
            sample(0x2F7D6D, minutesAgo: 11),
            sample(0x4F5BD5, minutesAgo: 26),
            sample(0x1F2A37, minutesAgo: 48),
            sample(0xE9E4DA, minutesAgo: 95),
        ])
    }

    static var scene: DemoScene {
        DemoScene(
            open: { ToolActionRouter.shared.open(toolID: "color-picker", activateApp: false) },
            steps: [
                DemoStep(at: 0.8) { ColorPickerService.shared.demoSetPicking(true) },
                DemoStep(at: 3.2) {
                    ColorPickerService.shared.demoSetPicking(false)
                    ColorPickerService.shared.add(sample(0xE8563F, minutesAgo: 0))
                },
            ],
            tail: 2.5
        )
    }
}
#endif
