# Ruler Settings, Close Responsiveness, and macOS 27 Icon Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Keep the shared worktree clean by editing only the files assigned to each workstream and never reverting another worker's changes.

**Goal:** Keep the current FreeRuler ruler behavior and rendering intact, bring both Ruler settings windows into the established MacPowerToys visual system, make Command-W close a ruler correctly on the first press without menu churn or lag, optically normalize applet Dock icons, and give the base app icon a restrained native macOS 27 Liquid Glass finish.

**Architecture:** Preserve the pinned AppKit ruler core, existing controllers, actions, persistence, accessibility identifiers, key equivalents, and zero-corner attachment behavior. Restyle the existing AppKit XIB hierarchy with the same measured tokens used by Awake, Text Extractor, and Color Picker instead of introducing a second settings implementation. Replace dynamic AppKit main-menu surgery with SwiftUI-native `Commands` driven by a small observable Ruler command context. Keep launcher/sidebar SVGs unchanged and apply Dock-only optical padding through one cached AppKit image helper. Supply the base icon as a layered Icon Composer document so the operating system, not baked raster effects, provides macOS 27 material and shine.

**Tech Stack:** Swift 5, AppKit, SwiftUI, XIB/Auto Layout, asset catalogs, Icon Composer 2.0, XCTest, XCUITest, Xcode 27 beta, macOS 27 with macOS 26.2 deployment compatibility.

## Measured Baseline and Non-Negotiable Constraints

- The ruler overlay itself is accepted. Do not alter ruler geometry, tick drawing, mouse tracking, grouping, cursors, opacity behavior, units, hotkeys, persistence, or the adaptive 60/30 Hz mouse-tick timer.
- The settings behavior remains FreeRuler-compatible, but this direct user correction overrides the older rule that settings chrome must remain visually identical to FreeRuler.
- `RulerSettingsControlsView.xib` is currently a flat 312 × 316 form with 15-point insets. `RulerSettingsController.xib` compresses that shared form into a 280-point-wide panel. Both must use one 420-point-wide, non-resizable layout with MacPowerToys section hierarchy and no intersecting frames.
- Awake, Text Extractor, and Color Picker are the visual references: 20-point outer gutter, 16-point content/section spacing, 8 points between section heading and card, 14-point card padding, 10-point card radius, 12-point controls, 12-point medium row titles, and 10-point medium uppercase secondary section headings.
- The exact committed `38ef9f7` Release build closes correctly: 89.3 ms cold and 4.0-15.9 ms warm across five repeats. The accessibility state check itself took 0.4-2.0 seconds, so the previously perceived delay can be testing overhead.
- The current uncommitted native-command candidate has a separate real regression: its first Command-W took about 747 ms, merely caused Ruler/Unit/Options menus to appear, and did not close on a second press. Finish the native command migration with an exact local Command-W safeguard before treating the candidate as shippable.
- The base AppIcon has transparent bounds of 396 × 396 inside a 512-point canvas (58-point inset per edge). Applet SVGs paint the full 512 × 512 canvas, making them 29.3% wider and roughly 67% larger by area in the Dock.
- Do not edit applet SVG geometry; those assets are correctly sized in the launcher and sidebar. Apply the 396/512 scale only when installing an alternate Dock icon.
- Do not bake blur, glare, gradient shine, refraction, or a rounded-square mask into the base icon artwork. Use native Icon Composer material for the macOS 27 finish and retain generated fallback behavior on macOS 26.2.
- Do not add dependencies, replace the AppKit settings controllers with SwiftUI, or create new settings/persistence models.
- Preserve localization keys and validate long German and Japanese labels.
- Preserve unrelated shared-worktree edits. Stage and commit only owned files at each checkpoint, inspect the complete staged diff before every commit, and push each checkpoint to the tracking remote.
- Do not install while Cloud Sync has a queued, running, retrying, or paused transfer.

## Parallel Ownership

- **Settings worker:** owns the three Ruler settings XIBs, the minimal shared AppKit style bridge, Ruler settings layout/accessibility tests, and Ruler settings design/spec updates.
- **Close worker:** owns the native Ruler command context and command menus, removal of legacy menu-repair code, Command-W routing, and menu/close tests. Existing uncommitted changes in those files are intentional starting work and must be completed, not reverted.
- **Icon worker:** owns the deterministic Dock icon image helper, Icon Composer package/layers, and icon-focused tests. It must not edit `AppDelegate.swift`; the primary agent performs the small integration call to avoid overlap with the close worker.
- **Primary agent:** owns plan checkpointing, cross-workstream integration, any one-line shared-file wiring, visual/accessibility/performance verification, full-suite verification, exact-source installation, and final documentation reconciliation.

---

### Task 1: Checkpoint this plan before implementation

**Files:**

- Create: `docs/superpowers/plans/2026-08-01-ruler-settings-close-icons.md`

- [ ] **Step 1: Confirm source and workspace state**

Record `git status --short`, `git log -6 --oneline`, the current Xcode/macOS/Icon Composer versions, and the currently running MacPowerToys path. Treat the four pre-existing dirty menu-integration files as owned work from the preceding Ruler task.

- [ ] **Step 2: Review the plan for unresolved markers and ownership collisions**

Run:

```bash
rg -n "TO[D]O|TB[D]|FIXM[E]" docs/superpowers/plans/2026-08-01-ruler-settings-close-icons.md
git diff --check -- docs/superpowers/plans/2026-08-01-ruler-settings-close-icons.md
```

Expected: no unresolved markers and no whitespace errors.

- [ ] **Step 3: Commit and push the plan alone**

Inspect the entire shared index, stage only the plan, and commit with:

```bash
git commit --only docs/superpowers/plans/2026-08-01-ruler-settings-close-icons.md \
  -m "Ruler: plan settings close and icon finish"
git push
```

---

### Task 2: Remove menu churn and restore first-press Command-W behavior

**Close worker files:**

- Modify: `powertoys/Core/AppCommands.swift`
- Modify: `powertoys/FreeRuler/AppDelegate+FreeRuler.swift`
- Modify: `powertoys/powertoysApp.swift`
- Modify: `powertoys/AppDelegate.swift`
- Modify: `powertoysTests/AppDelegateTests.swift`
- Modify if UI coverage requires it: `powertoysUITests/powertoysUITests.swift`

- [ ] **Step 1: Add failing tests for the intended command model**

Replace tests that expect AppKit menu insertion, KVO/did-update repair, and mutation of host Settings/New/Close menu items. Add coverage that proves:

1. Ruler context is exact for `ruler-window`, `ruler-settings-window`, `preferences-window`, and `ruler-color-panel`.
2. Entering Ruler context publishes Ruler/Unit/Options state; leaving it restores host command visibility without mutating `NSApp.mainMenu`.
3. the native Ruler command set contains the pinned titles, actions, shortcuts, enablement, and selection state;
4. one exact Command-W dispatch through the local Ruler key monitor calls `closeKeyWindow(_:)` and closes the active ruler on its first invocation;
5. Settings and New Transfer are conditionally replaced only while a Ruler-owned window is key;
6. no run-loop observer, `NSApplication.didUpdateNotification` repair callback, `mainMenu` observation, or recursive menu traversal remains.

Run the focused test before implementation and capture the expected failure.

- [ ] **Step 2: Finish the SwiftUI-native command context**

Keep one `@MainActor ObservableObject` shared context with only the state the command menus render: active context, ruler existence, horizontal/vertical wing visibility, unit, float, shadow, and group state. Update it from the existing `updateDisplay()` and window-key routing paths; do not add a second notification bus or timer.

Define `FreeRulerCommands` with the existing upstream-compatible Ruler, Unit, and Options menus and exact shortcuts. Use native command visibility and disabled state. Keep App Settings and New Item replacement inside `AppCommands` so SwiftUI owns its own menu tree.

- [ ] **Step 3: Delete the legacy AppKit menu-repair path**

Delete stored menu roots/defaults/host-state/observer fields, `FreeRulerMenuItemState`, menu factories, attach/detach/repair methods, recursive traversal, host command mutation, did-update/KVO/run-loop repair hooks, and their tests. This is the root-cause fix for menu rebuild churn and Command-W interception.

Keep the existing local key monitor for the Option-Command-comma distinction and exact Command-W. The borderless ruler panel does not provide a reliable native Close command once manual menu mutation is removed. Route only those exact key equivalents and return every unrelated event unchanged.

- [ ] **Step 4: Route Close through the existing ruler owner once**

Use the existing `closeKeyWindow(_:)` root path: close the controller containing the key ruler wing; if a Ruler-owned auxiliary panel is key, let that panel perform its native close; only use the no-key active-ruler fallback when the app is in Ruler context. Do not synchronously rebuild menus, spin the run loop, force persistence, or perform redundant window scans in the key equivalent path.

- [ ] **Step 5: Run focused correctness and timing checks**

```bash
MPT_CLOSE_DERIVED="$(mktemp -d /tmp/macpowertoys-close.XXXXXX)"
xcodebuild -project powertoys.xcodeproj -scheme powertoys \
  -destination 'platform=macOS' -derivedDataPath "$MPT_CLOSE_DERIVED" \
  test -only-testing:powertoysTests/AppDelegateTests CODE_SIGNING_ALLOWED=NO
```

Then build signed and verify ten cycles each from the ruler, Ruler Settings, and Ruler Defaults:

- first Command-W always closes the intended key window;
- no press merely reveals or rebuilds menus;
- cold direct event-to-window-close stays under 150 ms and warm repeats stay under 50 ms on this machine;
- no sustained main-thread sample shows menu repair or recursive menu traversal;
- reopening restores the expected persisted ruler set.

- [ ] **Step 6: Commit and push the close checkpoint**

Stage only the close worker files, inspect the full staged diff, commit `Ruler: make native commands close promptly`, and push.

---

### Task 3: Restyle Ruler Settings and Ruler Defaults using existing tokens

**Settings worker files:**

- Modify: `powertoys/FreeRuler/Base.lproj/RulerSettingsControlsView.xib`
- Modify: `powertoys/FreeRuler/Base.lproj/RulerSettingsController.xib`
- Modify: `powertoys/FreeRuler/Base.lproj/PreferencesController.xib`
- Modify only as needed: `powertoys/FreeRuler/PreferencesController.swift`
- Modify: `powertoys/Views/Components/UtilitySectionStyle.swift`
- Modify: `powertoysTests/FreeRulerCoreTests.swift`
- Modify: `powertoysUITests/powertoysUITests.swift`
- Modify: `DESIGN.md`
- Modify: `spec/troubleshoot/ruler.md`
- Modify: `spec/ruler-request-list.md`

- [ ] **Step 1: Lock behavior with existing tests and add failing layout tests**

Keep existing coverage for units, dimensions, color, both opacity sliders, float, shadow, reset/save defaults, factory reset, F/S keys, key-view order, child attachment, zero-corner positioning, color-panel clamping, and interaction suspension.

Replace the old flat-form layout assertion with tests for:

- 420-point fixed window width for both panels;
- 20-point shared outer edges;
- 16-point section gaps;
- 8 points from uppercase heading to card;
- 14-point content insets and 10-point card radius;
- 12-point row title/control typography and aligned baselines within one point;
- no intersecting frames under English, German, or Japanese localization;
- minimum 24-point interactive frames;
- preserved identifiers, labels/`labelledBy` relations, and complete key-view loop;
- the per-ruler controller remains a closable `NSPanel` with `.utilityWindow` behavior and child attachment.

Run the focused tests and capture the expected failures before editing XIBs.

- [ ] **Step 2: Add the smallest AppKit token bridge**

Reuse the values already defined by `UtilityLayout`. Add only the native views XIB cannot express reliably:

- a layer-backed section card view using dynamic `labelColor` at 0.05 opacity, 10-point radius, and `updateLayer()` so appearance changes do not cache a stale CGColor;
- an active `.hudWindow` material host if a plain XIB visual-effect view cannot provide the established utility background consistently.

Do not add a general design system, a SwiftUI wrapper, or a new model.

- [ ] **Step 3: Rebuild the shared controls into three sections**

Retain the current outlets/actions and arrange them as:

1. **MEASUREMENT:** Unit row; Dimensions row.
2. **APPEARANCE:** Ruler Color row; Foreground Opacity row; Background Opacity row.
3. **WINDOW:** Float ruler row; Show ruler shadow row.

Keep px/mm/in segments, dimension formatters, color-panel anchor, opacity ranges 5…100, 20 tick marks, 5% snapping, continuous actions, checkbox key equivalents, and reset-color visibility logic unchanged.

- [ ] **Step 4: Align window chrome and action hierarchy**

Make both windows 420 points wide, fixed-size, clear/non-opaque over an active HUD material, with transparent native titlebars. Do not add CompactTitlebar, tabs, floating settings buttons, or any overlay chrome.

For Ruler Settings, place `Reset to Default` as the secondary action and `Save as Default` as the primary action in one trailing 28-point action row. For Ruler Defaults, remove the duplicate bold headline and bordered box, and present `Reset to Factory Defaults` as a quiet destructive action. Preserve titles, actions, localizations, window identifiers, and restoration behavior.

- [ ] **Step 5: Update the design contract narrowly**

Amend the older parity language so ruler overlays and behavior remain pinned to FreeRuler while both settings windows follow MacPowerToys utility tokens. Record the new verification results in the Ruler request list and troubleshooting entry.

- [ ] **Step 6: Verify behavior, layout, accessibility, and localization**

Run the focused core/UI tests. On a signed clean build inspect both windows in light/dark appearance, increased contrast, reduced transparency, and English/German/Japanese. Check side-by-side rhythm against Awake, Text Extractor, and Color Picker; exercise all four zero corners, color-panel clamping, Tab order, Escape/Command-W dismissal, save/reset actions, and focus return to the ruler.

- [ ] **Step 7: Commit and push the settings checkpoint**

Stage only settings-owned files, inspect the full staged diff, commit `Ruler: align settings with utility design`, and push.

---

### Task 4: Normalize applet Dock icons without changing launcher assets

**Icon worker files:**

- Create: `powertoys/Core/DockIconImage.swift`
- Modify: `powertoysTests/UtilityToolsTests.swift`
- Modify by primary agent after worker completion: `powertoys/AppDelegate.swift`

- [ ] **Step 1: Add a failing optical-bounds test**

Render a full-canvas fixture through the future helper at a 512-point canvas. Assert the alpha bounds are exactly 396 × 396 at x=58, y=58. Add the same assertion for every non-AppIcon alternate Dock asset. Add a system-reset result for AppIcon. Deliberately prove a 1.0 scale mutation fails the bounds test.

- [ ] **Step 2: Add one cached Dock-only image helper**

Use an `NSImage` drawing handler to center a named vector image on a same-size clear canvas at the exact scale `396.0 / 512.0`. Cache the result per asset/appearance as needed so focus changes do not repeatedly redraw. Preserve vector input and do not create raster asset sets.

For `AppIcon`, return the system-reset path rather than a padded alternate image. In `AppDelegate.updateDockIcon(for:)`, assign `nil` to `NSApp.applicationIconImage` for the base icon so AppKit restores the bundle's system-rendered icon; assign the helper result only for applet windows.

- [ ] **Step 3: Verify switching and appearance behavior**

Run icon unit tests, then on a signed app switch repeatedly among main, Ruler, Awake, Color Picker, and Text Extractor windows. Verify equal enclosure bounds within two Dock pixels at 32-point and maximum Dock size, no cumulative growth, correct light/dark variants, and no launcher/sidebar size change.

- [ ] **Step 4: Commit and push the Dock icon checkpoint**

Stage the helper, focused tests, and the small AppDelegate wiring only. Inspect the complete staged diff, commit `Icons: normalize applet Dock scale`, and push.

---

### Task 5: Move the base app icon to native macOS 27 material

**Icon worker files:**

- Create: `powertoys/AppIcon.icon/icon.json`
- Create: layered SVG sources inside `powertoys/AppIcon.icon/` as produced by Icon Composer
- Remove only after fallback validation: `powertoys/Assets.xcassets/AppIcon.appiconset/*`
- Modify if source documentation needs clarification: `DESIGN.md`

- [ ] **Step 1: Create deterministic source layers**

Start from the accepted bolt identity in `docs/appicon.svg`, split into a quiet echo layer and primary white bolt layer, and use a solid `#1C1D22` Icon Composer fill. Do not import the flat rounded-square background mask. Keep the layer artwork SVG and human-reviewable.

- [ ] **Step 2: Configure with installed Icon Composer 2.0**

Use Design Generation 27. Let native material provide restrained specular response on the primary bolt, keep refraction low and the echo subordinate, and add no custom blur, glow, baked shadow, or gradient. Save the `.icon` package under the synchronized `powertoys` target root.

- [ ] **Step 3: Build and validate both platform generations**

Confirm the existing `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` resolves the `.icon` document without a project-file edit. Use `ictool` to export/inspect Design Generation 27 and 26 renditions at multiple sizes. Verify the 26.2 fallback retains the accepted silhouette, transparent enclosure, contrast, and legibility before removing the legacy `AppIcon.appiconset`.

Build the app and inspect `Assets.car`, bundle icon metadata, Finder, About, launcher, and Dock. Ensure the base icon resets through the system path after leaving an applet.

- [ ] **Step 4: Validate native response instead of baked shine**

Check the icon in light/dark appearance and at small/large Dock sizes. The highlight should respond to system light, the bolt must remain recognizable at 16/32 points, and no static gloss artifact may appear in the source SVG exports.

- [ ] **Step 5: Commit and push the base icon checkpoint**

Stage only the `.icon` package, validated legacy-set removal, tests, and any precise design-source clarification. Inspect the complete staged diff, commit `Icons: adopt native macOS 27 app material`, and push.

---

### Task 6: Full regression, visual audit, performance audit, and docs reconciliation

**Primary agent files:**

- Modify as evidence requires: `spec/ruler-request-list.md`
- Modify as evidence requires: `spec/troubleshoot/ruler.md`
- Modify as evidence requires: `spec/troubleshoot/main-shell.md`
- Modify as evidence requires: `DESIGN.md`

- [ ] **Step 1: Reconcile parallel diffs and delete dead compatibility code**

Inspect `git status`, `git diff`, recent commits, and overlapping symbols. Resolve only actual overlap. Search for dead menu-repair fields/methods, stale old-settings parity language, and duplicate icon paths. Do not leave compatibility shims or unused abstractions.

- [ ] **Step 2: Run static checks and focused suites**

```bash
git diff --check
rg -n "freeRulerMenuRoots|freeRulerHostMenuItemStates|repairFreeRulerMenu|didUpdateNotification|freeRulerMainMenuObservation|freeRulerMenuRepairObserver" powertoys powertoysTests

MPT_FINAL_DERIVED="$(mktemp -d /tmp/macpowertoys-final.XXXXXX)"
xcodebuild -project powertoys.xcodeproj -scheme powertoys \
  -destination 'platform=macOS' -derivedDataPath "$MPT_FINAL_DERIVED" \
  test -only-testing:powertoysTests/AppDelegateTests \
       -only-testing:powertoysTests/FreeRulerCoreTests \
       -only-testing:powertoysTests/UtilityToolsTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: the dead-code search is empty and all focused tests pass.

- [ ] **Step 3: Run the complete test matrix from a unique DerivedData path**

Run the repository's required formatting/build checks, the entire unit suite, and the signed UI suite using fresh products. Record the exact counts and `.xcresult` paths. Re-run any flaky failure once only after classifying whether it is product, harness, or environment; never dismiss a product failure as test overhead.

- [ ] **Step 4: Perform signed live verification**

From one exact clean-source signed build, verify:

- Ruler overlay visuals/behavior remain unchanged;
- Ruler Settings and Defaults match utility rhythm and every control works;
- Command-W closes on the first press from ruler wings and both auxiliary panels;
- Ruler/Unit/Options menus appear without delayed rebuilding and host commands return outside Ruler context;
- applet Dock icons match the base enclosure and do not grow across window switches;
- the base icon shows the native macOS 27 material and its macOS 26.2 fallback remains acceptable;
- light/dark, increased contrast, reduced transparency, keyboard navigation, VoiceOver labels, and long localization layouts pass.

- [ ] **Step 5: Record final evidence and checkpoint**

Update only durable troubleshooting/design/request-list facts, including the measured committed-build timing, accessibility-test overhead, the eliminated experimental menu regression, and the distinction between Dock optical padding and launcher SVG scale. Commit `Ruler: record finish verification` and push.

---

### Task 7: Build, install, and verify the exact committed source

- [ ] **Step 1: Require a clean committed tree**

Confirm `git status --short` is empty, `git rev-parse HEAD` is the intended pushed commit, and no Cloud Sync transfer is queued, running, retrying, or paused.

- [ ] **Step 2: Install from unique clean DerivedData**

Quit temporary candidates normally. Run:

```bash
MPT_INSTALL_DERIVED="$(mktemp -d /tmp/macpowertoys-install.XXXXXX)"
make install ALLOW_INSTALL=1 DERIVED_DATA="$MPT_INSTALL_DERIVED"
```

- [ ] **Step 3: Prove installed-source identity and live behavior**

Verify code signature, bundle identifier, executable architecture, and that the installed `MPTSourceCommit` equals `git rev-parse HEAD`. Launch the installed `/Applications/MacPowerToys.app`, confirm that exact process path, repeat one smoke flow for settings/Command-W/icons, and ensure no UI-test environment variables are present.

- [ ] **Step 4: Final handoff**

Report the implementation outcome, focused/full/UI test counts and result paths, measured Command-W response, installed source commit, and any deliberately skipped scope in no more detail than needed. Do not claim completion until every required check above has current evidence.
