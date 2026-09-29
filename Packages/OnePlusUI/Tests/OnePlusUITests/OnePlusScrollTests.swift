import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusScrollTests: XCTestCase {
    func testScrollViewListAndNativeTableKeepTheFullContentWidth() throws {
        for content in [
            AnyView(ScrollView { Color.clear.frame(height: 1000) }.onePlusScrollIndicators()),
            AnyView(List(0..<50, id: \.self) { Text("Row \($0)") }.onePlusScrollIndicators()),
            AnyView(OnePlusNativeTable(columns: [.init("Name", width: 300)],
                rows: (0..<50).map { .init(id: String($0), cells: ["Row \($0)"], symbol: "circle") },
                selection: .constant([]), sort: { _, _ in }, open: { _ in }, preview: { _ in },
                remove: { _ in }, actions: { _ in [] }))
        ] {
            let host = NSHostingView(rootView: content.frame(width: 420, height: 300))
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 420, height: 300),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            settle(host)
            let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
            for _ in 0..<3 {
                scroll.verticalScroller = NSScroller()
                scroll.scrollerStyle = .legacy
                settle(host)
                XCTAssertEqual(scroll.scrollerStyle, .overlay)
                XCTAssertTrue(scroll.verticalScroller is OnePlusOverlayScroller)
                XCTAssertEqual(scroll.contentView.frame.width, scroll.bounds.width, accuracy: 0.5)
            }
        }
    }

    func testScrollPolicyReleasesTheHostWithPendingWork() {
        weak var released: NSScrollView?
        autoreleasepool {
            let scroll = NSScrollView()
            released = scroll
            scroll.hasVerticalScroller = true
            scroll.configureOnePlusScrollIndicators()
            scroll.verticalScroller = NSScroller()
            scroll.scrollerStyle = .legacy
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNil(released)
    }

    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
