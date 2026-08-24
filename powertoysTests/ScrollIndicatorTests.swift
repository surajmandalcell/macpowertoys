import AppKit
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class ScrollIndicatorTests: XCTestCase {
    func testConfiguresOverlayAutohidingMiniScrollers() throws {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false

        scrollView.configureThinScrollIndicators()

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(try XCTUnwrap(scrollView.verticalScroller).controlSize, .mini)
        XCTAssertEqual(try XCTUnwrap(scrollView.horizontalScroller).controlSize, .mini)
    }

    func testSwiftUIModifierConfiguresItsScrollView() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: ScrollView {
                VStack {
                    ForEach(0..<40) { index in
                        Text("Row \(index)")
                    }
                }
            }
            .thinScrollIndicators()
            .frame(width: 240, height: 120)
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        let scrollView = try XCTUnwrap(firstScrollView(in: hostingView))
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(
            try XCTUnwrap(scrollView.verticalScroller).controlSize,
            .mini,
            hierarchyDescription(hostingView)
        )
    }

    func testEverySwiftUIScrollSurfaceUsesThinIndicators() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("powertoys", isDirectory: true)
        let swiftFiles = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )?.allObjects as? [URL]
        ).filter { $0.pathExtension == "swift" }
        let sources = try swiftFiles.map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }
        let surfaceCount = sources.reduce(0) {
            $0 + $1.matches(
                of: #/(?m)^\s*(?:return\s+)?(?:ScrollView|Form|TextEditor|List|Table)\s*[({]/#
            ).count
        }
        let modifierCount = sources.reduce(0) {
            $0 + $1.matches(of: #/\.thinScrollIndicators\(\)/#).count
        }

        XCTAssertEqual(surfaceCount, modifierCount)
        XCTAssertFalse(sources.contains { $0.contains("showsIndicators: false") })
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap(firstScrollView(in:)).first
    }

    private func hierarchyDescription(_ view: NSView, depth: Int = 0) -> String {
        ([String(repeating: "  ", count: depth) + String(describing: type(of: view))]
            + view.subviews.map { hierarchyDescription($0, depth: depth + 1) })
            .joined(separator: "\n")
    }
}
