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
        XCTAssertGreaterThanOrEqual(OnePlusMetrics.titleLeadingInset - 70, 12)
    }
}
