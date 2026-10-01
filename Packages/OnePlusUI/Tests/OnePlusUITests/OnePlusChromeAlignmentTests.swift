import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusChromeAlignmentTests: XCTestCase {
    func testHeaderTitlesAndTallestControlsStartOnTheTwentyPointTopLine() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for scale in [CGFloat(1), 2] {
                for density in OnePlusDensity.allCases {
                    let actions = OnePlusHeaderActions {
                        Button("Refresh") {}.buttonStyle(OnePlusButtonStyle())
                            .overlay { ChromeContentProbe("button") }
                        OnePlusSelect(choices: [("one", "One")], selection: .constant("one"),
                                      width: 100, accessibilityLabel: "Select")
                            .overlay { ChromeContentProbe("select") }
                        Toggle("Switch", isOn: .constant(true)).labelsHidden()
                            .toggleStyle(OnePlusSwitchStyle()).fixedSize()
                            .overlay { ChromeContentProbe("switch") }
                    }
                    let recipes: [(String, AnyView, CGFloat)] = [
                        ("page-\(density)", AnyView(OnePlusPageHeader(title: "HEADER") { actions }), density.gutter),
                        ("tool-\(density)", AnyView(OnePlusToolPageHeader(title: "HEADER", subtitle: "Description") {
                            Color.blue.overlay { ChromeContentProbe("icon") }
                        } actions: { actions }), density.gutter + 52)
                    ]
                    for (name, view, titleX) in recipes {
                        try checkHeader(view.onePlusDensity(density), name: name, titleX: titleX,
                                        appearance: appearance, scale: scale, probes: ["button", "select", "switch"])
                    }
                }
                for title in ["Awake", "Color Picker", "Text Extractor"] {
                    try checkHeader(OnePlusAppletTitlebar(title: title) {
                        Toggle("Display", isOn: .constant(true)).toggleStyle(OnePlusSwitchStyle()).fixedSize()
                            .overlay { ChromeContentProbe("switch") }
                        Button("Action") {}.buttonStyle(OnePlusButtonStyle(.primary, size: .small))
                            .overlay { ChromeContentProbe("button") }
                    }, name: title, titleX: 88, appearance: appearance, scale: scale, probes: ["button", "switch"])
                }
                try checkHeader(OnePlusSheet("HEADER", close: {}) { Color.clear.frame(height: 40) },
                                name: "sheet", titleX: 20, appearance: appearance, scale: scale, probes: [])
            }
        }
    }

    private func checkHeader(_ view: some View, name: String, titleX: CGFloat,
                             appearance: NSAppearance.Name, scale: CGFloat, probes: [String]) throws {
        let app = NSApplication.shared
        let saved = app.appearance
        app.appearance = NSAppearance(named: appearance)
        defer { app.appearance = saved }
        let host = NSHostingView(rootView: view.environment(\.displayScale, scale)
            .frame(width: 600, height: 150, alignment: .topLeading)
            .background(OnePlusColor.window))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 600, height: 150),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(600 * scale), pixelsHigh: Int(150 * scale), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let captures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/redesign/captures/chrome")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let filename = "r48-\(name.replacingOccurrences(of: " ", with: "-"))-\(appearance.rawValue)-\(Int(scale))x.png"
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: captures.appendingPathComponent(filename))
        let background = try XCTUnwrap(bitmap.colorAt(x: Int(300 * scale), y: 0)?.usingColorSpace(.sRGB))
        func paintedTop(x: Range<CGFloat>, threshold: CGFloat, linear: Bool = false) throws -> CGFloat {
            let space = linear ? NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)! : .sRGB
            let background = try XCTUnwrap(background.usingColorSpace(space))
            for y in 0..<Int(50 * scale) {
                for pixelX in Int(x.lowerBound * scale)..<Int(x.upperBound * scale) {
                    let color = try XCTUnwrap(bitmap.colorAt(x: pixelX, y: y)?.usingColorSpace(space))
                    if max(abs(color.redComponent - background.redComponent),
                           abs(color.greenComponent - background.greenComponent),
                           abs(color.blueComponent - background.blueComponent)) > threshold {
                        return CGFloat(y) / scale
                    }
                }
            }
            XCTFail("Missing paint: \(name)")
            return -1
        }
        // Linear light avoids counting the different Light/Dark antialiasing halos as cap strokes.
        XCTAssertEqual(try paintedTop(x: titleX..<(titleX + 90), threshold: 0.45, linear: true), 20, accuracy: 1 / scale,
                       "\(name) title \(appearance) \(scale)x")
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let controlFrames = try probes.map { probe in
            let node = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == probe })
            return node.convert(node.bounds, to: host)
        }
        let maximumHeight = controlFrames.map(\.height).max()
        let tallest = controlFrames.filter { $0.height == maximumHeight }.min { $0.minY < $1.minY }
        if let tallest { XCTAssertEqual(tallest.minY, 20, accuracy: 0.01, "\(name) tallest control") }
        for probe in probes + (name.hasPrefix("tool-") ? ["icon"] : []) {
            let node = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == probe })
            let rect = node.convert(node.bounds, to: host)
            if probe == "icon" {
                XCTAssertEqual(rect.minY, 20, accuracy: 0.01, "\(name) icon frame")
            } else if let tallest {
                XCTAssertEqual(rect.midY, tallest.midY, accuracy: 0.5, "\(name) \(probe) center")
            }
            let x = probe == "switch" ? rect.maxX - 16 : rect.midX
            let top = probe == "switch" ? rect.midY - 8.5 : rect.minY
            XCTAssertEqual(try paintedTop(x: (x - 1)..<(x + 1), threshold: 0.025), top, accuracy: 0.5,
                           "\(name) \(probe) paint \(appearance) \(scale)x")
        }
        if name == "sheet" {
            XCTAssertEqual(try paintedTop(x: 525..<531, threshold: 0.025), 27, accuracy: 0.5,
                           "Sheet close glyph stays inside its 24pt button at y20")
        }
    }

    func testDotHeaderPaintStartsAtTheRegularTextCapTop() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            for scale in [CGFloat(1), 2] {
                let text = try paintedTitleTop(style: .system, density: .regular, appearance: appearance, scale: scale)
                let dots = try paintedTitleTop(style: .dotMatrix, density: .compact, appearance: appearance, scale: scale)
                XCTAssertEqual(dots, text, accuracy: 1 / scale)
                XCTAssertEqual(text, 20, accuracy: 1 / scale)
                XCTAssertEqual(dots, 20, accuracy: 1 / scale)
                XCTAssertEqual(OnePlusTitleStyle.dotMatrix.lineHeight(for: .compact),
                               OnePlusTitleStyle.system.lineHeight(for: .regular))
            }
        }
    }

    func testNativeHoverAreasFollowLightsThroughLayoutChanges() async throws {
        for centerline in [CGFloat(22), 27] {
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 420, height: 300),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let chrome = OnePlusChromeView(size: window.frame.size, centerline: centerline,
                                           sizing: .swiftUI, report: { _ in })
            let originalClose = try XCTUnwrap(window.standardWindowButton(.closeButton))
            let nativeCloseX = originalClose.convert(originalClose.bounds, to: nil).minX
            window.contentView?.addSubview(chrome)
            defer {
                chrome.stopObserving()
                window.close()
            }
            await settleChrome(window, centerline: centerline)
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
                    container.setFrameOrigin(CGPoint(x: container.frame.minX + nativeCloseX - close.convert(close.bounds, to: nil).minX, y: container.frame.minY + delta))
                    NotificationCenter.default.post(name: event, object: window)
                    await settleChrome(window, centerline: centerline)
                    for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                        let button = try XCTUnwrap(window.standardWindowButton(type))
                        XCTAssertEqual(button.frame, nativeFrames[index], "Keep AppKit's button frames inside its container.")
                        XCTAssertEqual(window.frame.height - button.convert(button.bounds, to: nil).midY,
                                       centerline, accuracy: 0.5)
                        XCTAssertEqual(close.convert(close.bounds, to: nil).minX, 13, accuracy: 0.01)
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

    func testEveryWindowCanvasKeepsTheInsetAndTitleGap() async throws {
        for canvas in [OnePlusWindowCanvas.main, .diskExplorer, .netToys, .rclone, .systemCare,
                       .switchAccounts, .macTweaks, .systemMonitor, .logs, .inputDevices,
                       .awake, .colorPicker, .textExtractor] {
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: canvas.size),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            var titleX: CGFloat = 0
            let chrome = OnePlusChromeView(size: canvas.size, centerline: canvas.centerline,
                                           sizing: .swiftUI, report: { titleX = $0 + 14 })
            window.contentView?.addSubview(chrome)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                await settleChrome(window, centerline: canvas.centerline)
                let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
                let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
                let rect = close.convert(close.bounds, to: nil)
                XCTAssertEqual(rect.minX, 13, accuracy: 0.01)
                XCTAssertEqual(window.frame.height - rect.maxY, 20, accuracy: 0.01)
                XCTAssertEqual(titleX - zoom.convert(zoom.bounds, to: nil).maxX, 14, accuracy: 0.01)
            }
            chrome.stopObserving()
            window.close()
        }
    }

    func testSceneCanvasDoesNotAddOrRemoveATitlebarInset() async throws {
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
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            repeat {
                host.layoutSubtreeIfNeeded()
                if abs(host.fittingSize.height - 660) < 0.5 { break }
                try await Task.sleep(for: .milliseconds(10))
            } while ContinuousClock.now < deadline
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let content = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "first-row" })
            XCTAssertEqual(content.convert(content.bounds, to: host).minY, 79.8, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.height, 660, accuracy: 0.5)
        }
    }

    private func settleChrome(_ window: NSWindow, centerline: CGFloat) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        repeat {
            // Yield the main actor so the coalesced DispatchQueue pass can run.
            try? await Task.sleep(for: .milliseconds(10))
            let aligned = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].allSatisfy { type in
                guard let button = window.standardWindowButton(type) else { return false }
                let rect = button.convert(button.bounds, to: nil)
                return abs(window.frame.height - rect.midY - centerline) < 0.01
                    && (type != .closeButton || abs(rect.minX - 13) < 0.01)
            }
            if aligned { return }
        } while ContinuousClock.now < deadline
    }

    private func paintedTitleTop(style: OnePlusTitleStyle, density: OnePlusDensity,
                                 appearance: NSAppearance.Name, scale: CGFloat) throws -> CGFloat {
        let host = NSHostingView(rootView: OnePlusPageHeader(title: "OVERVIEW", titleStyle: style)
            .onePlusDensity(density).environment(\.displayScale, scale)
            .frame(width: 600, height: 100, alignment: .topLeading)
            .background(OnePlusColor.window))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 600, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(host.bounds.width * scale), pixelsHigh: Int(host.bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let space = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!
        let background = try XCTUnwrap(bitmap.colorAt(x: Int(300 * scale), y: 0)?.usingColorSpace(space))
        for y in 0..<Int(50 * scale) {
            for x in Int(density.gutter * scale)..<Int(180 * scale) {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(space))
                if abs(color.redComponent - background.redComponent) > (style == .dotMatrix ? 0.3 : 0.45) {
                    return CGFloat(y) / scale
                }
            }
        }
        XCTFail("The rendered header has no title pixels.")
        return -1
    }
}

private struct ChromeContentProbe: NSViewRepresentable {
    let name: String
    init(_ name: String = "first-row") { self.name = name }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(name)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
