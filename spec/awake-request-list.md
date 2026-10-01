# Awake Request List

Scroll edges, 2026-10-01: the shared floating gear overlays Home and Settings.
Its 52pt reserve is scroll-content end padding, so it does not shrink the body.
The 15 focused package checks pass, including both gear states at the 560x500
canvas. The four regressions fail on the old source. Signed scrolling and gear
interaction remain with the orchestrator. Report: `tmp/redesign/logs/w4-scroll-edges.md`.

Round 48 header picks, 2026-10-01: `bd2e0963` implements Inset B
(close x13, title 14pt after zoom) and Top B (title caps, icons, and action
tops at y20). Applet and sheet header rows are 44pt; applet lights use C=27.
Header switches retain their 24pt hit frame with the capsule at the top.
The body moves down 4pt with its existing gaps. Offscreen render and native
geometry checks pass (42 checks) in both appearances at 1x/2x. One
app/test compile gate passes. Cap strokes allow one physical pixel for
antialiasing; action frames are exact. Signed pixel captures
and real light hover remain with the orchestrator after installation.
Report: `tmp/redesign/logs/w4-chrome.md`.

Reviewed against current source and Git history on 2026-08-31.

## Round 12 audit, 2026-10-01

Applet critique item 2: steady active status uses the existing `.online` state,
with neutral text and a filled 4pt dot. Off keeps its hollow muted dot.
The regular row role, Turn Off action, row height, and assertion error banner
remain. The signed `43ce0eb9` dark/light captures show the original green line.
Source fix: `7a8a6c41`. Parsing and the single combined app/test-bundle
compile gate pass. Tests were compiled, not executed. Signed recapture
remains with the orchestrator.

## Round 11 audit, 2026-10-01

| Status | Task | Evidence | Remaining work |
|---|---|---|---|
| Source fixed | T073: Keep PID and process actions together. | `df0a2f5a` puts Process ID, the native field, Attach, and conditional Detach on one 44pt row with 8pt gaps. Validation, Return submission, and help remain. | Signed checks in the applet and embedded host, including errors and Detach. |
| Source fixed | T074: Keep Session rows on a 44pt pitch. | `df0a2f5a` uses a zero-gap stack beneath the section-title gap. Inside separators remain. | Signed checks for Off, timed, Until, and the embedded display switch. |

## Production audit, 2026-10-01

Both shared build modes pass for the Debug app and both desktop test bundles.
The new regression tests compile. Hosted tests and signed checks remain open.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Keep a protected running process attached and reject missing PIDs. | `bc131870` shares one positive-PID liveness check between attachment and timer expiry. Signal-zero probes accept EPERM as a running process. A source-derived check passed for this process, protected PID 1, invalid PIDs, and an exited child. `AwakeProcessTests` covers these cases. | Run on CI, then test Attach, Detach, and process expiry in the signed app. |
| Verify | Fit all eight quick times without clipped labels or a silent Add action. | `bc131870` keeps the single 8pt-spaced row scrollable and disables Add for zero, duplicate, and full preset lists. | Inspect eight long presets, Add, remove confirmation, and both settings hosts in the signed app. |
| Verify | Audit Off, indefinite, timed, Until, display preference, assertion ownership, persistence, CLI actions, status, and settings routes. | All service and view paths were traced. Read-only `pmset -g assertions` confirms the existing installed app owns the display-sleep assertion. | The installed source stamp is `36c585b4`, not this audit source. Installation and signed interaction checks belong to the orchestrator. S5 and A4-A7 remain open. |
| Verify | Apply the horizontal density and instant-motion correction. | `c03f046d` removes padded status, mode, quick-time, and process cards. Controls and related actions sit directly on the page. Preset and process help uses tooltips. Applet and embedded hosts disable implicit content animation. | Review both pages and both hosts after installation; confirm hover and page changes are instant. |
| Verify | Reject nonfinite, negative, and oversized time limits before clock conversion. | `44c2930a` validates timed sessions before changing mode and shares the 68-year bound with presets and labels. Source-derived checks pass infinity, NaN, huge values, negative values, UI limits, and ordinary countdowns. | Run AwakeProcessTests on CI. For longer sessions, use Indefinite. |
| Follow-up: main | Validate CLI time and PID arguments before changing an Awake session. | DeepLinkHandler sets display and mode before process attachment and ignores the attachment result. The service now rejects invalid durations and missing PIDs without changing its prior session. | The main owner must validate arguments with the shared service checks before mutations and handle a rejected attachment. The applet Attach path already handles failure. |


## OnePlusUI redesign, 2026-09-29

Round 3a uses one cards-only AwakeSettingsView for embedded and standalone
settings. The caller owns scrolling, gutters, and density. Preserve preset
editing when the foundation removes the old launcher-only preferences view.

Round 3 keeps the applet's 40pt titlebar. The status card stays fixed while
the mode, quick-time, and process cards own the home-page scrolling.

Round 5 keeps the titlebar display switch as the only display control in the
applet. Quick times use one 8pt-spaced row, minute labels include a space, and
every settings card header uses a 13pt symbol.

Round 6 starts Home 16pt below the titlebar. Applet content no longer uses the
58pt workspace-title offset.

Round 2 requires a protected floating settings area and a readable 12pt
status row. Window height uses the shared fixed-canvas correction.

Round 2 verification: Debug and build-for-testing pass. Tests were compiled,
not executed. Signed screenshot and interaction checks remain with the orchestrator.

Round 3 screenshot-review verification: Debug and desktop build-for-testing
pass. Tests were compiled, not executed. Signed visual and interaction checks
remain with the orchestrator.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Package verified; signed review pending | Keep applet lights at C=27 and close at x13, with title caps and the display switch at y20. | `bd2e0963` applies the shared Top B and Inset B picks. Native geometry, hover tracking, cap pixels, and the switch capsule pass in both appearances at 1x/2x. | The orchestrator must install clean source, recapture both pages, and verify real hover and focus changes. |
| Verify | Pair embedded session controls with Quick times and process attachment; use a labeled mode select. | Round 3 review uses one adaptive cards-only settings implementation. Keep awake is a 44pt row with a 160pt select, the PID field is 160pt, and hour chips read `1 h` and `2 h`. Narrow applets keep a vertical stack. | Verify all modes, preset editing, attachment, and both host widths in the signed build. |
| Verify | Remove the duplicate applet display control and align the quick-time row. | The applet passes `showsDisplayToggle: false`; quick times use one leading 8pt-spaced row with the add icon after the presets. Minute labels render as `15 min` and `30 min`. | Verify Home and Settings in both appearances. |
| Verify | Keep Awake's status visible while its controls scroll, without adding a workspace header inset. | Home now places `AwakeStatusCard` above the only `ScrollView`; Settings still uses the shared cards-only implementation inside `OnePlusPage`. | Verify scroll limits and page switching in the signed build. |
| Verify | Share one cards-only settings view between Awake and the main tool page. | `AwakeSettingsView()` owns the display, mode, quick-time, and process cards. The applet owns its OnePlusPage and floating-settings inset. Quick times use one row; the minute-based preset editor remains available. Debug and build-for-testing pass. | Foundation must dispatch to this type and remove AwakePreferencesView; then verify both hosts. |
| Verify | Keep the floating settings button clear of both page bodies. | Round 2 applies the shared 52pt body inset before the gear overlay. The old inner 44pt padding is removed. The gear keeps its 8pt edge inset and Command-comma action. | Verify scrolling, window size, and both pages in the next signed capture. |
| Verify | Render the Awake status in readable row type. | OnePlusStatus keeps the regular 12pt row role. Round 12 replaces success ink with the neutral `.online` state for a steady active assertion. The 4pt dot stays filled; Off remains hollow and muted. | Review active and inactive states in the next signed capture. |
| Verify | Use the 560 x 500 OnePlusUI applet, persistent display switch, status card, segmented modes, quick times, process attachment, and a replacing Settings page. | Debug build passes. DESIGN.md v14 supersedes the older material and two-light rules below. Routes are `home` and `settings`. | Review both appearances and controls in the orchestrator's installed build. |

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Call the inactive Awake state `Off` and let all four tray modes use the available width. | User-facing mode copy maps the persisted `.passive` value to `Off`; the signed `a5ad439` Awake window showed `Off`. The segmented tray picker uses regular control size and fills its container. Focused tests cover the exact Off, Indefinite, 30-minute, 1-hour, and custom-duration mappings. | None. Live popover sizing and feedback remain in the dedicated tray row. |
| Done | Choose no Awake menu item, the combined popover, or a separate icon. | The shared launcher selector stores None, Combined, or Separate. Awake preserves its combined default and any legacy separate choice. Focused tests cover each mode, the exact `MacPowerToys.awake` autosave name, its Open Awake route, disabled state, combined-tab support, and no-op refresh. | None. The shared five-tool physical placement, relaunch, and click matrix remains in the main request list. |
| Done | Keep the Awake window fixed instead of allowing it to grow. | `AwakeView` has a fixed 560pt by 500pt frame, its scene uses content-size resizability, and `WindowAccessor` removes the AppKit resizable style. | None. |
| Done | Vertically align Awake's titlebar items. | The shared 40pt `CompactTitlebar` applies one 4pt row inset and centers its title and switch on the same 22pt centerline. Unit coverage and the normal signed `98f35f6` build confirmed the alignment. | None. |
| Done | Move the traffic lights down for more breathing room. | `WindowAccessor` reapplies the shared 6pt downward offset after SwiftUI's delayed layout pass and every key-window transition. Regression coverage forces a late native reset and verifies recovery. | None. |
| Done | Remove the green expand control and reuse its space. | `WindowAccessor` hides zoom, and the shared title inset moves from 84pt to 60pt so Awake occupies the vacated position. The normal signed `98f35f6` accessibility tree contained only close and minimize, with the title in the reclaimed space. | None. |
| Done | Keep the compact Awake titlebar aesthetically consistent. | Awake uses the shared 24pt controls, titlebar-only 6pt radius, complete-row inset, and borderless chrome. The normal signed `98f35f6` build matched the other three recent applets. | None. |
| Done | Make the existing `Keep Display On` titlebar switch configurable while Awake is off. | The enabled titlebar binding calls `AwakeService.setKeepDisplayOn`, which saves the setting even when no power assertion is active. The UI regression test toggles it in both directions. | None. |
| Done | Do not add a separate display button. | The Awake titlebar contains only the existing `Keep Display On` switch as its display control. | None. |
| Done | Remove the large focus outline shown around `Keep Display On` when Awake opens. | The switch disables the default focus effect, and every compact applet routes initial focus to its invisible window accessor. Fresh-open and cross-window focus checks in the normal signed `98f35f6` build showed no outline. | None. |
| Done | Remove the titlebar bottom border. | The shared `CompactTitlebar` renders no divider or separator. | None. |
| Done | Make the Awake app name bold. | Awake applies bold weight to its 13pt compact titlebar title. | None. |
| Done | Keep the Mac awake after the Awake window closes and release the assertion on Off or timer expiry. | In the normal signed `0bc0c81` installed build, `pmset -g assertions` showed `MacPowerToys Awake is active` as a `PreventUserIdleDisplaySleep` assertion. It remained active after the Awake window closed. A controlled two-second session created the assertion and released it after expiry. [Apple documents](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep) that `PreventUserIdleDisplaySleep` also prevents idle system sleep while the display stays on. | None for idle sleep. Lid close, Apple menu Sleep, low battery, and thermal emergencies can still force sleep. |
| Done | Use Vorssaint as a behavior reference without copying its GPL source. | The read-only reference uses IOKit power assertions. MacPowerToys implements the same public macOS behavior independently. Apple documentation and the live assertion checks confirm that the current single required assertion is sufficient in each display mode. | None. |
| Done | Make the menu-bar Awake controls compact, selected, and clear about failures. | `ab81a67` replaces four indistinguishable buttons with one native segmented picker, keeps the display preference editable while Awake is off, shows assertion errors, and adds focused quick-mode coverage. It also removes the root popover height expansion while Cloud Sync keeps its internal scroll cap. | None. The physical Awake and Cloud Sync check is owned by the consolidated menu-bar matrix in `spec/main-request-list.md`. |
| Verify | Keep Awake's Off and indefinite modes idle. | The service no longer starts its one-second timer when Off or during an indefinite assertion without an attached process. Timed and Until modes retain expiry checks, and an active attached process retains its liveness check. Invalidated timers are released immediately. The focused timer-policy test passed in hosted run `36102526029`. | Confirm zero Awake timer owners while Off and during an indefinite assertion in the final signed app. |
| Done | Make every Awake mode row perform its named action. | `e3cb94e` makes Timed and Until activate their current interval or date when selected. `f4b7bf9` disables both Timed and Start when the interval is zero. The combined 543-test suite passes. | None. |
