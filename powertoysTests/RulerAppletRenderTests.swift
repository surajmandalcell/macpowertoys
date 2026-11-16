import AppKit
import XCTest
@testable import powertoys

/// Renders both Ruler applet windows offscreen and checks the Quiet Raised control geometry. Nothing is ordered on screen.
@MainActor
final class RulerAppletRenderTests: XCTestCase {
    private final class HiddenRuler: RulerWindow {
        override func makeKey() {}
        override func makeKeyAndOrderFront(_ sender: Any?) {}
        override func orderFront(_ sender: Any?) {}
        override func orderFrontRegardless() {}
        override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {}
    }

    func testRenderRulerAppletWindowsAndCheckQuietRaisedGeometry() throws {
        let ruler = RulerController(frame: NSRect(x: 0, y: 0, width: 400, height: 400),
                                    windowFactory: { HiddenRuler(frame: $0, settings: $1) })
        let settings = RulerSettingsController(rulerController: ruler)
        let defaults = PreferencesController()
        let windows = [("settings", try XCTUnwrap(settings.window)), ("defaults", try XCTUnwrap(defaults.window))]
        for (_, window) in windows {
            XCTAssertFalse(window.isVisible, "nib load must not order the applet window")
            XCTAssertEqual(window.frame.size, NSSize(width: 420, height: 500))
            try checkGeometry(in: XCTUnwrap(window.contentView))
        }

        let directory = ProcessInfo.processInfo.environment["RULER_RENDER_DIR"]
            ?? "/Volumes/External1TB/data/_custom/orca/workspaces/powertoys/v15-ruler"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (name, window) in windows {
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for scale in [1, 2] {
                    try render(XCTUnwrap(window.contentView), appearance: XCTUnwrap(NSAppearance(named: appearance)),
                               scale: CGFloat(scale),
                               to: URL(fileURLWithPath: "\(directory)/ruler-\(name)-\(mode)-\(scale)x.png"))
                }
            }
        }
        settings.close()
        defaults.close()
    }

    private func checkGeometry(in root: NSView) throws {
        root.layoutSubtreeIfNeeded()
        let views = all(root)
        let switches = views.compactMap { $0 as? RulerQuietRaisedSwitch }
        XCTAssertEqual(switches.count, 2)
        for item in switches { XCTAssertEqual(item.frame.height, 24) }
        let segmented = try XCTUnwrap(views.compactMap { $0 as? RulerQuietRaisedSegmentedControl }.first)
        XCTAssertEqual(segmented.frame.size, NSSize(width: 112, height: 24))
        let sliders = views.compactMap { $0 as? NSSlider }
        XCTAssertEqual(sliders.count, 3)
        for slider in sliders {
            XCTAssertTrue(slider.cell is RulerQuietRaisedSliderCell)
            // Track and knob share the slider's center line on whole points.
            XCTAssertEqual(slider.frame.height.truncatingRemainder(dividingBy: 2), 0)
        }
        // Every control in a group row centers on that row's 36 pt center line.
        for control in switches as [NSView] + [segmented] + sliders {
            guard let group = ancestor(of: control) else { return XCTFail("control outside a group") }
            let frame = control.convert(control.bounds, to: group)
            let fromTop = group.bounds.height - frame.midY
            XCTAssertEqual(fromTop.truncatingRemainder(dividingBy: 36), 18, accuracy: 0.01, "\(control)")
        }
    }

    private func ancestor(of view: NSView) -> RulerAppletGroupView? {
        var current = view.superview
        while let candidate = current {
            if let group = candidate as? RulerAppletGroupView { return group }
            current = candidate.superview
        }
        return nil
    }

    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    private func render(_ view: NSView, appearance: NSAppearance, scale: CGFloat, to url: URL) throws {
        view.window?.appearance = appearance
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        appearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
