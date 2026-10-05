import AppKit
import Carbon.HIToolbox
import Observation
import XCTest
@testable import powertoys

@MainActor
final class AppCommandTests: XCTestCase {
    func testShortcutConflictsRespectEnabledPhysicalChords() {
        let chord = GlobalShortcutAction.portman.defaultShortcut
        var sameKeys = chord
        sameKeys.keyLabel = "Different label"
        XCTAssertEqual(GlobalShortcutAction.mainPanel.defaultShortcut, .unset)
        XCTAssertEqual(GlobalShortcut.unset.display, "Not set")
        XCTAssertFalse(GlobalShortcutManager.usesCarbonHotKey(for: .unset))
        let saved: [GlobalShortcutAction: GlobalShortcut] = [.portman: chord]
        XCTAssertEqual(GlobalShortcutManager.conflictMessage(
            for: sameKeys, action: .mainPanel, shortcuts: saved, enabled: [.portman], awakeEnabled: false
        ), "Already used for Portman.")
        XCTAssertNil(GlobalShortcutManager.conflictMessage(
            for: sameKeys, action: .mainPanel, shortcuts: saved, enabled: [], awakeEnabled: false
        ))
        XCTAssertNil(GlobalShortcutManager.conflictMessage(
            for: chord, action: .portman, shortcuts: saved, enabled: [.portman], awakeEnabled: false
        ))
        let awake = GlobalShortcut(keyCode: UInt32(kVK_ANSI_A),
                                   carbonModifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "A")
        XCTAssertEqual(GlobalShortcutManager.conflictMessage(
            for: awake, action: .mainPanel, shortcuts: [:], enabled: [], awakeEnabled: true
        ), "Already used for Kwake.")
    }

    func testRecorderRejectsOtherWindowEvents() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 23, context: nil, characters: "p", charactersIgnoringModifiers: "p",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_P)
        ))
        XCTAssertTrue(ShortcutRecorderField.accepts(event, windowNumber: 23))
        XCTAssertFalse(ShortcutRecorderField.accepts(event, windowNumber: 24))
        XCTAssertFalse(ShortcutRecorderField.accepts(event, windowNumber: nil))
    }

    func testQuitMenuDescribesExistingScope() {
        XCTAssertEqual(AppCommands.quitMenuTitle(toolID: "rclone"), "Close RSync UI")
        XCTAssertEqual(AppCommands.quitMenuTitle(toolID: "ruler"), "Close Ruler")
        XCTAssertEqual(AppCommands.quitMenuTitle(toolID: nil), "Press ⌘Q again to quit")
    }

    func testSystemFormattingNotificationsInvalidateOnce() {
        let lifetime = AppInitializer.shared
        let revision = lifetime.formattingRevision
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        XCTAssertEqual(lifetime.formattingRevision, revision &+ 1)
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(lifetime.formattingRevision, revision &+ 2)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: nil)
        XCTAssertEqual(lifetime.formattingRevision, revision &+ 2)
    }
}
