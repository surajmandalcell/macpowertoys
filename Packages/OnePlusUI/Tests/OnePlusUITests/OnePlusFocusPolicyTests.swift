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
}
