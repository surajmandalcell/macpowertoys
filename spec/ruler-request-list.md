# Ruler Request List

Reviewed against the pinned [FreeRuler](https://github.com/pascalpp/FreeRuler)
source at commit `d38ca4f673f16c51485940e63eeee68babfbfeed` on 2026-08-24.
Update this list whenever Ruler requirements or verification results change.

## Current parity contract

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Keep the native titlebar visible and aesthetically continuous in Ruler Settings and Defaults. | Both AppKit controllers install the same active HUD material behind their transparent native titlebars instead of a generic window-background slab. The exact signed `7903fb9` build showed one continuous HUD surface with native traffic lights and title text in both windows. | None. |
| Done | Replace the custom MacPowerToys Ruler with FreeRuler while fitting the host architecture. | The pinned MIT source, localization catalog, and notices are vendored under `powertoys/FreeRuler`; MacPowerToys adapts host ownership, launch, routing, branding, and settings-window chrome. | None. |
| Done | Match FreeRuler overlay geometry and visual styling except for current MacPowerToys settings. | The 40pt L shape, ticks, labels, colors, zero corners, and handles follow the pinned build. Host adapters add the independent settings panel, adjustable border opacity, and the default disabled shadow. The core suite covers geometry, drawing, controls, persistence, and reset behavior. | None. |
| Done | Match pixel, millimeter, and inch units. | Core coverage checks tick scales and labels; the signed UI flow cycles `px` → `mm` → `in` → `px`. | None. |
| Done | Match moving and keyboard nudging. | The pinned controller and interaction tests cover direct and grouped drag. In the signed app, Right changed the saved X coordinate by `+1`, and Shift-Down changed the saved Y coordinate by `-10`. | None. |
| Done | Match end and corner resizing. | The upstream resize-handle and cursor code is byte-identical except for the host-delegate lookup. Focused tests cover horizontal and vertical drag, minimum and maximum clamping, cursor behavior, child-window handling, and all four zero corners. | None. |
| Done | Support multiple independent rulers. | The upstream `RulerManager` is preserved; the signed UI flow proves Command-N creates and activates a second ruler and Command-grave cycles rulers. | None. |
| Done | Match grouped and ungrouped ruler behavior. | Upstream tests cover grouping, stack order, follower attachment, grouped dragging, and persistence. The signed app toggled grouping without changing the ruler count and completed a grouped drag. | None. |
| Done | Match FreeRuler persistence. | Tests cover the versioned ruler set, active ruler, per-ruler settings, defaults, frame capture, and corrupt-data fallback. A signed ruler kept the same ID, built-in-display coordinates `[-2267, 1260]`, and `1920 × 1080` lengths through two full quit and relaunch cycles. Settings and Defaults also keep their own frames and display. | None. |
| Done | Match FreeRuler commands and shortcuts. | Host menus reproduce the Ruler, Unit, and Options commands. Core and signed checks cover wing visibility, unit cycling, grouping, floating, shadow, zero-corner flips, reset, new ruler, active-ruler cycling, Settings, Defaults, and close routing. Exact Command-W closes the focused ruler once and keeps the host running. | None. |
| Verify | Keep per-ruler Settings independent from the ruler and align its chrome with MacPowerToys. | The fixed 420pt panel uses the shared section, card, row, typography, and spacing system. It restores its own frame and display. It does not attach to, follow, or obstruct the ruler. Closing Settings leaves the ruler open. Its decorative titlebar material now passes mouse-down events to the native window drag path. Core coverage preserves target-scoped interaction suspension, controls, reset and default actions, color, opacity, dimensions, floating behavior, shadow, accessibility, localization-safe layout, and independent window placement. The signed `f0f4ce6` build showed the detached native panel and confirmed that its close control leaves the ruler open. | Verify titlebar dragging in the final installed build on each connected display. |
| Verify | Disable the ruler shadow by default without changing saved user choices. | The registered and factory-reset default is off. Existing `true` values still load as true. Focused tests cover both paths. The signed `f0f4ce6` panel showed the shadow disabled. | Verify a fresh default and a saved enabled choice in the final installed build. |
| Verify | Add Border Opacity to Ruler Settings and Defaults. | Both native windows provide a localized 0% to 100% slider. The default is 25%, which is half the former 50% border. Per-ruler JSON, global defaults, save-as-default, reset-to-default, factory reset, drawing, keyboard order, and accessibility relationships use the same value. Legacy per-ruler JSON falls back to 25%. The signed `f0f4ce6` panel exposed the accessible Border Opacity slider at 25%. | Verify a live border update in the final installed build. |
| Verify | Preserve Ruler Defaults behavior and align its chrome with MacPowerToys. | The fixed 420pt window removes the duplicate headline and border. It keeps factory reset as one quiet destructive action. The same titlebar drag handle preserves native movement. Core coverage preserves live default edits, persistence, and reset behavior. The launcher opened the native Defaults window. | Verify titlebar dragging in the final installed build. |
| Done | Match the FreeRuler color panel. | Focused tests cover color-well activation, zero-corner anchoring, display clamping, restored-frame ordering, and hidden alpha controls. The signed Settings window exposes the native color well and keeps it in the complete key loop. The current target-scoped bridge could not deliver the custom color-well activation event. | None. |
| Done | Preserve FreeRuler localizations. | The upstream `Localizable.xcstrings` catalog is vendored intact. Signed German and Japanese Ruler Settings checks showed complete labels with no overlap. | None. |
| Done | Launch on demand through MacPowerToys without a SwiftUI Ruler scene. | The launcher, `macpowertoys://open/ruler`, `powertoys://open/ruler`, the Raycast command, and the `Ruler` App Intent each opened or raised one AppKit `ruler-window`. Normal app startup opened no ruler. | None. |
| Done | Show Ruler settings from its launcher detail without duplicating the native implementation. | `Open Ruler Settings` opens the native independent Settings panel. `Open Defaults` opens the native `preferences-window`. | None. |
| Done | Keep Ruler focused so shortcuts do not reach the previously focused app. | Ruler activation makes its borderless AppKit window key and the signed UI suite successfully drives ruler-local shortcuts. In the normal signed `4662560` build, Raycast launched the MacPowerToys Ruler from its focused `Ruler` query. macOS then reported MacPowerToys as frontmost with `ruler-window` as the focused window. The following `H` key hid only the horizontal ruler wing, and a second `H` restored it. | None. |
| Done | Make `Ruler` appear when searching in Raycast. | The Raycast extension builds successfully. A live search on 2026-08-23 showed `Ruler` from MacPowerToys as the first result after the development process stopped. | None. |

## Superseded custom behavior

| Status | Superseded request | Current behavior |
|---|---|---|
| Superseded | Always open exactly two forced-pair rulers. | FreeRuler opens one L-shaped ruler and permits any number of independent rulers. |
| Superseded | Keep an 8pt gap between separate horizontal and vertical overlays. | FreeRuler joins horizontal and vertical wings at one zero corner. |
| Superseded | Add guides, region measurement/capture, and developer copy formats. | Those custom SwiftUI features were deleted; the pinned FreeRuler surface is the product. |
| Superseded | Calibrate each display or expose points as a unit. | FreeRuler provides pixels, millimeters, and inches with its native conversion behavior. |
| Superseded | Default length to 30% of the screen and expose `defaultSizeFraction`. | FreeRuler owns its default dimensions and Defaults window. |
| Superseded | Use a compact 560×600 SwiftUI applet with `New Ruler` and `Measure Region` titlebar actions. | Ruler uses FreeRuler's borderless AppKit overlay plus independent Settings and Defaults windows. |
| Done | Make Command-Q close only Ruler inside the shared process. | `0544fad` routes Command-Q through `RulerManager` to close Settings, Defaults, and every ruler and stop the mouse timer. The signed `f0f4ce6` build confirmed that one Command-Q closes the Ruler scope and leaves the launcher open. | None. |
| Superseded | Apply MacPowerToys-specific 48pt thickness, thin ticks, reduced borders, 75% fill, migrations, and custom state models. | FreeRuler's 40pt geometry, ticks, fill, and state model remain. The current Border Opacity control is the only requested border adjustment. |

## Verification record

- A fresh pinned upstream run passed 125 tests with zero failures or skipped
  tests.
- The host adapters add on-demand routing, independent Settings placement,
  adjustable border opacity, and the default disabled shadow to the pinned
  FreeRuler implementation.
- All 128 focused Ruler tests pass. They cover 420pt utility windows,
  independent Settings placement, border opacity, shadow preference
  preservation, section rhythm, card geometry, 12pt row typography,
  accessibility relationships, the complete key order, 24pt minimum controls,
  and collision-free English, German, and Japanese labels.
- The complete host unit suite passed 400 tests with zero failures or skipped
  tests.
- All five localized controls XIBs compile. Focused tests also verify opaque
  native title bars and the Settings and Defaults autosave names.
- A same-machine comparison of the pinned build and the signed host build
  matched the default 40pt L geometry, tick spacing, labels, and color.
- The signed appearance matrix passed in Light, Dark, Increase Contrast, and
  Reduce Transparency modes. German and Japanese Ruler Settings remained
  readable and collision-free. The original system appearance settings were
  restored after the check.
- The signed route matrix passed for both URL schemes, Raycast, the Ruler App
  Intent, launcher activation, and both launcher settings buttons.
- The signed persistence check kept one ruler ID, built-in-display coordinates,
  and dimensions across two quit and relaunch cycles. The temporary saved ruler
  set was removed after verification.
- The lifecycle check created 24 additional rulers and closed all visible
  rulers. RSS rose from 112,752 KB to 158,528 KB, then stabilized between
  125,088 KB and 125,264 KB. CPU returned to 0.0%, and CPU time stayed flat at
  0:07.80. The original four hidden legacy records did not change.
- The last complete signed UI suite passed all 11 methods across 22 configured
  executions. A new signed runner passed strict code-sign verification on
  2026-08-24, but two attempts timed out while enabling Xcode automation mode
  before any test assertion ran. Live signed checks supplied the final product
  evidence.
- Direct Command-W handler measurements complete in 4-16ms after the first cold
  invocation. The monitor keeps a handled event consumed, so AppKit cannot send
  the same event to the host.
