//
//  DemoDirector.swift
//  powertoys
//
//  Plays one scripted clip per tool for the site capture. Launch the demo build with
//  `-MPTDemoScene <name>` (names in `scenes`), optional `-MPTDemoLeadIn <seconds>` (default 1.5)
//  and `-MPTDemoQuitAfter YES`. The director writes `scene.json` into the demo data folder with the
//  scene's window numbers, so the capture tool records that one window.
//

#if MPT_DEMO
import AppKit

struct DemoStep {
    /// Seconds after the lead-in ends.
    let at: Double
    let run: @MainActor () -> Void
}

struct DemoScene {
    /// Opens the tool's window or panel without activating the app.
    let open: @MainActor () -> Void
    let steps: [DemoStep]
    /// Seconds the clip keeps rolling after the last step.
    var tail: Double = 1.5
}

@MainActor
enum DemoDirector {
    static let scenes: [String: () -> DemoScene] = [
        "fan": { DemoFan.scene },
        "menu-panel": { DemoMenuPanel.scene },
        "awake": { DemoAwake.scene },
        "portman": { DemoPortman.scene },
        "portman-detail": { DemoPortman.detailScene },
        "portman-hosts": { DemoPortman.hostsScene },
        "portman-mode": { DemoPortman.modeScene },
        "portman-menu": { DemoPortman.menuScene },
        "portman-scan": { DemoPortman.scanScene },
        "portman-forward": { DemoPortman.jobSwitchScene },
        "portman-empty": { DemoPortman.emptyScene },
        "portman-add": { DemoPortman.addScene },
        "portman-add-error": { DemoPortman.addErrorScene },
        "portman-pick": { DemoPortman.pickScene },
        "event-viewer": { DemoEventViewer.scene },
        "rsync": { DemoRSync.scene },
        "rsync-menu": { DemoRSync.menuScene },
        "mac-tweaks": { DemoMacTweaks.scene },
        "color-picker": { DemoColorPicker.scene },
        "text-extractor": { DemoTextExtractor.scene },
        "ruler": { DemoRuler.scene },
        "ruler-design": { DemoRuler.designScene },
        "input-devices": { DemoInputDevices.scene },
    ]

    /// Fills every service with the site's fake values before any window opens.
    static func prepare() {
        if DemoStill.directory != nil { DemoStill.forceActiveLook() }
        DemoFan.seed()
        DemoMenuPanel.seed()
        DemoAwake.seed()
        DemoPortman.seed()
        DemoEventViewer.seed()
        DemoRSync.seed()
        DemoMacTweaks.seed()
        DemoColorPicker.seed()
        DemoTextExtractor.seed()
        DemoRuler.seed()
        DemoInputDevices.seed()
    }

    static func playRequestedScene() {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: "MPTDemoScene") else { return }
        guard let make = scenes[name] else {
            NSLog("MacPowerToys Demo: unknown scene %@. Known: %@", name, scenes.keys.sorted().joined(separator: ", "))
            return
        }
        let leadIn = defaults.object(forKey: "MPTDemoLeadIn") == nil ? 1.5 : defaults.double(forKey: "MPTDemoLeadIn")
        let quitAfter = defaults.bool(forKey: "MPTDemoQuitAfter")
        let scene = make()
        // Visible ones only: a panel built at launch and shown by the scene must still count.
        let windowsBefore = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        scene.open()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            let windows = NSApp.windows.filter { $0.isVisible && !windowsBefore.contains($0.windowNumber) }
            writeSceneFile(name: name, windows: windows, leadIn: leadIn)
            try? await Task.sleep(for: .seconds(max(0, leadIn - 0.6)))
            var elapsed = 0.0
            let stillAt = DemoStill.stopAt
            for step in scene.steps.sorted(by: { $0.at < $1.at }) {
                if let stillAt, step.at > stillAt { break }
                try? await Task.sleep(for: .seconds(max(0, step.at - elapsed)))
                elapsed = max(elapsed, step.at)
                step.run()
            }
            if let directory = DemoStill.directory {
                // Lets SwiftUI and the services settle so no half-drawn frame is drawn.
                try? await Task.sleep(for: .seconds(max(0, (stillAt ?? elapsed) - elapsed) + 1))
                DemoStill.write(scene: name, windows: DemoStill.sceneWindows(excluding: windowsBefore), to: directory)
                markSceneDone()
                // Keeps the windows up for a one-shot reference screenshot, then quits.
                try? await Task.sleep(for: .seconds(4))
                exit(0)
            }
            // The recording starts about 1 s after launch; this keeps every site clip at 6 s or more.
            try? await Task.sleep(for: .seconds(max(scene.tail, 7.5 - leadIn - elapsed)))
            markSceneDone()
            // The demo has nothing to save, and the normal quit path waits on real-app shutdown steps.
            // The capture tool polls scene.json, so the window stays up a moment after done:true.
            if quitAfter { try? await Task.sleep(for: .seconds(1)); exit(0) }
        }
    }

    private static var sceneFileURL: URL { AppDataLocation.directory.appendingPathComponent("scene.json") }

    private static func writeSceneFile(name: String, windows: [NSWindow], leadIn: Double) {
        let object: [String: Any] = [
            "scene": name,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "leadIn": leadIn,
            "started": Date().timeIntervalSince1970,
            "done": false,
            "windows": windows.map { ["number": $0.windowNumber, "title": $0.title,
                                      "width": $0.frame.width, "height": $0.frame.height] },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: sceneFileURL, options: .atomic)
        }
    }

    private static func markSceneDone() {
        guard let data = try? Data(contentsOf: sceneFileURL),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        object["done"] = true
        if let updated = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? updated.write(to: sceneFileURL, options: .atomic)
        }
    }
}
#endif
