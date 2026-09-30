import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusScrollTests: XCTestCase {
    func testLongPageWithNestedEditorKeepsTwentyFourPointGuttersAfterLayout() throws {
        let host = NSHostingView(rootView: OnePlusPage {
            OnePlusPageHeader(title: "Cloud Sync")
        } content: {
            OnePlusCard {
                OnePlusCardHeader("Ignore patterns")
                OnePlusTextEditor("Ignore patterns", text: .constant("*.tmp\n.cache/**"))
                    .frame(height: 180).padding(16)
            }
            Color.clear.frame(height: 1000)
        })
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1024, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        settle(host)
        let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
        let editor = try XCTUnwrap(scrolls.first { $0.documentView is NSTextView })
        let page = try XCTUnwrap(scrolls.first { editor.isDescendant(of: $0) && $0 !== editor })
        XCTAssertEqual(scrolls.count, 2)
        for _ in 0..<3 {
            page.scrollerStyle = .legacy
            page.tile()
            host.needsLayout = true
            settle(host)
            XCTAssertEqual(page.scrollerStyle, .overlay)
            XCTAssertEqual(page.contentView.frame.width, page.bounds.width, accuracy: 0.5)
            let editorRect = editor.convert(editor.bounds, to: host)
            // The editor has 16pt padding inside its card, outside the page gutter.
            XCTAssertEqual(editorRect.maxX + 16, host.bounds.width - 24, accuracy: 0.5)
            XCTAssertEqual(editorRect.minX - 16, 24, accuracy: 0.5)
            // SwiftUI can restore the legacy clip width after the style is already overlay.
            page.contentView.setFrameSize(NSSize(width: page.bounds.width - 17, height: page.contentView.frame.height))
            settle(host)
            XCTAssertEqual(page.contentView.frame.width, page.bounds.width, accuracy: 0.5)
            XCTAssertEqual(editor.convert(editor.bounds, to: host).maxX + 16, host.bounds.width - 24, accuracy: 0.5)
        }
    }

    func testProbeConfiguresItsNearestEnclosingScrollBeforeANestedEditor() throws {
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            OnePlusTextEditor("Ignore patterns", text: .constant("*.tmp")).frame(height: 450)
            Color.clear.frame(height: 1000)
        })
        host.frame = CGRect(x: 0, y: 0, width: 1024, height: 1450)
        let document = NSView(frame: host.frame)
        document.addSubview(host)
        let page = NSScrollView(frame: CGRect(x: 0, y: 0, width: 1024, height: 500))
        page.hasVerticalScroller = true
        page.scrollerStyle = .legacy
        page.documentView = document
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1024, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page
        defer { window.close() }
        settle(page)
        let editor = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let probe = OnePlusScrollProbe(frame: document.convert(page.bounds, from: page))
        document.addSubview(probe)
        settle(page)
        XCTAssertEqual(page.scrollerStyle, .overlay)
        XCTAssertTrue(page.verticalScroller is OnePlusOverlayScroller)
        XCTAssertTrue(editor.verticalScroller is OnePlusOverlayScroller)
    }

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
