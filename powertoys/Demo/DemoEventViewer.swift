//
//  DemoEventViewer.swift
//  powertoys
//

#if MPT_DEMO
import Foundation

@MainActor
enum DemoEventViewer {
    private struct Line {
        let minutesAgo: Double
        let level: LogLevel
        let source: String
        let message: String
    }

    private static let lines = [
        Line(minutesAgo: 38, level: .info, source: "App", message: "MacPowerToys 1.9.4 started"),
        Line(minutesAgo: 37, level: .info, source: "Fan", message: "Fan helper connected"),
        Line(minutesAgo: 35, level: .info, source: "Portman", message: "Watching ports 3000–9999"),
        Line(minutesAgo: 31, level: .info, source: "RSync UI", message: "Cloud Sync started: Photos → Google Drive"),
        Line(minutesAgo: 27, level: .info, source: "Awake", message: "Keeping this Mac awake for 1 hour"),
        Line(minutesAgo: 22, level: .warning, source: "RSync UI", message: "Retrying 2 files after a network timeout"),
        Line(minutesAgo: 19, level: .info, source: "Color Picker", message: "Copied #3A7BF2 as HEX"),
        Line(minutesAgo: 15, level: .info, source: "RSync UI", message: "Cloud Sync finished: 1,284 files, 2.1 GB"),
        Line(minutesAgo: 11, level: .info, source: "Text Extractor", message: "Recognized 14 lines in 0.31 s"),
        Line(minutesAgo: 8, level: .error, source: "Input Devices", message: "Could not read the Magic Mouse battery level"),
        Line(minutesAgo: 5, level: .info, source: "Portman", message: "Forward build-box:5432 → localhost:5432 is up"),
        Line(minutesAgo: 2, level: .debug, source: "Fan", message: "Fan 1 at 2,140 rpm, CPU 61 °C"),
    ]

    private static let warningAt = 1.6
    private static let warning = "web on :3000 uses 781 MB, up 639 MB"

    static func seed() {
        let now = Date()
        LogManager.shared.demoReplace(with: lines.map { line in
            LogEntryData(id: UUID(), timestamp: now.addingTimeInterval(-line.minutesAgo * 60),
                         level: line.level, source: line.source, message: line.message)
        })
    }

    static var scene: DemoScene {
        DemoScene(
            open: {
                seed()
                ToolActionRouter.shared.open(toolID: "logs", activateApp: false)
            },
            steps: [DemoStep(at: warningAt) { LogManager.shared.warning(warning, source: "Portman") }]
        )
    }
}
#endif
