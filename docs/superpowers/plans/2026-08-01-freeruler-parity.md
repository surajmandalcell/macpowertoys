# FreeRuler Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the custom MacPowerToys Ruler implementation with the ruler behavior, visuals, settings, persistence, and commands from FreeRuler commit `d38ca4f673f16c51485940e63eeee68babfbfeed`.

**Architecture:** Vendor FreeRuler's AppKit ruler core and settings resources directly. Keep its geometry and behavior files byte-identical to the pinned upstream commit. Adapt only the standalone `AppDelegate` responsibilities, XIB module names, and product branding needed to run inside MacPowerToys. Remove the current SwiftUI Ruler scene and all custom Ruler models, guides, measurement capture, calibration, history, and copy formats. Continue to launch the Ruler on demand through the existing MacPowerToys launcher, deep link, Raycast command, and App Intent.

**Tech Stack:** Swift 5, AppKit, SwiftUI host shell, XIB resources, XCTest, XCUITest, Xcode 26.2+, macOS 26.2+.

## Global Constraints

- Treat this request as a direct correction of all earlier Ruler requirements. The FreeRuler behavior at the pinned commit is the source of truth.
- Pin the copy to `pascalpp/FreeRuler` commit `d38ca4f673f16c51485940e63eeee68babfbfeed`, dated 2026-06-28. Do not copy from a moving branch.
- Preserve Pascal Balthrop's copyright and the complete MIT license notice in `THIRD_PARTY_NOTICES.md`, and ship the verbatim upstream license as `powertoys/FreeRuler/FreeRuler-LICENSE.txt` inside the app bundle.
- Preserve these FreeRuler behaviors exactly:
  - one 40-point-thick L-shaped ruler window with horizontal and vertical wings;
  - multiple ruler windows, active-ruler cycling, per-ruler settings, grouping, wing visibility, and staggered creation;
  - pixel, millimeter, and inch units;
  - all four zero corners, origin flipping, mouse alignment, reset, movement, resizing, arrow-key nudging, and Shift-arrow 10-point nudging;
  - foreground and background opacity, color, float, shadow, grouping, active border, mouse tick labels, cursors, and hotkey bezels;
  - FreeRuler defaults, ruler-set persistence, per-ruler persistence, and default settings for newly created rulers;
  - `H`, `V`, `U`, `F`, `G`, `S`, `O`, Shift-`H`, Shift-`V`, Command-`,`, Option-Command-`,`, Command-`` ` ``, Command-`N`, Command-`R`, and Command-`W` behavior;
  - the upstream Ruler Settings panel and default-settings window layout, controls, anchoring, color panel behavior, and localizations.
- Delete these MacPowerToys-only Ruler features:
  - separate horizontal, vertical, and joined ruler types;
  - the forced two-ruler pair and 8-point L gap;
  - 48-point thickness and the 30-percent default-size control;
  - points versus backing-pixels semantics and display calibration;
  - guides, crosshairs, region measurement, pins, measurement history, aspect presets, and cursor-marker tools;
  - CSS, SwiftUI, CGRect, JSON, and custom dimension copy output;
  - the SwiftUI Ruler control window, compact titlebar actions, custom context menu, and local Command-`Q` interception;
  - the legacy Control-Option-Command-`R` global shortcut.
- Keep only these MacPowerToys host seams:
  - MacPowerToys remains the bundle, application name, app icon, updater, release vehicle, and launcher.
  - The Ruler opens only when the user launches it. It must not open at MacPowerToys startup or reopen through the host application's dock-reopen path.
  - `macpowertoys://open/ruler`, the legacy URL scheme, the Raycast Ruler launcher, and the Open Ruler App Intent continue to work.
  - The upstream `Free Ruler Settings` title becomes `Ruler Defaults`. The settings layout and controls do not change.
  - The MacPowerToys application settings remain separate. Ruler Settings controls the active ruler, and Ruler Defaults controls new rulers.
  - FreeRuler's standalone app icon, Sparkle updater, app-store rendering code, help book, entitlements, and root MainMenu XIB are not copied.
- Do not migrate the old `ruler.states.v1`, `ruler.style.v1`, measurement, guide, or calibration values. Leave those unused defaults inert so the replacement does not perform a destructive preferences rewrite.
- Do not add a dependency. The host already has AppKit, SwiftUI, Foundation, and Carbon.
- Keep the upstream Swift files byte-identical where listed below. Put all host changes in `AppDelegate+FreeRuler.swift`, the existing host files, and the XIB integration edits.
- Keep upstream's deliberate `NSColor.ignoresAlpha` compatibility code and accept its deprecation warning. Do not modernize vendor behavior during the parity port.
- Do not use FreeRuler's three PNG snapshot tests as the sole visual gate. On this machine, all three snapshots fail against the pinned upstream source under the current Xcode beta and macOS 27 SDK, while all 125 upstream core tests pass. Use the upstream build on the same machine as the visual oracle.
- Do not release, tag, notarize, or publish a new app version as part of this work.

## Pinned Upstream Manifest

Copy these Swift files without edits from `Free Ruler/`:

```text
HorizontalRule.swift
HotkeyBezel.swift
MouseTickTimerPolicy.swift
Notifications.swift
PreferencesController.swift
Prefs.swift
ResizeHandleView.swift
RuleView.swift
Ruler.swift
RulerCursorController.swift
RulerMouseInteractionState.swift
RulerTickLayout.swift
RulerWindow.swift
UnitLabelView.swift
VerticalRule.swift
```

Copy these settings and localization resources:

```text
Base.lproj/PreferencesController.xib
Base.lproj/RulerSettingsController.xib
Base.lproj/RulerSettingsControlsView.xib
Localizable.xcstrings
de.lproj/{MainMenu,PreferencesController,RulerSettingsController,RulerSettingsControlsView}.strings
es.lproj/{MainMenu,PreferencesController,RulerSettingsController,RulerSettingsControlsView}.strings
fi.lproj/{MainMenu,PreferencesController,RulerSettingsController,RulerSettingsControlsView}.strings
ja.lproj/{MainMenu,PreferencesController,RulerSettingsController,RulerSettingsControlsView}.strings
zh-hans.lproj/{MainMenu,PreferencesController,RulerSettingsController,RulerSettingsControlsView}.strings
```

Do not copy these standalone-app files:

```text
AppDelegate.swift as an application entry point
AppIconGenerator.swift
AppIconRenderer.swift
AppStoreScreenshotPreview.swift
AppStoreScreenshotViews.swift
Base.lproj/MainMenu.xib
Free_Ruler.entitlements
Free_Ruler.github.entitlements
Images.xcassets
Info.plist
Info.github.plist
UITestSupport+App.swift
FreeRulerUITestSupport
FreeRuler.help
Sparkle configuration
appstore screenshots
```

---

### Task 1: Record the exact upstream source and legal notice

**Files:**

- Create: `THIRD_PARTY_NOTICES.md`
- Create: `powertoys/FreeRuler/FreeRuler-LICENSE.txt`

- [ ] **Step 1: Recreate the read-only upstream source checkout**

Use a task-specific temporary directory and verify the exact revision before copying any source:

```bash
MPT_FREERULER_SOURCE="$(mktemp -d /tmp/freeruler-source.XXXXXX)"
git clone --filter=blob:none https://github.com/pascalpp/FreeRuler.git "$MPT_FREERULER_SOURCE"
git -C "$MPT_FREERULER_SOURCE" checkout --detach d38ca4f673f16c51485940e63eeee68babfbfeed
git -C "$MPT_FREERULER_SOURCE" rev-parse HEAD
test ! -e /tmp/macpowertoys-freeruler-source
ln -s "$MPT_FREERULER_SOURCE" /tmp/macpowertoys-freeruler-source
```

Expected final line:

```text
d38ca4f673f16c51485940e63eeee68babfbfeed
```

- [ ] **Step 2: Add the third-party notice**

Create `THIRD_PARTY_NOTICES.md` with the upstream URL, pinned commit, `Copyright (c) 2019 Pascal Balthrop`, and the complete MIT permission and warranty text copied from the pinned `LICENSE` file. Copy that `LICENSE` file byte for byte to `powertoys/FreeRuler/FreeRuler-LICENSE.txt`. Do not paraphrase the license.

- [ ] **Step 3: Verify provenance and formatting**

Run:

```bash
rg -n "FreeRuler|d38ca4f673f16c51485940e63eeee68babfbfeed|Pascal Balthrop|Permission is hereby granted" THIRD_PARTY_NOTICES.md
cmp "$MPT_FREERULER_SOURCE/LICENSE" powertoys/FreeRuler/FreeRuler-LICENSE.txt
git diff --check -- THIRD_PARTY_NOTICES.md
```

Expected: all provenance terms are found and `git diff --check` prints nothing.

- [ ] **Step 4: Commit the legal checkpoint**

Before committing, inspect the complete staged diff and stage only the notice:

```bash
git add THIRD_PARTY_NOTICES.md powertoys/FreeRuler/FreeRuler-LICENSE.txt
git diff --cached --check
git diff --cached -- THIRD_PARTY_NOTICES.md powertoys/FreeRuler/FreeRuler-LICENSE.txt
git commit --only THIRD_PARTY_NOTICES.md powertoys/FreeRuler/FreeRuler-LICENSE.txt -m "Ruler: record FreeRuler source and license"
```

---

### Task 2: Replace the custom Ruler core with pinned FreeRuler source

**Files:**

- Create: the 15 files under `powertoys/FreeRuler/` in the pinned Swift manifest
- Create: `powertoys/FreeRuler/AppDelegate+FreeRuler.swift`
- Create: the XIB and localization files under `powertoys/FreeRuler/` in the pinned resource manifest
- Create: `powertoysTests/FreeRulerCoreTests.swift`
- Modify: `powertoys/AppDelegate.swift`
- Delete: `powertoys/Models/RulerModels.swift`
- Delete: `powertoys/Services/RulerManager.swift`
- Delete: `powertoys/Services/RulerGuideController.swift`
- Delete: `powertoys/Services/MeasurementOverlayController.swift`
- Delete: `powertoys/Views/Ruler/RulerControlView.swift`
- Delete: `powertoys/Views/Ruler/RulerOverlayPanel.swift`
- Delete: `powertoys/Views/Ruler/RulerOverlayView.swift`
- Delete: `powertoysTests/RulerManagerTests.swift`

- [ ] **Step 1: Add the upstream core contract before replacing the implementation**

Copy `FreeRulerTests/RulerCoreTests.swift` to `powertoysTests/FreeRulerCoreTests.swift`. Change only `@testable import Free_Ruler` to `@testable import powertoys`. Keep 124 of the upstream commit's 125 core tests. Remove only `testUITestResetClearsSavedRulerSetState`, because it tests the standalone `FREE_RULER_UI_TESTS` helper instead of ruler product behavior. The MacPowerToys launch reset is covered in Task 4.

- [ ] **Step 2: Prove the upstream contract does not pass against the custom implementation**

```bash
MPT_RULER_DERIVED="$(mktemp -d /tmp/macpowertoys-ruler-red.XXXXXX)"
xcodebuild -project powertoys.xcodeproj -scheme powertoys -destination 'platform=macOS' -derivedDataPath "$MPT_RULER_DERIVED" test -only-testing:powertoysTests/RulerCoreTests CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because the current custom Ruler does not expose the upstream FreeRuler contract. Record the first relevant compiler error.

- [ ] **Step 3: Remove the entire custom Ruler implementation**

Delete the eight custom production and test files listed above. Do not leave typealiases, migration shims, hidden controls, or dead measurement code.

- [ ] **Step 4: Vendor the 15 upstream Swift files exactly**

Use `apply_patch` to add the exact content from the pinned checkout. Do not rename upstream types such as `Ruler`, `RulerWindow`, `RulerController`, `RulerManager`, `RulerSettings`, `Prefs`, `Unit`, or `ZeroCorner`.

Verify byte identity:

```bash
MPT_FREERULER_SOURCE=/tmp/macpowertoys-freeruler-source
MPT_FREERULER_FILES=(HorizontalRule.swift HotkeyBezel.swift MouseTickTimerPolicy.swift Notifications.swift PreferencesController.swift Prefs.swift ResizeHandleView.swift RuleView.swift Ruler.swift RulerCursorController.swift RulerMouseInteractionState.swift RulerTickLayout.swift RulerWindow.swift UnitLabelView.swift VerticalRule.swift)
for MPT_FREERULER_FILE in "${MPT_FREERULER_FILES[@]}"; do
  cmp "$MPT_FREERULER_SOURCE/Free Ruler/$MPT_FREERULER_FILE" "powertoys/FreeRuler/$MPT_FREERULER_FILE"
done
```

Expected: `cmp` prints nothing for all 15 files.

- [ ] **Step 5: Vendor the settings XIBs and localizations**

Copy the settings XIBs, string catalog, and `.strings` files from the pinned manifest. Make only these integration edits:

```text
customModule="Free_Ruler" -> customModule="powertoys"
PreferencesController window title="Free Ruler Settings" -> title="Ruler Defaults"
```

Replace the `F0z-JX-Cv5.title` value with `Lineal-Standardeinstellungen` (German), `Valores predeterminados de la regla` (Spanish), `Viivaimen oletusasetukset` (Finnish), `ルーラーのデフォルト設定` (Japanese), and `标尺默认设置` (Simplified Chinese). Keep every upstream control, constraint, action, identifier, segmented item, slider range, checkbox, and button. The project uses a file-system-synchronized root, so do not edit `project.pbxproj`.

- [ ] **Step 6: Adapt the ruler-only upstream AppDelegate responsibilities**

Add stored ruler properties to the existing `AppDelegate`. Put ruler methods in `powertoys/FreeRuler/AppDelegate+FreeRuler.swift`. Preserve upstream bodies unless a host seam requires a change.

Expose these host entry points:

```swift
extension AppDelegate {
    func installFreeRulerRouting()
    func openFreeRuler()
    @IBAction func openPreferences(_ sender: Any)
    func updateFreeRulerForApplicationActivation(_ isActive: Bool)
    func prepareFreeRulerForTermination()
    static func isFreeRulerWindowIdentifier(_ identifier: String?) -> Bool
}
```

Use one `freeRulerDidInitialize` Boolean. The first `openFreeRuler()` call subscribes to preferences, updates display state, restores saved rulers, and calls `showRulers()`. Later calls only show and activate the existing rulers.

Declare stored members used by the separate extension with internal access. Swift `private` and `fileprivate` members in `AppDelegate.swift` are not visible from another file.

Copy the ruler-owned unit, option, settings, preferences, new, cycle, close, align, reset, wing, flip, hotkey, cursor, mouse-timer, persistence, menu-validation, and display methods from upstream. Omit upstream `UITestSupport` state-file writes. When `AppRuntime.isUITesting` is true, reset only the FreeRuler preference keys before the first test-mode ruler opens. Do not copy the upstream application entry point, updater, app icon, screenshot generator, dock-reopen, standalone quit, or auto-show-at-launch behavior.

- [ ] **Step 7: Make the adapted core suite green**

```bash
MPT_RULER_DERIVED="$(mktemp -d /tmp/macpowertoys-ruler-core.XXXXXX)"
xcodebuild -project powertoys.xcodeproj -scheme powertoys -destination 'platform=macOS' -derivedDataPath "$MPT_RULER_DERIVED" test -only-testing:powertoysTests/RulerCoreTests CODE_SIGNING_ALLOWED=NO
```

Expected:

```text
Executed 124 tests, with 0 failures
** TEST SUCCEEDED **
```

- [ ] **Step 8: Verify settings resources in the built bundle**

```bash
MPT_RULER_DERIVED="$(mktemp -d /tmp/macpowertoys-ruler-resources.XXXXXX)"
make build-for-testing DERIVED_DATA="$MPT_RULER_DERIVED"
find "$MPT_RULER_DERIVED/Build/Products/Debug/MacPowerToys.app/Contents/Resources" \( -name 'PreferencesController.nib' -o -name 'RulerSettingsController.nib' -o -name 'RulerSettingsControlsView.nib' -o -name 'Localizable.strings' -o -name 'FreeRuler-LICENSE.txt' \) -print
```

Expected: all three compiled nibs, the development-language strings, and the bundled FreeRuler license are present.

- [ ] **Step 9: Commit the core replacement**

Inspect the complete staged diff. Stage only the files listed for this task. Then run:

```bash
git diff --cached --check
git diff --cached --stat
git commit --only powertoys/FreeRuler powertoys/AppDelegate.swift powertoysTests/FreeRulerCoreTests.swift powertoys/Models/RulerModels.swift powertoys/Services/RulerManager.swift powertoys/Services/RulerGuideController.swift powertoys/Services/MeasurementOverlayController.swift powertoys/Views/Ruler/RulerControlView.swift powertoys/Views/Ruler/RulerOverlayPanel.swift powertoys/Views/Ruler/RulerOverlayView.swift powertoysTests/RulerManagerTests.swift -m "Ruler: replace custom core with FreeRuler"
```

---

### Task 3: Integrate FreeRuler with MacPowerToys launch, lifecycle, and menus

**Files:**

- Modify: `powertoys/AppDelegate.swift`
- Modify: `powertoys/FreeRuler/AppDelegate+FreeRuler.swift`
- Modify: `powertoys/Core/AppInitializer.swift`
- Modify: `powertoys/Core/ToolActionRouter.swift`
- Modify: `powertoys/Core/AppCommands.swift`
- Modify: `powertoys/Core/GlobalShortcutManager.swift`
- Modify: `powertoys/Core/PowerToysIntents.swift`
- Modify: `powertoys/Models/Tool.swift`
- Modify: `powertoys/powertoysApp.swift`
- Modify: `powertoysTests/AppDelegateTests.swift`
- Modify: `powertoysTests/ToolActionRouterTests.swift`
- Modify: `powertoysTests/UtilityToolsTests.swift`

- [ ] **Step 1: Reduce the public Ruler action surface to upstream behavior**

Keep only these Ruler action IDs:

```swift
case rulerOpen = "ruler.open"
case rulerSettings = "ruler.settings"
```

Remove `ruler.new-horizontal`, `ruler.new-vertical`, `ruler.new-joined`, and `ruler.measure`. Remove `.rulerSettings` from `opensWindow`, because the AppKit controller owns the window.

Special-case Ruler before the generic SwiftUI window path:

```swift
func open(toolID: String) {
    let resolved = Self.windowAliases[toolID] ?? toolID
    if resolved == "ruler" {
        execute(ToolActionRequest(action: .rulerOpen))
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    // Existing host and marketplace routing remains unchanged.
}
```

- [ ] **Step 2: Install a lazy action bridge from the host AppDelegate**

Call `installFreeRulerRouting()` from the existing `applicationDidFinishLaunching`. The bridge observes `.toolActionRequested` but does not instantiate a ruler until it receives `.rulerOpen` or `.rulerSettings`.

```swift
switch action {
case .rulerOpen:
    openFreeRuler()
case .rulerSettings:
    openFreeRuler()
    openRulerSettings(self)
default:
    break
}
```

Observe `.commandOpenSettings`. Open the active Ruler Settings panel only when the key window identifier is `ruler-window`, `ruler-settings-window`, `preferences-window`, or `ruler-color-panel`.

- [ ] **Step 3: Forward application lifecycle without auto-opening the ruler**

Add `applicationDidBecomeActive` and `applicationDidResignActive` forwarding that does nothing until `freeRulerDidInitialize` is true. Then run the same foreground/background opacity, mouse-timer, active-border, and cursor updates as upstream.

Call `prepareFreeRulerForTermination()` at the start of the existing asynchronous termination path so the color panel closes and `rulerSetState` is saved before the host exits.

Keep the existing MacPowerToys `applicationShouldHandleReopen`. It opens the launcher and never creates a ruler.

- [ ] **Step 4: Remove the SwiftUI Ruler scene and eager singleton**

Delete the `Window("Ruler Settings", id: "ruler")` scene from `powertoysApp.swift`. Remove `_ = RulerManager.shared` from `AppInitializer.initialize`. The new upstream `prefs` and manager remain lazy until `openFreeRuler()`.

- [ ] **Step 5: Install the exact FreeRuler menus inside the shared app**

Build the upstream `Ruler`, `Unit`, and `Options` top-level menus programmatically in `AppDelegate+FreeRuler.swift`. Use the exact actions, order, separators, states, and key equivalents from the pinned `MainMenu.xib`.

Resolve localized titles from the copied `MainMenu.strings` tables with upstream object IDs:

```swift
func freeRulerMenuTitle(id: String, fallback: String) -> String {
    Bundle.main.localizedString(
        forKey: "\(id).title",
        value: fallback,
        table: "MainMenu"
    )
}
```

The three menus are visible only while a FreeRuler ruler, settings, defaults, or color-panel window is active. Preserve this command map:

```text
Ruler: New Ruler ⌘N; Hide/Show Horizontal H; Hide/Show Vertical V; Ruler Settings… ⌘,
Unit: Pixels; Millimeters; Inches; Cycle Units U
Options: Flip Horizontal ⇧H; Flip Vertical ⇧V; Float F; Shadow S; Group G; Align O; Reset ⌘R
Window Close: ⌘W routes to closeKeyWindow:
Ruler Defaults: ⌥⌘, routes to openPreferences:
Cycle active ruler: ⌘`
```

When a FreeRuler window becomes key, temporarily route the host Window > Close item to `closeKeyWindow:`. Temporarily clear the host Settings and New Transfer key equivalents so the upstream Command-`,` and Command-`N` items are unambiguous. Restore all saved targets, actions, key equivalents, and modifier masks when another tool becomes key. Keep upstream `performRulerHotkey` unchanged.

Keep the MacPowerToys Settings item. In Ruler context, Command-`,` opens active Ruler Settings and Option-Command-`,` opens Ruler Defaults. Outside Ruler context, Command-`,` retains the existing active-tool settings behavior.

- [ ] **Step 6: Remove obsolete host commands and shortcut registration**

Remove `New Horizontal Ruler` from `AppCommands.Utilities`. Remove legacy Carbon hotkey registration ID `1` and its `.rulerNewHorizontal` route. Keep Awake registration ID `2` and every user-configurable global shortcut unchanged.

- [ ] **Step 7: Update launcher and automation copy without adding features**

Change `RulerTool` to describe upstream behavior only:

```swift
let description = "Measure the screen with movable, resizable rulers in pixels, millimeters, or inches."

let manual = [
    ToolManualSection(title: "Rulers", points: [
        "Drag a ruler to move it and drag an end or corner to resize it.",
        "Press ⌘N for another ruler. Use H or V to show or hide a wing, and ⌘` to cycle rulers.",
        "Use U for units, F for floating, S for shadow, G for grouping, and O to align at the pointer."
    ]),
    ToolManualSection(title: "Settings", points: [
        "Press ⌘, to edit the active ruler. Press ⌥⌘, to edit defaults for new rulers.",
        "Choose color, foreground and background opacity, dimensions, float, and shadow."
    ])
]
```

Change the Open Ruler App Intent description to `Opens the MacPowerToys screen rulers.` Raycast needs no source change because it already opens tool ID `ruler` through the shared router.

- [ ] **Step 8: Preserve Ruler dock identity for upstream windows**

Update `AppDelegate.dockIconAsset(for:)` so `ruler-window`, `ruler-settings-window`, `preferences-window`, and `ruler-color-panel` map to `RulerLogo`. Do not rename upstream accessibility identifiers.

- [ ] **Step 9: Update host integration tests**

Make these exact changes:

- `ToolActionRouterTests` parses `macpowertoys://run/ruler.settings?source=test`, classifies no Ruler action as a SwiftUI window action, and rejects every removed custom action.
- `ToolActionRouterTests` proves `ruler-window` is not raised through `presentSingleWindow`.
- `AppDelegateTests` verifies the three upstream menu roots, command equivalents, Option-Command-`,` defaults command, and FreeRuler window identifier matcher.
- `UtilityToolsTests` keeps dock-icon assertions for all four Ruler identifiers and changes the action-ID assertion to `.rulerOpen`.
- Remove every old custom geometry, copy-format, joined-ruler, migration, calibration, and default-size test from `UtilityToolsTests`.

Run:

```bash
MPT_RULER_DERIVED="$(mktemp -d /tmp/macpowertoys-ruler-host.XXXXXX)"
xcodebuild -project powertoys.xcodeproj -scheme powertoys -destination 'platform=macOS' -derivedDataPath "$MPT_RULER_DERIVED" test \
  -only-testing:powertoysTests/AppDelegateTests \
  -only-testing:powertoysTests/ToolActionRouterTests \
  -only-testing:powertoysTests/UtilityToolsTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass.

- [ ] **Step 10: Commit the host integration**

Stage only the files listed for Task 3. Inspect the complete staged diff. Then run:

```bash
git diff --cached --check
git diff --cached --stat
git commit --only powertoys/AppDelegate.swift powertoys/FreeRuler/AppDelegate+FreeRuler.swift powertoys/Core/AppInitializer.swift powertoys/Core/ToolActionRouter.swift powertoys/Core/AppCommands.swift powertoys/Core/GlobalShortcutManager.swift powertoys/Core/PowerToysIntents.swift powertoys/Models/Tool.swift powertoys/powertoysApp.swift powertoysTests/AppDelegateTests.swift powertoysTests/ToolActionRouterTests.swift powertoysTests/UtilityToolsTests.swift -m "Ruler: integrate FreeRuler with MacPowerToys"
```

---

### Task 4: Replace obsolete Ruler tests with upstream parity checks

**Files:**

- Modify: `powertoysTests/FreeRulerCoreTests.swift`
- Modify: `powertoys/Core/WindowStateManager.swift`
- Modify: `powertoys/Views/Components/WindowAccessor.swift`
- Modify: `powertoysTests/UtilityModelTests.swift`
- Modify: `powertoysTests/WindowAccessorTests.swift`
- Modify: `powertoysTests/WindowStateManagerTests.swift`
- Modify: `powertoysUITests/powertoysUITests.swift`

- [ ] **Step 1: Delete remaining custom Ruler contracts**

Remove all Ruler-only tests from `UtilityModelTests.swift`. Remove `ruler` from the production and test compact SwiftUI applet lists in `WindowAccessor.swift` and `WindowAccessorTests.swift`. Remove it from the production and test `WindowStateManager` known and fixed-size lists. The upstream `RulerManager` owns ruler-window persistence.

```bash
rg -n "RulerZeroCorner|RulerState|RulerMeasurement|RulerGeometry|RulerCopyFormat|defaultSizeFraction|displayCalibrations" powertoysTests
```

Expected: no matches.

- [ ] **Step 2: Port focused upstream UI flows into the host UI suite**

Replace `testRulerLaunchStaysInOverlayMode` with these tests:

```text
testRulerLaunchUsesUpstreamWindowAndBothWings
testRulerWingAndUnitHotkeys
testRulerSettingsAndDefaultsShortcuts
testRulerCreatesCyclesAndGroupsMultipleWindows
testRulerCloseWithCommandWLeavesMacPowerToysRunning
```

Use the upstream identifiers:

```swift
let rulerWindow = app.dialogs["ruler-window"]
let horizontalRuler = app.otherElements["horizontal-ruler-view"]
let verticalRuler = app.otherElements["vertical-ruler-view"]
let rulerSettings = app.windows["ruler-settings-window"]
let rulerDefaults = app.windows["preferences-window"]
```

Prove that launch creates one L-shaped ruler and no SwiftUI Ruler scene; `H`, `V`, and `U` match upstream; Command-`,` opens active settings; Option-Command-`,` opens defaults; Command-`N` creates a second ruler; Command-`` ` `` cycles it; `G` toggles grouping without changing the count; and Command-`W` closes the active ruler while MacPowerToys remains running. Do not automate Command-`Q` termination in this focused suite.

- [ ] **Step 3: Prove the core suite detects a real regression**

Temporarily change `Ruler.thickness` from `40` to `41`, run the focused core tests, and confirm a geometry or layout assertion fails. Restore `40` with `apply_patch`, rerun, and record the failing test name. Do not commit the mutation.

- [ ] **Step 4: Run all unit tests**

```bash
MPT_RULER_DERIVED="$(mktemp -d /tmp/macpowertoys-ruler-tests.XXXXXX)"
make test DERIVED_DATA="$MPT_RULER_DERIVED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Build and verify the signed UI runner before launch**

```bash
MPT_RULER_UI_DERIVED="$(mktemp -d /tmp/macpowertoys-ruler-ui.XXXXXX)"
xcodebuild -project powertoys.xcodeproj -scheme powertoys -destination 'platform=macOS' -derivedDataPath "$MPT_RULER_UI_DERIVED" -configuration Debug build-for-testing CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=GF57JXJF5A CODE_SIGN_ENTITLEMENTS= PROVISIONING_PROFILE_SPECIFIER=
codesign --verify --deep --strict "$MPT_RULER_UI_DERIVED/Build/Products/Debug/powertoysUITests-Runner.app"
xcodebuild -project powertoys.xcodeproj -scheme powertoys -destination 'platform=macOS' -derivedDataPath "$MPT_RULER_UI_DERIVED" test-without-building \
  -only-testing:powertoysUITests/powertoysUITests/testRulerLaunchUsesUpstreamWindowAndBothWings \
  -only-testing:powertoysUITests/powertoysUITests/testRulerWingAndUnitHotkeys \
  -only-testing:powertoysUITests/powertoysUITests/testRulerSettingsAndDefaultsShortcuts \
  -only-testing:powertoysUITests/powertoysUITests/testRulerCreatesCyclesAndGroupsMultipleWindows \
  -only-testing:powertoysUITests/powertoysUITests/testRulerCloseWithCommandWLeavesMacPowerToysRunning
```

Expected: `codesign` prints nothing and all five UI tests pass. If the Xcode UI harness fails before an assertion runs, retry once. Then use Task 6 live accessibility checks and report the harness failure separately from product results.

- [ ] **Step 6: Commit the parity coverage**

Stage only the Task 4 files and inspect the staged diff:

```bash
git diff --cached --check
git diff --cached --stat
git commit --only powertoysTests/FreeRulerCoreTests.swift powertoys/Core/WindowStateManager.swift powertoys/Views/Components/WindowAccessor.swift powertoysTests/UtilityModelTests.swift powertoysTests/WindowAccessorTests.swift powertoysTests/WindowStateManagerTests.swift powertoysUITests/powertoysUITests.swift -m "Ruler: replace custom tests with FreeRuler parity coverage"
```

---

### Task 5: Rewrite Ruler requirements and product documentation

**Files:**

- Create: `spec/troubleshoot/ruler.md`
- Modify: `spec/troubleshoot/troubleshoot.md`
- Modify: `spec/troubleshoot/main-shell.md`
- Modify: `spec/troubleshoot/ui-chrome.md`
- Modify: `spec/ruler-request-list.md`
- Modify: `spec/text-extractor-request-list.md`
- Modify: `DESIGN.md`
- Modify: `docs/powertoys-feasibility-and-ruler-plan.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the Ruler troubleshooting invariant and route it**

Create `spec/troubleshoot/ruler.md` with:

```markdown
# Ruler Troubleshooting

## FreeRuler Parity Drift

- **Symptom:** The MacPowerToys Ruler has different geometry, controls, shortcuts, defaults, persistence, or settings from the pinned FreeRuler reference.
- **Cause:** A MacPowerToys customization was reintroduced or an upstream source file was edited inside the vendor directory.
- **Invariant:** Ruler product behavior follows FreeRuler commit `d38ca4f673f16c51485940e63eeee68babfbfeed`. The only permitted differences are MacPowerToys branding, on-demand host launch, host routing, and exclusion of standalone updater, app-icon, help, and app-store infrastructure.
- **Check:** Run `RulerCoreTests`, compare all 15 direct-copy Swift files with the pinned source using `cmp`, then compare the normal signed MacPowerToys ruler and settings windows with a same-machine build of the pinned upstream commit.

## Ruler Launch Ownership

- **Symptom:** A ruler opens when MacPowerToys starts, or the launcher opens a blank SwiftUI Ruler window.
- **Cause:** FreeRuler's standalone startup behavior or the deleted `Window(id: "ruler")` scene was restored.
- **Invariant:** MacPowerToys owns discovery and launches FreeRuler on demand through `ToolActionRouter`. FreeRuler owns every ruler and Ruler settings window after launch.
- **Check:** Launch MacPowerToys with no restored windows, confirm no `ruler-window` exists, then open tool ID `ruler` and confirm one `ruler-window` with both ruler views appears.
```

Add `ruler.md` to the troubleshooting index. Route all future Ruler behavior corrections through it.

- [ ] **Step 2: Replace the dedicated Ruler request list**

Rewrite `spec/ruler-request-list.md` around the new correction. Record the pinned URL and commit; every deleted customization as `Superseded`; parity rows for geometry, visuals, units, movement, resizing, multiple rulers, grouping, persistence, commands, both settings windows, color panel, localizations, host launch, and focus; the 124-test adapted upstream result; the upstream snapshot baseline limitation; and the signed visual comparison result after Task 6.

Do not leave forced-pair, gap, calibration, region capture, copy-format, or Command-`Q` requirements marked `Done`.

- [ ] **Step 3: Remove Ruler from shared compact-window guidance**

Update:

- `spec/troubleshoot/main-shell.md` so the SwiftUI one-window applet list excludes Ruler;
- `spec/troubleshoot/ui-chrome.md` so compact titlebar checks cover Awake, Text Extractor, and Color Picker only;
- `spec/text-extractor-request-list.md` so cross-applet statements no longer cite Ruler;
- `DESIGN.md` so Ruler is a borderless AppKit overlay exception with attached settings panels, not a 560×600 compact SwiftUI applet.

Keep the Ruler logo and orange launcher identity. Those are host branding, not ruler-window styling.

- [ ] **Step 4: Supersede the old feasibility plan**

Add this notice below the title of `docs/powertoys-feasibility-and-ruler-plan.md`:

```markdown
> [!IMPORTANT]
> The Ruler implementation section is superseded by the pinned FreeRuler parity plan in `docs/superpowers/plans/2026-08-01-freeruler-parity.md`. The current product intentionally removes the earlier custom SwiftUI ruler, guides, calibration, measurement capture, and developer copy features.
```

Do not rewrite the historical feasibility research.

- [ ] **Step 5: Update product copy and changelog**

Change the README Ruler row to `Measure the screen with movable, resizable rulers in pixels, millimeters, or inches.` Change the screenshot caption to `Ruler · multiple rulers, precise units, grouping, and per-ruler settings`.

Add an `Unreleased` changelog section with one `Changed` bullet that says the custom Ruler was replaced by the pinned FreeRuler behavior and settings under its MIT license.

- [ ] **Step 6: Verify documentation consistency**

```bash
rg -n "paired rulers|8pt gap|8-point gap|Measure Region|calibrat|RulerCopyFormat|points \(pt\)|defaultSizeFraction|Command-Q close|⌘Q close" README.md DESIGN.md spec docs --glob '*.md'
rg -n "d38ca4f673f16c51485940e63eeee68babfbfeed|FreeRuler" THIRD_PARTY_NOTICES.md spec/ruler-request-list.md spec/troubleshoot/ruler.md docs/superpowers/plans/2026-08-01-freeruler-parity.md
git diff --check
```

Expected: the first search finds only explicitly marked historical or superseded text. The second finds the pinned source in every provenance document. `git diff --check` prints nothing.

- [ ] **Step 7: Commit the documentation checkpoint**

Stage only the Task 5 files and inspect the complete staged diff:

```bash
git diff --cached --check
git diff --cached --stat
git commit --only spec/troubleshoot/ruler.md spec/troubleshoot/troubleshoot.md spec/troubleshoot/main-shell.md spec/troubleshoot/ui-chrome.md spec/ruler-request-list.md spec/text-extractor-request-list.md DESIGN.md docs/powertoys-feasibility-and-ruler-plan.md README.md CHANGELOG.md -m "Ruler: document FreeRuler parity contract"
```

---

### Task 6: Prove live parity, refresh the screenshot, and install the final commit

**Files:**

- Modify: `docs/screenshots/ruler.png`
- Modify: `spec/ruler-request-list.md`

- [ ] **Step 1: Re-run the pinned upstream baseline**

```bash
MPT_FREERULER_SOURCE=/tmp/macpowertoys-freeruler-source
test "$(git -C "$MPT_FREERULER_SOURCE" rev-parse HEAD)" = d38ca4f673f16c51485940e63eeee68babfbfeed
MPT_FREERULER_DERIVED="$(mktemp -d /tmp/freeruler-baseline.XXXXXX)"
xcodebuild -project "$MPT_FREERULER_SOURCE/Free Ruler.xcodeproj" -scheme 'Free Ruler' -destination 'platform=macOS' -derivedDataPath "$MPT_FREERULER_DERIVED" test -only-testing:FreeRulerTests/RulerCoreTests CODE_SIGNING_ALLOWED=NO
```

Expected:

```text
Executed 125 tests, with 0 failures
** TEST SUCCEEDED **
```

Do not require the three upstream PNG snapshot tests to pass under this SDK. Record their same-machine baseline failure as an environment limitation, not a MacPowerToys regression.

- [ ] **Step 2: Build a launchable pinned upstream visual reference**

```bash
xcodebuild -project "$MPT_FREERULER_SOURCE/Free Ruler.xcodeproj" -scheme 'Free Ruler' -configuration Debug -destination 'platform=macOS' -derivedDataPath "$MPT_FREERULER_DERIVED" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
codesign --verify --deep --strict "$MPT_FREERULER_DERIVED/Build/Products/Debug/Free Ruler.app"
```

Expected: the build succeeds and `codesign` prints nothing.

- [ ] **Step 3: Build and install a normal signed MacPowerToys candidate**

Confirm there is no active Cloud Sync transfer. Then run from a clean committed tree:

```bash
git status --short
MPT_FINAL_DERIVED="$(mktemp -d /tmp/macpowertoys-freeruler-final.XXXXXX)"
make test DERIVED_DATA="$MPT_FINAL_DERIVED"
make raycast
make build DERIVED_DATA="$MPT_FINAL_DERIVED"
codesign --verify --deep --strict "$MPT_FINAL_DERIVED/Build/Products/Release/MacPowerToys.app"
plutil -extract MPTSourceCommit raw "$MPT_FINAL_DERIVED/Build/Products/Release/MacPowerToys.app/Contents/Info.plist"
git rev-parse HEAD
```

Expected: the tree is clean, tests and build succeed, `codesign` prints nothing, and both commit hashes match.

Quit the installed MacPowerToys normally, then run:

```bash
make install ALLOW_INSTALL=1 DERIVED_DATA="$MPT_FINAL_DERIVED"
```

- [ ] **Step 4: Compare upstream and integrated products on the same screen**

Use the same display, appearance, scale, unit, zero corner, dimensions, color, opacity, float, shadow, and grouping state. Compare one product at a time.

Verify:

```text
default 40-point L ruler
horizontal-only and vertical-only wings
all four zero corners
pixel, millimeter, and inch ticks and labels
mouse tick and label
move, end resize, corner resize, arrow nudge, and Shift-arrow nudge
active and inactive opacity
float and shadow states
two rulers with grouping off and on
H, V, U, F, G, S, O, Shift-H, Shift-V, Command-`, Command-N, Command-R, and Command-W
Ruler Settings panel and its attached position
Ruler Defaults window
color panel with alpha disabled
hotkey bezel text and placement
close, reopen, persisted geometry, active ruler, and per-ruler settings
```

The only accepted differences are the Global Constraints host seams. Correct any other difference and rerun affected checks.

Also invoke `macpowertoys://open/ruler`, the legacy scheme equivalent, the built Raycast Ruler command, and the Open Ruler App Intent. Each route must raise the existing AppKit rulers instead of opening a SwiftUI scene or creating duplicate restored state. Actual Raycast search registration remains the separate open item already tracked in `spec/ruler-request-list.md`.

- [ ] **Step 5: Capture the real integrated Ruler screenshot**

Capture the normally initialized, signed, installed MacPowerToys build in place on a quiet dark desktop. Show the live ruler and Ruler Settings panel with the native window shadow. Do not use `MACPOWERTOYS_UI_TEST=1`, generated mock UI, or an isolated transparent window composited over another background.

Replace `docs/screenshots/ruler.png` and preview its README rendering at the existing 50-percent column width.

- [ ] **Step 6: Record final evidence and commit the screenshot**

Update `spec/ruler-request-list.md` with exact test totals, signed build result, visual comparison result, and the upstream snapshot environment limitation.

```bash
git diff --check
git add docs/screenshots/ruler.png spec/ruler-request-list.md
git diff --cached --check
git diff --cached --stat
git commit --only docs/screenshots/ruler.png spec/ruler-request-list.md -m "Ruler: record signed FreeRuler parity verification"
```

- [ ] **Step 7: Rebuild and reinstall the exact screenshot commit**

The screenshot commit changes `HEAD`, so rebuild and install again:

```bash
MPT_FINAL_DERIVED="$(mktemp -d /tmp/macpowertoys-freeruler-installed.XXXXXX)"
make test DERIVED_DATA="$MPT_FINAL_DERIVED"
make install ALLOW_INSTALL=1 DERIVED_DATA="$MPT_FINAL_DERIVED"
plutil -extract MPTSourceCommit raw /Applications/MacPowerToys.app/Contents/Info.plist
git rev-parse HEAD
git status --short --branch
```

Expected: tests pass, the installed commit equals `HEAD`, and the worktree is clean.

- [ ] **Step 8: Push the completed checkpoints**

```bash
git log --oneline --decorate -n 8
git status --short --branch
git push origin main
```

Expected: all Ruler checkpoints are on `origin/main`. Do not create a release tag.

## Completion Criteria

- The custom SwiftUI Ruler implementation and every custom Ruler feature are deleted.
- The 15 direct-copy Swift files match the pinned upstream commit byte for byte.
- The adapted upstream core suite executes 124 tests with zero failures.
- All host unit tests and five focused signed UI tests pass, or a UI harness bootstrap failure is reported separately with live accessibility evidence.
- The ruler, menus, settings panels, defaults window, shortcuts, persistence, and multi-ruler behavior match a same-machine build of the pinned upstream commit.
- MacPowerToys does not open a ruler at app startup.
- The launcher, both deep-link schemes, the built Raycast command, and the App Intent route to the AppKit ruler directly.
- Old custom Ruler state is ignored without destructive migration.
- The MIT notice, request list, troubleshooting route, design documentation, changelog, README copy, and real product screenshot are current.
- The final installed app is signed, embeds final `HEAD`, and comes from a clean worktree.
