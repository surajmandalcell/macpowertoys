import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusPageTests: XCTestCase {
    func testFixedRegionsKeepTheirGeometryWhileRowsScroll() throws {
        let host = NSHostingView(rootView: OnePlusPage(scrolls: false) {
            PageRegionProbe("header").frame(height: 50)
        } tabs: {
            PageRegionProbe("tabs").frame(height: 36)
        } toolbar: {
            PageRegionProbe("toolbar").frame(width: 100, height: 28)
        } footer: {
            PageRegionProbe("footer").frame(width: 100, height: 22)
        } content: {
            ScrollView { Color.clear.frame(height: 3000) }
                .onePlusScrollIndicators().overlay { PageRegionProbe("rows") }
        })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for height in [CGFloat(500), 700] {
            host.frame = CGRect(x: 0, y: 0, width: 600, height: height)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            let views = descendants(host)
            func rect(_ name: String) throws -> CGRect {
                let view = try XCTUnwrap(views.first { $0.identifier?.rawValue == name })
                return view.convert(view.bounds, to: host)
            }
            let before = try ["header", "tabs", "toolbar", "footer", "rows"].map(rect)
            XCTAssertEqual(before[2].minY, 102, accuracy: 0.5)
            XCTAssertEqual(before[2].minX, 24, accuracy: 0.5)
            XCTAssertEqual(before[3].minX, 24, accuracy: 0.5)
            XCTAssertEqual(before[4].minY, 146, accuracy: 0.5)
            XCTAssertEqual(before[4].maxY, height - 62, accuracy: 0.5)
            XCTAssertEqual(before[3].maxY, height - 24, accuracy: 0.5)
            XCTAssertEqual(before[4].width, 600 - 48, accuracy: 0.5)
            let scroll = try XCTUnwrap(views.compactMap { $0 as? NSScrollView }.first)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: 800))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
            XCTAssertEqual(try ["header", "tabs", "toolbar", "footer", "rows"].map(rect), before)
        }
    }

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
                subtitleRole: .mono).onePlusDensity(density).frame(width: 600))
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

private struct PageRegionProbe: NSViewRepresentable {
    let name: String
    init(_ name: String) { self.name = name }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(name)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
