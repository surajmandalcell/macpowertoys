import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusMenuSizingTests: XCTestCase {
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
    func testPanelShrinksAfterSwitchingFromLongToShortContent() {
        let model = MenuSizingModel()
        let host = NSHostingView(rootView: MenuSizingContent(model: model))
        host.frame.size = NSSize(width: 356, height: 600)
        for height in [CGFloat(900), 120, 400, 0, 80] {
            model.height = height
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 356, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.height, min(600, 48 + 11 + height), accuracy: 0.5)
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

    func testClosedPanelDoesNotConstructItsContent() {
        let counter = MenuContentCounter()
        let hidden = NSHostingView(rootView: OnePlusMenuPanelShell(
            maximumHeight: 600, tabs: EmptyView(), actions: EmptyView(),
            toolbar: { AnyView(counter.content()) }, footer: { AnyView(counter.content()) },
            content: { counter.content() }
        ).environment(\.onePlusIsVisible, false))
        hidden.layoutSubtreeIfNeeded()
        XCTAssertEqual(counter.buildCount, 0)

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
