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
        case .portman: "cable.connector.horizontal"
        case .macTweaks: "slider.vertical.3"
        case .switchAccounts: "power.circle.fill"
        }
    }

    var rotation: Double { self == .ruler ? -45 : 0 }
}

extension Tool {
    var iconRotation: Double { ToolGlyph(rawValue: id)?.rotation ?? 0 }
}
