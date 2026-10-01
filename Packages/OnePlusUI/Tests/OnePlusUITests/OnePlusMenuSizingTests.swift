import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusMenuSizingTests: XCTestCase {
    func testVisitedTabRetainsControlStateAndStopsHiddenWork() throws {
        let selection = MenuTabSelection()
        let probe = MenuTabProbe()
        let host = NSHostingView(rootView: MenuTabContent(selection: selection, probe: probe))
        host.frame.size = NSSize(width: 356, height: 600)
        func layout() {
            autoreleasepool {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                host.layoutSubtreeIfNeeded()
            }
        }
        layout()
        let first = try XCTUnwrap(probe.markers[0])
        first.count.wrappedValue = 7
        layout()
        XCTAssertEqual(first.count.wrappedValue, 7)
        selection.tab = 1
        layout()
        XCTAssertEqual(probe.liveTabs, [1])
        selection.tab = 0
        layout()
        XCTAssertEqual(probe.markers[0]?.count.wrappedValue, 7)
        XCTAssertEqual(probe.liveTabs, [0])
        selection.visible = false
        layout()
        XCTAssertTrue(probe.liveTabs.isEmpty)
        weak var discardedTab = probe.markers[1]
        probe.markers.removeValue(forKey: 1)
        layout()
        XCTAssertNil(discardedTab, "Closing retains only the currently measured tab host.")
        selection.visible = true
        layout()
        XCTAssertEqual(probe.liveTabs, [0])
        XCTAssertEqual(probe.markers[0]?.count.wrappedValue, 7, "The warm current tab keeps its state.")
        XCTAssertEqual(host.fittingSize.height, 48 + 11 + 120, accuracy: 0.5)
    }

    func testOfflineHostReadingsUseMutedInkInBothAppearances() throws {
        for name in [NSAppearance.Name.darkAqua, .aqua] {
            var coverageByState: [[CGFloat]] = []
            for online in [false, true] {
                var coverages: [CGFloat] = []
                let card = { (value: String) in
                    OnePlusMenuItemCard(
                        "Sample host", systemImage: "server.rack", status: online ? "Connected" : "Offline", online: online,
                        metrics: [.init("CPU", systemImage: "cpu", value: value),
                                  .init("RAM", systemImage: "memorychip", value: value),
                                  .init("Network", systemImage: "arrow.up.arrow.down", value: value)]
                    ) { Text("No disk data") } actions: { EmptyView() }
                }
                let host = NSHostingView(rootView: card("—"))
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 338, height: 109),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                let appearance = try XCTUnwrap(NSAppearance(named: name))
                window.appearance = appearance
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height, 109, accuracy: 0.01)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                host.rootView = card(" ")
                host.layoutSubtreeIfNeeded()
                let empty = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: empty)
                var expected: CGFloat = 0, fill: CGFloat = 0
                appearance.performAsCurrentDrawingAppearance {
                    expected = NSColor(online ? OnePlusColor.ink : OnePlusColor.muted).usingColorSpace(.sRGB)!.redComponent
                    fill = NSColor(OnePlusColor.panel).usingColorSpace(.sRGB)!.redComponent
                }
                for column in 0..<3 {
                    var reading: CGFloat = name == .darkAqua ? 0 : 1
                    var valuePixels = 0
                    // Measure value paint against a blank glyph with the same native line box.
                    // This follows horizontal metadata without sampling labels.
                    for x in (column * bitmap.pixelsWide / 3)..<((column + 1) * bitmap.pixelsWide / 3) {
                        for y in 0..<bitmap.pixelsHigh {
                            let ink = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent
                            let background = try XCTUnwrap(empty.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent
                            guard abs(ink - background) > 0.015 else { continue }
                            valuePixels += 1
                            reading = name == .darkAqua ? max(reading, ink) : min(reading, ink)
                        }
                    }
                    XCTAssertGreaterThan(valuePixels, 0)
                    // Compare coverage of the same glyph in both states. Antialiased ink can
                    // be closer to a different token even when the intended ink is correct.
                    let coverage = abs(reading - fill) / abs(expected - fill)
                    XCTAssertGreaterThan(coverage, 0.4)
                    XCTAssertLessThanOrEqual(coverage, 1.08)
                    coverages.append(coverage)
                }
                coverageByState.append(coverages)
            }
            // Native text contrast adjustment changes coverage by up to 6%,
            // well below the difference produced by using either ink for both states.
            for column in 0..<3 {
                XCTAssertEqual(coverageByState[0][column], coverageByState[1][column], accuracy: 0.06,
                               "Reading ink must follow availability at the same native glyph coverage")
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

    func testSuppliedScreenCapIsUsedBeforeFirstMeasurement() {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        for cap in [CGFloat(400), screenHeight * 2] {
            var heights: [CGFloat] = []
            let host = NSHostingView(rootView: OnePlusMenuPanelShell(
                maximumHeight: cap, tabs: EmptyView(), actions: EmptyView(),
                content: { Color.clear.frame(height: screenHeight * 3) }
            ).onOnePlusMenuHeightChange { heights.append($0) })
            host.frame.size = NSSize(width: 356, height: cap)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.height, cap, accuracy: 0.5)
            XCTAssertFalse(heights.isEmpty)
            XCTAssertTrue(heights.allSatisfy { abs($0 - cap) < 0.5 }, "First heights: \(heights)")
        }
    }

    func testAttachedScreenSuppliesTheInitialFallbackCap() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.visibleFrame.height != NSScreen.main?.visibleFrame.height }
                                   ?? NSScreen.screens.last)
        let window = MenuScreenWindow(screen: screen)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: OnePlusMenuPanelShell(
            maximumHeight: nil, tabs: EmptyView(), actions: EmptyView(),
            content: { Color.clear.frame(height: 10_000) }
        ))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expected = try XCTUnwrap(window.screen).visibleFrame.height * OnePlusMenuMetrics.heightFraction
        XCTAssertEqual(host.fittingSize.height, expected, accuracy: 0.5)
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

private final class MenuScreenWindow: NSWindow {
    let attachedScreen: NSScreen
    init(screen: NSScreen) {
        attachedScreen = screen
        super.init(contentRect: NSRect(x: -10000, y: -10000, width: 356, height: 300),
                   styleMask: .borderless, backing: .buffered, defer: false)
    }
    override var screen: NSScreen? { attachedScreen }
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

@MainActor private final class MenuTabSelection: ObservableObject {
    @Published var tab = 0
    @Published var visible = true
}
@MainActor private final class MenuTabProbe {
    var markers: [Int: MenuTabMarker.View] = [:]
    var liveTabs = Set<Int>()
}
private struct MenuTabContent: View {
    @ObservedObject var selection: MenuTabSelection
    let probe: MenuTabProbe
    var body: some View {
        OnePlusMenuPanelShell(maximumHeight: 600, contentID: selection.tab,
                             tabs: EmptyView(), actions: EmptyView()) {
            if selection.tab == 0 {
                MenuStatefulTab(tab: 0, probe: probe).frame(height: 120)
            } else {
                MenuStatefulTab(tab: 1, probe: probe).frame(height: 900)
            }
        }.environment(\.onePlusIsVisible, selection.visible)
    }
}
private struct MenuStatefulTab: View {
    let tab: Int
    let probe: MenuTabProbe
    @State private var count = 0
    @Environment(\.onePlusIsVisible) private var visible
    var body: some View {
        MenuTabMarker(tab: tab, count: $count, probe: probe)
            .task(id: visible) {
                guard visible else { return }
                probe.liveTabs.insert(tab)
                defer { probe.liveTabs.remove(tab) }
                do { try await Task.sleep(for: .seconds(60)) } catch {}
            }
    }
}
private struct MenuTabMarker: NSViewRepresentable {
    let tab: Int
    @Binding var count: Int
    let probe: MenuTabProbe
    func makeNSView(context: Context) -> View {
        let view = View(count: $count)
        probe.markers[tab] = view
        return view
    }
    func updateNSView(_ view: View, context: Context) { view.count = $count }
    final class View: NSView {
        var count: Binding<Int>
        init(count: Binding<Int>) { self.count = count; super.init(frame: .zero) }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    }
}
