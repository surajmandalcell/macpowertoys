import AppKit
import XCTest
@testable import powertoys

@MainActor
final class ScrollIndicatorTests: XCTestCase {
    func testConfiguresOverlayAutohidingMiniScrollers() throws {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false

        scrollView.configureThinScrollIndicators()

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(try XCTUnwrap(scrollView.verticalScroller).controlSize, .mini)
        XCTAssertEqual(try XCTUnwrap(scrollView.horizontalScroller).controlSize, .mini)
    }
}
