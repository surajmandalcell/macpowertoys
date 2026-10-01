import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusNativeInputTests: XCTestCase {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], window: NSWindow? = nil) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: window?.windowNumber ?? 0, context: nil,
                        characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: code)!
    }

    func testActionKeysPassThroughUnlessPlainAndHandled() {
        let table = StorageTable()
        var calls: [UInt16] = []
        table.keyAction = { calls.append($0); return true }
        for code: UInt16 in [36, 76, 49, 51, 117] {
            for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
                XCTAssertFalse(table.handleActionKey(key(code, flags: flags)))
            }
            XCTAssertTrue(table.handleActionKey(key(code, flags: [.numericPad, .function])))
        }
        XCTAssertEqual(calls, [36, 76, 49, 51, 117])
        table.keyAction = { _ in false }
        XCTAssertFalse(table.handleActionKey(key(49)))
        table.keyAction = nil
        XCTAssertFalse(table.handleActionKey(key(36)))
        XCTAssertFalse(table.handleActionKey(key(125)))
    }

    func testPopupKeysBelongToTheirWindowAndSupportedModifiers() {
        let parent = NSWindow(), popup = NSWindow(), other = NSWindow()
        for code: UInt16 in [126, 125, 36, 76, 53] {
            XCTAssertNotNil(OnePlusPopupPresenter.popupKey(for: key(code)))
            for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
                XCTAssertNil(OnePlusPopupPresenter.popupKey(for: key(code, flags: flags)))
            }
        }
        XCTAssertNotNil(OnePlusPopupPresenter.popupKey(for: key(0, flags: .shift)))
        XCTAssertTrue(OnePlusPopupPresenter.owns(key(0, window: parent), parent: parent, popup: popup))
        XCTAssertTrue(OnePlusPopupPresenter.owns(key(0, window: popup), parent: parent, popup: popup))
        XCTAssertFalse(OnePlusPopupPresenter.owns(key(0, window: other), parent: parent, popup: popup))
        XCTAssertFalse(OnePlusPopupPresenter.owns(key(0), parent: nil, popup: nil))
    }
}
