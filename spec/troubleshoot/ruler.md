# Ruler Troubleshooting

## Unit Presentation Spies, Run 66, 2026-10-01

- **Symptom:** Ruler fixtures call native key-window paths during local tests.
- **Cause:** Controller show, manager showAll and cycleActiveRuler, Settings,
  context menus, new-ruler hotkeys, color wells, and resize handles reach
  real native window ordering or makeKey.
- **Invariant:** Inject a RulerWindow presentation spy through the controller
  window factory and the existing manager factory. Settings presentation uses
  a window spy with the real nib content and delegate. Color-well presentation
  passes through its existing presenter closure to a color-panel spy.
  Keep real model, geometry, grouping, suspension, control, and close paths.
  Keep unpresented nib checks native. Normal factories keep their original
  RulerWindow behavior; never change overlay activation to suit a test.
- **Check:** The class name must match FreeRulerCoreTests. Run only
  `tmp/redesign/tools/xtest.sh <log> -only-testing:powertoysTests/FreeRulerCoreTests`.
  Both guarded runs pass 130 tests with zero failures or skips. The final run
  includes resize fixtures and asserts that color panels stay hidden and
  non-key. The foreground guard does not abort. All original assertions remain.
  Report: `tmp/redesign/logs/w8-ruler-tests.md`.

## Localized Settings Dimensions, 2026-10-01

- **Symptom:** Millimeter or inch fields use a decimal dot in a locale that
  requires a comma. The field formatter rejects the displayed value.
- **Cause:** The controller used locale-free printf formatting while its
  NumberFormatter used the current locale.
- **Invariant:** Format each field with that field's NumberFormatter locale.
  Keep pixel rounding and the existing millimeter and inch precision.
- **Check:** German `25,5` and `3,125` and English `2.750` round trip through
  Foundation. A native text field reads `25,5` as `25.5`. Run
  `RulerDimensionLocaleTests` on CI and inspect both installed windows.

## OnePlusUI Settings Bodies, 2026-09-29

- **Invariant:** Settings and Defaults retain their native independent
  windows, XIB layout, localized strings, and explicit key loop. Their bodies
  use OnePlusUI native surfaces and form styles. Dimension fields add native
  steppers without replacing formatter validation or target/action routing.
  Float and shadow keep NSButton state and shortcuts with switch drawing.
- **Resource rule:** Preference observations capture the controller weakly.
  Delayed color-panel setup does nothing after the active well closes.
- **Check:** The Debug build passes. Run the Ruler geometry, localization,
  and key-loop tests on hosted CI, then inspect both installed windows.

## Ruler Dimensions In Hosted Tests

- **Symptom:** A ruler-settings test passed on the owner's display but failed
  on the hosted Mac when entered millimeters produced a 150-point or 120-point
  ruler instead of the required 200-point minimum.
- **Cause:** Fixed millimeter inputs converted to different pixel lengths on
  different displays. Whole-pixel conversion also shifted the displayed
  millimeters by more than the test's fixed 0.15 tolerance.
- **Invariant:** Derive test inputs above the 200-point minimum from the active
  screen's dots per millimeter. Compare the displayed value within half a pixel
  plus its one-decimal rounding allowance.
- **Check:** The complete hosted run `36096121530` passes `RulerCoreTests`.

## Automated Ruler Window Checks

- **Symptom:** A macOS logout confirmation appeared while the borderless Ruler
  overlay stayed open.
- **Cause:** The automation sent `Command+W`, observed that Ruler remained open,
  then sent `Command+Q` to the same unverified keyboard target. The earlier
  `CMD+W` form had already failed with `keyNotFound("CMD")`. The session trace
  proves this unsafe sequence; it does not prove how macOS routed the last key.
- **Invariant:** Native desktop automation does not send synthetic keyboard
  shortcuts. Once the Ruler overlay is open, use read-only inspection unless
  an explicit visible Ruler control can be used without changing the owner's
  focus. Never click the covered launcher or try another input after an
  unchanged accessibility state.
- **Check:** Confirm the overlay by app-scoped screenshot and accessibility
  state. Use a verified Ruler control or a documented non-GUI close path; if
  neither exists, leave the overlay open. If a system session dialog appears,
  ask the owner to use Cancel before any further UI input. Non-GUI verification
  may continue.

## FreeRuler Parity Drift

- **Symptom:** The MacPowerToys Ruler overlay has different geometry, controls,
  shortcuts, defaults, or persistence from the pinned FreeRuler reference.
- **Cause:** A MacPowerToys customization was reintroduced or an upstream
  source file was edited inside the vendor directory.
- **Invariant:** Ruler product behavior follows FreeRuler commit
  `d38ca4f673f16c51485940e63eeee68babfbfeed`. The only permitted differences
  are MacPowerToys branding, on-demand host launch, host routing, utility-token
  styling for both settings windows, independent Settings placement,
  adjustable border opacity, the default disabled shadow, and exclusion of
  standalone updater, app-icon, help, and App Store infrastructure.
- **Check:** Run `RulerCoreTests`. Compare the vendored Swift files with the
  pinned source and audit each difference against the permitted list. Then
  compare the normal signed MacPowerToys overlay with a same-machine build of
  the pinned commit.

## Ruler Settings Utility Chrome

- **Symptom:** Ruler Settings or Ruler Defaults returns to a narrow flat form,
  a transparent native titlebar, a bordered Defaults group, or duplicate body
  title.
- **Cause:** The pinned FreeRuler settings nib was treated as a visual source of
  truth after settings chrome moved to MacPowerToys utility tokens, or Ruler
  Settings kept only part of the working Ruler Defaults window pattern. A plain
  `NSWindow` with a different native titlebar style mask is not the same pattern.
  Ruler Settings also changed the ruler panel's floating state after it ordered
  itself frontmost. That late Ruler-only change could reorder the ruler above
  Settings and block the native titlebar. Interaction suspension also left the
  borderless ruler pointer-active, so an overlapping ruler could take titlebar
  drags and close-button clicks from Settings.
- **Invariant:** Both fixed 420pt windows use active HUD material in the body
  and opaque native titlebars. Both XIBs instantiate plain `NSWindow` objects
  with the same titled, closable, and miniaturizable native titlebar style.
  Do not add a custom window subclass, titlebar material, or drag overlay. They
  use 20pt outer edges, 16pt section gaps, 8pt
  heading gaps, and 14pt card insets. Cards use a 10pt radius and dynamic label
  color at 5%.
  Settings uses trailing secondary and primary actions. Defaults uses one quiet
  destructive action. Both windows keep their autosaved positions and displays.
  Settings never attaches to or follows a ruler. It keeps a target reference so
  controls update the intended ruler. Closing Settings leaves the ruler open.
  Suspend the target ruler before Settings makes itself key and frontmost. Do
  not mutate the ruler panel level after the final native window ordering.
  Suspended rulers ignore mouse events until the utility window closes.
  The native color panel can remain a child of Settings.
- **Check:** Compile all three XIBs. Run `RulerCoreTests` and the focused signed
  Ruler UI flow. Inspect light, dark, increased-contrast, reduced-transparency,
  English, German, and Japanese states. Confirm each native titlebar remains
  opaque and visibly distinct from the HUD body, with no overlap, 24pt hit frames,
  the complete key loop, Command-W dismissal, and focus return to the ruler.
  Move Settings from the native titlebar, move the ruler, and confirm that the
  Settings window stays in place.
  The ordering regression must prove the target ruler is suspended before
  Settings calls `makeKeyAndOrderFront`. The interaction regression must prove
  that every suspended ruler is click-through and that input returns on close.
  Close Settings and confirm that the ruler stays open.

## Ruler Border And Shadow Defaults

- **Symptom:** A new ruler has a strong border or a shadow, a saved shadow
  choice is lost, or Settings and Defaults show different border values.
- **Cause:** Drawing used a fixed 50% border, or one persistence and reset path
  did not include the new border value.
- **Invariant:** New and factory-reset rulers use a 25% border and no shadow.
  A saved shadow choice remains unchanged. Border Opacity uses one 0% to 100%
  value across per-ruler settings, defaults, JSON, drawing, reset, and
  save-as-default paths. Legacy per-ruler JSON uses 25% when the key is absent.
- **Check:** Run `RulerCoreTests`. Change Border Opacity in Settings and confirm
  an immediate border update. Save it as the default, create a ruler, reset the
  current ruler, and run the factory reset. Confirm each expected value. Enable
  the shadow, relaunch, and confirm that the saved choice remains enabled.

## Background Ruler Open Takes Foreground Focus

- **Symptom:** A background tool URL activates MacPowerToys and selects the
  ruler even though the caller passed activateApp=false.
- **Cause:** The router discarded that choice. The delegate always activated,
  the manager always made the active ruler key, and the controller always
  used NSWindowController.showWindow before ordering.
- **Invariant:** Carry activation through the queued action and native
  delegate, manager and controller. Background opens use orderFrontRegardless
  without showWindow, makeKey or app activation. Default user launches and
  capture paths keep their pinned behavior.
- **Check:** Actual presentation bodies against non-GUI spies fail old source
  and pass both activation choices. The actual router also preserves a queued
  background request. Run `tmp/redesign/perf/w3-windows/check-ruler.py` and
  `check-routes.py`. In current signed source, verify foreground app identity
  after a background open, then test user launch and capture in isolation.

## Ruler Launch Ownership

- **Symptom:** A ruler opens when MacPowerToys starts, or the launcher opens a
  blank SwiftUI Ruler window.
- **Cause:** FreeRuler's standalone startup behavior or the deleted
  `Window(id: "ruler")` scene was restored.
- **Invariant:** MacPowerToys owns discovery and launches FreeRuler on demand
  through `ToolActionRouter`. FreeRuler owns every ruler and Ruler settings
  window after launch.
- **Check:** Launch MacPowerToys with no restored windows, confirm no
  `ruler-window` exists, then open tool ID `ruler` and confirm one
  `ruler-window` with both ruler views appears.

## Command-W Closes The Ruler Once

- **Symptom:** Command-W closes the ruler and then also closes the MacPowerToys
  host window, or feels delayed while a ruler is active.
- **Cause:** A local-event-monitor adapter used
  `handler(event) ?? event`. The ruler handler intentionally returned `nil` to
  consume Command-W, but the nil-coalescing expression resurrected the same
  event. AppKit then dispatched it again after the ruler had closed, with the
  host window newly key.
- **Invariant:** The monitor returns the handler result verbatim while its
  delegate exists; `nil` means consumed. If the delegate has deallocated, it
  returns the original event. Exact Command-W closes the captured ruler
  synchronously, while additional modifiers pass through. Native command state
  publishes only when its rendered value changes during ruler interaction.
- **Check:** Unit-test the installed monitor closure, not only its downstream
  handler: exact Command-W returns nil, extra-modifier Command-W returns the
  identical event, the key-window transition leaves the host open, and a
  deallocated delegate returns the event. In the signed UI build, confirm the
  ruler disappears while MacPowerToys remains running with its host window.
