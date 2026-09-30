import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusPageTests: XCTestCase {
    func testTabRuleStaysInsideItsFrameOnThePageGutters() throws {
        for density in OnePlusDensity.allCases {
            let host = NSHostingView(rootView: OnePlusPage(scrolls: false) {
                EmptyView()
            } tabs: {
                OnePlusTabStrip(tabs: [OnePlusTab<String>](), selection: .constant("home"))
            } content: {
                PageRegionProbe("card").frame(height: 40)
            }.background(OnePlusColor.window).onePlusDensity(density))
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 600, height: 200),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let card = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "card" })
            XCTAssertEqual(card.convert(card.bounds, to: host).minY, 36 + 16, accuracy: 0.5)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
                try XCTUnwrap(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
            }
            XCTAssertEqual(try color(density.gutter + 10, 35).redComponent, 43.0 / 255, accuracy: 0.01)
            XCTAssertEqual(try color(density.gutter - 2, 35).redComponent, 22.0 / 255, accuracy: 0.01)
            XCTAssertEqual(try color(density.gutter + 10, 36).redComponent, 22.0 / 255, accuracy: 0.01)
        }
    }
    func testFirstContentStartsSixteenPointsAfterHeaderBlock() throws {
        let header = OnePlusPageHeader(title: "Processes", subtitle: "Live system activity")
        let headerHeight = NSHostingView(rootView: header.frame(width: 600)).fittingSize.height
            - OnePlusMetrics.pageHeaderBottom
        let host = NSHostingView(rootView: OnePlusPage(scrolls: false) {
            header
        } content: {
            PageRegionProbe("content").frame(height: 40)
        })
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
        host.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "content" })
        XCTAssertEqual(content.convert(content.bounds, to: host).minY - headerHeight,
                       OnePlusMetrics.contentGap, accuracy: 0.5)
    }

    func testFixedPageReservesItsDensityGutterBelowTheRowViewport() throws {
        for density in OnePlusDensity.allCases {
        let host = NSHostingView(rootView: OnePlusPage(scrolls: false) {
            PageRegionProbe("header").frame(height: 50)
        } content: {
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 900)
                    PageRegionProbe("last-row").frame(height: 40)
                }
            }
            .onePlusScrollIndicators()
            .overlay { PageRegionProbe("scroll-frame") }
        }.onePlusDensity(density))
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 600, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        let views = descendants(host)
        let scrollFrame = try XCTUnwrap(views.first { $0.identifier?.rawValue == "scroll-frame" })
        let scroll = try XCTUnwrap(views.compactMap { $0 as? NSScrollView }.first)
        XCTAssertEqual(scrollFrame.convert(scrollFrame.bounds, to: host).maxY, host.bounds.maxY - density.gutter, accuracy: 0.5)
        XCTAssertEqual(scroll.contentInsets.bottom, 0, accuracy: 0.5)
        }
    }

    func testConditionalEmptyFooterDoesNotAddAContentGap() throws {
        for showsNotice in [false, true] {
            let host = NSHostingView(rootView: OnePlusPage(scrolls: false) {
                Color.clear.frame(height: 50)
            } footer: {
                if showsNotice { PageRegionProbe("footer").frame(height: 44) }
            } content: {
                PageRegionProbe("table")
            })
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
            host.layoutSubtreeIfNeeded()
            let table = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "table" })
            XCTAssertEqual(table.convert(table.bounds, to: host).maxY,
                           500 - 24 - (showsNotice ? 60 : 0), accuracy: 0.5)
        }
    }

    func testAppletBodyAndFixedRegionsUseSixteenPointGaps() throws {
        for showsTabs in [false, true] {
            let host = NSHostingView(rootView: OnePlusPage(scrolls: false, layout: .applet) {
                OnePlusAppletTitlebar(title: "Applet") { EmptyView() }
            } tabs: {
                if showsTabs {
                    OnePlusTabStrip(tabs: [.init("history", "History")], selection: .constant("history"), layout: .applet)
                }
            } toolbar: {
                PageRegionProbe("toolbar").frame(height: 28)
            } footer: {
                PageRegionProbe("footer").frame(height: 24)
            } content: {
                PageRegionProbe("rows")
            })
            host.frame = CGRect(x: 0, y: 0, width: 420, height: 460)
            host.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            func rect(_ name: String) throws -> CGRect {
                let view = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == name })
                return view.convert(view.bounds, to: host)
            }
            let toolbar = try rect("toolbar"), rows = try rect("rows"), footer = try rect("footer")
            XCTAssertEqual(toolbar.minY, showsTabs ? 92 : 56, accuracy: 0.5)
            XCTAssertEqual(rows.minY - toolbar.maxY, 16, accuracy: 0.5)
            XCTAssertEqual(footer.minY - rows.maxY, 16, accuracy: 0.5)
            XCTAssertEqual(rows.minX, 16, accuracy: 0.5)
            XCTAssertEqual(rows.maxX, 404, accuracy: 0.5)
        }
    }

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

@MainActor private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
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
