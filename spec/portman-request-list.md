# Portman request list

## OnePlusUI redesign, 2026-09-29

Round 3a uses one cards-only PortmanSettingsView. The caller owns search,
scrolling, and density. The menu panel sets compact density; embedded
settings inherit the launcher's regular density.

Round 3 fixes the Servers summary and footer around a row-only scroller,
fixes Forward's host form above its results, and fixes Settings search above
its card stack. Server projections and installed-editor discovery run outside
the main actor. Selection dropdowns use `OnePlusSelect`.

Round 5 removes the regular-control override from the compact panel. Panel
fields, selects, steppers, and buttons are 24pt. Switch rows use their control's
width, captions live inside 56pt rows, Forward actions are both 64pt, and the
Servers sort select is 96pt.

Round 5 follow-up keeps the popover on the current app appearance when reused,
falls back to the process name when a server works from `/`, adds the required
Open App action, and keeps Forward's two 64pt action columns aligned. The manual
port field remains readable before a host is entered.

Round 8 adopts the shared fixed toolbar and footer slots. Servers keeps its
summary and footer; Forward keeps the host form; Settings keeps search; detail
keeps its header. Only rows or cards scroll. Nested scrollers and screen-based
row-height estimates are removed. The opener measures its host before showing
it. The shared shell still needs first-frame measurement before visibility.

Round 2 keeps the Servers composition. Sort by must show a menu affordance
and match Clean up in height and baseline. Port and memory values stay mono.
Forward and Settings use 24pt compact controls and aligned control columns.

Round 2 verification: Debug and build-for-testing pass. Tests were compiled,
not executed. Signed menu, form, and interaction checks remain with the orchestrator.

Round 3 screenshot-review verification: Debug and desktop build-for-testing
pass. Tests were compiled, not executed. Signed visual and interaction checks
remain with the orchestrator.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Select requested Portman pages before presentation and retain page state across tab switches. | The controller accepts an explicit page and consumes queued tool links before hosting. Visible panels receive page links directly. Settings retains its confirmation state and editor cache in panel-owned state. The fixed 200ms startup wait is removed; the visible-anchor retry remains. Debug and build-for-testing compile the changes and two focused regressions. | The diagnostics owner must select before opening or use `show(initialPage:activateApp:)`. Execute the regressions on hosted CI and measure native first frames and tab switches. |
| Verify | Open at natural content height and switch tabs without an intermediate layout. | The opener fits its hosted view before presentation. Tab navigation clears detail and cleanup in one nonanimated transaction without an identity reset. Row content has no screen-sized frame or nested scroller. Debug and build-for-testing compile these hosts with the fixed-region API. | Foundation must remove visibility-gated measurement and preference-delayed sizing. Verify first open, every tab pair, filtered Settings, empty Servers, and the 90 percent cap in signed frame captures. |
| Verify | Restore Portman identity colors without changing the approved Servers composition. | OnePlusColor.portmanSeries restores the five original server hues with darker light inks. Port labels, memory segments, sparklines, memory and CPU plots, process bars, and link hover reuse these tokens. Debug compiles. | Capture all tabs, one and several servers, detail, and hover in both appearances. Verify natural panel height and immediate tab layout after the shared shell update. |
| Verify | Resolve the shared round 4 panel review dependencies. | Portman adopts the shared fixed regions and 160pt Mode track. The shared shortcut recorder now defaults to 160pt control-role text. Signed `8cf8c02` stills retain stale geometry and all four panel names mismatch their pages. | Foundation must finish first-frame natural measurement. Orchestrator must capture all three pages in both appearances after selection is confirmed, then verify recorder and Mode bounds. |
| Verify | Align the Ports & processes fields and show complete short captions. | Round 3 review uses one 180pt field column in regular embeds and one 160pt column in compact panels. Protected apps and cleanup mode show short complete captions, with full behavior in help. | Verify both densities after the shared setting-row reset reservation is removed. |
| Verify | Fix the remaining Round 2 Portman panel review findings. | Reused popovers take `NSApp.appearance`, root-folder servers show their process name, Open App routes to the Portman tool page, and the Forward form keeps a 234pt field column beside 64pt actions. | Recapture Servers, Forward, and Settings in both appearances with the corrected diagnostics tab selection. |
| Verify | Use compact controls and readable setting rows throughout the menu panel. | The panel inherits shared compact density. Switch rows release the 160pt field column, protected-app and cleanup captions use `OnePlusSettingRow`, and separators remain between rows. | Verify label fit and 24pt controls in every panel tab. |
| Verify | Keep Portman controls fixed, scroll only row or card regions, and meet the 100ms page-switch gate. | Servers caches sorted rows, memory totals, cleanup suggestions, and sparklines off the main actor. Forward keeps its host form fixed. Settings keeps search fixed. Detail keeps its header fixed. | Source now places the form and search in the shared fixed toolbar. Remeasure page switches and scrolling in the signed build after the foundation completes atomic sizing. |
| Verify | Share one cards-only settings view with inherited density. | `PortmanSettingsView(search: "")` owns the setting cards. The menu host owns search, scrolling, and 24pt compact density. The no-result state is a card. Debug and build-for-testing pass. | Foundation must remove its page wrapper; then verify regular embedded settings and compact menu search. |
| Verify | Make Sort by read as a menu beside Clean up, with mono memory and port values. | Sort by uses a 96pt select at the same 24pt height as Clean up. The large memory value and detail port use mono type. Forward keeps a full-width host field with 64pt Scan and Add port actions. | Inspect all tabs, sort choices, and hover in the next signed capture. |
| Verify | Keep the Servers composition; move its type, colors, and controls to tokens. Use the 356pt menu shell, Forward cards, and searchable Settings with 24pt controls. | Debug build passes. Saved tabs, equal Link/Stop actions, scan cancellation, range selection, auth-failure-only password prompts, and idle scan policy remain in source. Open and refresh tasks now cancel. | Review all tabs, tunnels, SSH failures, and cleanup in the orchestrator's installed build. |

The owner requested a MacPowerToys tool based on the detailed WhatThePort
showcase at `/Users/surajmandal/tmp/what-the-port-showcase/README.md`, adapted
to MacPowerToys' native design. Portman is a menu-bar-only applet: the launcher,
Raycast, Spotlight, and deep links open its full menu-bar panel, with no separate
Portman window or reduced duplicate tab. Its status item shows the server count.
SSH local forwarding lets selected ports on a private server appear on loopback
on this Mac. The native reference's overview, detail, cleanup, settings, and
contextual actions are the design and behavior targets, not just a port list.

The owner reviewed the live panel and requested these corrections:

- Use a monochrome menu-bar glyph derived from Portman's socket icon.
- Give Servers, Forward, and Settings equal full-width tab cells, hit targets,
  and underline lengths; make each server row respond across its visible width.
  Use a link symbol for open actions and show stop symbols in red on hover.
- Remove excess popover height. Keep detail charts aligned, prevent the CPU
  plot from spilling past its axes, and reserve space for the shared hover time.
  Move the localhost and more-actions controls into the detail header; the
  more-actions control must not show a second down arrow.
- Let Return run the relevant Forward form action. Widen the manual remote-port
  field, support Select all and Shift-click range selection after a scan, and
  provide Clear scan. Leaving Forward clears its pending selection.
- Keep closed-panel and non-Servers tab monitoring inexpensive.

The next live review requested a smaller menu-bar and panel glyph, inset server
hover rows, compact side actions, and a tab line flush with the divider.
The owner's later screenshot supersedes the earlier row and memory treatment:
the hover surface extends farther toward both edges while retaining inner text
padding; link and stop replace both the sparkline and memory number in a fixed
trailing slot, with blue and red hover feedback. The overview shows only memory
used by listening processes, not whole-Mac usage. Tab changes keep labels and
content stable with a restrained selection change on the divider. Forward
must accept `user@IP`, prompt for an SSH password when key access fails, allow
a password retry without persisting the credential, and identify scanned ports
by service or process. Port rows should show full available detail on hover
and reveal more on click, including a
Node command or Docker name when the remote host exposes it. The panel should
match the compact, neutral style of the combined MacPowerToys menu bar.
OpenSSH records a new host key on first connection and still rejects a changed
key. Portman never saves the SSH password.

The latest live review asks for overview rows and their hover surface to match
the memory bar's width while retaining their inner text padding. The server
footer should use less height and offer Sort by Port, Memory, Name, or CPU;
Port is the default. Remove the Alerts feature, including its page, background
notifications, tray attention color, alert settings, and chart threshold.
Settings replaces Alerts as the third tab, with a refresh action in the header
and a search field that filters individual settings. Tab selection should fade
in place; the earlier travelling underline entered from an unexpected edge,
and the later instant switch removed the requested animation altogether.
Keep high-usage servers excluded from automatic cleanup independently of the
removed alert presentation.

The current live review reports that the tab underline still appears to enter
from unrelated edges. A remote scan of `oci2` labels most listeners as unknown;
try other available read-only sources such as privileged process metadata,
containers, and system services before falling back to unknown. Remove the
always-visible SSH password button; request a password only after SSH reports
an authentication failure. In Settings, inset the search field consistently,
align labels left and controls right, replace the ineffective tall cleanup
steppers, and make every selector usable. Check the actual running UI with
computer control, without taking over the owner's desktop.

The next review asks for equal-sized Link and Stop controls in active forwarding
rows. Closing and reopening Portman must restore the selected Servers, Forward,
or Settings tab. Other menu-bar tab groups must also remember their selected
tab. Each tab's panel height should follow its content so short pages do not
leave a large blank area below the last control. Pending scan selections still
clear when leaving Forward, as requested earlier.

The latest Forward screenshot shows a detached spinner and loading message,
while the same panel already says `Listening on oci1` and shows empty-result
controls. Keep scan progress compact and aligned with the host action, avoid
claiming discovery is complete until it is, and prevent a temporary empty
result from reading like a finished scan. Preserve accessible progress and a
stable panel layout in both appearances.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Complete | Refine the SSH scan loading state and related Forward layout. | The scan now has one inline status row and Cancel action, with no completed result until SSH succeeds. Hosted run `36242288305` passed Portman's normal-launch, invalid-host, Settings, hover, and reopened-tab UI checks plus the unit suite. Its 400pt dark/light loading renders end just below the manual-port row; the idle capture shows the compact panel without duplicate empty controls. The invalid-host error is visible and has a stable accessibility target. The current source passed a local compile-only build. Existing SSH service tests cover successful discovery and loopback forwarding. | The signed installed-app handoff and live private-host success/cancel checks remain in the broader Portman rows. |
| In progress | Match active-forward Link and Stop control sizes, remember selected menu-bar tabs, and remove excess bottom space from short tab pages. | Link and Stop now use the same small native control size and 28-point label width. Portman saves the chosen tab across popup recreation; the combined tray and Monitor already persist their tabs. The Portman panel follows measured content height. Hosted run `36212055219` passed the real status-item close/reopen UI test; its dark and light active-forward renders show equal button dimensions. The 400-point Forward capture has no large blank tail, and the local compile-only check passed. | Verify the final signed installed app. |
| In progress | Fix the live-reviewed tab, remote identification, password, and Settings defects. | Each fixed tab underline and label emphasis now fade over 0.16 seconds; the password button is gone; remote scans probe non-interactive privileged `ss`, Docker, and systemd; and Settings has a full-width search and compact trailing controls. Read-only `oci2` inspection confirmed that ordinary `ss` hid most process owners while the added sources exposed them. Hosted run `36208481934` passed the first normal-mode Portman launch, tab navigation, Settings controls, hover checks, and the unit-test step. Its captures show the underline at each fixed tab position. After confirming zero Cloud Sync transfers, the tested signed app and helper were installed with matching source stamps and passed strict signature verification. | Intermediate fade frames and Reduce Motion still need live inspection; native Computer access to MacPowerToys was rejected by automatic approval review. |
| Complete | Match the server rows to the memory bar, sort by Port, Memory, Name, or CPU, and replace Alerts with searchable Settings. | Hosted run `36175966070` passed the Portman UI job and unit-test step. Its normal-mode four-listener capture shows the footer fully inside the panel, and the row and memory bar accessibility frames match. The same job exercised sorting, Forward navigation, and individual Settings filtering; the filtered capture shows the panel ending just below its controls. Alerts delivery and presentation are removed, while high-usage cleanup protection remains. The signed app and helper were installed from clean HEAD and launched in the background without local UI tests. | None for this review. |
| In progress | Route every Portman entry point to one full menu-bar panel, with a count-bearing status item. | The source has one dedicated 400-point panel and status item. The launcher Open action and deep link route there; a Raycast command builds offline, and Xcode extracted a discoverable Spotlight App Shortcut. The separate window, shallow combined tab, and duplicate launcher settings form are gone; the launcher detail now shows only the tool guide. | Verify all entry routes, count, and dismissal in the final signed app. |
| In progress | Recreate the reference's connected overview and detail states in the menu bar. | The panel has a listening-process memory breakdown, stable port colors, linked row/bar hover, sparklines at rest, expandable metadata and process tree, ten-minute history, and shared memory/CPU chart hover. Hovering a memory segment changes the heading, large memory amount, RAM share, and CPU while row hover highlights the segment. The scan hides system and GUI listeners by default, retains CLI runtimes packaged inside an app bundle, and can show all listeners. Hosted run `36119359116` saved a one-server overview and light/dark detail at 400 points. The memory axis reads GB/MB across ten minutes, and the compact detail keeps its Open localhost action visible even at the hosted screen's 488-point panel cap. | Inspect the sorted row list, segment hover, disclosure, and dismissal in a hosted render and final signed app. |
| In progress | Preserve cleanup and process-tree actions, with protection and accurate reclaimed-memory preview. | Stop checks same-user identity and process start before SIGTERM, and checks child identity and parent before signaling. After a configurable three-second grace period, it sends SIGKILL only to still-running processes with the original start time and user. Restart uses the same grace policy. The cleanup estimate deduplicates process identities and leaves high-usage servers unselected. Cleanup suggestions cover deleted folders, four observed idle hours, and three running days by default. Off hides suggestions; opt-in Automatic sends stop requests for fresh eligible processes without selecting high-usage or protected processes. Manual stopping still requires confirmation. Detail offers Restart only when the same process still exposes a runnable executable, arguments, environment, and folder. Restart rechecks identity, waits for the listener to release, and writes output to a Portman log. Hosted run `36111474606` passed the cleanup policy and changed-process force-stop tests; run `36107019320` relaunched a real rclone listener. Run `36119359116` saved selected-cleanup renders in both appearances: the memory estimate and footer fit, and the final Stop action is visibly red. | Verify destructive confirmation and process-tree behavior in the signed UI. |
| In progress | Keep searchable settings and applicable session/preview links from the reference. | Settings control the scan range and interval (two seconds by default), protected process names, listener scope, idle threshold, a configurable global shortcut, and an installed-editor preference with Finder fallback. The detail menu opens a discovered project folder in that editor. An opt-in detail link reads the exact Claude Code session ID from the process environment or labels a recent Codex folder match; it only copies a resume command. A separate opt-in checks public GitHub pull requests and successful preview deployments over an ephemeral, credential-free connection; verified links appear in detail. | Verify search, editor, session, preview, and settings states in isolation. Private repository lookups require a future credential-safe design. |
| In progress | Discover remote listening ports over SSH aliases or `user@IP` and forward selected ports to localhost. | The scan parses `ss` or `lsof`, accepts manual ports, and starts `ssh -N -L` bound to 127.0.0.1. Key login remains the default. Password login uses the existing memory-only askpass channel, prompts and retries in the panel, and disables public-key attempts for that connection. A first-use host key is accepted while a changed key is rejected. Process names appear in scan rows; opening a row fetches its command and Docker port mapping once. A tunnel becomes Running only after its own SSH process opens the local listener. Disabling Portman closes its tunnels. Hosted run `36117442936` exercised key-based remote scan, HTTP through loopback, duplicate mapping, stop, and an occupied local port. Run `36122992178` verified unexpected SSH exit changes the tunnel to Failed. Run `36150132160` exercised password rejection and metadata parsing without a Portman test failure; its unit job failed unrelated focus-style checks. Run `36150985951` passed the fresh-runner password prompt, retry, Cancel, Return-to-add, selection reset, and Settings UI checks. | Verify successful password login against a private host, live process and Docker context, and final signed UI. |
| In progress | Keep menu-bar server count and tunnel status current without high idle cost. | A dedicated Portman item owns monitoring while enabled. Its right-click menu opens the applet, refreshes, or opens a listed localhost port. The tunnel page puts running/failed forwards first and offers stop, open, and retry. The open panel uses the chosen scan interval; the closed menu item uses a 30-second minimum interval, and reopening restarts sampling immediately. The policy test passed in hosted run `36108595241`. Read-only command probes measured about 0.08 CPU seconds for the two `lsof` scans and one full process-table read on this Mac, so the idle cadence avoids most of that cost. | Verify live status changes, closed-menu idle cost, and tunnel recovery in the final signed app. |

The owner requested that verification leave the active desktop alone after
Xcode tests coincided with macOS privacy and Gatekeeper prompts. Build-only and
static checks are allowed here; executable interaction checks require an
isolated macOS account or VM.

For the latest review the owner also explicitly requested computer-control
inspection of the running app. Use app-scoped native control on the exact
installed build only when it preserves their foreground focus; executable
XCTest still belongs in an isolated macOS environment.

The hosted macOS unit-test run [36119359116](https://github.com/surajmandalcell/macpowertoys/actions/runs/36119359116)
passed at `a3786e2` with 864 passed, five skipped, and zero failures. It ran
Portman's actual SSH scan and tunnel service against a disposable sshd and
HTTP server, including occupied-port failure, listener restart, idle-scan,
alert and cleanup policy, and process-identity force-stop tests. Its Portman
overview, Forward, active tunnel, detail, selected cleanup, and Settings images
were inspected at the panel's actual hosted height. The final light/dark
cleanup and detail captures show the red Stop action and visible localhost
button. The local build-for-testing passed without launching either bundle.
The ad-hoc signed universal Release app and helper passed
`codesign --verify --deep --strict` at the reviewed code revision. Rebuild the
final committed source before installation.
The installed `/Applications` copy is older; installation and live UI review
remain deferred under the focus-preserving verification rule.

Hosted runs [36120696699](https://github.com/surajmandalcell/macpowertoys/actions/runs/36120696699)
and [36121832154](https://github.com/surajmandalcell/macpowertoys/actions/runs/36121832154)
each failed a new unexpected-SSH-exit assertion. That test inferred a process
ID from `lsof`, so it did not prove that it had signaled Portman's owned
`Process`. The service was also changed to publish exit before draining stderr.

Hosted run [36122992178](https://github.com/surajmandalcell/macpowertoys/actions/runs/36122992178)
passed 864 tests, with five skipped and zero failures. The disconnect test
signaled the exact SSH process owned by Portman and confirmed the Failed state,
process cleanup, and Stop action. Its light/dark Failed Forward renders showed
that the error was clipped beside Retry and Stop. The row now gives the error
its own line and exposes the full message in a tooltip. Hosted run
[36123964928](https://github.com/surajmandalcell/macpowertoys/actions/runs/36123964928)
passed 864 tests, with five skipped and zero failures. Its new light/dark
Failed Forward renders show the full exit message, local and remote mapping,
Retry, and Stop at the actual 400pt panel width. A signed universal Release
build of the Portman revision passed strict app and helper signature checks.
The signed hosted `dc97280` build was installed and launched from
`/Applications/MacPowerToys.app` in the background. Its app and helper stamps
match that tested code revision, the fresh installed process uses the expected
path, and the Raycast extension contains the Portman command. No Cloud Sync
transfer was active. Later repository commits changed documentation and tests,
not Portman product code. A read-only native Computer inspection of the live
menu-bar panel was denied by automatic approval review; the hosted renders and
process checks did not take desktop focus. A private host and live menu-bar
interactions still need owner-approved inspection.

The current source adds a hosted UI test for normal `--open portman` launch and
Servers, Forward, Alerts, and Settings navigation. The owner's live review
then identified the icon, hit targets, detail charts, spacing, and Forward
selection issues listed above. Their source fixes include a socket status
glyph, full-width controls, compact charts and header, Return actions,
multi-selection, Clear scan, scan cancellation, and tab-specific monitoring.
Swift syntax, the SVG, and asset JSON passed static checks. Hosted run
`36134013052` could not compile this revision because a CPU `BarMark` width
modifier was invalid; the chart now passes width in its initializer. Run
`36134700387` compiled and ran the app tests, then failed the repository's
focus-style check for five Portman controls. Source now suppresses the
mismatched native outline on those controls. The owner's second review found
unequal tab spacing, so the buttons and their container now stretch equally;
the hosted appearance test also captures Alerts. A local compile-only build
reached unrelated, concurrently edited Disk Explorer code and stopped on a
type-check timeout there. The next hosted build, interaction and screenshot
checks, and replacement of installed `dc97280` remain open.

Hosted run `36135491916` passed the unit step but its subsequent Portman UI
step could not find the menu-bar panel. Its failure screenshot shows Local
Network and Device Control permission dialogs from unrelated app startup in
front of the desktop. No permission choice was made. Portman UI navigation now
runs as a separate job on a fresh hosted Mac, while the unit job keeps its
offscreen renders and installable archive. A local `build-for-testing` of the
subsequent committed source passed without launching an app or runner.

The first fresh-runner UI capture had no privacy dialog but also no Portman
panel, which narrowed the failure to cold-launch routing or popover timing.
The app delegate now routes `--open portman` at launch, independently of SwiftUI
scene setup, and the controller defers presentation until its status item is
ready. Hosted run `36138020899` passed the fresh-runner navigation test:
Servers, edge clicks on Forward and Alerts, Return to add a remote port,
selection reset, and Settings. Its capture showed equal tab widths but clipped
the zero-server empty state. Run `36138772279` passed after replacing the tall
empty placeholder with a compact card, yet the card's second line still fell
below the 300-point panel. The empty overview now budgets the card's full
height, shows numeric `0 KB`, and has a hosted visibility assertion. Its hosted
capture and the remaining signed-install gate are recorded below.

Run `36139447108` passed the fresh hosted Portman navigation and empty-text
visibility checks. Its Servers capture shows equal tab widths and the complete
empty-state message, but leaves excess space below that card. The zero-server
panel is now 330 points rather than 375.

Hosted run `36140052984` passed the empty-text assertion and captured the
330-point panel with the full card and a small bottom inset. Run `36140955732`
passed Portman's fresh-runner UI navigation and the hosted unit-test step after
the new Mac Tweaks registry expectations were corrected: 869 tests, five skips,
zero failures. Run `36142313540` passed the added equality checks for all
three tab button widths and the visible `0 KB` label. The signed installed copy
and helper at `1319b8e` passed strict signature checks and launched from
`/Applications` in the background. Recheck their source stamps against current
`HEAD` at final handoff after any later repository commits.

The owner's earlier review drove smaller Portman glyphs, inset full-row server
hover, side link/stop actions, and a tab underline flush with the divider. The
Forward page now accepts `user@IP`, offers a memory-only SSH password sheet and
retry, identifies scanned processes, and loads command and Docker details on
row disclosure. Hosted run `36150132160` exposed a modal-sheet test mistake and
a long SSH diagnostic beneath the sheet. The test now cancels the native modal
before navigation, and authentication errors are concise and hidden while the
sheet is open. Run `36150985951` passed its dedicated Portman UI job. Its
Servers, Forward, initial password, retry, Alerts, and Settings captures were
inspected; the retry sheet is contained without an error overflowing below it.
The local app and test bundles compiled without launching either on the owner's
desktop. Hosted run `36153836043` passed 879 unit tests with five skips and
zero failures; its Portman and Fan UI jobs passed, and its app archive built.
Hosted run `36156271937` passed its Portman and Fan UI jobs and the unit-test
step for the final implementation; its archive step was still running when
this note was written. The installed app and helper at `d1f9e83` carried the
same source stamp, passed strict signature verification under team
`GF57JXJF5A`, and were launched from `/Applications` without a local UI test.
Recheck the installed stamp against `HEAD` at handoff because other applets
share this repository.

The latest screenshot showed the hover surface still too narrow and the graph
remaining behind its actions. The revised source gives overview rows a wider
hover surface, preserves their inner text gutter, and crossfades the fixed
trailing metrics slot to inset link/stop actions. The overview no longer scans
or displays unrelated whole-Mac memory, and a single underline moves between
equal tab cells without crossfading the entire page. Hosted run
[36168580633](https://github.com/surajmandalcell/macpowertoys/actions/runs/36168580633)
passed its fresh-runner Portman UI tests. The inspected rest, row-hover, and
link-hover captures show the wider inset selection, the complete metrics swap,
and the link's blue hover state at the actual 400-point width. The local app and
test bundles compiled without launching XCTest on the owner's desktop, and the
signed Release build passed strict signature verification.
