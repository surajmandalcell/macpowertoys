import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusChromeAlignmentTests: XCTestCase {
    func testDotHeaderPaintStartsAtTheRegularTextCapTop() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            for scale in [CGFloat(1), 2] {
                let text = try paintedTitleTop(style: .system, density: .regular, appearance: appearance, scale: scale)
                let dots = try paintedTitleTop(style: .dotMatrix, density: .compact, appearance: appearance, scale: scale)
                XCTAssertEqual(dots, text, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(dots, 20, "The dots must not paint above the native lights.")
                XCTAssertEqual(OnePlusTitleStyle.dotMatrix.lineHeight(for: .compact),
                               OnePlusTitleStyle.system.lineHeight(for: .regular))
            }
        }
    }

    func testNativeHoverAreasFollowLightsThroughLayoutChanges() throws {
        for centerline in [CGFloat(22), 27] {
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 420, height: 300),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            let chrome = OnePlusChromeView(size: window.frame.size, centerline: centerline,
                                           sizing: .swiftUI, report: { _ in })
            window.contentView?.addSubview(chrome)
            defer { chrome.stopObserving() }
            let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
            let parent = try XCTUnwrap(close.superview)
            let nativeFrames = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .map { window.standardWindowButton($0)!.frame }
            for appearance in [NSAppearance.Name.darkAqua, .aqua] {
                window.appearance = NSAppearance(named: appearance)
                for event in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                              NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                              NSWindow.didExitFullScreenNotification, NSWindow.didUpdateNotification] {
                    // Simulate AppKit restoring the original titlebar container position.
                    let delta = window.frame.height - parent.convert(parent.bounds, to: nil).midY - 16
                    let container = try XCTUnwrap(parent.superview)
                    container.setFrameOrigin(CGPoint(x: container.frame.minX, y: container.frame.minY + delta))
                    NotificationCenter.default.post(name: event, object: window)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                    for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                        let button = try XCTUnwrap(window.standardWindowButton(type))
                        XCTAssertEqual(button.frame, nativeFrames[index], "Keep AppKit's button frames inside its container.")
                        XCTAssertEqual(window.frame.height - button.convert(button.bounds, to: nil).midY,
                                       centerline, accuracy: 0.5)
                        let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
                        let localCenter = button.convert(center, to: parent)
                        XCTAssertTrue(parent.bounds.contains(button.frame))
                        XCTAssertTrue(parent.trackingAreas.contains { area in
                            area.options.contains(.mouseEnteredAndExited) &&
                            (area.options.contains(.inVisibleRect) ? parent.visibleRect : area.rect).contains(localCenter)
                        }, "The native hover tracker must cover every light.")
                        let nativeFrame = try XCTUnwrap(parent.superview?.superview)
                        XCTAssertTrue(nativeFrame.hitTest(button.convert(center, to: nativeFrame.superview)) === button)
                    }
                }
            }
        }
    }

    func testSceneCanvasDoesNotAddOrRemoveATitlebarInset() throws {
        for nested in [false, true] {
            let root = OnePlusWindowRoot(canvas: .systemMonitor) {
                VStack(spacing: 0) {
                    OnePlusSidebarTitle("Task Manager")
                    Spacer(minLength: 0)
                }
            } content: {
                OnePlusPage(scrolls: false) {
                    OnePlusPageHeader(title: "OVERVIEW", subtitle: "System activity", titleStyle: .dotMatrix)
                } content: {
                    ChromeContentProbe().frame(height: 40)
                }
            }
            let host = NSHostingView(rootView: Group {
                if nested { root.onePlusFixedCanvas(.systemMonitor) }
                else { root }
            })
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1080, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            host.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let content = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "first-row" })
            XCTAssertEqual(content.convert(content.bounds, to: host).minY, 75.8, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.height, 660, accuracy: 0.5)
        }
    }

    private func paintedTitleTop(style: OnePlusTitleStyle, density: OnePlusDensity,
                                 appearance: NSAppearance.Name, scale: CGFloat) throws -> CGFloat {
        let host = NSHostingView(rootView: OnePlusPageHeader(title: "OVERVIEW", titleStyle: style)
            .onePlusDensity(density).frame(width: 600, height: 100, alignment: .topLeading)
            .background(OnePlusColor.window))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 600, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(host.bounds.width * scale), pixelsHigh: Int(host.bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let background = try XCTUnwrap(bitmap.colorAt(x: Int(300 * scale), y: 0)?.usingColorSpace(.sRGB))
        for y in 0..<Int(50 * scale) {
            for x in Int(density.gutter * scale)..<Int(180 * scale) {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(color.redComponent - background.redComponent) > 0.3 { return CGFloat(y) / scale }
            }
        }
        XCTFail("The rendered header has no title pixels.")
        return -1
    }
}

private struct ChromeContentProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("first-row")
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
