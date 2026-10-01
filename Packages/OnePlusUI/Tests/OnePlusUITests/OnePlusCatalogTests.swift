import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusCatalogTests: XCTestCase {
    func testSummaryUsesSixteenPointNativeBaselinePitch() {
        var pitch: CGFloat = 0
        let host = NSHostingView(rootView: CatalogBaselineProbe(measured: { pitch = $0 }) {
            Text("First line\nSecond line").font(OnePlusCatalogMetrics.summaryFont)
                .lineSpacing(OnePlusCatalogMetrics.summaryLineSpacing)
                .lineLimit(2, reservesSpace: true)
        })
        _ = host.fittingSize
        XCTAssertEqual(pitch, 16, accuracy: 0.01)
    }
}

private struct CatalogBaselineProbe: Layout {
    let measured: (CGFloat) -> Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let dimensions = subviews[0].dimensions(in: proposal)
        measured(dimensions[.lastTextBaseline] - dimensions[.firstTextBaseline])
        return CGSize(width: dimensions.width, height: dimensions.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}
