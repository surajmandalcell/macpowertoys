import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusWindowContentTests: XCTestCase {
    func testCloseReleasesContentAndReopenRebuildsBeforeOrdering() throws {
        let probe = WindowContentProbe()
        let host = NSHostingView(rootView: OnePlusWindowContent { WindowPayloadView(probe: probe) })
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
        }
        settle()
        XCTAssertNotNil(probe.payload)
        let originalSize = host.fittingSize
        for cycle in 1...3 {
            NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
            settle()
            XCTAssertNotNil(probe.payload, "Minimizing must preserve the graph.")
            if cycle == 1 { window.close() }
            else { NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window) }
            settle()
            XCTAssertNil(probe.payload, "Closed scene must release its state and hosted views.")
            XCTAssertEqual(probe.released, cycle)
            XCTAssertEqual(host.fittingSize, originalSize, "Closing must preserve content-size constraints.")
            XCTAssertFalse(window.isVisible)
            window.onePlusPrepareForOpening()
            settle()
            XCTAssertNotNil(probe.payload, "Router must reconstruct content before ordering.")
            XCTAssertEqual(probe.created, cycle + 1)
            XCTAssertEqual(host.fittingSize, originalSize)
            XCTAssertFalse(window.isVisible, "Preparation must never order or activate a window.")
        }
    }
}

@MainActor private final class WindowContentProbe {
    weak var payload: WindowPayload?
    var created = 0
    var released = 0
}

@MainActor private final class WindowPayload: ObservableObject {
    let probe: WindowContentProbe
    init(probe: WindowContentProbe) {
        self.probe = probe
        probe.created += 1
        probe.payload = self
    }
    isolated deinit { probe.released += 1 }
}

private struct WindowPayloadView: View {
    @StateObject private var payload: WindowPayload
    init(probe: WindowContentProbe) { _payload = StateObject(wrappedValue: WindowPayload(probe: probe)) }
    var body: some View { WindowPayloadMarker(payload: payload).frame(width: 320, height: 240) }
}

private struct WindowPayloadMarker: NSViewRepresentable {
    let payload: WindowPayload
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {}
}
