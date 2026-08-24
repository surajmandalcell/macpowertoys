# Ruler Request List

Reviewed against the pinned [FreeRuler](https://github.com/pascalpp/FreeRuler)
source at commit `d38ca4f673f16c51485940e63eeee68babfbfeed` on 2026-08-24.
Update this list whenever Ruler requirements or verification results change.

## Current parity contract

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Keep the native titlebar visibly distinct in Ruler Settings and Defaults. | Both AppKit controllers use `.windowBackgroundColor` behind the native titlebar while retaining the HUD material body. Focused `RulerCoreTests` pass. | Inspect both windows in the latest normal signed build. |
| Done | Replace the custom MacPowerToys Ruler with FreeRuler while fitting the host architecture. | The pinned MIT source, localization catalog, and notices are vendored under `powertoys/FreeRuler`; MacPowerToys adapts host ownership, launch, routing, branding, and settings-window chrome. | None. |
| Done | Match FreeRuler overlay geometry and visual styling. | Ten product Swift files are byte-identical. Four files differ only in the host-delegate lookup. `PreferencesController.swift` contains the intentional MacPowerToys settings chrome. The core suite covers the 40pt L shape, ticks, labels, colors, zero corners, handles, opacity, shadow, and layout. A same-machine comparison matched the pinned build and the signed host build. | None. |
| Done | Match pixel, millimeter, and inch units. | Core coverage checks tick scales and labels; the signed UI flow cycles `px` → `mm` → `in` → `px`. | None. |
| Done | Match moving and keyboard nudging. | The pinned controller and interaction tests cover direct and grouped drag. In the signed app, Right changed the saved X coordinate by `+1`, and Shift-Down changed the saved Y coordinate by `-10`. | None. |
| Done | Match end and corner resizing. | The upstream resize-handle and cursor code is byte-identical except for the host-delegate lookup. Focused tests cover horizontal and vertical drag, minimum and maximum clamping, cursor behavior, child-window handling, and all four zero corners. | None. |
| Done | Support multiple independent rulers. | The upstream `RulerManager` is preserved; the signed UI flow proves Command-N creates and activates a second ruler and Command-grave cycles rulers. | None. |
| Done | Match grouped and ungrouped ruler behavior. | Upstream tests cover grouping, stack order, follower attachment, grouped dragging, and persistence. The signed app toggled grouping without changing the ruler count and completed a grouped drag. | None. |
| Done | Match FreeRuler persistence. | Tests cover the versioned ruler set, active ruler, per-ruler settings, defaults, frame capture, and corrupt-data fallback. A signed ruler kept the same ID, built-in-display coordinates `[-2267, 1260]`, and `1920 × 1080` lengths through two full quit and relaunch cycles. Settings and Defaults also keep their own frames and display. | None. |
| Done | Match FreeRuler commands and shortcuts. | Host menus reproduce the Ruler, Unit, and Options commands. Core and signed checks cover wing visibility, unit cycling, grouping, floating, shadow, zero-corner flips, reset, new ruler, active-ruler cycling, Settings, Defaults, and close routing. Exact Command-W closes the focused ruler once and keeps the host running. | None. |
| Done | Preserve the attached per-ruler Settings behavior and align its chrome with MacPowerToys. | The fixed 420pt panel uses the shared section, card, row, typography, and spacing system. Core coverage preserves attachment, anchoring, suspension, controls, reset/defaults, color, opacity, dimensions, float, shadow, accessibility, and localization-safe layout. Signed checks cover the full key loop and focus return. | None. |
| Done | Preserve Ruler Defaults behavior and align its chrome with MacPowerToys. | The fixed 420pt window removes the duplicate headline and border. It keeps factory reset as one quiet destructive action. Core coverage preserves live default edits, persistence, and reset behavior. The launcher opened the native Defaults window. | None. |
| Done | Match the FreeRuler color panel. | Focused tests cover color-well activation, zero-corner anchoring, display clamping, restored-frame ordering, and hidden alpha controls. The signed Settings window exposes the native color well and keeps it in the complete key loop. The current target-scoped bridge could not deliver the custom color-well activation event. | None. |
| Done | Preserve FreeRuler localizations. | The upstream `Localizable.xcstrings` catalog is vendored intact. Signed German and Japanese Ruler Settings checks showed complete labels with no overlap. | None. |
| Done | Launch on demand through MacPowerToys without a SwiftUI Ruler scene. | The launcher, `macpowertoys://open/ruler`, `powertoys://open/ruler`, the Raycast command, and the `Ruler` App Intent each opened or raised one AppKit `ruler-window`. Normal app startup opened no ruler. | None. |
| Done | Show Ruler settings from its launcher detail without duplicating the native implementation. | `Open Ruler Settings` opened the native attached panel. `Open Defaults` opened the native `preferences-window`. | None. |
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
| Superseded | Use a compact 560×600 SwiftUI applet with `New Ruler` and `Measure Region` titlebar actions. | Ruler uses FreeRuler's borderless AppKit overlay plus attached Settings and separate Defaults windows. |
| Superseded | Make Command-Q close only Ruler inside the shared process. | Command-Q retains standard app Quit behavior; focused ruler windows close with Command-W. |
| Superseded | Apply MacPowerToys-specific 48pt thickness, thin ticks, reduced borders, 75% fill, migrations, and custom state models. | FreeRuler's exact 40pt geometry, drawing, defaults, and persistence own those contracts. |

## Verification record

- A fresh pinned upstream run passed 125 tests with zero failures or skipped
  tests.
- Ten product Swift files are byte-identical to the pinned source. Four files
  differ only in host-delegate lookup. `PreferencesController.swift` contains
  the intentional MacPowerToys chrome and accessibility work.
- All 126 focused Ruler tests pass. They cover 420pt utility windows, section
  rhythm, card geometry, 12pt row typography, accessibility relationships, the
  complete key order, 24pt minimum controls, and collision-free English,
  German, and Japanese labels.
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
