import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusActionMenuTests: XCTestCase {
    func testExistingSwiftUICommandsKeepActionsDisabledStateAndGroups() throws {
        var opened = false
        var copied = false
        let entries = OnePlusHostedActionMenu.entries(Group {
            Button("Open") { opened = true }
            Button("Unavailable") {}.disabled(true)
            Toggle("Selected", isOn: .constant(true))
            Divider()
            Menu("Results") { Button("Copy") { copied = true } }
        })
        let items = entries.compactMap(\.item)
        XCTAssertEqual(items.map(\.title), ["Open", "Unavailable", "Selected", "Copy"])
        XCTAssertFalse(items[1].isEnabled)
        XCTAssertTrue(items[2].isSelected)
        XCTAssertTrue(items[3].isEnabled)
        XCTAssertTrue(entries.contains { if case .section(_, "Results") = $0 { true } else { false } })
        XCTAssertTrue(entries.contains { if case .separatorItem = $0 { true } else { false } })
        items[0].action()
        items[3].action()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertTrue(opened)
        XCTAssertTrue(copied)
    }
}
