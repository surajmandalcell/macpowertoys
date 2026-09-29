import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusMenuSizingTests: XCTestCase {
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
