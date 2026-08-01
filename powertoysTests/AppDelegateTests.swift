import XCTest
@testable import powertoys

final class AppDelegateTests: XCTestCase {
    private func menuItems(in menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        return menu.items.flatMap { [$0] + menuItems(in: $0.submenu) }
    }

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
    func testFreeRulerMenusMatchUpstreamCommands() throws {
        let delegate = AppDelegate()
        let roots = delegate.makeFreeRulerMenuRoots()
        XCTAssertEqual(
            roots.compactMap { $0.identifier?.rawValue },
            ["dMs-cI-mzQ", "iDP-2z-irv", "H8h-7b-M4v"]
        )
        XCTAssertEqual(
            roots[0].submenu?.items.map { $0.isSeparatorItem ? "-" : $0.identifier?.rawValue ?? "" },
            ["rWt-KM-qSf", "-", "fLB-gk-0Jy", "NgD-7h-fjO", "-", "rSt-Tg-232"]
        )
        XCTAssertEqual(
            roots[1].submenu?.items.map { $0.isSeparatorItem ? "-" : $0.identifier?.rawValue ?? "" },
            ["pYR-Ba-kKi", "B6Y-Hi-AkN", "lt1-Hj-2TR", "-", "2nm-aL-kZd"]
        )
        XCTAssertEqual(
            roots[2].submenu?.items.map { $0.isSeparatorItem ? "-" : $0.identifier?.rawValue ?? "" },
            ["TkR-03-X6l", "GDK-AC-uC8", "a8D-hN-A59", "-", "7Ga-Fb-LLc", "iKV-uW-hwy", "6ph-5N-O9R"]
        )

        let items = menuItems(in: roots[0].submenu)
            + menuItems(in: roots[1].submenu)
            + menuItems(in: roots[2].submenu)
        let commands: [(String, String, NSEvent.ModifierFlags, Selector)] = [
            ("rWt-KM-qSf", "n", .command, #selector(AppDelegate.newRuler(_:))),
            ("fLB-gk-0Jy", "h", [], #selector(AppDelegate.toggleHorizontalRuler(_:))),
            ("NgD-7h-fjO", "v", [], #selector(AppDelegate.toggleVerticalRuler(_:))),
            ("rSt-Tg-232", ",", .command, #selector(AppDelegate.openRulerSettings(_:))),
            ("2nm-aL-kZd", "u", [], #selector(AppDelegate.cycleUnits(_:))),
            ("GZl-Zd-Ad4", "h", .shift, #selector(AppDelegate.flipHorizontalRuler(_:))),
            ("IQD-xF-keq", "v", .shift, #selector(AppDelegate.flipVerticalRuler(_:))),
            ("GDK-AC-uC8", "f", [], #selector(AppDelegate.toggleFloatRulers(_:))),
            ("a8D-hN-A59", "s", [], #selector(AppDelegate.toggleRulerShadow(_:))),
            ("7Ga-Fb-LLc", "g", [], #selector(AppDelegate.toggleGroupRulers(_:))),
            ("iKV-uW-hwy", "o", [], #selector(AppDelegate.alignRulersAtMouseLocation(_:))),
            ("6ph-5N-O9R", "r", .command, #selector(AppDelegate.resetRulerPositions(_:))),
        ]
        for (identifier, key, modifiers, action) in commands {
            let item = try XCTUnwrap(items.first { $0.identifier?.rawValue == identifier })
            XCTAssertEqual(item.keyEquivalent, key, identifier)
            XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, identifier)
            XCTAssertEqual(item.action, action, identifier)
            XCTAssertTrue(item.target === delegate, identifier)
        }
    }

    @MainActor
    func testFreeRulerDefaultsCommandUsesOptionCommandComma() {
        let delegate = AppDelegate()
        let item = delegate.makeFreeRulerDefaultsMenuItem()

        XCTAssertEqual(item.title, "Ruler Defaults…")
        XCTAssertEqual(item.keyEquivalent, ",")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.option, .command])
        XCTAssertEqual(item.action, #selector(AppDelegate.openPreferences(_:)))
        XCTAssertTrue(item.target === delegate)
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
    func testFreeRulerMenuContextTemporarilyRoutesAndRestoresHostCommands() {
        let originalMainMenu = NSApp.mainMenu
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu
        defer { NSApp.mainMenu = originalMainMenu }

        let applicationRoot = NSMenuItem(title: "App", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "App")
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.openMainWindowFromStatusItem),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = .command
        applicationMenu.addItem(settings)
        applicationRoot.submenu = applicationMenu
        mainMenu.addItem(applicationRoot)

        let fileRoot = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let newTransfer = NSMenuItem(
            title: "New Transfer",
            action: #selector(AppDelegate.quitFromStatusItem),
            keyEquivalent: "n"
        )
        newTransfer.keyEquivalentModifierMask = .command
        let close = NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        close.keyEquivalentModifierMask = .command
        fileMenu.addItem(newTransfer)
        fileMenu.addItem(close)
        fileRoot.submenu = fileMenu
        mainMenu.addItem(fileRoot)

        let delegate = AppDelegate()
        delegate.freeRulerMenuRoots = delegate.makeFreeRulerMenuRoots()
        delegate.freeRulerDefaultsMenuItem = delegate.makeFreeRulerDefaultsMenuItem()

        let rulerWindow = NSWindow()
        rulerWindow.identifier = NSUserInterfaceItemIdentifier("ruler-window")
        delegate.updateFreeRulerMenuContext(for: rulerWindow)

        XCTAssertTrue(delegate.freeRulerMenuRoots.allSatisfy { !$0.isHidden })
        XCTAssertFalse(delegate.freeRulerDefaultsMenuItem!.isHidden)
        XCTAssertTrue(delegate.freeRulerMenuRoots.allSatisfy { $0.menu === mainMenu })
        XCTAssertTrue(delegate.freeRulerDefaultsMenuItem!.menu === applicationMenu)
        XCTAssertEqual(delegate.freeRulerMenuRoots[0].submenu?.items[0].keyEquivalent, "n")
        XCTAssertEqual(delegate.freeRulerMenuRoots[0].submenu?.items[5].keyEquivalent, ",")
        XCTAssertEqual(settings.keyEquivalent, "")
        XCTAssertEqual(newTransfer.keyEquivalent, "")
        XCTAssertEqual(close.action, #selector(AppDelegate.closeKeyWindow(_:)))
        XCTAssertTrue(close.target === delegate)
        XCTAssertEqual(
            Set(delegate.freeRulerHostMenuItemStates.map(\.keyEquivalent)),
            [",", "n", "w"]
        )

        let awakeWindow = NSWindow()
        awakeWindow.identifier = NSUserInterfaceItemIdentifier("awake")
        delegate.updateFreeRulerMenuContext(for: awakeWindow)

        XCTAssertTrue(delegate.freeRulerHostMenuItemStates.isEmpty)
        XCTAssertTrue(delegate.freeRulerMenuRoots.allSatisfy { $0.isHidden })
        XCTAssertTrue(delegate.freeRulerDefaultsMenuItem!.isHidden)
        XCTAssertTrue(delegate.freeRulerMenuRoots.allSatisfy { $0.menu == nil })
        XCTAssertNil(delegate.freeRulerDefaultsMenuItem!.menu)
        XCTAssertEqual(settings.keyEquivalent, ",")
        XCTAssertEqual(settings.keyEquivalentModifierMask, .command)
        XCTAssertEqual(settings.action, #selector(AppDelegate.openMainWindowFromStatusItem))
        XCTAssertEqual(newTransfer.keyEquivalent, "n")
        XCTAssertEqual(newTransfer.keyEquivalentModifierMask, .command)
        XCTAssertEqual(newTransfer.action, #selector(AppDelegate.quitFromStatusItem))
        XCTAssertEqual(close.action, #selector(NSWindow.performClose(_:)))
        XCTAssertNil(close.target)
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
