import AppKit
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusFocusPolicyTests: XCTestCase {
    func testPolicyChangesWithEitherAccessibilityMode() {
        let policy = OnePlusFocusPolicy.shared
        defer { policy.refresh() }
        for (keyboard, voice, expected) in [(false, false, false), (true, false, true),
                                           (false, true, true), (true, true, true), (false, false, false)] {
            policy.update(fullKeyboardAccess: keyboard, voiceOver: voice)
            XCTAssertEqual(policy.showsFocus, expected)
        }
    }

    func testPresentationAndPointerFocusKeepKeyboardAndTextEditing() {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp] {
            XCTAssertTrue(OnePlusFocusPolicy.isPointerEvent(type))
        }
        XCTAssertFalse(OnePlusFocusPolicy.isPointerEvent(.keyDown))
        XCTAssertFalse(OnePlusFocusPolicy.isPointerEvent(nil))
        XCTAssertFalse(OnePlusFocusPolicy.acceptsFocus(isVisible: false, pointer: false, textInput: true))
        XCTAssertFalse(OnePlusFocusPolicy.acceptsFocus(isVisible: true, pointer: true, textInput: false))
        XCTAssertTrue(OnePlusFocusPolicy.acceptsFocus(isVisible: true, pointer: true, textInput: true))
        XCTAssertTrue(OnePlusFocusPolicy.acceptsFocus(isVisible: true, pointer: false, textInput: false))
        let window = NSWindow(contentRect: .init(x: -2000, y: -2000, width: 300, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let field = NSTextField(frame: .init(x: 10, y: 10, width: 120, height: 28))
        window.contentView?.addSubview(field)
        OnePlusFocusPolicy.shared.configure(window)
        XCTAssertNil(window.initialFirstResponder)
        XCTAssertTrue(window.firstResponder === window)
        XCTAssertFalse(window.makeFirstResponder(field), "Hidden hosts must not focus their first input.")
        let policy = OnePlusFocusPolicy.shared
        defer { policy.refresh() }
        policy.update(fullKeyboardAccess: true, voiceOver: false)
        XCTAssertEqual(field.focusRingType, .default)
        policy.update(fullKeyboardAccess: false, voiceOver: false)
        XCTAssertEqual(field.focusRingType, .none)
        policy.update(fullKeyboardAccess: false, voiceOver: true)
        XCTAssertEqual(field.focusRingType, .default)
    }

    func testFocusSampleHasRestingPaintWhenAccessibilityModesAreOff() throws {
        let policy = OnePlusFocusPolicy.shared
        defer { policy.refresh() }
        policy.update(fullKeyboardAccess: false, voiceOver: false)
        func pixels(_ state: OnePlusControlState) throws -> Data {
            let host = NSHostingView(rootView: Button("Action") {}
                .buttonStyle(OnePlusButtonStyle()).environment(\.onePlusControlState, state))
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame.size = host.fittingSize
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        XCTAssertEqual(try pixels(.focus), try pixels(.rest))
        policy.update(fullKeyboardAccess: true, voiceOver: false)
        XCTAssertNotEqual(try pixels(.focus), try pixels(.rest))
        policy.update(fullKeyboardAccess: false, voiceOver: true)
        XCTAssertNotEqual(try pixels(.focus), try pixels(.rest))
    }

    func testNativeSelectionKeepsPointerFocusWithoutDrawingFocus() throws {
        let owner = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let policy = OnePlusFocusPolicy.shared
        defer { policy.stop(); policy.refresh() }
        for (keyboard, voice) in [(false, false), (true, false), (false, true)] {
            policy.stop()
            let window = FocusTestWindow(contentRect: .init(x: -10000, y: -10000, width: 300, height: 150),
                                         styleMask: .borderless, backing: .buffered, defer: false)
            let table = NSTableView(frame: .init(x: 0, y: 0, width: 260, height: 80))
            let rows = FocusTestRows()
            table.addTableColumn(NSTableColumn(identifier: .init("row")))
            table.dataSource = rows
            table.reloadData()
            window.contentView?.addSubview(table)
            policy.configure(window)
            policy.update(fullKeyboardAccess: keyboard, voiceOver: voice)
            XCTAssertTrue(OnePlusFocusPolicy.allows(table, in: window, pointer: true))
            XCTAssertTrue(window.makeFirstResponder(table))
            OnePlusFocusPolicy.dismissPointerFocus(in: window, at: .init(x: 20, y: 20))
            XCTAssertTrue(window.firstResponder === table)
            XCTAssertEqual(table.focusRingType, keyboard || voice ? .default : .none)
            OnePlusFocusPolicy.dismissPointerFocus(in: window, at: .init(x: 280, y: 120))
            XCTAssertTrue(window.firstResponder === window)
            window.presented = false
            XCTAssertFalse(OnePlusFocusPolicy.allows(table, in: window, pointer: true))
        }
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, owner)
    }

    func testReactivationRetainsNestedRespondersAndTextSelection() throws {
        let policy = OnePlusFocusPolicy.shared
        policy.stop()
        defer { policy.stop(); policy.refresh() }
        let window = FocusTestWindow(contentRect: .init(x: -10000, y: -10000, width: 300, height: 150),
                                     styleMask: .borderless, backing: .buffered, defer: false)
        let nested = NSView(frame: .init(x: 0, y: 0, width: 280, height: 130))
        let control = FocusTestControl(frame: .init(x: 10, y: 10, width: 100, height: 28))
        let text = NSTextView(frame: .init(x: 10, y: 50, width: 200, height: 60))
        text.string = "Keep this selection"
        nested.addSubview(control); nested.addSubview(text)
        window.contentView?.addSubview(nested)
        XCTAssertTrue(window.makeFirstResponder(text))
        text.setSelectedRange(.init(location: 5, length: 4))
        policy.configure(window)
        XCTAssertTrue(window.firstResponder === text, "Attachment must preserve an active editor.")
        for (keyboard, voice) in [(false, false), (true, false), (false, true)] {
            policy.update(fullKeyboardAccess: keyboard, voiceOver: voice)
            XCTAssertEqual(OnePlusFocusPolicy.allows(control, in: window, pointer: true), keyboard || voice)
            for responder in [text, control] {
                XCTAssertTrue(window.makeFirstResponder(responder))
                policy.configure(window)
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
                XCTAssertTrue(window.firstResponder === responder)
            }
            XCTAssertEqual(text.selectedRange(), .init(location: 5, length: 4))
        }
    }

    func testKeyAndDisplayUpdatesClearOnlyInvalidResponders() throws {
        let policy = OnePlusFocusPolicy.shared
        policy.stop()
        defer { policy.stop(); policy.refresh() }
        let window = FocusTestWindow(contentRect: .init(x: -10000, y: -10000, width: 300, height: 150),
                                     styleMask: .borderless, backing: .buffered, defer: false)
        let control = FocusTestControl(frame: .init(x: 10, y: 10, width: 100, height: 28))
        window.contentView?.addSubview(control)
        policy.configure(window)
        for event in [NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification] {
            for invalid in 0..<4 {
                control.isHidden = false; control.isEnabled = true
                control.frame.origin.y = 10
                window.contentView?.addSubview(control)
                XCTAssertTrue(window.makeFirstResponder(control))
                switch invalid {
                case 0: control.isHidden = true
                case 1: control.isEnabled = false
                case 2: control.frame.origin.y = 500
                default: control.removeFromSuperview()
                }
                NotificationCenter.default.post(name: event, object: window)
                XCTAssertTrue(window.firstResponder === window, "event=\(event.rawValue) invalid=\(invalid) frame=\(control.frame) visible=\(control.visibleRect)")
            }
        }
    }
}

private final class FocusTestWindow: NSWindow {
    var presented = true
    override var isVisible: Bool { presented }
}

private final class FocusTestControl: NSButton {
    override var acceptsFirstResponder: Bool { true }
}

private final class FocusTestRows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 3 }
}
