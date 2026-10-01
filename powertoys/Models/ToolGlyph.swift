import SwiftUI

nonisolated enum ToolGlyph: String, CaseIterable {
    case cloudSync = "rclone"
    case logs, ruler, awake
    case colorPicker = "color-picker"
    case textExtractor = "text-extractor"
    case inputDevices = "input-devices"
    case systemCare = "system-care"
    case diskman = "disk-explorer"
    case taskManager = "system-monitor"
    case netToys = "nettoys"
    case portman
    case macTweaks = "mac-tweaks"
    case switchAccounts = "switch"

    var symbol: String {
        switch self {
        case .cloudSync: "cloud"
        case .logs: "terminal"
        case .ruler: "ruler"
        case .awake: "eye"
        case .colorPicker: "eyedropper"
        case .textExtractor: "text.viewfinder"
        case .inputDevices: "computermouse"
        case .systemCare: "tray.and.arrow.up"
        case .diskman: "opticaldisc"
        case .taskManager: "waveform.path.ecg.rectangle"
        case .netToys: "point.3.connected.trianglepath.dotted"
        case .portman: "PortmanStatusGlyph"
        case .macTweaks: "slider.vertical.3"
        case .switchAccounts: "stop.circle"
        }
    }

    @MainActor var assetImage: Image? {
        guard self == .portman, let image = NSImage(named: symbol) else { return nil }
        return Image(nsImage: image).renderingMode(.template)
    }

    @MainActor var image: Image { assetImage ?? Image(systemName: symbol) }

    var rotation: Double { self == .ruler ? -45 : 0 }
}

extension Tool {
    var iconRotation: Double { ToolGlyph(rawValue: id)?.rotation ?? 0 }
}
