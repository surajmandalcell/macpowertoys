import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusMenuSizingTests: XCTestCase {
    func testOfflineHostReadingsUseMutedInkInBothAppearances() throws {
        for name in [NSAppearance.Name.darkAqua, .aqua] {
            for online in [false, true] {
                let host = NSHostingView(rootView: OnePlusMenuItemCard(
                    "Sample host", systemImage: "server.rack", status: online ? "Connected" : "Offline", online: online,
                    metrics: [.init("CPU", systemImage: "cpu", value: "—"),
                              .init("RAM", systemImage: "memorychip", value: "—"),
                              .init("Network", systemImage: "arrow.up.arrow.down", value: "—")]
                ) { Text("No disk data") } actions: { EmptyView() })
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 338, height: 109),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                let appearance = try XCTUnwrap(NSAppearance(named: name))
                window.appearance = appearance
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height, 109, accuracy: 0.01)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
                var expected: CGFloat = 0, opposite: CGFloat = 0
                appearance.performAsCurrentDrawingAppearance {
                    expected = NSColor(online ? OnePlusColor.ink : OnePlusColor.muted)
                        .usingColorSpace(.sRGB)!.redComponent
                    opposite = NSColor(online ? OnePlusColor.muted : OnePlusColor.ink)
                        .usingColorSpace(.sRGB)!.redComponent
                }
                for column in 0..<3 {
                    var reading: CGFloat = name == .darkAqua ? 0 : 1
                    for x in Int((CGFloat(column) * 113 + 7) * scale)..<Int((CGFloat(column) * 113 + 50) * scale) {
                        for y in Int(39 * scale)..<Int(51 * scale) {
                            let ink = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent
                            reading = name == .darkAqua ? max(reading, ink) : min(reading, ink)
                        }
                    }
                    // Text antialiasing blends the token with the panel fill.
                    XCTAssertLessThan(abs(reading - expected), abs(reading - opposite),
                                      "Reading ink must follow the host's availability")
                }
            }
        }
    }

    func testEmptyFixedRegionBuildersDoNotReserveGaps() {
        let host = NSHostingView(rootView: OnePlusMenuPanelShell(
            maximumHeight: 600,
            tabs: OnePlusMenuTabStrip(tabs: [.init("home", "Home", systemImage: "house")], selection: .constant("home")),
            actions: OnePlusMenuOpenApp {},
            toolbar: { AnyView(EmptyView()) }, footer: { AnyView(EmptyView()) },
            content: { Color.clear.frame(height: 120) }
        ).environment(\.onePlusIsVisible, true))
        host.frame.size = NSSize(width: 356, height: 600)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, 48 + 11 + 120, accuracy: 0.5)
    }
    func testFixedRegionsStayOutsideTheCappedBodyScroller() throws {
        let model = MenuSizingModel()
        let toolbar = NSView(), footer = NSView()
        let host = NSHostingView(rootView: OnePlusMenuPanelShell(
            maximumHeight: 600,
            tabs: OnePlusMenuTabStrip(tabs: [.init("home", "Home", systemImage: "house")], selection: .constant("home")),
            actions: OnePlusMenuOpenApp {},
            toolbar: { AnyView(MenuRegionMarker(view: toolbar).frame(height: 40)) },
            footer: { AnyView(MenuRegionMarker(view: footer).frame(height: 24)) },
            content: { MenuBody(model: model) }
        ).environment(\.onePlusIsVisible, true))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 356, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        func layout() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
        }
        layout()
        XCTAssertNil(toolbar.enclosingScrollView)
        XCTAssertNil(footer.enclosingScrollView)
        XCTAssertEqual(host.fittingSize.height, 600, accuracy: 0.5)
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap(findScroll).first
        }
        let scroll = try XCTUnwrap(findScroll(host))
        XCTAssertEqual(scroll.frame.height, 600 - 48 - 48 - 37, accuracy: 0.5)
        let toolbarRect = toolbar.convert(toolbar.bounds, to: host)
        let footerRect = footer.convert(footer.bounds, to: host)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        layout()
        XCTAssertEqual(toolbar.convert(toolbar.bounds, to: host), toolbarRect)
        XCTAssertEqual(footer.convert(footer.bounds, to: host), footerRect)
        model.height = 120
        layout()
        XCTAssertEqual(host.fittingSize.height, 48 + 48 + 120 + 37, accuracy: 0.5)
        model.height = 0
        layout()
        XCTAssertEqual(host.fittingSize.height, 48 + 48 + 37, accuracy: 0.5)
    }
    func testTabSwitchCommitsOnlyTheDestinationHeight() {
        let model = MenuSizingModel()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 356, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        var committedHeights: [CGFloat] = []
        let host = NSHostingView(rootView: MenuSizingContent(model: model)
            .onOnePlusMenuHeightChange { [weak window] height in
                committedHeights.append(height)
                if window?.contentView?.frame.height != height {
                    window?.setContentSize(NSSize(width: 356, height: height))
                }
            })
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        for height in [CGFloat(120), 900, 400, 0, 80, 900, 120] {
            committedHeights.removeAll()
            model.height = height
            host.layoutSubtreeIfNeeded()
            let expected = min(600, 48 + 11 + height)
            XCTAssertEqual(host.fittingSize.width, 356, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.height, expected, accuracy: 0.5)
            XCTAssertFalse(committedHeights.isEmpty)
            XCTAssertTrue(committedHeights.allSatisfy { abs($0 - expected) < 0.5 }, "Intermediate heights: \(committedHeights)")
            XCTAssertEqual(window.contentView!.frame.height, expected, accuracy: 0.5)
        }
    }

    func testExplicitMaximumCannotExceedTheVisibleScreenCap() {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let host = NSHostingView(rootView: OnePlusMenuPanelShell(
            maximumHeight: screenHeight * 2,
            tabs: OnePlusMenuTabStrip(tabs: [.init("home", "Home", systemImage: "house")],
                                      selection: .constant("home")),
            actions: OnePlusMenuOpenApp {},
            content: { Color.clear.frame(height: screenHeight * 3) }
        ).environment(\.onePlusIsVisible, true))
        host.frame.size = NSSize(width: 356, height: 600)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(host.fittingSize.height, screenHeight * 0.9, accuracy: 0.5)
    }

    func testClosedPanelKeepsItsLayoutMounted() {
        let counter = MenuContentCounter()
        let hidden = NSHostingView(rootView: OnePlusMenuPanelShell(
            maximumHeight: 600, tabs: EmptyView(), actions: EmptyView(),
            toolbar: { AnyView(counter.content()) }, footer: { AnyView(counter.content()) },
            content: { counter.content() }
        ).environment(\.onePlusIsVisible, false))
        hidden.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(counter.buildCount, 0)

        let visible = NSHostingView(rootView: OnePlusMenuPanelShell(
            maximumHeight: 600, tabs: EmptyView(), actions: EmptyView(),
            content: { counter.content() }
        ).environment(\.onePlusIsVisible, true))
        visible.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(counter.buildCount, 0)
    }
}

private struct MenuRegionMarker: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct MenuBody: View {
    @ObservedObject var model: MenuSizingModel
    var body: some View { Color.clear.frame(height: model.height) }
}

@MainActor
private final class MenuSizingModel: ObservableObject {
    @Published var height: CGFloat = 900
}

private struct MenuSizingContent: View {
    @ObservedObject var model: MenuSizingModel
    var body: some View {
        OnePlusMenuPanelShell(
            maximumHeight: 600,
            tabs: OnePlusMenuTabStrip(tabs: [.init("home", "Home", systemImage: "house")],
                                      selection: .constant("home")),
            actions: OnePlusMenuOpenApp {},
            content: { Color.clear.frame(height: model.height) }
        ).environment(\.onePlusIsVisible, true)
    }
}

@MainActor private final class MenuContentCounter {
    var buildCount = 0
    func content() -> some View {
        buildCount += 1
        return Color.clear.frame(height: 80)
    }
}
