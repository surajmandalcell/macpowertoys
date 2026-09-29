import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusPageTests: XCTestCase {
    func testTitleLineStartsBelowTheEmptyWindowTitleRow() {
        XCTAssertEqual(OnePlusMetrics.contentTop, 58)
        XCTAssertEqual(OnePlusMetrics.contentGap, 16)
        XCTAssertEqual(OnePlusMetrics.contentTop - OnePlusMetrics.titleRow, 4)
        for density in OnePlusDensity.allCases {
            for style in [OnePlusTitleStyle.system, .dotMatrix] {
                let line = style.lineHeight(for: density)
                let host = NSHostingView(rootView: OnePlusPageHeader(title: "Overview", titleStyle: style) {
                    Color.clear.frame(width: 24, height: 24)
                }.onePlusDensity(density).frame(width: 600))
                XCTAssertEqual(host.fittingSize.height, 58 + line + OnePlusMetrics.pageHeaderBottom, accuracy: 0.5)
            }
        }
        let drawing = OnePlusDotGlyphs.drawing("OVERVIEW", height: OnePlusDotTitle.lineHeight, scale: 2)
        XCTAssertGreaterThanOrEqual(drawing.path.boundingRect.minY + OnePlusMetrics.contentTop, 58)
        XCTAssertLessThanOrEqual(drawing.path.boundingRect.maxY + OnePlusMetrics.contentTop, 78)
    }

    func testNamedHeadersUseTheSharedTitleTopWithoutASecondOffset() {
        for density in OnePlusDensity.allCases {
            let standard = NSHostingView(rootView: OnePlusPageHeader(title: "Storage", subtitle: "/Volumes/Data",
                subtitleRole: .mono) { EmptyView() }.onePlusDensity(density).frame(width: 600))
            let diskman = NSHostingView(rootView: OnePlusDiskmanHeader("Storage", path: "/Volumes/Data") {
                EmptyView()
            }.onePlusDensity(density).frame(width: 600))
            XCTAssertEqual(diskman.fittingSize.height, standard.fittingSize.height, accuracy: 0.5)
            let catalog = NSHostingView(rootView: OnePlusToolPageHeader(title: "Tool", subtitle: "Description") {
                Color.clear
            } actions: { EmptyView() }.onePlusDensity(density).frame(width: 600))
            XCTAssertGreaterThanOrEqual(catalog.fittingSize.height, 58 + 40 + OnePlusMetrics.pageHeaderBottom)
        }
    }
}
