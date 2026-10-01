import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusAppearanceTests: XCTestCase {
    func testAccessibilityDisplayChangesInvalidateRegisteredRoots() {
        let owner = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let host = AppearanceCountingHost(rootView: AnyView(Color.clear.onePlusAppAppearance()))
        let window = NSPanel(contentRect: .init(x: -10000, y: -10000, width: 100, height: 100),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let appearance = window.appearance
        host.needsDisplay = false
        host.displayRequests = 0
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                   object: NSWorkspace.shared)
        XCTAssertEqual(host.displayRequests, 1)
        XCTAssertEqual(window.appearance, appearance)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, owner)
    }

    func testPresentationRootsFollowAppAppearanceAndLiveChanges() throws {
        let app = NSApplication.shared
        let saved = app.appearance
        defer { app.appearance = saved }
        let popup = OnePlusPopupSession(entries: [.item(.init("Action") {})], density: .compact, initialID: nil)
        let tabs = AppearanceProbeView(), body = AppearanceProbeView(), sheet = AppearanceProbeView()
        let workspace = AppearanceProbeView()
        let roots: [(AnyView, [AppearanceProbeView])] = [
            (AnyView(OnePlusMenuPanel(tabs: { AppearanceProbe(view: tabs).frame(width: 20, height: 20) },
                                     actions: { EmptyView() }, content: {
                AppearanceProbe(view: body).frame(height: 80).background(OnePlusColor.panel)
            })), [tabs, body]),
            (AnyView(OnePlusSheet("Sheet") {
                AppearanceProbe(view: sheet).frame(height: 80).background(OnePlusColor.panel)
            }), [sheet]),
            (AnyView(OnePlusPopupMenuView(session: popup)), []),
            (AnyView(OnePlusWindowRoot(canvas: .awake, sidebar: { EmptyView() }, content: {
                AppearanceProbe(view: workspace)
            })), [workspace]),
        ]
        let owner = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for (root, probes) in roots {
            app.appearance = NSAppearance(named: .darkAqua)
            // Reproduce the diagnostic environment and status-host light override.
            let host = NSHostingView(rootView: root.environment(\.colorScheme, .light))
            host.appearance = NSAppearance(named: .aqua)
            let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 356, height: 200),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            defer { window.contentView = nil }
            for name: NSAppearance.Name? in [.darkAqua, .aqua, .darkAqua, nil] {
                app.appearance = name.flatMap(NSAppearance.init(named:))
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                host.layoutSubtreeIfNeeded()
                let expected = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
                XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), expected)
                XCTAssertEqual(host.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), expected)
                for probe in probes {
                    XCTAssertEqual(probe.scheme, expected == .darkAqua ? .dark : .light)
                    XCTAssertEqual(probe.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), expected)
                }
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let surface = try XCTUnwrap(bitmap.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
                let brightness = (surface.redComponent + surface.greenComponent + surface.blueComponent) / 3
                XCTAssertEqual(brightness < 0.5, expected == .darkAqua, "Rendered surface must follow the app")
                XCTAssertFalse(window.isVisible)
            }
        }
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, owner)
    }
}

private final class AppearanceProbeView: NSView {
    var scheme: ColorScheme?
}

private final class AppearanceCountingHost: NSHostingView<AnyView> {
    var displayRequests = 0
    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue { displayRequests += 1 }
            super.needsDisplay = newValue
        }
    }
}

private struct AppearanceProbe: NSViewRepresentable {
    let view: AppearanceProbeView
    func makeNSView(context: Context) -> AppearanceProbeView { view }
    func updateNSView(_ view: AppearanceProbeView, context: Context) { view.scheme = context.environment.colorScheme }
}
