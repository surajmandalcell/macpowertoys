import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusUITests: XCTestCase {
    func testContentControlsKeepTheirPaintedMinimumSize() {
        let view = HStack(spacing: OnePlusMetrics.actionSpacing) {
            Button("Configure") {}
                .onePlusControl(
                    minWidth: 88,
                    minHeight: OnePlusMetrics.contentControlHeight,
                    horizontalPadding: OnePlusMetrics.contentControlHorizontalPadding
                )
            Button("Connect") {}
                .onePlusControl(
                    .primary,
                    minWidth: 88,
                    minHeight: OnePlusMetrics.contentControlHeight,
                    horizontalPadding: OnePlusMetrics.contentControlHorizontalPadding
                )
        }
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(host.fittingSize.width, 184)
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, OnePlusMetrics.contentControlHeight)
    }

    func testSharedTitlebarGeometryKeepsTheRequiredTrafficLightGap() {
        XCTAssertEqual(OnePlusMetrics.titlebarHeight, 40)
        XCTAssertEqual(OnePlusMetrics.titleLeadingInset, 84)
        XCTAssertEqual(OnePlusMetrics.fixedTitleLeadingInset, 62)
        XCTAssertEqual(OnePlusMetrics.trafficLightVerticalOffset, 4)
        XCTAssertGreaterThanOrEqual(OnePlusMetrics.titleLeadingInset - 70, 12)
        XCTAssertGreaterThanOrEqual(OnePlusMetrics.fixedTitleLeadingInset - 48, 12)
    }

    func testSearchTextCellCentersItsSingleDisplayAndEditingRect() {
        let cell = OnePlusCenteredTextFieldCell(textCell: "Search name, path, or PID")
        cell.font = .systemFont(ofSize: 10.5)
        let bounds = NSRect(x: 0, y: 0, width: 240, height: 18)
        let textRect = cell.drawingRect(forBounds: bounds)

        XCTAssertEqual(textRect.midY, bounds.midY, accuracy: 0.5)
        XCTAssertGreaterThan(textRect.minY, bounds.minY)
        XCTAssertLessThan(textRect.maxY, bounds.maxY)
    }

    func testDitherTextureLoadsItsPackagedImage() {
        XCTAssertNotNil(OnePlusDitherTexture.resourceImage)
        XCTAssertEqual(OnePlusDitherTexture.resourceImage?.size, NSSize(width: 240, height: 150))
    }

    func testFixedWindowChromeReappliesSizeAndStyle() {
        let expectedSize = NSSize(width: 920, height: 680)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 700, height: 500)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: OnePlusFixedWindowChrome(contentSize: expectedSize))
        window.contentView?.layoutSubtreeIfNeeded()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))

        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.contentView?.bounds.size, expectedSize)
        XCTAssertEqual(window.frame.size, expectedSize)
        XCTAssertTrue(try XCTUnwrap(window.standardWindowButton(.zoomButton)?.isHidden))
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)?.isEnabled))
    }
}
