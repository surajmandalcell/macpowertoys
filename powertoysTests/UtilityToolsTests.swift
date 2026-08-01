import Carbon.HIToolbox
import XCTest
@testable import powertoys

@MainActor
final class UtilityToolsTests: XCTestCase {
    func testDockIconMatchesActiveToolWindow() {
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "ruler-window"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "ruler-settings-window"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "preferences-window"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "ruler-color-panel"), "RulerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "awake-AppWindow-1"), "AwakeLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "color-picker"), "ColorPickerLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "text-extractor"), "TextExtractorLogo")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: "main"), "AppIcon")
        XCTAssertEqual(AppDelegate.dockIconAsset(for: nil), "AppIcon")
    }

    func testColorFormatting() {
        let sample = ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1)
        XCTAssertEqual(sample.string(.hex), "#FF8000")
        XCTAssertEqual(sample.string(.rgb), "rgb(255, 128, 0)")
        XCTAssertTrue(sample.string(.swiftUI).hasPrefix("Color(red:"))
        XCTAssertTrue(sample.matches(ColorSample(red: 1, green: 0.5, blue: 0, alpha: 1)))
        XCTAssertFalse(sample.matches(ColorSample(red: 0, green: 0.5, blue: 0, alpha: 1)))
    }

    func testAwakeDurationFormatting() {
        XCTAssertEqual(AwakeService.duration(65), "01:05")
        XCTAssertEqual(AwakeService.duration(3661), "1:01:01")
    }

    func testActionIDsMapToTools() {
        XCTAssertEqual(ToolActionID.rulerOpen.toolID, "ruler")
        XCTAssertEqual(ToolActionID.colorPickerCopyLast.toolID, "color-picker")
        XCTAssertEqual(ToolActionID.textExtractorCapture.toolID, "text-extractor")
    }

    func testGlobalShortcutKeysCoverAlphabetWithoutDuplicateCodes() {
        XCTAssertEqual(GlobalShortcutKey.allCases.map(\.title), Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init))
        XCTAssertEqual(Set(GlobalShortcutKey.allCases.map(\.keyCode)).count, 26)
    }

    func testFixedSizeWindowRestoreKeepsPositionNotSavedSize() {
        let saved = NSRect(x: 100, y: 300, width: 480, height: 600)
        let restored = WindowStateManager.positionOnlyFrame(saved: saved, currentSize: NSSize(width: 480, height: 320))
        XCTAssertEqual(restored.minX, 100)
        XCTAssertEqual(restored.maxY, saved.maxY)
        XCTAssertEqual(restored.size, NSSize(width: 480, height: 320))
    }

    func testDefaultGlobalShortcuts() {
        let textExtractor = GlobalShortcutAction.textExtractor.defaultShortcut
        XCTAssertEqual(textExtractor.keyCode, UInt32(kVK_ANSI_2))
        XCTAssertEqual(textExtractor.carbonModifiers, UInt32(shiftKey | cmdKey))
        XCTAssertEqual(textExtractor.display, "⇧⌘2")

        let colorPicker = GlobalShortcutAction.colorPicker.defaultShortcut
        XCTAssertEqual(colorPicker.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertEqual(colorPicker.carbonModifiers, UInt32(shiftKey | cmdKey))
        XCTAssertEqual(colorPicker.display, "⇧⌘3")
        XCTAssertTrue(colorPicker.overridesSystemScreenshotShortcut)
        XCTAssertTrue(colorPicker.matches(
            keyCode: UInt32(kVK_ANSI_3),
            flags: [.maskCommand, .maskShift]
        ))
        XCTAssertFalse(colorPicker.matches(
            keyCode: UInt32(kVK_ANSI_3),
            flags: [.maskCommand, .maskShift, .maskControl]
        ))
        XCTAssertFalse(textExtractor.overridesSystemScreenshotShortcut)
    }

    func testShortcutRecorderUsesPhysicalNumberKeyLabelWithShift() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "#",
            charactersIgnoringModifiers: "#",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_3)
        ))

        let shortcut = try XCTUnwrap(ShortcutRecorderField.shortcut(from: event))
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertEqual(shortcut.carbonModifiers, UInt32(shiftKey | cmdKey))
        XCTAssertEqual(shortcut.keyLabel, "3")
        XCTAssertEqual(shortcut.display, "⇧⌘3")
    }
}
