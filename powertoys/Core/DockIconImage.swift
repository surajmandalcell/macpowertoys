import AppKit

@MainActor
enum DockIconImage {
    private struct CacheKey: Hashable {
        let assetName: String
        let appearanceName: NSAppearance.Name
    }

    private static let opticalScale = 396.0 / 512.0
    private static var cache: [CacheKey: NSImage] = [:]

    static func image(
        named assetName: String,
        appearance requestedAppearance: NSAppearance? = nil
    ) -> NSImage? {
        guard assetName != "AppIcon" else { return nil }

        let appearance = requestedAppearance ?? NSApp.effectiveAppearance
        let appearanceName = resolvedAppearanceName(for: appearance)
        let key = CacheKey(assetName: assetName, appearanceName: appearanceName)
        if let image = cache[key] { return image }
        guard let source = NSImage(named: assetName) else { return nil }

        let image = inset(source, appearance: appearance)
        cache[key] = image
        return image
    }

    static func inset(_ source: NSImage, appearance: NSAppearance) -> NSImage {
        let image = NSImage(size: source.size, flipped: false) { bounds in
            let contentSize = NSSize(
                width: bounds.width * opticalScale,
                height: bounds.height * opticalScale
            )
            let contentRect = NSRect(
                x: (bounds.width - contentSize.width) / 2,
                y: (bounds.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )
            appearance.performAsCurrentDrawingAppearance {
                source.draw(in: contentRect)
            }
            return true
        }
        image.isTemplate = source.isTemplate
        return image
    }

    static func resolvedAppearanceName(for appearance: NSAppearance) -> NSAppearance.Name {
        appearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
    }
}
