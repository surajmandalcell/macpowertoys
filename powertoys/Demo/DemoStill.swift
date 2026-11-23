//
//  DemoStill.swift
//  powertoys
//
//  Still mode for the site: `-MPTDemoStillDir <folder>`, optional `-MPTDemoStillAt <seconds after the lead-in>`.
//  The app draws its own scene windows at 2x into <folder>/<scene>.png. No screen capture runs, so macOS draws
//  no recording indicator, and the 2x pixels come from AppKit drawing on a 1x screen, not from upscaling.
//

#if MPT_DEMO
import AppKit
import ObjectiveC

@MainActor
enum DemoStill {
    private static let scale = 2.0
    /// Status items and the Portman anchor are tiny windows; only real scene windows count.
    private static let minimumArea = 5_000.0

    static var directory: URL? {
        UserDefaults.standard.string(forKey: "MPTDemoStillDir").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static var stopAt: Double? {
        UserDefaults.standard.object(forKey: "MPTDemoStillAt") == nil ? nil : UserDefaults.standard.double(forKey: "MPTDemoStillAt")
    }

    /// The demo app never becomes active, so AppKit would draw gray traffic lights and inactive materials.
    /// AppKit asks these window methods for its active look; answering yes changes only drawing, never focus.
    static func forceActiveLook() {
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        let yesForButton: @convention(block) (AnyObject, Int) -> Bool = { _, _ in true }
        for name in ["_hasActiveAppearance", "_hasActiveAppearanceIgnoringKeyFocus", "_hasKeyAppearance",
                     "_hasMainAppearance", "hasKeyAppearance", "hasMainAppearance"] {
            guard let method = class_getInstanceMethod(NSWindow.self, NSSelectorFromString(name)) else { continue }
            method_setImplementation(method, imp_implementationWithBlock(yes))
        }
        if let method = class_getInstanceMethod(NSWindow.self, NSSelectorFromString("_hasActiveAppearanceForStandardWindowButton:")) {
            method_setImplementation(method, imp_implementationWithBlock(yesForButton))
        }
    }

    static func sceneWindows(excluding before: Set<Int>) -> [NSWindow] {
        // orderedWindows runs front to back but leaves out panels; drawing runs back to front.
        let order = NSApp.orderedWindows.map(\.windowNumber)
        return NSApp.windows.filter {
            $0.isVisible && !before.contains($0.windowNumber) && $0.frame.width * $0.frame.height > minimumArea
        }.sorted {
            ($0.level.rawValue, -(order.firstIndex(of: $0.windowNumber) ?? 0))
                < ($1.level.rawValue, -(order.firstIndex(of: $1.windowNumber) ?? 0))
        }
    }

    static func write(scene: String, windows: [NSWindow], to directory: URL) {
        for window in windows { window.contentView?.superview?.displayIfNeeded() }
        let region = windows.map(\.frame).reduce(NSRect.null) { $0.union($1) }
        guard !region.isEmpty, let canvas = bitmap(size: region.size),
              let context = NSGraphicsContext(bitmapImageRep: canvas) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for window in windows {
            let frame = window.frame
            render(window).draw(in: NSRect(x: frame.minX - region.minX, y: frame.minY - region.minY,
                                           width: frame.width, height: frame.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(scene).png")
        try? canvas.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
        NSLog("MacPowerToys Demo: still %@ %dx%d from %d windows", url.path, canvas.pixelsWide, canvas.pixelsHigh, windows.count)
    }

    private static func bitmap(size: NSSize) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((size.width * scale).rounded()),
                                   pixelsHigh: Int((size.height * scale).rounded()), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = size
        return rep
    }

    /// The whole window as AppKit draws it (title bar and buttons included), cut to the window server's own corner mask.
    private static func render(_ window: NSWindow) -> NSImage {
        let image = NSImage(size: window.frame.size)
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = bitmap(size: view.bounds.size) else { return image }
        view.cacheDisplay(in: view.bounds, to: rep)
        let selector = NSSelectorFromString("_cornerMask")
        if window.responds(to: selector), let mask = window.perform(selector)?.takeUnretainedValue() as? NSImage,
           let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            mask.draw(in: NSRect(origin: .zero, size: view.bounds.size), from: .zero, operation: .destinationIn, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        image.addRepresentation(rep)
        return image
    }
}
#endif
