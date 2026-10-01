import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusMenuRadiusTests: XCTestCase {
    func testShellHasEightPointTransparentCornersAndInsetBorderInBothAppearances() throws {
        let previous = NSApp.appearance
        defer { NSApp.appearance = previous }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = try XCTUnwrap(NSAppearance(named: name))
            let host = NSHostingView(rootView: OnePlusMenuPanel(maximumHeight: 600,
                tabs: { EmptyView() }, actions: { EmptyView() }, content: { Color.clear.frame(height: 120) }))
            host.frame.size = NSSize(width: 356, height: 179)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.height, 179, accuracy: 0.5)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
            let scale = CGFloat(width) / 356
            func pixel(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
                try XCTUnwrap(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
            }
            for flipX in [false, true] {
                for flipY in [false, true] {
                    func corner(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
                        let px = flipX ? width - 1 - Int(x * scale) : Int(x * scale)
                        let py = flipY ? height - 1 - Int(y * scale) : Int(y * scale)
                        return try XCTUnwrap(bitmap.colorAt(x: px, y: py))
                    }
                    XCTAssertLessThan(try corner(0, 0).alphaComponent, 0.05)
                    // These points are inside radius 8, outside the former radius 11.
                    XCTAssertGreaterThan(try corner(1, 4).alphaComponent, 0.9)
                    XCTAssertGreaterThan(try corner(4, 1).alphaComponent, 0.9)
                }
            }
            let line = try pixel(20, 0), fill = try pixel(20, 3)
            NSApp.appearance?.performAsCurrentDrawingAppearance {
                XCTAssertEqual(line.redComponent, NSColor(OnePlusColor.line).usingColorSpace(.sRGB)!.redComponent, accuracy: 0.02)
                XCTAssertEqual(fill.redComponent, NSColor(OnePlusColor.sidebar).usingColorSpace(.sRGB)!.redComponent, accuracy: 0.02)
            }
            XCTAssertEqual(line.alphaComponent, 1, accuracy: 0.01)
            let former = NSHostingView(rootView: OnePlusColor.sidebar
                .clipShape(RoundedRectangle(cornerRadius: 11)))
            former.frame.size = host.frame.size
            former.layoutSubtreeIfNeeded()
            let old = try XCTUnwrap(former.bitmapImageRepForCachingDisplay(in: former.bounds))
            former.cacheDisplay(in: former.bounds, to: old)
            XCTAssertLessThan(try XCTUnwrap(old.colorAt(x: Int(scale), y: Int(4 * scale))).alphaComponent, 0.1)
        }
    }

    func testNativeHostKeepsTransparentShapeShadowAndControllerThroughResize() {
        let presenter = OnePlusMenuPresenter()
        let controller = NSHostingController(rootView: Color.clear)
        presenter.contentViewController = controller
        presenter.contentSize = NSSize(width: 356, height: 179)
        let top = presenter.window.frame.maxY
        for height in [CGFloat(600), 179, 253] {
            presenter.contentSize = NSSize(width: 356, height: height)
            XCTAssertTrue(presenter.contentViewController === controller)
            XCTAssertEqual(presenter.window.frame.maxY, top)
            XCTAssertEqual(presenter.window.frame.height, height)
            XCTAssertFalse(presenter.window.isOpaque)
            XCTAssertEqual(presenter.window.backgroundColor, .clear)
            XCTAssertTrue(presenter.window.hasShadow)
            XCTAssertFalse(presenter.window.styleMask.contains(.titled))
        }
        let screen = NSRect(x: -1920, y: -1080, width: 1920, height: 1056)
        for x in [CGFloat(-1920), -960, 0] {
            let frame = OnePlusMenuPresenter.frame(anchor: NSRect(x: x, y: -24, width: 24, height: 24),
                                                   size: NSSize(width: 356, height: 179), screen: screen)
            XCTAssertTrue(screen.contains(frame))
            XCTAssertEqual(frame.maxY, -24)
        }
        presenter.close()
    }
}
