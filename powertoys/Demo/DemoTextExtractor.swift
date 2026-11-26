//
//  DemoTextExtractor.swift
//  powertoys
//

#if MPT_DEMO
import Foundation

@MainActor
enum DemoTextExtractor {
    static func seed() {
        func entry(_ text: String, minutesAgo: Double) -> TextExtraction {
            TextExtraction(text: text, createdAt: Date(timeIntervalSinceNow: -minutesAgo * 60))
        }
        TextExtractorService.shared.demoSeed([
            entry("https://storefront.dev/checkout?step=shipping", minutesAgo: 6),
            entry("error TS2345: Argument of type 'string' is not assignable to parameter of type 'number'.", minutesAgo: 12),
            entry("Compiled in 8.4s\nGenerated 24 pages", minutesAgo: 19),
            entry("Flight UA 2417 · SFO → JFK · Seat 14C · Boards 7:45 AM", minutesAgo: 34),
            entry("Invoice INV-2048 · Due Dec 4 · $1,240.00", minutesAgo: 52),
            entry("git rebase -i HEAD~3", minutesAgo: 71),
            entry("Tracking number 9400 1112 0206 3374 5820 16", minutesAgo: 96),
            entry("Meeting moved to Thursday 3:30 PM, room Orion.", minutesAgo: 140),
            entry("https://docs.storefront.dev/api/orders#refunds", minutesAgo: 205),
        ])
    }

    static var scene: DemoScene {
        DemoScene(
            open: { ToolActionRouter.shared.open(toolID: "text-extractor", activateApp: false) },
            steps: [
                DemoStep(at: 2.6) {
                    TextExtractorService.shared.demoCapture("ssh -L 5432:localhost:5432 build-box")
                },
            ],
            tail: 3
        )
    }

    static var deniedScene: DemoScene {
        DemoScene(
            open: { ToolActionRouter.shared.open(toolID: "text-extractor", activateApp: false) },
            steps: [DemoStep(at: 0.5) { TextExtractorService.shared.demoDeny() }],
            tail: 3
        )
    }
}
#endif
