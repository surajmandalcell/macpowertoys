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
        let host = NSHostingView(rootView: OnePlusMenuPanel(maximumHeight: screenHeight * 2) {
            OnePlusMenuTabStrip(tabs: [.init("home", "Home", systemImage: "house")], selection: .constant("home"))
        } actions: {
            OnePlusMenuOpenApp {}
        } content: {
            Color.clear.frame(height: screenHeight * 3)
        })
        host.frame.size = NSSize(width: 356, height: 600)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(host.fittingSize.height, screenHeight * 0.9, accuracy: 0.5)
    }
}

@MainActor
private final class MenuSizingModel: ObservableObject {
    @Published var height: CGFloat = 900
}

private struct MenuSizingContent: View {
    @ObservedObject var model: MenuSizingModel
    var body: some View {
        OnePlusMenuPanel(maximumHeight: 600) {
            OnePlusMenuTabStrip(tabs: [.init("home", "Home", systemImage: "house")], selection: .constant("home"))
        } actions: {
            OnePlusMenuOpenApp {}
        } content: {
            Color.clear.frame(height: model.height)
        }
    }
}
