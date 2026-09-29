import AppKit
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusChromeTests: XCTestCase {
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
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            let writes = window.propertyWrites
            let passes = chrome.appliedPassCount
            let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
            for index in 0..<20 {
                window.setFrame(NSRect(x: -2000, y: -2000, width: 420, height: 270 + index * 4), display: false)
                zoom.setFrameOrigin(NSPoint(x: zoom.frame.minX, y: zoom.frame.minY + 5))
                chrome.layout()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
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
