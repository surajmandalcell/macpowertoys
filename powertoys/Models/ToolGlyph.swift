import SwiftUI
import OnePlusUI

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

    var symbol: String {
        switch self {
        case .cloudSync: "cloud"
        case .logs: "EventViewerGlyph"
        case .ruler: "ruler"
        case .awake: "eye"
        case .colorPicker: "eyedropper"
        case .textExtractor: "text.viewfinder"
        case .inputDevices: "computermouse"
        case .systemCare: "SystemCareGlyph"
        case .diskman: "opticaldisc"
        case .taskManager: "waveform.path.ecg.rectangle"
        case .netToys: "NetToysGlyph"
        case .portman: "PortmanStatusGlyph"
        case .macTweaks: "slider.vertical.3"
        }
    }

    @MainActor private static var assetImages: [ToolGlyph: NSImage] = [:]

    @MainActor var assetNSImage: NSImage? {
        guard isAsset else { return nil }
        if let image = Self.assetImages[self] { return image }
        guard let source = NSImage(named: symbol) else { return nil }
        let image = StatusItemIcon.rasterized(source).0
        image.isTemplate = true
        Self.assetImages[self] = image
        return image
    }

    @MainActor var assetImage: Image? {
        guard let image = assetNSImage else { return nil }
        return Image(nsImage: image).renderingMode(.template)
    }

    var isAsset: Bool { [.portman, .systemCare, .netToys, .logs].contains(self) }

    @MainActor var image: Image { assetImage ?? Image(systemName: symbol) }

    var rotation: Double { self == .ruler ? -45 : 0 }
}

extension Tool {
    var iconRotation: Double { ToolGlyph(rawValue: id)?.rotation ?? 0 }
}

struct ToolGlyphImage: View {
    let glyph: ToolGlyph?
    let size: CGFloat
    var fallback = "house"

    var body: some View {
        if let image = glyph?.assetImage {
            image.onePlusAssetGlyph(size: size)
        } else {
            Image(systemName: glyph?.symbol ?? fallback).font(.system(size: size, weight: .regular))
        }
    }
}
