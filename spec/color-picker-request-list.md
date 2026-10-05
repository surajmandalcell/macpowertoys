# Color Picker Request List

Native close and reopen, run 80, 2026-10-02: the shared opener must skip
closed SwiftUI applet windows. Background reopen uses the existing native
factory; explicit reopen uses SwiftUI. Cold hidden applet measurement and
the Space and focus rules stay in effect. The new native-close route calls
the existing window delegate. Prior plain-host height and release fixtures
do not prove real scene recovery. The orchestrator owns installed History,
Projects and Settings close/open/capture checks.
The single test build and 31 guarded tests pass, including cold applet body
measurement. Closed-scene source cases pass without activation.
Report: `tmp/redesign/logs/w17-native-close.md`.

Inactive background ordering, run 79, 2026-10-02: applet routes and the
separate diagnostic panel use back ordering while the app is inactive.
Other Spaces still skip ordering. Explicit opens and Pick keep their paths.
The shared source probe passes inactive applet reuse and diagnostic panel
ordering, with zero front/key calls. The one test build passes. Guarded native
tests stop before execution when the foreground app changes. Signed History,
Projects, Settings and panel capture remain with the orchestrator.
Report: `tmp/redesign/logs/w16-activation-cause.md`.

Background Spaces, run 78, 2026-10-02: applet routes and the separate
diagnostic panel skip ordering on another Space while retaining content and
page updates. Explicit opens and Pick keep their activation paths. Source
checks pass off-Space applet reuse and retain the input-capture
guard. Native close/reopen still passes every height bound. All five guarded
background-window tests pass, including off-Space and applet-height checks.
Signed History, Projects, Settings, lock/unlock and full-screen checks remain
with the
orchestrator. Report: `tmp/redesign/logs/w15-space-focus.md`.

Close verification, run 77, 2026-10-02: the guarded applet fixture passes
native close and model release at 250, 355, and 460pt. It now orders the
offscreen window before each close, so AppKit sends every close notification.
All four background-window tests and the single compile gate pass. The
stronger shared probe passes 102 cycles, including both applet height ranges.
Production source and installed interaction status are unchanged.
Report: `tmp/redesign/logs/w14-blank-tests.md`.

Background reopen, run 76, 2026-10-02: the shared presenter preserves the
SwiftUI scene controller and host. WindowAccessor supplies the mounted body
height before ordering, without the host's stale titlebar inset. The native
fixture covers 250, 355, and 460pt bodies across cold first routes and native
close/reopen cycles. `a46233f2` fails the controller-ownership check. Signed
History, Projects, Settings, native close, and focus checks remain with the
orchestrator. Report: `tmp/redesign/logs/w14-blank-focus.md`.

Native reopen, run 75, 2026-10-02: the shared presenter remounts closed
scene hosts before ordering. Background hosts preserve their closed frame
and restore content first. The hidden source fixture passes Color Picker
at 250, 355, and 460pt through native performClose and close, with mounted
content and the expected first frame. All 102 shared cycles pass with zero
activation calls. The single app/test compile gate passes. Installed native
close, History/Projects/Settings routes, controls, and timing remain with
the orchestrator. Report: `tmp/redesign/logs/w14-blank-main.md`.

Round 17 applet correction, run 68, 2026-10-01: OnePlusUI `a02d43d`
restores the shared 40pt row and C22 for Awake, Color Picker, and Text
Extractor. Action frames span y10..34; untabbed content begins at y56.
All 21 focused package checks pass in both appearances at 1x/2x. The
app and test bundles compile. The app still pins OnePlusUI 1.0.0, so its
two corrected Settings height assertions await the orchestrator's tag
and dependency update. Signed page and interaction checks remain open.
Report: `tmp/redesign/logs/w10-fix17-applets.md`.

Local verification, run 63, 2026-10-01: all 145 OnePlusUI tests pass.
Header, chrome, focus, and scroll checks pass. The guarded app run stops
after 475 passes and 5 skips when FocusEffectTests changes the foreground.
This does not complete installed Color Picker interaction or screen capture.
Report: `tmp/redesign/logs/w7-local-tests.md`.

Background creation, run 60, 2026-10-01: cold and retained History, Projects,
and Settings opens must preserve the frontmost app. A background Pick URL
opens the applet; only an explicit Pick action starts the screen sampler.
The actual-source probe passes cold and retained ordering without activation,
plus the background Pick guard. The final app module and changed tests
typecheck after repair of the single compile-gate error. The guarded
installed replay remains with the orchestrator.
Report: `tmp/redesign/logs/w6-no-activation.md`.

Background opens, run 55, 2026-10-01: `a5a87ec8` routes every external
window and page URL through the background-aware handler. Empty SwiftUI
creation and reuse matches prevent Projects, History, and Settings from
bypassing false activation intent. Explicit user opens retain activation.
The source regression rejects `d6ccf9cb`; non-GUI router/presenter checks
pass. Final app and changed-test typechecks pass without diagnostics.
The one tests gate failed on a removed Command-Q ID list, now restored.
Hosted execution and clean signed foreground checks remain with the
orchestrator. Report: `tmp/redesign/logs/w4-focus-fix.md`.

Settings gear and scroll end: the gear is the titlebar ghost icon button
`OnePlusAppletSettingsButton`, left of Pick Color, selected while Settings is
open. Nothing floats over content. History and Projects end 24pt above the
window bottom; Settings scroll content ends 24pt above it.
Signed History, Projects, Settings, and gear checks remain with the
orchestrator.

Round 48 header picks, 2026-10-01: `bd2e0963` implements Inset B
(close x13, title 14pt after zoom) and Top B (title caps, icons, and action
tops at y20). Applet and sheet header rows are 44pt; applet lights use C=27.
The row amendment centers switch paint in its unchanged 24pt hit frame.
Only the tallest action starts at y20; captions and smaller controls share
its center and text baseline, with 12pt gaps. History and Projects toolbars
use the shared row. Three focused package render checks pass in both
appearances at 1x/2x. Signed review stays with the orchestrator.
Report: `tmp/redesign/logs/w4-header-rows.md`.
The body moves down 4pt with its existing gaps. Offscreen render and native
geometry checks pass (42 checks) in both appearances at 1x/2x. One
app/test compile gate passes. Cap strokes allow one physical pixel for
antialiasing; action frames are exact. Signed pixel captures
and real light hover remain with the orchestrator after installation.
Report: `tmp/redesign/logs/w4-chrome.md`.

Round 11 shared focus, 2026-10-01: native tables keep keyboard focus after
row clicks without focus paint when accessibility modes are off. Key-window
reactivation preserves valid responders and active text selection. Detached,
hidden, disabled, or fully clipped responders are cleared. All six focus
package checks and all 17 focused chrome checks pass. Signed Tab, Shift-Tab,
arrows, Space, Return, VoiceOver, and scroll/tab checks remain with the
orchestrator. Report: `tmp/redesign/logs/w3-chrome.md`.

Glyph pass, 2026-10-01: `91d9a538` uses `ToolGlyph.colorPicker` in the
launcher, Home, and separate placement. Status template images have a 14pt
canvas and 11.2pt maximum ink. Headless checks pass at 1x, 2x, and 4x.
Both shared app and test-bundle compile gates pass.
The signed status image and both appearances remain with the orchestrator.

Reviewed against the current app source on 2026-08-31. Update this list when a
direct user correction or verified result changes a status.

Window performance: the shared ledger records applet open, tab selection,
and Settings selection. It ends after native display submission. Two package
checks pass. Signed `198055e4` History measured 543ms in the orchestrator
replay and 305ms on a later changed-page replay. The wait profile found a
shared launcher Login Items query after unrelated defaults writes.
`da3146a3` filters these writes and moves the query off the main thread.
The actual preference-observer check and both compile gates pass. Signed
after measurements and complete first/late frames remain. The 250ms open
and 100ms page limits stay open. Commands: `tmp/redesign/perf/w1-windows.md`.

## Round 11 audit, 2026-10-01

| Status | Task | Evidence | Remaining work |
|---|---|---|---|
| Source fixed | T076: Remove the empty Projects card tail. | `df0a2f5a` shows natural-height 44pt destinations directly below actions. Only longer lists use the capped scroller. Full-row hover, counts, and minimum canvas remain. | Signed short/long list and project-creation checks in both appearances. |
| Source fixed | T077: Keep history separators inside each row. | `8fa61fbd` puts 1pt lines in bottom overlays; separators add no height to the 44pt pitch. | Signed row/action alignment and hover. |
| Measured; source fixed | T078: Save growing pinned/project history off-main. | The actual 10,000-color, 100-project pin/save callback took 25ms. `66d13874` orders background encoding and writes; the callback is below 0.1ms and a drained reload equals memory. No pins are trimmed. `5ed9cbf0` adds `async throws`, encodes both arrays before writes, and preserves retryable current state. Native failure/retry/recovery checks pass. | Hosted regression and signed interaction. Lifecycle integration uses `try await ColorPickerService.shared.flushPersistence()` in a critical 10s stage before logs and Cloud Sync. |
| Source fixed | T080: Undo reversible history and project actions. | `b8fc89fa` uses the owning window UndoManager for pin, delete, clear, project creation, and selection. Native fixture checks pass undo/redo, order, IDs, persistence, and unrelated changes. Colors from an undone project remain in Unfiled until redo. | Hosted AppletHistoryUndoTests and signed native Edit menu/confirmation checks. |
| Source fixed | T081: Attach CSS Save to Color Picker. | `6be161e9` passes the initiating scene window to `beginSheetModal`; modeless fallback requires no owner. Atomic background export and visible errors remain. | Signed Cancel, Escape, failure, and appearance checks. |

## Production audit, 2026-10-01

Both shared build modes pass for the Debug app and both desktop test bundles.
The new regression tests compile. Hosted tests and signed checks remain open.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Highlight the full project row, including its export action and gutters. | `8252798d` applies the shared `onePlusRowHover(selected:)` to the complete row. The primary button no longer paints a separate partial surface. | Verify Unfiled, selected and unselected projects, export hover, and keyboard focus in both appearances. |
| Verify | Use the shared compact popup for all nine row copy formats. | `8252798d` uses `OnePlusMenuButton` and keeps the format actions and labels. Source-derived checks passed all nine exact output strings, project-scoped search, and counts. | Verify popup placement, copying, Return, keys 1-9, and Escape in the signed app. |
| Verify | Audit native pick, cancel and overlap guard, project-owned history, pinning, deletion, clear confirmation, project creation, persistence, CSS export, shortcuts, and settings routes. | All service and view paths were traced. The existing installed History was captured without activation. The sampler was not started and user history was not changed. Existing ColorPickerTests cover service seams. | Run tests on CI. The orchestrator must install current source and check all three pages, shortcut recording, native sampler, and export. S5 and A4-A7 remain open. |
| Verify | Apply the horizontal density and instant-motion correction. | `c03f046d` moves project creation controls outside the content card, replaces count pills with trailing plain numbers, uses 44pt history rows, moves settings help to tooltips, and disables implicit content animation. `edcd9037` keeps row actions visible at rest; `e5474093` preserves accessible headings and count labels. The source-derived compact height check passes. | Review all three pages, long project names, count alignment, and row hover after installation. |


## OnePlusUI redesign, 2026-09-29

The 2026-10-01 shared chrome fix preserves native button frames and moves
the enclosing titlebar container with its tracking areas. Package checks pass
for the 22pt applet centerline in both appearances. Signed pointer hover
checks remain with the orchestrator. See `tmp/redesign/logs/w1-chrome.md`.

Foundation round 10 gates history-row focus fill on the shared live policy.
Full Keyboard Access or VoiceOver can expose keyboard actions. All 72 package
tests, Debug, and desktop build-for-testing pass. Signed history interaction
checks and the protected shared selector focus gate remain with the owners.
Report: `tmp/redesign/logs/02f-fix10-report.md`.

Hosted run `36741797887` at `b3d55c3c` passed `ColorPickerTests`, including
the v14 28pt history search control. All 995 executed unit tests passed, with
five skips and no failures. Signed Color Picker interaction checks remain
with the orchestrator.

Round 3a uses one cards-only ColorPickerSettingsView. The applet supplies
OnePlusPage; the launcher supplies its existing page, gutters, and scrolling.

Round 3 keeps the tab strip, search, format selector, and project controls
fixed. Only history rows and project rows scroll. Row strings, timestamps,
search results, and project counts are prepared off the main actor.

Round 5 puts history rows inside one card with 1pt separators. Projects grow
from 250pt with their rows and editor, up to 460pt, where rows start scrolling.
The titlebar action is 24pt and all Settings card headers use symbols.

Round 6 uses 16pt after the tab strip and between the fixed History toolbar
and its rows. Projects keep content-sized 250 to 460pt window heights. Pure
color formatting is nonisolated, so cached row preparation stays off the main
actor without concurrency warnings.

Round 2 requires full-width Settings cards inside 16pt body gutters,
neutral copy controls, and a 24pt bottom gutter on every page.

Round 2 verification: Debug and build-for-testing pass with shared fixes B
and I. Tests were compiled, not executed. Signed screenshot review remains.

Round 3 screenshot-review verification: Debug and desktop build-for-testing
pass. Tests were compiled, not executed. Signed visual and interaction checks
remain with the orchestrator.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Size the applet Settings page to its cards within 250 to 460pt. | Round 6 shows a blank tail because Settings always requested the maximum height. Height is the measured card height plus the shared 40pt titlebar, 16pt top gap, and 24pt bottom gutter. The 296pt content fixture gives 376pt; the two-card source budget gives 352pt. A height regression covers short content and the upper cap. | Check the permission notice, scrolling at the cap, and Settings-to-History return through the titlebar gear in the signed build. |
| Verify | Fill the shortcut control column and use the control text role. | Signed `8cf8c02` round 4 captures confirm the full Settings gutters, complete minimum Projects row, Clear all copy, and aligned History rows. The shared recorder still paints a 116pt bezel inside the 160pt column and uses mono type. | Foundation must expose a fill-width recorder with control text and controlInk. Adopt it in the shared settings card and verify idle, recording, disabled, and cancel states. |
| Verify | Pair the short embedded settings cards and use sentence case for clearing. | Round 3 review reuses the Global shortcut and Saved colors cards in equal columns when both fit; the applet keeps full-width stacked cards. The action and confirmation use `Clear all`. | Verify both hosts and clear confirmation in the signed build. |
| Verify | Show complete project rows and use native list anatomy for history. | `projectsHeight` includes each project row and the 60pt project editor before the 460pt cap. History uses one card with stable row ids and `lineSoft` separators. | Verify the minimum and maximum window heights in the signed build. |
| Verify | Keep Color Picker controls fixed and scroll only the rows. | History scrolls below fixed tabs, search, and format controls. Projects scrolls only its rows below the fixed card header and new-project field. Row presentation is cached by the current history request. | Verify smooth scrolling and page switches within 100ms in the signed build. |
| Verify | Embed one cards-only settings view without nested scrolling or gutters. | `ColorPickerSettingsView()` owns only its shortcut and saved-colors cards. The applet supplies OnePlusPage with 16pt gutters. Permission and clear-history paths remain in the shared cards. Debug and build-for-testing pass. | Verify embedded and applet Settings in the signed build. |
| Verify | Put the settings gear in the titlebar left of Pick Color and keep the last card off the window bottom. | `OnePlusAppletSettingsButton` (OnePlusUI 1.0.3) toggles History and Settings, keeps Command-comma, and shows a selected fill on Settings. No gear reserve remains. History and Projects pad 24pt below their content; Settings scroll content ends 24pt above the bottom. A render test writes both appearances to `tmp/redesign/captures/applet-color-*.png`. | Verify all three pages, the gear selected state, and scroll limits in the signed build. |
| Verify | Keep Settings cards full width inside equal 16pt gutters. | Round 2 explicitly expands the settings stack before the body insets. Shared fix B removes the scroller gutter. Both compile checks pass. | Inspect both appearances in the next signed capture. |
| Verify | Use the 420pt applet with 250 to 460pt height, three native lights, persistent Pick Color, 16pt gutters, underline tabs, equal-height search and format controls, history actions, project export, and replacing Settings. | Debug build passes. DESIGN.md v14 supersedes the older material, gutters, and two-light rules below. Routes are `history`, `projects`, and `settings`. | Review both appearances, copying, projects, and export in the orchestrator's installed build. |

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Use the new Color Picker eyedropper icon. | `ColorPickerLogo` is a 512px RGBA asset with a violet sample, coral/cyan accents, and one eyedropper. Focused icon and Raycast checks pass. | Inspect launcher and Dock in the final signed app. |
| Done | Choose no Color Picker menu item, the combined popover, or a separate icon. | The shared launcher selector stores None, Combined, or Separate. Focused tests cover each mode, the exact `MacPowerToys.color-picker` autosave name, the Pick Color route, disabled state, legacy migration, combined-tab support, and no-op item refresh. | None. The shared five-tool physical placement, relaunch, and click matrix remains in the main request list. |
| Done | Keep project counts and color timestamps on their related row. | `4ad3da2` puts each project count beside its name and each timestamp beside its color value. In the normal signed `4662560` build, an intentionally long project name truncated before `0 colors`, and the long NSColor representation truncated before `1 mo ago` and the row actions. | None. |
| Done | Remove lag while the native color sampler is active. | `5b3d174` rejects overlapping sampler sessions and reuses the row date formatter. A live process watcher in the normal signed `4662560` build detected the native ColorSampler 334.7 ms after the Pick Color action. The action disabled while the sampler was active and recovered after the controlled test restart. | None. |
| Done | Prevent transient or persistent titlebar focus outlines. | Shared titlebar controls suppress focus effects, and Color Picker routes initial focus to its invisible window accessor like every compact applet. Fresh-open and cross-window focus checks in the normal signed `98f35f6` build showed no outline. | None. |
| Done | Make the Color Picker window narrower. | `ColorPickerLayout.windowWidth` is a fixed 420pt. | None. |
| Done | Move the tool title and primary pick action into one compact top row. | `CompactTitlebar` contains the text-only title and `Pick Color`. | None. |
| Done | Keep titlebar buttons compact, slightly rounded, and visually separate. | Shared actions are separate 24pt controls with the titlebar-only 6pt radius; only `Pick Color` has accent fill. Fresh-open, hover, disabled, and keyboard-focused checks in the normal signed `4662560` build kept the compact geometry, showed the disabled dimming, and added no focus outline. | None. |
| Done | Remove the titlebar bottom border, app icon, and Clear action. | The shared titlebar has no separator or app icon; destructive clearing lives in Settings. | None. |
| Done | Move shortcut controls into a proper settings page. | Settings contains the enable toggle, a click-to-record `ShortcutRecorderField` that captures any modifier-plus-key combination, and explanatory text. | None. |
| Done | Show the same Color Picker settings when selected in the main launcher. | The applet and launcher both render `ColorPickerSettingsView`; shortcut, recorder, and Clear All behavior have one implementation. The normal signed `4662560` launcher showed the shared enable toggle, Clear All action, help text, and recorder surface. | None. |
| Verify | Use Command-Shift-3 as the default Pick Color shortcut and allow it to be recorded. | Color Picker defaults to the physical 3 key with Command and Shift. The normal signed `4662560` launcher shows `⌘⇧3`. The shared recorder normalizes shifted number-row labels. `76009bc` prevents the reserved screenshot chord from registering through Carbon: with Accessibility access, only the suppressing event tap handles it; without access, Color Picker does not run and the native screenshot remains unchanged. `1ddf571` synchronously restores the retained event tap when macOS disables it for a timeout or user input. Direct callback regressions pass in the combined 543-test suite. | Use a physical Command-Shift-3 chord from another foreground app after granting Accessibility access. Confirm that Color Picker opens and that macOS does not write a screenshot. |
| Done | Show only Settings content while Settings is open, with no top body margin. | History and Projects tabs render only outside Settings; the settings body has no top padding. | None. |
| Done | Left-align `Enable Pick Color shortcut` and place `Clear All` below it. | Both controls use leading alignment; clearing has scope text and confirmation. | None. |
| Done | Add Projects creation, selection, project-owned picks, persistence, and export. | `ColorPickerService` owns projects and selected destination; `ColorPickerTests` covers ownership and persistence; each named project exports CSS. | None. |
| Done | Keep the history search thin while the format Select stays compact. | `9bd56e2` adds `testHistoryUsesNativeSmallContentSearch`, which renders the real history and verifies its native small `NSSearchField` stays within the shared 24pt content-search slot. The adjacent format Select remains a fixed 28pt compact control. | None. |
| Done | Fix selected-tab and content left-edge alignment. | Tabs, controls, rows, cards, and settings use one 12pt outer gutter; selection does not change tab geometry. | None. |
| Done | Reduce left and right body padding. | `ColorPickerLayout.bodyHorizontalInset` is 12pt throughout the applet body. | None. |
| Done | Vertically align the complete titlebar row, lower traffic lights, remove zoom, and reclaim its title space. | Color Picker uses one 4pt row inset, a 22pt centerline, a 6pt traffic-light shift, a 60pt title start, hidden zoom, and a fixed root size. `WindowAccessor` now reapplies the shared alignment whenever the window becomes key; regression coverage forces the late native reset that previously left the lights 6pt high. | None. |
| Done | Prevent the unsigned UI-runner Gatekeeper dialog and stale visual checks. | The mandatory verification rules prohibit unsigned UI runners, UI-test-mode visual QA, stale provenance, and shared DerivedData. | None. |
