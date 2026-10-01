import AppKit
import Observation
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusPageTests: XCTestCase {
    func testSelectedTabUnderlineSurvivesInitialEntryAndTabChanges() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let state = TabEntryState()
            let host = NSHostingView(rootView: TabEntryPage(state: state))
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1240, height: 840),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            for selection in ["tasks", "history", "tasks"] {
                state.selection = selection
                state.visible = true
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
                var underline: [CGPoint] = []
                for y in 94..<100 { for x in 224..<350 {
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(CGFloat(x) * scale),
                        y: Int(CGFloat(y) * scale))?.usingColorSpace(.sRGB))
                    if color.redComponent > 0.6 && color.redComponent > color.greenComponent * 1.6
                        && color.redComponent > color.blueComponent * 1.6 {
                        underline.append(CGPoint(x: x, y: y))
                    }
                } }
                XCTAssertEqual(underline.map(\.y).min(), 96, "Initial entry and tab changes must paint the 2pt underline")
                XCTAssertEqual(underline.map(\.y).max(), 97)
                XCTAssertEqual(underline.map(\.x).min(), selection == "tasks" ? 224 : 278)
                XCTAssertEqual(underline.map(\.x).max(), selection == "tasks" ? 255 : 318)
                XCTAssertEqual(underline.count, selection == "tasks" ? 64 : 82)
            }
        }
    }

    func testPairedPanelsKeepTheirNaturalHeightAndTopAlignment() throws {
        let host = NSHostingView(rootView: HStack(alignment: .top, spacing: 16) {
            OnePlusPanel {
                VStack(spacing: 0) {
                    OnePlusCardHeader("Sync engine")
                    ForEach(0..<3) { _ in
                        OnePlusSettingRow("Setting", caption: "Description") { Text("On") }
                    }
                }
            }.overlay { PageRegionProbe("short-card") }
            OnePlusPanel {
                VStack(spacing: 0) {
                    OnePlusCardHeader("Transfers")
                    ForEach(0..<3) { _ in
                        OnePlusSettingRow("Setting", caption: "Description") { Text("On") }
                    }
                    OnePlusSettingRow("Default operation") { Text("Copy") }
                }
            }.overlay { PageRegionProbe("tall-card") }
        }.fixedSize(horizontal: false, vertical: true).frame(maxHeight: .infinity, alignment: .top))
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 500)
        host.layoutSubtreeIfNeeded()
        let short = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "short-card" })
        let tall = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "tall-card" })
        let shortFrame = short.convert(short.bounds, to: host)
        let tallFrame = tall.convert(tall.bounds, to: host)
        XCTAssertEqual(shortFrame.height, 208, accuracy: 0.01)
        XCTAssertEqual(tallFrame.height, 252, accuracy: 0.01)
        XCTAssertEqual(shortFrame.minY, tallFrame.minY, accuracy: 0.01)
    }

    func testPanelsWithFlexibleTablesAndInspectorsStillFillFixedPages() throws {
        let host = NSHostingView(rootView: OnePlusPage(scrolls: false) {
            Color.clear.frame(height: 50)
        } content: {
            HStack(alignment: .top, spacing: 16) {
                OnePlusPanel {
                    OnePlusCardHeader("Records")
                    OnePlusNativeTable(columns: [.init("Name", width: 300)],
                        rows: [.init(id: "1", cells: ["Record"], symbol: "doc")], selection: .constant([]),
                        sort: { _, _ in }, open: { _ in }, preview: { _ in }, remove: { _ in }, actions: { _ in [] })
                }.overlay { PageRegionProbe("table-card") }
                OnePlusPanel {
                    OnePlusCardHeader("Inspector")
                    VStack {
                        Text("Record details")
                        Spacer(minLength: 0)
                    }
                }.frame(width: 220).overlay { PageRegionProbe("inspector-card") }
            }
        })
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 800, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        for name in ["table-card", "inspector-card"] {
            let view = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == name })
            let frame = view.convert(view.bounds, to: host)
            XCTAssertEqual(frame.minY, 66, accuracy: 0.01)
            XCTAssertEqual(frame.maxY, 476, accuracy: 0.01)
        }
    }

    func testTabCountSlotStaysThreeDigitsWhileDataArrives() {
        let tab = OnePlusTab("largest", "Largest files", count: 0)
        let widths = [0, 1, 99, 100].map { count in
            NSHostingView(rootView: OnePlusNavBadge(count, minimumDigits: tab.countDigits)).fittingSize.width
        }
        for width in widths { XCTAssertEqual(width, widths[0], accuracy: 0.5) }
        XCTAssertGreaterThan(NSHostingView(rootView: OnePlusNavBadge(10000, minimumDigits: 3)).fittingSize.width, widths[0])
    }
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
            let background = try color(300, 100).redComponent
            XCTAssertGreaterThan(try color(density.gutter + 10, 35).redComponent, background + 0.02)
            XCTAssertEqual(try color(density.gutter - 2, 35).redComponent, background, accuracy: 0.01)
            XCTAssertEqual(try color(density.gutter + 10, 36).redComponent, background, accuracy: 0.01)
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

    func testTitleLineStartsAtTheTrafficLightTopEdge() {
        XCTAssertEqual(OnePlusMetrics.contentTop, 16)
        XCTAssertEqual(OnePlusMetrics.contentGap, 16)
        XCTAssertEqual(OnePlusMetrics.titleRow, 54)
        for density in OnePlusDensity.allCases {
            for style in [OnePlusTitleStyle.system, .dotMatrix] {
                let line = style.lineHeight(for: density)
                let host = NSHostingView(rootView: OnePlusPageHeader(title: "Overview", titleStyle: style) {
                    PageRegionProbe("action").frame(width: 24, height: 24)
                }.onePlusDensity(density).frame(width: 600))
                XCTAssertEqual(host.fittingSize.height, 16 + line + OnePlusMetrics.pageHeaderBottom, accuracy: 0.5)
                host.frame.size = host.fittingSize
                host.layoutSubtreeIfNeeded()
                let action = descendants(host).first { $0.identifier?.rawValue == "action" }!
                XCTAssertEqual(action.convert(action.bounds, to: host).midY, 16 + line / 2, accuracy: 1)
            }
        }
        let drawing = OnePlusDotGlyphs.drawing("OVERVIEW", height: OnePlusDotTitle.lineHeight, scale: 2)
        XCTAssertGreaterThanOrEqual(drawing.path.boundingRect.minY + OnePlusMetrics.contentTop, 16)
        XCTAssertLessThanOrEqual(drawing.path.boundingRect.maxY + OnePlusMetrics.contentTop, 36)
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
            XCTAssertGreaterThanOrEqual(catalog.fittingSize.height, 16 + 40 + OnePlusMetrics.pageHeaderBottom)
        }
    }
}

@MainActor @Observable
private final class TabEntryState {
    var visible = false
    var selection = "tasks"
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

@MainActor
private struct TabEntryPage: View {
    let state: TabEntryState
    var body: some View {
        OnePlusWindowRoot(canvas: .systemCare) {
            Color.clear
        } content: {
            if state.visible {
                OnePlusPage(scrolls: false) {
                    OnePlusPageHeader(title: "Maintenance", subtitle: "Run advanced tasks in Terminal.")
                } tabs: {
                    OnePlusTabStrip(tabs: [.init("tasks", "Tasks"), .init("history", "History")],
                        selection: Binding(get: { state.selection }, set: { state.selection = $0 })) {
                        if state.selection == "history" { Button("Refresh") {} }
                    }
                } content: { Text("Mole") }
            }
        }.buttonStyle(OnePlusButtonStyle())
    }
}
