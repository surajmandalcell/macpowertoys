import AppKit
import Combine
import SwiftUI
import OnePlusUI
import XCTest
@testable import powertoys

@MainActor
final class BackgroundToolWindowTests: XCTestCase {
    func testOffSpaceRoutesUpdatePagesWithoutOrdering() {
        final class WindowSpy: NSWindow {
            var reportsActiveSpace = true
            var minimized = false
            var reportsVisible = false
            var backgroundOrders = 0
            var frontOrders = 0
            var keyOrders = 0
            var deminiaturizations = 0
            override var isOnActiveSpace: Bool { reportsActiveSpace }
            override var isMiniaturized: Bool { minimized }
            override var isVisible: Bool { reportsVisible }
            override func orderFrontRegardless() { frontOrders += 1 }
            override func orderFront(_ sender: Any?) { frontOrders += 1 }
            override func orderBack(_ sender: Any?) { backgroundOrders += 1 }
            override func makeKeyAndOrderFront(_ sender: Any?) { keyOrders += 1 }
            override func deminiaturize(_ sender: Any?) { deminiaturizations += 1 }
        }
        let tools = ["main", "rclone", "logs", "awake", "color-picker", "text-extractor",
                     "input-devices", "system-care", "disk-explorer", "system-monitor", "nettoys", "switch", "mac-tweaks"]
        XCTAssertFalse(NSApp.isActive, "The guarded unit host must stay inactive")
        for tool in tools {
            for visible in [false, true] {
                let window = WindowSpy(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
                window.identifier = .init(tool)
                window.reportsVisible = visible
                var activations = 0
                func present(_ explicit: Bool) {
                    ToolActionRouter.presentSingleWindow(id: tool, windows: [window], activateApp: explicit,
                        createWindow: { _ in XCTFail("Reuse must keep the window"); return nil },
                        activate: { activations += 1 },
                        openWindow: { _ in XCTFail("Reuse must not call openWindow") })
                }
                present(false)
                XCTAssertEqual(window.backgroundOrders, 1)
                window.reportsActiveSpace = false
                for page in tool == "main" ? ["all-tools", "favorites"] : ["settings", "settings"] {
                    ToolPageRouter.shared.post(tool: tool, page: page, recordTiming: false)
                    present(false)
                    XCTAssertEqual(ToolPageRouter.shared.take(tool: tool)?.page, page)
                    XCTAssertEqual(window.backgroundOrders, 1, "Off-Space route: \(tool)/\(page)")
                }
                window.minimized = true
                present(false)
                XCTAssertEqual(window.backgroundOrders, 1)
                XCTAssertEqual(window.keyOrders, 0)
                XCTAssertEqual(window.frontOrders, 0, "Inactive routes must make no front-ordering call")
                XCTAssertEqual(window.deminiaturizations, 0)
                XCTAssertEqual(activations, 0)
                present(true)
                XCTAssertEqual(window.keyOrders, 1)
                XCTAssertEqual(window.deminiaturizations, 1)
                XCTAssertEqual(activations, 1)
            }
        }
    }

    func testNativeCloseRebuildsTheHostAndFixedFrameBeforeOrdering() throws {
        let window = BackgroundToolWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1240, height: 840),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.identifier = .init("main")
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.prepareContent()
        for _ in 0..<3 {
            let original = try XCTUnwrap(window.contentViewController)
            window.performClose(nil)
            XCTAssertNil(window.contentViewController)
            window.prepareContent()
            XCTAssertNotNil(window.contentViewController)
            XCTAssertFalse(window.contentViewController === original)
            XCTAssertEqual(window.frame.size, NSSize(width: 1240, height: 840))
            XCTAssertFalse(window.styleMask.contains(.resizable))
            XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
            XCTAssertTrue(window.titlebarAppearsTransparent)
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(window.isKeyWindow)
        }
    }

    func testColdHiddenSceneKeepsItsHostBeforeOrdering() throws {
        final class WindowSpy: NSWindow {
            override var isOnActiveSpace: Bool { true }
            var beforeOrdering: () -> Void = {}
            var backgroundOrders = 0
            var keyOrders = 0
            override func orderFrontRegardless() { XCTFail("Inactive scene ordered front") }
            override func orderBack(_ sender: Any?) { beforeOrdering(); backgroundOrders += 1 }
            override func makeKeyAndOrderFront(_ sender: Any?) { beforeOrdering(); keyOrders += 1 }
        }
        let window = WindowSpy(
            contentRect: NSRect(x: -10000, y: -10000, width: 1240, height: 840),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.identifier = .init("main")
        window.isReleasedWhenClosed = false
        defer { window.beforeOrdering = {}; window.close() }
        let probe = BackgroundWindowProbe()
        window.contentViewController = NSHostingController(rootView:
            OnePlusWindowContent {
                BackgroundWindowPayloadView(probe: probe).onePlusFixedCanvas(.main)
            })
        let original = try XCTUnwrap(window.contentViewController)
        let host = try XCTUnwrap(window.contentView)
        window.beforeOrdering = {
            XCTAssertTrue(window.contentViewController === original)
            XCTAssertTrue(window.contentView === host)
            XCTAssertNotNil(probe.payload)
            XCTAssertEqual(window.frame.size, NSSize(width: 1240, height: 840))
        }
        ToolActionRouter.presentSingleWindow(id: "main", windows: [window], activateApp: false,
            createWindow: { _ in XCTFail("Cold first route must keep its scene"); return nil },
            activate: { XCTFail("Cold first route must not activate") },
            openWindow: { _ in XCTFail("Cold first route must not call openWindow") })
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertEqual(window.backgroundOrders, 1)
        XCTAssertEqual(window.keyOrders, 0)
    }

    func testColdHiddenAppletMeasuresItsBodyBeforeOrdering() throws {
        final class WindowSpy: NSWindow {
            override var isOnActiveSpace: Bool { true }
            var beforeOrdering: () -> Void = {}
            override func orderFrontRegardless() { XCTFail("Inactive applet ordered front") }
            override func orderBack(_ sender: Any?) { beforeOrdering() }
        }
        for height: CGFloat in [250, 355, 460] {
            let window = WindowSpy(
                contentRect: NSRect(x: -10000, y: -10000, width: 420, height: height),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.identifier = .init("color-picker")
            window.isReleasedWhenClosed = false
            defer { window.beforeOrdering = {}; window.close() }
            let probe = BackgroundWindowProbe()
            // An unregistered ID keeps this fixture out of owner window preferences.
            window.contentViewController = NSHostingController(rootView: OnePlusWindowContent {
                BackgroundWindowPayloadView(probe: probe, height: height)
                    .background(WindowAccessor(identifier: "BackgroundToolWindowTests"))
                    .onePlusFixedCanvas(.colorPicker)
            })
            window.contentView?.layoutSubtreeIfNeeded()
            window.identifier = .init("color-picker")
            let original = try XCTUnwrap(window.contentViewController)
            window.beforeOrdering = {
                XCTAssertTrue(window.contentViewController === original)
                XCTAssertNotNil(probe.payload)
                XCTAssertEqual(window.frame.size, NSSize(width: 420, height: height))
            }
            ToolActionRouter.presentSingleWindow(id: "color-picker", windows: [window], activateApp: false,
                createWindow: { _ in XCTFail("Cold applet must keep its scene"); return nil },
                activate: { XCTFail("Background applet must not activate") },
                openWindow: { _ in XCTFail("Background applet must not call openWindow") })
            XCTAssertFalse(window.isKeyWindow)
        }
    }

    func testCloseReleasesTheHostAndModelWithoutReleasingTheWindow() {
        let window = BackgroundToolWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 240),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let probe = BackgroundWindowProbe()
        func settle() {
            autoreleasepool {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
        }
        for _ in 0..<3 {
            autoreleasepool {
                window.contentViewController = NSHostingController(rootView:
                    OnePlusWindowContent { BackgroundWindowPayloadView(probe: probe) })
            }
            settle()
            weak var controller = window.contentViewController
            weak var host = window.contentView
            XCTAssertNotNil(probe.payload)
            let size = window.contentView!.frame.size
            autoreleasepool { window.close() }
            settle()
            XCTAssertNil(controller)
            XCTAssertNil(host)
            XCTAssertNil(probe.payload)
            XCTAssertEqual(window.contentView?.frame.size, size)
            XCTAssertFalse(window.isVisible)
        }
    }
}

@MainActor private final class BackgroundWindowProbe {
    weak var payload: BackgroundWindowPayload?
}

@MainActor private final class BackgroundWindowPayload: ObservableObject {}

private struct BackgroundWindowPayloadView: View {
    let probe: BackgroundWindowProbe
    var height: CGFloat = 240
    @StateObject private var payload = BackgroundWindowPayload()
    var body: some View {
        let _ = { probe.payload = payload }()
        return Text("Window content").frame(width: 320, height: height)
    }
}
