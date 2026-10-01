import AppKit
import SwiftUI
import OnePlusUI
import XCTest
@testable import powertoys

@MainActor
final class BackgroundToolWindowTests: XCTestCase {
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
    @StateObject private var payload = BackgroundWindowPayload()
    var body: some View {
        let _ = { probe.payload = payload }()
        return Text("Window content").frame(width: 320, height: 240)
    }
}
