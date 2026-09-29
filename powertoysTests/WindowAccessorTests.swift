import AppKit
import OnePlusUI
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class WindowAccessorTests: XCTestCase {
    func testAccessorSetsIdentityWithoutTakingOverSceneSizing() {
        let window = AccessorCountingWindow(
            contentRect: NSRect(x: -2000, y: -2000, width: 420, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        let identifier = "window-accessor-test-\(UUID().uuidString)"
        window.contentView = NSHostingView(rootView:
            Color.clear.frame(width: 420, height: 300)
                .background(WindowAccessor(identifier: identifier))
        )
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(window.identifier?.rawValue, identifier)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.isMovable)
        XCTAssertNil(window.appearance)
        XCTAssertTrue(window.styleMask.contains(.resizable), "The canvas modifier owns fixed chrome.")
        XCTAssertEqual(window.contentSizeWrites, 0, "The accessor must not fight SwiftUI sizing.")
        // Native chrome layout, centerlines, and resize policy are exercised by
        // OnePlusChromeTests in the package that now owns that behavior.
    }

    func testWorkspaceSizeLookupUsesEveryRegisteredCanvas() throws {
        let expected: [String: NSSize] = [
            "main": NSSize(width: 1240, height: 840),
            "rclone": NSSize(width: 1240, height: 840),
            "logs": NSSize(width: 1080, height: 660),
            "input-devices": NSSize(width: 1080, height: 660),
            "system-care": NSSize(width: 1240, height: 840),
            "system-monitor": NSSize(width: 1080, height: 660),
            "nettoys": NSSize(width: 1440, height: 900),
            "disk-explorer": NSSize(width: 1440, height: 900),
            "switch": NSSize(width: 1240, height: 840),
            "mac-tweaks": NSSize(width: 1120, height: 826),
            "awake": NSSize(width: 560, height: 500),
            "color-picker": NSSize(width: 420, height: 250),
            "text-extractor": NSSize(width: 480, height: 270),
        ]
        for (identifier, size) in expected {
            XCTAssertEqual(try XCTUnwrap(UtilityLayout.minimumContentSize(for: identifier)), size, identifier)
        }
        XCTAssertNil(UtilityLayout.minimumContentSize(for: "unknown"))
    }

    func testLauncherContentPaneFitsFourToolCardsInOneRow() {
        let layout = UtilityLayout.self
        let contentWidth = layout.launcherContentSize.width - layout.compactSidebarWidth
        let columns = CGFloat(layout.launcherColumnCount)
        let required = columns * layout.launcherCardMinimumWidth
            + (columns - 1) * layout.launcherGridSpacing
            + 2 * layout.launcherContentInset
        XCTAssertEqual(contentWidth, 1024)
        XCTAssertEqual(required, 976)
        XCTAssertGreaterThanOrEqual(contentWidth, required)
        XCTAssertLessThan(contentWidth, required + layout.launcherGridSpacing + layout.launcherCardMinimumWidth)
    }

    func testLauncherRestoresPositionOnlySoAnOldSavedSizeCannotReturn() {
        XCTAssertTrue(WindowStateManager.restoresPositionOnly("main"))
        XCTAssertTrue(WindowStateManager.restoresPositionOnly("system-monitor"))
        XCTAssertFalse(WindowStateManager.restoresPositionOnly("rclone"))
        let saved = NSRect(x: 40, y: 60, width: 780, height: 732)
        let restored = WindowStateManager.positionOnlyFrame(saved: saved, currentSize: NSSize(width: 1240, height: 840))
        XCTAssertEqual(restored.size, NSSize(width: 1240, height: 840))
        XCTAssertEqual(restored.minX, 40)
        XCTAssertEqual(restored.maxY, saved.maxY)
    }

    func testWorkspaceDensityUsesFoundationMetrics() {
        XCTAssertEqual(UtilityLayout.compactSidebarWidth, 216)
        XCTAssertEqual(UtilityLayout.dataSidebarWidth, 216)
        XCTAssertEqual(UtilityLayout.sidebarRowHeight, 32)
        XCTAssertEqual(UtilityLayout.workspaceTitlebarHeight, 54)
        XCTAssertEqual(UtilityLayout.workspaceContentTopInset, 54)
        XCTAssertEqual(UtilityLayout.workspaceTitleLeadingInset, 84)
        XCTAssertEqual(UtilityLayout.workspaceActionHeight, 28)
        XCTAssertEqual(UtilityLayout.separatorOpacity, 1)
        XCTAssertEqual(UtilityLayout.increasedContrastSeparatorOpacity, 1)
    }

    func testNativeSearchWrapperKeepsEditingAndSharedType() throws {
        let host = NSHostingView(rootView:
            NativeSearchField(text: .constant(""), placeholder: "Find content")
                .frame(width: 240, height: 28)
        )
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 28)
        host.layoutSubtreeIfNeeded()
        let search = try XCTUnwrap(firstView(of: NSSearchField.self, in: host))
        XCTAssertTrue(search.isEditable)
        XCTAssertTrue(search.isSelectable)
        XCTAssertEqual(search.font?.pointSize, 12)
        XCTAssertEqual(search.accessibilityLabel(), "Find content")
        XCTAssertLessThanOrEqual(search.frame.height, 28)
    }

    func testSingleStepStepperDoesNotRepeatWhileMouseIsHeld() throws {
        var value = 800
        let host = NSHostingView(rootView: SingleStepStepper(
            "TCP timeout: 800 ms", value: Binding(get: { value }, set: { value = $0 }),
            in: 100...5_000, step: 100
        ))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 28)
        host.layoutSubtreeIfNeeded()
        let stepper = try XCTUnwrap(firstView(of: NSStepper.self, in: host))
        XCTAssertFalse(stepper.autorepeat)
        XCTAssertEqual(stepper.increment, 100)
        stepper.integerValue = 900
        stepper.sendAction(stepper.action, to: stepper.target)
        XCTAssertEqual(value, 900)
    }

    func testMacTweaksContentSizeAccountsForNativeTitlebar() {
        XCTAssertEqual(MacTweaksLayout.contentSize.width, MacTweaksLayout.windowSize.width)
        XCTAssertEqual(MacTweaksLayout.contentSize.height + UtilityLayout.hiddenTitlebarBottomSurplus,
                       MacTweaksLayout.windowSize.height, accuracy: 0.5)
    }

    func testUtilityMotionStopsWhenReduceMotionIsEnabled() {
        XCTAssertNotNil(UtilityMotion.animation(reduceMotion: false))
        XCTAssertNil(UtilityMotion.animation(reduceMotion: true))
    }

    func testUtilityInteractionButtonStates() {
        XCTAssertEqual(UtilityInteractionButtonStyle.highlightOpacity(isEnabled: true, isHovering: false, isPressed: false), 0)
        XCTAssertEqual(UtilityInteractionButtonStyle.highlightOpacity(isEnabled: true, isHovering: true, isPressed: false), 0.06)
        XCTAssertEqual(UtilityInteractionButtonStyle.highlightOpacity(isEnabled: true, isHovering: true, isPressed: true), 0.1)
        XCTAssertEqual(UtilityInteractionButtonStyle.highlightOpacity(isEnabled: false, isHovering: true, isPressed: true), 0)
    }

    private func firstView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { self.firstView(of: type, in: $0) }.first
    }
}

@MainActor
private final class AccessorCountingWindow: NSWindow {
    var contentSizeWrites = 0
    override func setContentSize(_ size: NSSize) {
        contentSizeWrites += 1
        super.setContentSize(size)
    }
}
