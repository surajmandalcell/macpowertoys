# Ruler Request List

Test audit, run 65, 2026-10-01: RulerCoreTests still calls controller show,
manager showAll and cycleActiveRuler, and Settings presentation paths that
can make real windows key. The orchestrator owns replacement of these calls
with presentation spies and isolated checks of real native presentation.
The inactive host policy does not replace these native calls. No direct
Finder opener is found, and the Finder foreground change has no proved cause.
Ruler fixtures were not changed or rerun in this task.
Report: `tmp/redesign/logs/w8-tests-finish.md`.

Local verification, run 64, 2026-10-01: the Settings presentation spy orders
its fixture offscreen without making it key. Its suspension and visibility
assertions remain. The XCTest host prohibits activation. Both desktop test
bundles compile; no unit test executes before the foreground guard stops.
Ruler execution waits for the orchestrator. The installed app is unchanged.
Report: `tmp/redesign/logs/w8-tests-quiet.md`.

Local verification, run 63, 2026-10-01: the guarded app run stops before
RulerCoreTests when FocusEffectTests activates MacPowerToys. Ruler's current
local execution remains open. No Ruler window or installed app was changed.
Report: `tmp/redesign/logs/w7-local-tests.md`.

Background creation, run 60, 2026-10-01: retain false activation intent
through cold and reused Ruler and Ruler Settings creation. Background routes
must only order the window. Explicit opens keep activation and key ordering.
The actual Ruler presentation check passes background and explicit ordering.
The final app module and changed tests typecheck after repair of the single
compile-gate error. The guarded installed replay remains with the orchestrator.
Report: `tmp/redesign/logs/w6-no-activation.md`.

Background opens, run 55, 2026-10-01: `a5a87ec8` removes automatic
SwiftUI URL scene selection across the app. The existing `ruler.settings`
route from `d6ccf9cb` already passes false activation intent through the
action handler and Settings controller. Actual-source non-GUI checks pass
for background ruler/settings ordering and explicit key ordering.
Final app and changed-test typechecks pass. The one tests gate failed on
an ID list still used by Command-Q; that list is restored. Both URL schemes,
cold/reused Settings, explicit user opens, and signed foreground identity
remain with the orchestrator. Report: `tmp/redesign/logs/w4-focus-fix.md`.

Round 11 shared focus, 2026-10-01: native tables keep keyboard focus after
row clicks without focus paint when accessibility modes are off. Key-window
reactivation preserves valid responders and active text selection. Detached,
hidden, disabled, or fully clipped responders are cleared. All six focus
package checks and all 17 focused chrome checks pass. Signed Tab, Shift-Tab,
arrows, Space, Return, VoiceOver, and scroll/tab checks remain with the
orchestrator. Report: `tmp/redesign/logs/w3-chrome.md`.

Glyph pass, 2026-10-01: `91d9a538` defines Ruler at -45 degrees in
`ToolGlyph`. Sidebar, fallback tile, Home action, and launcher Settings use
that definition. The 14-tool contact sheet was reviewed at 16pt and 32pt in
both appearances. Both shared compile gates pass. Signed review remains
with the orchestrator.

Production window performance, 2026-10-01: the tool router now records Ruler
open through native layout and display submission in the shared timing ledger.
Round 11 `bed02260` carries activateApp through the queued action, delegate,
manager and controller. A background open only orders the overlay; user
launches keep activation and key ordering. The actual presentation-body
check fails on old source and passes both choices. The actual router check
also proves queued intent. The installed `198055e4` still activates, so no
live Ruler open was sent. The Debug app and both test bundles compile. Signed
foreground identity, capture-session behavior and latency remain.
See `tmp/redesign/perf/w1-windows.md`.

Reviewed against the pinned [FreeRuler](https://github.com/pascalpp/FreeRuler)
source at commit `d38ca4f673f16c51485940e63eeee68babfbfeed` on 2026-08-31.
Update this list whenever Ruler requirements or verification results change.

## Production audit, 2026-10-01

Both shared build modes pass for the Debug app and both desktop test bundles.
The new regression tests compile. Hosted tests and signed checks remain open.

Main launcher, `4ab747b9`: Settings and Defaults are two related native
actions directly on one row. Single-action card wrappers are removed under
the horizontal-density correction. The Settings button keeps the shared
slanted Ruler glyph. Both actions follow tool enablement. `11388f43` uses this
shared body and puts the separate "Open Ruler" action in the fixed footer.
Both shared compile modes pass. Hosted checks and signed interaction remain.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Build verified; signed review pending | Show and dismiss hotkey feedback at once in both Reduce Motion modes. | `0948ba7a` removes the custom AppKit alpha animations. The existing 1.2-second dismissal and native panel ordering stay in place. The gated Debug retry compiles the app and both desktop test bundles. Ruler geometry and controls are unchanged. | Check grouping, units, float, shadow, and origin feedback in the installed app. Report: `tmp/redesign/logs/w1-motion-sweep.md`. |
| Verify | Preserve decimal dimensions in each field's locale. | `adcf8bf2` formats millimeters and inches with the corresponding NumberFormatter locale. Foundation round trips passed German and English decimals. A native NSTextField read `25,5` back as `25.5`. `RulerDimensionLocaleTests` covers unit conversion and separate field locales. | Run on CI, then edit both windows in German and English in the signed app. |
| Verify | Show the color-well focus marker only under the shared keyboard focus policy. | `adcf8bf2` gates the existing first-responder marker with `OnePlusFocusPolicy.showsFocus`. | Verify mouse, Tab, VoiceOver, and Full Keyboard Access behavior in the signed app. |
| Verify | Audit Settings and Defaults units, dimensions, color panel, opacity, border, float, shadow, reset, Save as Default, persistence, key loop, localization, independent placement, and close restoration. | Both controllers, the shared controls view, and all three XIBs were traced. Existing FreeRulerCoreTests cover routing, controls, layout, persistence, and target suspension. | Current-source install and both native windows require the orchestrator. Ruler opening activates the app, so the audit did not open it. The pinned overlay stays unchanged. S5 and A4-A7 remain open. |
| Verify | Apply the horizontal density and instant-motion correction without changing the pinned overlay. | The native controls already use same-row values, adjacent actions, grouped multi-row content, and no custom hover or page animation. No further Ruler code or XIB change was needed. | Check both native windows after installation. |


## OnePlusUI redesign, 2026-09-29

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Apply the owner-review fixed-region and render-path rules to Ruler Settings and Defaults. | Both native AppKit windows are fixed card stacks. They have no table, list, toolbar, inspector, footer, scroll view, SwiftUI page header, or dropdown. XIB loading remains on the main actor as AppKit requires. No source change was needed. | Recheck both native windows in the signed build. |
| Verify | Restyle Settings and Defaults bodies with OnePlusUI cards and native controls. Keep native titlebars, independent windows, localization, key order, and the pinned overlay. | Debug build passes. Both XIBs use shared native surfaces, switches, and dimension steppers. Preference observers capture the controller weakly. DESIGN.md v14 replaces the older HUD material rules below. | Review both windows, localized labels, color panels, and key order in the orchestrator's installed build. |

## Current parity contract

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Keep the native titlebar visible and aesthetically continuous in Ruler Settings and Defaults. | Both AppKit controllers keep opaque native titlebars above the shared HUD body. No custom titlebar material or drag overlay remains. The 129-test Ruler suite checks opaque, movable, non-full-size native chrome. | None. |
| Done | Replace the custom MacPowerToys Ruler with FreeRuler while fitting the host architecture. | The pinned MIT source, localization catalog, and notices are vendored under `powertoys/FreeRuler`; MacPowerToys adapts host ownership, launch, routing, branding, and settings-window chrome. | None. |
| Done | Match FreeRuler overlay geometry and visual styling except for current MacPowerToys settings. | The 40pt L shape, ticks, labels, colors, zero corners, and handles follow the pinned build. Host adapters add the independent settings panel, adjustable border opacity, and the default disabled shadow. The core suite covers geometry, drawing, controls, persistence, and reset behavior. | None. |
| Done | Match pixel, millimeter, and inch units. | Core coverage checks tick scales and labels; the signed UI flow cycles `px` → `mm` → `in` → `px`. | None. |
| Done | Match moving and keyboard nudging. | The pinned controller and interaction tests cover direct and grouped drag. In the signed app, Right changed the saved X coordinate by `+1`, and Shift-Down changed the saved Y coordinate by `-10`. | None. |
| Done | Match end and corner resizing. | The upstream resize-handle and cursor code is byte-identical except for the host-delegate lookup. Focused tests cover horizontal and vertical drag, minimum and maximum clamping, cursor behavior, child-window handling, and all four zero corners. | None. |
| Done | Support multiple independent rulers. | The upstream `RulerManager` is preserved; the signed UI flow proves Command-N creates and activates a second ruler and Command-grave cycles rulers. | None. |
| Done | Match grouped and ungrouped ruler behavior. | Upstream tests cover grouping, stack order, follower attachment, grouped dragging, and persistence. The signed app toggled grouping without changing the ruler count and completed a grouped drag. | None. |
| Done | Match FreeRuler persistence. | Tests cover the versioned ruler set, active ruler, per-ruler settings, defaults, frame capture, and corrupt-data fallback. A signed ruler kept the same ID, built-in-display coordinates `[-2267, 1260]`, and `1920 × 1080` lengths through two full quit and relaunch cycles. Settings and Defaults also keep their own frames and display. | None. |
| Done | Match FreeRuler commands and shortcuts. | Host menus reproduce the Ruler, Unit, and Options commands. Core and signed checks cover wing visibility, unit cycling, grouping, floating, shadow, zero-corner flips, reset, new ruler, active-ruler cycling, Settings, Defaults, and close routing. Exact Command-W closes the focused ruler once and keeps the host running. | None. |
| Done | Make Command-Q close only Ruler inside the shared process. | `0544fad` routes Command-Q through `RulerManager` to close Settings, Defaults, every ruler, and the mouse timer. The signed `f0f4ce6` build confirmed that one Command-Q closes the Ruler scope and leaves the launcher open. | None. |
| Verify | Keep per-ruler Settings independent from the ruler and align its chrome with MacPowerToys. | The fixed 420pt Settings window copies the complete native titlebar pattern from Ruler Defaults: the same plain independent `NSWindow` class and titled, closable, and miniaturizable style mask. It is not an `NSPanel`, utility window, child, or sheet, and it has no custom titlebar drag layer. It restores its own frame and display. Settings suspends its target before final ordering. A suspended ruler is not floating and ignores mouse events, so it cannot take titlebar drags or close-button clicks. The order and pointer regressions failed with the old paths and pass with the fixes. Closing Settings restores ruler input and leaves the ruler open. Core coverage preserves target-scoped interaction suspension, controls, reset and default actions, color, opacity, dimensions, shadow, accessibility, localization-safe layout, and independent window placement. | Verify native titlebar dragging on each connected display in the newly installed build. |
| Done | Disable the ruler shadow by default without changing saved user choices. | The registered and factory-reset default is off, and existing `true` values still load as true. Focused tests cover both paths. In the signed installed build, a fresh ruler started with shadow off, retained an enabled choice after Settings closed and reopened, and returned to off after the reversible check. | None. |
| Done | Add Border Opacity to Ruler Settings and Defaults. | Both native windows provide a localized 0% to 100% slider. The default is 25%, which is half the former 50% border. Per-ruler JSON, global defaults, save-as-default, reset-to-default, factory reset, drawing, keyboard order, and accessibility relationships use the same value. Legacy per-ruler JSON falls back to 25%. In the signed installed build, the control and visible ruler changed from 25% to 100% and returned to 25%. | None. |
| Verify | Preserve Ruler Defaults behavior and align its chrome with MacPowerToys. | The fixed 420pt window removes the duplicate headline and border. It keeps factory reset as one quiet destructive action and uses the same opaque native titlebar as Settings. Core coverage preserves live default edits, persistence, and reset behavior. In the signed installed build, Defaults opened as its own standard window and closing it left Settings open and unchanged. | Verify native titlebar dragging in the final installed build. |
| Done | Match the FreeRuler color panel. | Focused tests cover color-well activation, zero-corner anchoring, display clamping, restored-frame ordering, and hidden alpha controls. The signed Settings window exposes the native color well and keeps it in the complete key loop. The current target-scoped bridge could not deliver the custom color-well activation event. | None. |
| Done | Preserve FreeRuler localizations. | The upstream `Localizable.xcstrings` catalog is vendored intact. Signed German and Japanese Ruler Settings checks showed complete labels with no overlap. | None. |
| Done | Launch on demand through MacPowerToys without a SwiftUI Ruler scene. | The launcher, `macpowertoys://open/ruler`, `powertoys://open/ruler`, the Raycast command, and the `Ruler` App Intent each opened or raised one AppKit `ruler-window`. Normal app startup opened no ruler. | None. |
| Done | Show Ruler settings from its launcher detail without duplicating the native implementation. | `Open Ruler Settings` opens the native independent Settings panel. `Open Defaults` opens the native `preferences-window`. | None. |
| Done | Keep Ruler focused so shortcuts do not reach the previously focused app. | Ruler activation makes its borderless AppKit window key and the signed UI suite successfully drives ruler-local shortcuts. In the normal signed `4662560` build, Raycast launched the MacPowerToys Ruler from its focused `Ruler` query. macOS then reported MacPowerToys as frontmost with `ruler-window` as the focused window. The following `H` key hid only the horizontal ruler wing, and a second `H` restored it. | None. |
| Done | Make `Ruler` appear when searching in Raycast. | The Raycast extension builds successfully. A live search on 2026-08-23 showed `Ruler` from MacPowerToys as the first result after the development process stopped. | None. |

## Verification record

- The 2026-10-01 chrome audit did not open Ruler. Its deep-link action calls
  `openFreeRuler()`, which activates the app. The production pass forbids
  taking focus. Ruler keeps its native chrome and is outside the shared fix.

- Hosted redesign run `36741797887` at `b3d55c3c` passed
  `RulerCoreTests`. All 995 executed unit tests passed, with five skips
  and no failures. Signed Ruler window checks remain with the orchestrator.
- A fresh pinned upstream run passed 125 tests with zero failures or skipped
  tests.
- The host adapters add on-demand routing, independent Settings placement,
  adjustable border opacity, and the default disabled shadow to the pinned
  FreeRuler implementation.
- All 129 focused Ruler tests pass. They cover fixed 420pt windows,
  independent Settings placement, border opacity, shadow preference
  preservation, section rhythm, card geometry, 12pt row typography,
  accessibility relationships, the complete key order, 24pt minimum controls,
  and collision-free English, German, and Japanese labels.
- Hosted run `36096121530` passed `RulerCoreTests` within the 842-test suite.
  Dimension inputs now use the active display scale, and assertions allow
  half-pixel plus one-decimal display rounding.
- The complete host unit suite passed 543 tests with zero failures or skipped
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
