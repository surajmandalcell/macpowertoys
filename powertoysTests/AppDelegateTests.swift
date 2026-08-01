import XCTest
import Carbon.HIToolbox
import SwiftUI
@testable import powertoys

final class AppDelegateTests: XCTestCase {
    func testStatusItemInterceptsLeftAndRightClicks() {
        XCTAssertTrue(AppDelegate.statusItemEventMask.contains(.leftMouseDown))
        XCTAssertTrue(AppDelegate.statusItemEventMask.contains(.rightMouseDown))
    }

    @MainActor
    func testStatusItemContextMenuContainsOnlyOpenAndQuit() {
        let menu = AppDelegate().statusItemContextMenu()

        XCTAssertEqual(menu.items.map(\.title), ["Open MacPowerToys", "Quit"])
        XCTAssertTrue(menu.items.allSatisfy { $0.image != nil })
        XCTAssertEqual(
            menu.items.map(\.action),
            [
                #selector(AppDelegate.openMainWindowFromStatusItem),
                #selector(AppDelegate.quitFromStatusItem)
            ]
        )
    }

    @MainActor
    func testFreeRulerNativeCommandsMatchPinnedCommandSet() {
        XCTAssertEqual(FreeRulerCommand.rulerMenu, [.newRuler, .horizontalWing, .verticalWing, .rulerSettings])
        XCTAssertEqual(FreeRulerCommand.unitMenu, [.pixels, .millimeters, .inches, .cycleUnits])
        XCTAssertEqual(
            FreeRulerCommand.optionsMenu,
            [.flipHorizontal, .flipVertical, .floatRuler, .rulerShadow, .groupRulers, .alignAtMouse, .resetPosition]
        )

        let context = FreeRulerCommandContext.shared
        context.hasRuler = true
        context.horizontalVisible = true
        context.verticalVisible = false
        context.unit = .inches
        context.floatRulers = false
        context.rulerShadow = true
        context.groupRulers = false

        let commands: [(FreeRulerCommand, String, Selector, FreeRulerCommandShortcut?)] = [
            (.newRuler, "New Ruler", #selector(AppDelegate.newRuler(_:)), .init("n", modifiers: .command)),
            (.horizontalWing, "Hide Horizontal Ruler", #selector(AppDelegate.toggleHorizontalRuler(_:)), .init("h")),
            (.verticalWing, "Show Vertical Ruler", #selector(AppDelegate.toggleVerticalRuler(_:)), .init("v")),
            (.rulerSettings, "Ruler Settings…", #selector(AppDelegate.openRulerSettings(_:)), .init(",", modifiers: .command)),
            (.pixels, "Pixels", #selector(AppDelegate.setUnitPixels(_:)), nil),
            (.millimeters, "Millimeters", #selector(AppDelegate.setUnitMillimetres(_:)), nil),
            (.inches, "Inches", #selector(AppDelegate.setUnitInches(_:)), nil),
            (.cycleUnits, "Cycle Units", #selector(AppDelegate.cycleUnits(_:)), .init("u")),
            (.flipHorizontal, "Flip Horizontal", #selector(AppDelegate.flipHorizontalRuler(_:)), .init("h", modifiers: .shift)),
            (.flipVertical, "Flip Vertical", #selector(AppDelegate.flipVerticalRuler(_:)), .init("v", modifiers: .shift)),
            (.floatRuler, "Float Ruler", #selector(AppDelegate.toggleFloatRulers(_:)), .init("f")),
            (.rulerShadow, "Show Ruler Shadow", #selector(AppDelegate.toggleRulerShadow(_:)), .init("s")),
            (.groupRulers, "Group Rulers", #selector(AppDelegate.toggleGroupRulers(_:)), .init("g")),
            (.alignAtMouse, "Align Ruler at Mouse Location", #selector(AppDelegate.alignRulersAtMouseLocation(_:)), .init("o")),
            (.resetPosition, "Reset Ruler Position", #selector(AppDelegate.resetRulerPositions(_:)), .init("r", modifiers: .command)),
        ]
        for (command, title, action, shortcut) in commands {
            XCTAssertEqual(command.title(in: context), title)
            XCTAssertEqual(command.action, action)
            XCTAssertEqual(command.shortcut, shortcut)
        }

        XCTAssertEqual(FreeRulerCommand.horizontalWing.title(in: context), "Hide Horizontal Ruler")
        XCTAssertFalse(FreeRulerCommand.horizontalWing.isEnabled(in: context))
        XCTAssertEqual(FreeRulerCommand.verticalWing.title(in: context), "Show Vertical Ruler")
        XCTAssertTrue(FreeRulerCommand.verticalWing.isEnabled(in: context))
        XCTAssertEqual(FreeRulerCommand.inches.selection(in: context), true)
        XCTAssertEqual(FreeRulerCommand.floatRuler.selection(in: context), false)
        XCTAssertEqual(FreeRulerCommand.rulerShadow.selection(in: context), true)
        XCTAssertEqual(FreeRulerCommand.groupRulers.selection(in: context), false)
    }

    func testFreeRulerWindowIdentifierMatcherIsExact() {
        for identifier in [
            "ruler-window",
            "ruler-settings-window",
            "preferences-window",
            "ruler-color-panel",
        ] {
            XCTAssertTrue(AppDelegate.isFreeRulerWindowIdentifier(identifier), identifier)
        }
        XCTAssertFalse(AppDelegate.isFreeRulerWindowIdentifier("ruler"))
        XCTAssertFalse(AppDelegate.isFreeRulerWindowIdentifier("ruler-window-extra"))
        XCTAssertFalse(AppDelegate.isFreeRulerWindowIdentifier(nil))
    }

    @MainActor
    func testFreeRulerContextPublishesStateWithoutMutatingMainMenu() {
        let originalMainMenu = NSApp.mainMenu
        let mainMenu = NSMenu()
        let sentinel = NSMenuItem(title: "Host", action: nil, keyEquivalent: "")
        mainMenu.addItem(sentinel)
        NSApp.mainMenu = mainMenu
        defer { NSApp.mainMenu = originalMainMenu }

        let oldGroupRulers = prefs.groupRulers
        prefs.groupRulers = true
        defer { prefs.groupRulers = oldGroupRulers }

        let delegate = AppDelegate()
        let controller = delegate.rulerManager.createRuler(
            defaults: RulerSettings(unit: .inches, floatRulers: false, rulerShadow: true),
            screenFrame: NSRect(x: 0, y: 0, width: 1000, height: 800)
        )
        controller.setWing(.vertical, isVisible: false)
        delegate.updateDisplay()

        let rulerWindow = NSWindow()
        rulerWindow.identifier = NSUserInterfaceItemIdentifier("ruler-window")
        delegate.updateFreeRulerMenuContext(for: rulerWindow)

        let context = FreeRulerCommandContext.shared
        XCTAssertTrue(context.isActive)
        XCTAssertTrue(context.hasRuler)
        XCTAssertTrue(context.horizontalVisible)
        XCTAssertFalse(context.verticalVisible)
        XCTAssertEqual(context.unit, .inches)
        XCTAssertFalse(context.floatRulers)
        XCTAssertTrue(context.rulerShadow)
        XCTAssertTrue(context.groupRulers)
        XCTAssertFalse(context.showsHostCommands)
        XCTAssertTrue(NSApp.mainMenu === mainMenu)
        XCTAssertTrue(mainMenu.items.first === sentinel)

        let awakeWindow = NSWindow()
        awakeWindow.identifier = NSUserInterfaceItemIdentifier("awake")
        delegate.updateFreeRulerMenuContext(for: awakeWindow)

        XCTAssertFalse(context.isActive)
        XCTAssertTrue(context.showsHostCommands)
        XCTAssertTrue(NSApp.mainMenu === mainMenu)
        XCTAssertTrue(mainMenu.items.first === sentinel)
    }

    @MainActor
    func testExactCommandWClosesActiveRulerOnFirstDispatch() throws {
        let delegate = AppDelegate()
        let controller = delegate.rulerManager.createRuler(
            screenFrame: NSRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: controller.rulerWindow.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_W)
        ))
        let unrelatedEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .command],
            timestamp: 0,
            windowNumber: controller.rulerWindow.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_W)
        ))

        XCTAssertTrue(
            delegate.handleFreeRulerWindowKeyDown(
                unrelatedEvent,
                keyWindow: controller.rulerWindow
            ) === unrelatedEvent
        )
        XCTAssertEqual(delegate.rulerManager.controllers.count, 1)
        XCTAssertNil(delegate.handleFreeRulerWindowKeyDown(event, keyWindow: controller.rulerWindow))
        XCTAssertTrue(delegate.rulerManager.controllers.isEmpty)
    }

    @MainActor
    func testDoubleClickCancelsDelayedSingleClick() async throws {
        let coordinator = StatusItemClickCoordinator(delay: 0.01)
        var singleClicks = 0
        var doubleClicks = 0

        coordinator.handle(
            clickCount: 1,
            singleClick: { singleClicks += 1 },
            doubleClick: { doubleClicks += 1 }
        )
        coordinator.handle(
            clickCount: 2,
            singleClick: { singleClicks += 1 },
            doubleClick: { doubleClicks += 1 }
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(singleClicks, 0)
        XCTAssertEqual(doubleClicks, 1)
    }

    @MainActor
    func testSingleClickRunsAfterDelay() async throws {
        let coordinator = StatusItemClickCoordinator(delay: 0.01)
        var singleClicks = 0

        coordinator.handle(
            clickCount: 1,
            singleClick: { singleClicks += 1 },
            doubleClick: {}
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(singleClicks, 1)
    }
}
