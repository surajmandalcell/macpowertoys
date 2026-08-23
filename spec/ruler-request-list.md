# Ruler Request List

Reviewed against the pinned [FreeRuler](https://github.com/pascalpp/FreeRuler)
source at commit `d38ca4f673f16c51485940e63eeee68babfbfeed` on 2026-08-01.
Update this list whenever Ruler requirements or verification results change.

## Current parity contract

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Replace the custom MacPowerToys Ruler with FreeRuler while fitting the host architecture. | The pinned MIT source, localization catalog, and notices are vendored under `powertoys/FreeRuler`; MacPowerToys adapts host ownership, launch, routing, branding, and settings-window chrome. | None. |
| Done | Match FreeRuler overlay geometry and visual styling. | Eleven direct-copy Swift files remain byte-identical; the other four differ only by the host-delegate lookup. The adapted core suite asserts the 40pt L shape, ticks, labels, colors, zero corners, handles, opacity, shadow, and overlay layout. | Complete the signed same-machine overlay comparison below. |
| Done | Match pixel, millimeter, and inch units. | Core coverage checks tick scales and labels; the signed UI flow cycles `px` → `mm` → `in` → `px`. | None. |
| Done | Match moving and keyboard nudging. | The pinned ruler controller owns drag and arrow/Shift-arrow movement; its interaction tests are preserved. | Exercise both paths in the final installed build. |
| Done | Match end and corner resizing. | The upstream resize handle and cursor implementations are direct copies apart from the host-delegate lookup, with focused geometry and drag tests. | Exercise both paths in the final installed build. |
| Done | Support multiple independent rulers. | The upstream `RulerManager` is preserved; the signed UI flow proves Command-N creates and activates a second ruler and Command-grave cycles rulers. | None. |
| Done | Match grouped and ungrouped ruler behavior. | Upstream grouping, stack order, grouped dragging, and persistence tests are preserved; the signed UI flow proves `G` toggles grouping without changing ruler count. | Exercise grouped dragging in the final installed build. |
| Done | Match FreeRuler persistence. | The upstream versioned ruler-set state, active-ruler restoration, per-ruler settings, defaults copying, frame autosave, and corrupt-data fallback tests are preserved. Ruler Settings and Ruler Defaults now keep their standalone positions and use their ruler's persisted display when attached. | Verify close/reopen state across attached displays in the final installed build. |
| Done | Match FreeRuler commands and shortcuts. | Host menus reproduce Ruler, Unit, and Options commands; core and signed UI coverage exercise `H`, `V`, `U`, `G`, Command-N, Command-grave, Command-comma, and Command-W routing. Exact Command-W is consumed once by the native local monitor, closes the focused ruler synchronously, and leaves the host window running. | Complete the full installed shortcut matrix. |
| Done | Preserve the attached per-ruler Settings behavior and align its chrome with MacPowerToys. | The fixed 420pt active-HUD panel follows the same section-heading, inset-card, row, typography, and spacing system as Awake, Text Extractor, and Color Picker. Its Measurement, Appearance, and Window sections use trailing secondary/primary actions. Core coverage preserves attachment, anchoring, suspension, controls, reset/defaults, color, opacity, dimensions, float, shadow, accessibility, and localization-safe layout. | Complete the signed appearance matrix below. |
| Done | Preserve Ruler Defaults behavior and align its chrome with MacPowerToys. | The fixed 420pt active-HUD window removes the duplicate headline and border, and keeps factory reset as one quiet destructive action. Core coverage preserves live default edits, persistence, and factory reset. | Complete the signed appearance matrix below. |
| Done | Match the FreeRuler color panel. | The upstream color-well behavior, zero-corner anchoring, and alpha-disabled color panel are preserved with focused tests. | Exercise it in the final installed build. |
| Done | Preserve FreeRuler localizations. | The upstream `Localizable.xcstrings` catalog is vendored intact and compiled into MacPowerToys. | None. |
| Done | Launch on demand through MacPowerToys without a SwiftUI Ruler scene. | `ToolActionRouter` opens or raises the AppKit ruler manager. Signed UI coverage proves startup creates no ruler and launcher activation creates one `ruler-window` with both wings. | Verify every external route in the final installed build. |
| Done | Show Ruler settings from its launcher detail without duplicating the native implementation. | The launcher Settings page routes to the existing active-ruler Settings panel and Ruler Defaults window owned by FreeRuler. | Verify both buttons in the final installed build. |
| Verify | Keep Ruler focused so shortcuts do not reach the previously focused app. | Ruler activation makes its borderless AppKit window key and the signed UI suite successfully drives ruler-local shortcuts. | Prove focus ownership from another foreground app in the installed build. |
| Open | Make `Ruler` appear when searching in Raycast. | `raycast/package.json` and `raycast/src/ruler.ts` define the command, but installed Raycast search registration remains separate from source parity. | Install or register the extension and prove Raycast search discovery. |

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

- Pinned upstream baseline: 125 core tests pass. Its three PNG snapshot tests
  fail in the pristine source under the current Xcode beta/macOS 27 SDK, so
  they are an environment limitation and not used as the visual oracle.
- Integrated core: 124 adapted upstream product tests plus one host Command-N
  integration test pass (125 total). A temporary 40pt → 41pt mutation was
  detected by four geometry/layout tests and then restored.
- Settings core: all 126 Ruler tests pass. The layout checks cover 420pt fixed
  windows, utility section rhythm, card geometry, 12pt row typography,
  accessibility relationships, complete key order, 24pt minimum controls, and
  collision-free English, German, and Japanese labels. All five localized
  controls XIBs compile and contain the three translated section headings.
- The focused ruler chrome regression test passes with visible native titlebars
  and autosave names for both Settings and Defaults.
- XIB validation: Ruler Settings, Ruler Defaults, and their shared controls all
  compile with `ibtool`.
- Host unit suite: 383 tests pass with zero failures or runtime warnings.
- Signed host UI suite: all 11 methods pass across 22 configured executions,
  including the focused Ruler flows and the exact Command-W host-survival case.
  Xcode 27 reports one launch-time Security performance diagnostic per fresh UI
  test process immediately after its missing DetachedSignatures lookup; it
  occurs before tool interaction and is not on the Ruler close path.
- Command-W dispatch: direct native-handler measurements complete in 4-16ms
  after the first cold invocation. The monitor adapter preserves a handled
  handler's `nil` result, so AppKit cannot redispatch the same event to the host.
- Signed same-machine visual comparison: pending final installed-build check.
- Performance and 25-window lifecycle check: pending final installed-build
  check; record observed CPU and memory ranges here before handoff.
