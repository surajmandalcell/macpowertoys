import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusSelectLayoutTests: XCTestCase {
    func testFlexibleSelectFollowsItsColumnAndFixedSelectKeepsItsWidth() throws {
        for density in OnePlusDensity.allCases {
            for columnWidth in [CGFloat(100), 220] {
                for width in [CGFloat?.none, 80] {
                    let host = NSHostingView(rootView: OnePlusSelect(
                        choices: [("percent", "Percentage")], selection: .constant("percent"),
                        width: width, accessibilityLabel: "Format"
                    ).onePlusDensity(density).frame(width: columnWidth, height: 44))
                    host.frame = CGRect(x: 0, y: 0, width: columnWidth, height: 44)
                    host.layoutSubtreeIfNeeded()
                    let anchor = try XCTUnwrap(descendants(host).first { $0 is OnePlusPopupAnchorView })
                    XCTAssertEqual(anchor.bounds.width, width ?? columnWidth, accuracy: 0.5)
                    XCTAssertEqual(anchor.bounds.height, density.controlHeight, accuracy: 0.5)
                }
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
