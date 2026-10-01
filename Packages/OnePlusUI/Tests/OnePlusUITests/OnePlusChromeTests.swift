import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusChromeTests: XCTestCase {
    func testDisplayUpdateRepairsLateNativeButtonResetsInBothAppearances() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            for centerline in [CGFloat(22), 27] {
                let window = ChromeCountingWindow(contentRect: CGRect(x: -10000, y: -10000, width: 420, height: 300),
                    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                let chrome = OnePlusChromeView(size: window.frame.size, centerline: centerline,
                                             sizing: .swiftUI, report: { _ in })
                window.contentView?.addSubview(chrome)
                waitForChrome(window, centerline: centerline)
                window.propertyWrites = 0
                let passes = chrome.appliedPassCount
                for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    let button = try XCTUnwrap(window.standardWindowButton(type))
                    button.postsFrameChangedNotifications = false
                    button.setFrameOrigin(CGPoint(x: button.frame.minX, y: button.frame.minY + 11))
                }
                NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
                waitForChrome(window, centerline: centerline)
                for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    let button = try XCTUnwrap(window.standardWindowButton(type))
                    XCTAssertEqual(window.frame.height - button.convert(button.bounds, to: nil).midY, centerline, accuracy: 0.5)
                }
                XCTAssertEqual(window.propertyWrites, 0)
                XCTAssertEqual(chrome.appliedPassCount - passes, 1)
                for _ in 0..<100 {
                    NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
                }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                XCTAssertEqual(chrome.appliedPassCount - passes, 1, "Aligned display updates need no chrome pass")
                chrome.stopObserving()
            }
        }
    }
    func testCanvasUsesVisibleHeightWithoutAddingTheTitlebar() {
        for canvas in [OnePlusWindowCanvas.systemMonitor, .diskExplorer, .awake, .colorPicker, .textExtractor] {
            let height = canvas.heightRange?.upperBound ?? canvas.size.height
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: canvas.size),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            let host = NSHostingView(rootView:
                OnePlusWindowRoot(canvas: canvas) { Color.clear } content: { Color.clear }
                    .frame(height: height).onePlusFixedCanvas(canvas))
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            waitForChrome(window, centerline: canvas.centerline)
            XCTAssertEqual(host.fittingSize.width, canvas.size.width)
            XCTAssertEqual(host.fittingSize.height, height)
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
            waitForChrome(window, centerline: canvas.centerline)
            XCTAssertEqual(window.frame.height, height)
            XCTAssertTrue(window.styleMask.contains(.miniaturizable))
            let minimize = window.standardWindowButton(.miniaturizeButton)!
            XCTAssertTrue(minimize.isEnabled)
            XCTAssertNotNil(minimize.action)
            XCTAssertTrue(window.responds(to: #selector(NSWindow.miniaturize(_:))))
            let zoom = window.standardWindowButton(.zoomButton)!
            XCTAssertFalse(zoom.isEnabled)
            XCTAssertEqual(height - zoom.convert(zoom.bounds, to: nil).midY, canvas.centerline, accuracy: 0.5)
        }
    }

    func testRepeatedNativeLayoutDoesNotWriteWindowPropertiesSynchronously() {
        let window = ChromeCountingWindow(contentRect: NSRect(x: -2000, y: -2000, width: 420, height: 300),
                                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                          backing: .buffered, defer: false)
        let chrome = OnePlusChromeView(size: NSSize(width: 420, height: 300), centerline: 22, report: { _ in })
        window.contentView?.addSubview(chrome)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        window.propertyWrites = 0
        let passes = chrome.appliedPassCount
        for _ in 0..<100 {
            chrome.layout()
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        }
        XCTAssertEqual(window.propertyWrites, 0, "Layout events must only schedule work.")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(window.propertyWrites, 0, "An unchanged window needs no property writes.")
        XCTAssertEqual(chrome.appliedPassCount - passes, 1, "One hundred events must coalesce into one pass.")
        chrome.stopObserving()
    }

    func testSwiftUIOwnsResizingAndFlexibleHeightThroughRepeatedLayout() throws {
        for sizing in [OnePlusChromeSizing.swiftUI, .swiftUIHeight] {
            let window = ChromeCountingWindow(contentRect: NSRect(x: -2000, y: -2000, width: 420, height: 300),
                                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                              backing: .buffered, defer: false)
            window.contentMinSize = NSSize(width: 200, height: 240)
            window.contentMaxSize = NSSize(width: 800, height: 460)
            let chrome = OnePlusChromeView(size: NSSize(width: 420, height: 300), centerline: 22,
                                          sizing: sizing, report: { _ in })
            window.contentView?.addSubview(chrome)
            waitForChrome(window, centerline: 22)
            let writes = window.propertyWrites
            let passes = chrome.appliedPassCount
            let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
            for index in 0..<20 {
                window.setFrame(NSRect(x: -2000, y: -2000, width: 420, height: 270 + index * 4), display: false)
                zoom.setFrameOrigin(NSPoint(x: zoom.frame.minX, y: zoom.frame.minY + 5))
                chrome.layout()
                waitForChrome(window, centerline: 22)
                XCTAssertEqual(window.frame.height - zoom.convert(zoom.bounds, to: nil).midY, 22, accuracy: 0.5)
            }
            XCTAssertEqual(window.contentSizeWrites, 0, "Chrome must not resize a SwiftUI canvas.")
            XCTAssertEqual(window.propertyWrites, writes, "Resize passes must not repeat style or limit writes.")
            XCTAssertLessThanOrEqual(chrome.appliedPassCount - passes, 20, "Moving our own buttons must not enqueue more work.")
            XCTAssertEqual(window.contentMinSize.width, 420)
            XCTAssertEqual(window.contentMaxSize.width, 420)
            if sizing == .swiftUIHeight {
                XCTAssertEqual(window.contentMinSize.height, 240)
                XCTAssertEqual(window.contentMaxSize.height, 460)
                XCTAssertEqual(window.frame.height, 346, accuracy: 0.5)
            }
            chrome.apply()
            let beforeClose = chrome.appliedPassCount
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            XCTAssertEqual(chrome.appliedPassCount, beforeClose, "Closing must cancel pending work.")
        }
    }

    private func waitForChrome(_ window: NSWindow, centerline: CGFloat) {
        let deadline = Date(timeIntervalSinceNow: 1)
        repeat {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            let aligned = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].allSatisfy { type in
                guard let button = window.standardWindowButton(type) else { return false }
                return abs(window.frame.height - button.convert(button.bounds, to: nil).midY - centerline) <= 0.5
            }
            if aligned, window.titleVisibility == .hidden { return }
        } while Date() < deadline
    }
}

@MainActor
private final class ChromeCountingWindow: NSWindow {
    var propertyWrites = 0
    var contentSizeWrites = 0
    override func setContentSize(_ size: NSSize) {
        contentSizeWrites += 1
        super.setContentSize(size)
    }
    override var styleMask: NSWindow.StyleMask {
        get { super.styleMask }
        set { propertyWrites += 1; super.styleMask = newValue }
    }
    override var titleVisibility: NSWindow.TitleVisibility {
        get { super.titleVisibility }
        set { propertyWrites += 1; super.titleVisibility = newValue }
    }
    override var titlebarAppearsTransparent: Bool {
        get { super.titlebarAppearsTransparent }
        set { propertyWrites += 1; super.titlebarAppearsTransparent = newValue }
    }
    override var collectionBehavior: NSWindow.CollectionBehavior {
        get { super.collectionBehavior }
        set { propertyWrites += 1; super.collectionBehavior = newValue }
    }
    override var contentMinSize: NSSize {
        get { super.contentMinSize }
        set { propertyWrites += 1; super.contentMinSize = newValue }
    }
    override var contentMaxSize: NSSize {
        get { super.contentMaxSize }
        set { propertyWrites += 1; super.contentMaxSize = newValue }
    }
}
