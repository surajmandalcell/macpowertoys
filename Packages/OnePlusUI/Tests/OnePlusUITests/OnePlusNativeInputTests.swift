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

    func testExternalTextWaitsForCompositionAndKeepsLatestValue() {
        let editor = NSTextView()
        editor.string = "start"
        let synchronization = OnePlusTextSynchronization()
        editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 5))
        XCTAssertTrue(editor.hasMarkedText())
        synchronization.update("first external", in: editor)
        synchronization.update("latest external", in: editor)
        XCTAssertEqual(editor.string, "あ")
        editor.unmarkText()
        synchronization.applyPending(in: editor)
        XCTAssertEqual(editor.string, "latest external")
        synchronization.applyPending(in: editor)
        XCTAssertEqual(editor.string, "latest external")
    }

    func testSameResourceReplacementPreservesClampedSelectionAndNativeUndo() throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        editor.allowsUndo = true
        window.contentView = editor
        let synchronization = OnePlusTextSynchronization()
        synchronization.update("123456", in: editor, resourceID: "A")
        editor.setSelectedRange(NSRange(location: 4, length: 2))
        synchronization.update("short", in: editor, resourceID: "A")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 1))
        let undo = try XCTUnwrap(editor.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(editor.string, "123456")
        editor.setSelectedRange(NSRange(location: 4, length: 2))
        synchronization.update("second", in: editor, resourceID: "B")
        XCTAssertFalse(undo.canUndo)
        editor.setSelectedRange(NSRange(location: 3, length: 1))
        synchronization.update("123456", in: editor, resourceID: "A")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 2))
        XCTAssertFalse(window.isVisible)
    }
}
