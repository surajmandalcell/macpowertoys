# Color Picker Request List

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
neutral copy controls, and a protected floating settings area on every page.

Round 2 verification: Debug and build-for-testing pass with shared fixes B
and I. Tests were compiled, not executed. Signed screenshot review remains.

Round 3 screenshot-review verification: Debug and desktop build-for-testing
pass. Tests were compiled, not executed. Signed visual and interaction checks
remain with the orchestrator.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Size the applet Settings page to its cards within 250 to 460pt. | Round 6 shows a blank tail because Settings always requested the maximum height. The applet now uses measured card height plus the shared 40pt titlebar, 16pt top gap, and 52pt gear reserve. The initial two-card budget gives 404pt. A height regression covers short content and the upper cap. | Recapture both appearances. Check the permission notice, scrolling at the cap, gear edge inset, and Settings-to-History return in the signed build. |
| Verify | Fill the shortcut control column and use the control text role. | Signed `8cf8c02` round 4 captures confirm the full Settings gutters, complete minimum Projects row, Clear all copy, and aligned History rows. The shared recorder still paints a 116pt bezel inside the 160pt column and uses mono type. | Foundation must expose a fill-width recorder with control text and controlInk. Adopt it in the shared settings card and verify idle, recording, disabled, and cancel states. |
| Verify | Pair the short embedded settings cards and use sentence case for clearing. | Round 3 review reuses the Global shortcut and Saved colors cards in equal columns when both fit; the applet keeps full-width stacked cards. The action and confirmation use `Clear all`. | Verify both hosts and clear confirmation in the signed build. |
| Verify | Show complete project rows and use native list anatomy for history. | `projectsHeight` includes each project row and the 60pt project editor before the 460pt cap. History uses one card with stable row ids and `lineSoft` separators. | Verify the minimum and maximum window heights in the signed build. |
| Verify | Keep Color Picker controls fixed and scroll only the rows. | History scrolls below fixed tabs, search, and format controls. Projects scrolls only its rows below the fixed card header and new-project field. Row presentation is cached by the current history request. | Verify smooth scrolling and page switches within 100ms in the signed build. |
| Verify | Embed one cards-only settings view without nested scrolling or gutters. | `ColorPickerSettingsView()` owns only its shortcut and saved-colors cards. The applet supplies OnePlusPage with 16pt gutters. Permission and clear-history paths remain in the shared cards. Debug and build-for-testing pass. | Verify embedded and applet Settings in the signed build. |
| Verify | Keep the floating settings button clear of History, Projects, and Settings. | Round 2 applies the shared 52pt body inset before the gear overlay and removes the old inner 44pt padding. The gear keeps its 8pt edge inset and Command-comma action. | Verify all three pages and their scroll limits in the next signed capture. |
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
