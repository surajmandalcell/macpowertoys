# System Tools Request List

Scope: Input Devices, System Care (with Mole), Task Manager (formerly System
Monitor), NetToys, and the window behavior these tools share.

Ownership: the orchestrator owns hosted tests, clean signed installation, and
installed-app interaction checks unless a row says otherwise. Status words:
Done (no work left), Verify (source built, check pending), Open (work or
publication pending). Logs live in `tmp/redesign/logs/` and
`tmp/redesign/perf/`. Update this list when a direct user correction or a
verified result changes a status.

## Cross-tool open verification

- Install: the installed app is older than current source (most notes cite
  `198055e4`). Install a clean signed HEAD and check its source stamp and
  running path. See `spec/troubleshoot/verification.md`.
- Background opens (runs 55-80): background routes must order windows back
  without activation, skip other Spaces, and reuse closed scene hosts. Source
  probes pass for all 13 scene roots. Still open on the signed build: close
  and reopen, Dock reopen, menu Open App, launcher Open, full-screen, and
  lock/unlock replay, with the frontmost app unchanged. Guarded native tests
  stop when the foreground app changes, so they need a quiet desktop.
- Hosted tests: most rows ran source-derived checks and compile gates only.
  Run the focused classes (`InputDevicesTests`, `SystemCareTests`,
  `SystemMonitorTests`, `SystemMonitorRemoteTests`, NetToys tests) with
  `tmp/redesign/tools/xtest.sh` while no game or full-screen app is in front.
- Performance (DESIGN quality gate 9): warm panel open at most 100ms, cold
  panel and window open at most 250ms, page and tab switch at most 100ms,
  measured to the complete final frame. Signed `198055e4` measured Task
  Manager pages at 215-287ms and panel tabs at 128-244ms. Fixes since then
  (`da3146a3`, `8adbcc30`, `027ea904`, `e0432849`, `58932d0c`, `00227de5`,
  `ff74d88b`) need a signed rerun. Cold Processes preparation is open.
  Evidence: `tmp/redesign/perf/w1-windows.md`.
- Shared OnePlusUI: adopt the next tag with `7dbcb3f`, `10b09f5`, `68c91bf`,
  `716ad8b`, and `a02d43d`. The app pins 1.0.0, so two corrected applet
  Settings height assertions wait for the tag. Then verify Task Manager card
  headers, System Care panel glyphs, and Disk geometry in both appearances.
- Both appearances: every row marked Verify needs a Light and Dark capture of
  the signed build, including focus modes (Full Keyboard Access, VoiceOver).

### Memory and closed-window recovery

Signed `e25d7c99` grew to 7,055 MB with 6.5 GB in Foundation (app-icon TIFFs).
Signed `d911b0fa` stayed at 327.5 MiB after all windows closed. Fixes:
`1529ae52` (80 x 80 icon images, caches cleared on close), `1b789232`,
`92e3b394`, `76ed9b89` (subprocess output caps and drained pools),
`44d8e12c` (unmount closed scene roots), `bc4132ca` (release inactive panel
roots), `329d6caf` (reuse glyph bitmaps), `2a036b02` (release closed
hosting controllers), and `a6aeff3a` (diagnostic `close-window/<tool-id>`
route). A follow-up sample found no retained 550 MB Overview increase.

Open: install a clean signed build, run the full route matrix, close all
surfaces, wait 30 seconds, then record heap, footprint, and reopen timing.
Goal: under 250 MB after close, with fast reopen. Reports:
`tmp/redesign/logs/w4-memory.md`, `w5-memory3.md`, `w6-memory4.md`,
`w7-memory5.md`.

## NetToys

Open verification:

- Permissions card buttons (`7c2a619`, neutral style at inherited density) and
  the Scanner stale-result note (`746abf9`): publish, adopt the dependency,
  and check every action state in both appearances.
- Production panel (`f9622ca5`, `9d10953e`): signed check of Scan network,
  Copy IP, switches, saved disclosures, and page routes.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Align Scanner cells and remove standalone row chrome (T089-T091). | `7ae93446`, `ed44cc0d`, `3145a948`: shared cell geometry in all 15 columns, empty scan is one open 44pt row. | Hosted checks, signed interaction. Report `w3-audit-nettoys.md`. |
| Verify | Audit every NetToys feature; apply the horizontal density and instant-motion correction. | `c125c479`, `f7294b61`, `5d5b5bca`, `b9220f87`: settings edits, Wi-Fi subprocess bounds, scanner sort, all-down rows, import, comments, archive, history. A permitted /24 scan returned 254 rows. | Hosted tests, signed install, both appearances. Run a fresh signed scan (the unsigned probe got EHOSTUNREACH for the gateway). Report `w1-audit-nettoys.md`. |
| Open | Run NetToys standalone and as the MacPowerToys package, with tagged OnePlusUI shared by both. | NetToys `8ed9d38` to `104224c` move core, views, menu, resources and tests; 99 tests pass; OnePlusUI 1.0.0 is pinned. | Publish both 1.0.0 tags, generate lockfiles, apply `tmp/redesign/nettoys-final.patch`, remove the unused in-tree OnePlusUI after remote builds. Verify clean clones, signed helper migration, both hosts, permissions, installed stamps. Report `w9-nettoys-extract.md`. |
| Verify | Show current network data and quick actions in the main panel (route, SSID, IPv4, bounded gateway probe, Scan network, Copy IP). | Reuses parser and cancellable subprocess code. No poller added. | Check Wi-Fi, wired, missing permission, no route, gateway timeout, both actions, first frames, idle work. |
| Verify | Add current-network tiles to the main menu panel, prepared off the main thread. | Panel keeps configuration, helper status, five recent anchors and failures across tabs. | Check loaded, empty, error, expanded states in both appearances. |
| Verify | Resolve the capture findings through round 6 (T=16, 24pt bottom bound, trailing chevrons, Scanner inset, permissions, natural short lists). | `60a0890` shows "No scans in this period" when saved runs exist outside the range. | Hosted regression, signed empty-period copy, popups, focus modes, populated Scanner cells, active scrollers, latency, a live scan. Report `25r9-nettoys.md`. |
| Verify | Correct round 3 findings (permission actions, Automatic enrollment alignment, uptime chart, outage viewport). | `61c1a0a`, `6dfebb2`, `371941d`. | Signed dark/light review and row scrolling. |
| Verify | Keep automatic scans on the active subnet; label retained results by their completed target. | `d3e2397`, `7131746`. The round 7 capture still showed an old archive from `192.168.0.255/24`. | Hosted regression and a fresh signed scan: confirm archive date, target, gateway row, open ports. Report `26-nettoys-scan.md`. |
| Verify | Correct round 2 review findings (uptime counts outages, Anchor lists, subnet default, status cells, row pitch). | `af4bb86d`, `136ba287`, `ae2d282c`, `70c9b132`. | Signed dark and light captures and focused tests. |
| Verify | Keep headers, controls, and status fixed; only list rows scroll; page changes within 100 ms. | SSH Anchor, Wi-Fi Priority, History use card-owned scrolling; loads run on utility tasks; `95077be` caches the Scanner table. | Measure page switches, profile Scanner scrolling, inspect fixed regions. |
| Verify | Embed shared settings cards without a second page or gutter. | `725b398`: `NetToysSettingsView()` keeps Background helper, Permissions, Data in one 16pt stack. | Confirm the dispatcher adds no extra `OnePlusPage`; signed review. |
| Verify | Round 2 screenshot corrections (scanner columns, Add Anchor edge, one permissions card). | `36f710c`, `fa73849`, `0992a44`. | Signed captures and the hosted column-layout check. |
| Verify | Rebuild all NetToys pages with DESIGN.md v14 at 1440 x 900 with a 200pt sidebar. | `6abfe1d` covers every page and sheet. | Captures and installed interaction. |
| Verify | Keep NetToys idle and import work light. | Installed `e1b9384` idled at 0.0% CPU; probe tick no longer writes a second file every two seconds; imports have byte and entry limits. | Exercise a selected-file import in the signed app. |
| Verify | Keep large exports responsive; saved scans stay importable. | Export formats on utility tasks; 32 MiB limit with recovery message. | Large export, append, and round trip in the signed app. |
| Verify | Make NetToys useful from the tray; add SSH Anchor and Wi-Fi Priority page switches before Refresh. | `7504bc2`: global SSH Anchor gate keeps per-anchor choices and skips probes while off. | Check both page switches and tray controls; confirm the helper stops the request class while a switch is off. |
| Verify | Use the new NetToys network-module icon. | 512px RGBA asset. | Inspect launcher and Dock in the signed app. |
| Verify | Keep the Tailscale device chooser compact (360pt, 40pt rows, height cap 260pt). | Layout regression; installed `a39cc93` showed five peers at 257pt. | Six-or-more-peer scrolling cap; hover and pressed feedback. |
| Verify | Put the shared Close control in both SSH Anchor sheets. | Structure regression; Tailscale sheet verified in `a39cc93`. | Open Key Access sheet; confirm Close stays visible with loading and error content. |
| Verify | Fill IP Scanner rows as each field arrives; give the table more space. | Streaming merge by IP; one-host fixture 35.1 to 1.57 seconds; default window 1,280 x 800. | Repeat the signed scan at the minimum window size; confirm names on the real network. |
| Verify | Add SSH Anchor for local devices with changing IPs (2-3 second port checks, one-click enrollment, host-key identity, atomic edit). | `362cc86`, `8e648a7`, `6fedddd`, `180d425`; parser, selected-address, atomic-write, recovery tests pass. | Verify the signed login helper across two connections; confirm SSH needs no host-key confirmation after the address changes. |
| Verify | Keep SSH key-only after an anchored device changes address (secure one-use password sheet, `ssh-copy-id`, Windows ACLs). | Regressions pass; `77dc585` helper healthy; `ssh -G win1` shows stable alias, `accept-new`, `CheckHostIP no`. | Change the anchored local address for `win1` and confirm key-only access. |
| Verify | Prefer a local SSH Anchor, fall back through Tailscale, switch back without flapping. | `4e9df5f`, `800bdd0`, `5a1fd89`; 61-test recovery class passes. | Exercise one signed anchor across a real local outage with a disposable SSH host. |
| Verify | Keep SSH Anchor compact and stable while state changes. | `5ec34ce`: stable columns and reserved widths; 6pt row inset. | Check row spacing and the 1,100pt minimum width. |

Done:

| Request | Evidence |
|---|---|
| Persistent, expandable tray activity (SSH Anchor, Wi-Fi Priority, History; five-item previews). | `d06c96c` |
| Clear Network History from History and Settings with one confirmation. | `3c20d0a` |
| Destinations: IP Scanner, SSH Anchor, Network History, Wi-Fi Priority. | `6b837a6`, `552f4e8` |
| Compact sidebar, scanner controls, and SSH Anchor form. | `362597b`, `9cc115d` |
| Every NetToys stepper changes once per press. | `8eee13e` |
| Native IPv4 scanner workflow (targets, ports, progress, filters, details, comments, favorites, history, six export formats), written without Angry IP Scanner source. | `13be002`, `6b837a6`, `77e683d`, `84a8533` |
| Scanner work and sort persist across destinations and relaunch. | `4dbe863`, `a6eb399` |
| Neighbor MAC addresses with a signed on-demand daemon; permission failures explained. | `e1f5f2b` to `1f7c394` |
| Background-approval recovery works while the tool is off. | `73c6042` |
| Scanner fetchers, openers, vendor registry, import, navigation, statistics, deep-link prefills. | `ad49590` to `f2ad983` |
| Literal SSH aliases; SSH Anchor draft from a scan result. | `d346c89` |
| Stable and randomized MAC identity. | `6b0ffc4`, `362cc86`, `180d425` |
| SSH config preserved except the selected `HostName` token. | `bc5e6e7`, `6fedddd` |
| Gateway, internet, and Wi-Fi tracking by SSID. | `5ec34ce`, `a3e85b4`, `2132bc7`, `1857966` |
| Location permission requested only from the visible action; state and recovery shown. | Explicit-action regression |
| SSID uptime and outage timeline. | `0c5aa1d` |
| Ordered Wi-Fi failover with iPhone hotspot fallback (macOS manages Instant Hotspot; no public API to invoke it). | `552f4e8` |
| Bundled login helper required while NetToys is enabled, with source-commit handshake. | `8e648a7`, `74ecb5f`, `81e7595` |
| NetToys integrated with the launcher, scene, deep link, icon, window state, Raycast. Visible Raycast rendering stays in the central Raycast rows. | `6b837a6`, `b61b0b3`, `95fc954` |
| NetToys and Task Manager open without blocking the launcher. | Loading shell, off-main archive decode |

## Input Devices

Open verification:

- Scroll reverse (`59122487`): the saved 3.0x endpoint stored
  `3.0000000000000004` and the strict range guard rejected the mouse profile.
  The transform now accepts one float step beyond each endpoint. Open: real
  wheel verification on the signed build (installed `38158c11` has an enabled
  tap), hosted tests. Report `w4-scroll-fix.md`.
- Tray identities (`cf56cc76`): signed hover and visual review.
- Accessibility revocation during an active tap or queued smoothing (T083):
  verify in an isolated session. Revoke trust during wheel smoothing, require
  zero interception and visible recovery, then regrant by explicit action.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Remove direct-row card insets and the duplicate Devices header (T082). | `fa3c0e3d`; header renders 338 x 40pt in both appearances. | Hosted `InputDevicesTests`; signed shell-edge alignment, Refresh and disclosure clicks, hover, keyboard. Report `w3-audit-input.md`. |
| Verify | Complete collapsible control surface and feature audit (B6, S5). | `57acd38c`, `64b510fb`: separate saved disclosures, one "Use custom scrolling" switch, HID refresh on a utility task, queued smoothing rejected on disable. | Hosted tests; every control, disclosure persistence, permission recovery, hardware behavior, first frames, focus, idle CPU, timing. Report `w1-audit-input.md`. |
| Verify | Compact first open of the main panel. | `d1bea33b`: Devices expanded, Mouse, Trackpad, Scroll device collapsed when keys are unset; saved choices kept. | Hosted tests; fresh defaults and saved choices in the signed app. |
| Verify | Device and battery summaries before controls in the main panel. | Shared cards show cached names, connection, battery, state, direction, speed. | Reported and unknown batteries, Refresh, permission actions, quick switch, every expanded setting. |
| Verify | Round 6 capture review (readable rows, both profiles, fixed Scroll device footer with 24pt clearance). | No owned source change needed. | Live scrolling, keyboard, hardware, compact panel height, idle CPU, latency. Report `25r9-tweaks.md`. |
| Verify | Scroll device footer clearance. | `3860c82`: footer in the page footer slot. | Check the footer at y636 in the signed 1080 x 660 window. |
| Verify | Round 5 fixes (equal profile columns, 56pt control row, omit missing metadata, neutral healthy state). | Source built. | Inspect Devices, Scrolling, About, compact panel in the signed build. |
| Verify | Round 3 rules (one page gutter, card-only row scroller, fixed footer, custom selects). | Source built. | Measure page switching; inspect full window and compact panel. |
| Verify | Round 2 findings (full-width key-value rows, top-aligned grid, picker placement). | `62ddf9b`. | Recapture all pages in dark and light. |
| Verify | One adaptive settings implementation for the 338pt panel and full Scrolling page. | `InputDevicesSettingsContent()` is shared; panel embeds it directly. | Inspect both hosts. |
| Verify | Redesign on the fixed 1080 x 660 canvas with Devices, Scrolling, About routes. | Shared sidebar, device cards, per-device controls. | Inspect each route in dark and light; real mouse and trackpad behavior. |
| Verify | Align the Scroll device picker edge with the shared trailing gutter. | `7504bc2`, `b88a40b`; rendered tray edge at x = 340. | Inspect tray and window in the signed build. |
| Verify | Use the new Input Devices mouse icon. | 512px RGBA asset. | Inspect launcher and Dock. |
| Verify | Show useful hardware details per device (transport, maker, speed, resolution, polling, buttons, IDs, firmware, serial); omit absent values. | Source built. | Inspect sparse USB and built-in devices. |
| Verify | Keep scroll control active after macOS disables the event tap. | `328c336` re-enables the tap inside the callback. | Sustained wheel input, then lock and unlock; confirm the profile stays active. |
| Verify | Confirm real mouse and trackpad control after Accessibility permission. | Unit seams cover profile selection and transformation. | Test vertical, horizontal, reverse, speed, smooth wheel on real hardware. |
| Verify | Redraw the workspace as one professional native tool (native controls, system focus ring, truncation, gated switches). | Signed `e41ef3c` showed equal cards and shared settings in the menu-bar tab. | Hover, keyboard traversal, accessibility text sizes. |

Done:

| Request | Evidence |
|---|---|
| Add Input Devices as an on-demand tool with its own window, route, icon. | `cfa8832` |
| Launcher intro sits directly below the tabs. | Layout regression |
| Menu bar choice None, Combined, or Separate. | Focused tests, autosave `MacPowerToys.input-devices` |
| Scroll device selector at the bottom, native bar on the 20pt gutter. | `65f1c0e`, `52663c4` |
| Separate mouse and trackpad profiles in adaptive cards. | `InputDevicesManager` |
| Six labeled controls per profile (use profile, speed, reverse vertical, horizontal, reverse horizontal, smooth wheel). | `e038609` |
| Mouse profile has a horizontal scrolling control. | `e038609` |
| Device card shows live control state (Not controlled, Permission needed, Passthrough, Controlled). | `testControlStateFollowsPermissionAndProfile` |
| One implementation of the scroll settings. | `InputDevicesScrollSettings` |
| Distinguish mouse-like from trackpad-like events, with manual override. | Manager classifier |
| Shift plus wheel scrolls sideways, with a switch. | `d2df0ff` |
| Neutral state label; compact key-value device identity. | Round 5 |
| Readable metadata at the normal width. | `cd11057` |
| About page shows intro and How to Use only. | `d2df0ff` |

## System Care and Mole

Open verification:

- Maintenance Tasks underline (Round 12, `9631144f`): both supplied signed
  captures already show the underline (64 opaque coral pixels at x224-255,
  y100-101), and actual-source checks pass in Debug and Release. No source fix
  is needed. Verify initial entry and Tasks -> History -> Tasks in both
  appearances on the signed build. Reports `w3-syscare-ui.md`,
  `w13-fix18-app.md`.
- Round 17 panel repair (`53b31541`, `517c5593`, `7c2a8222`, `34c24557`):
  adopt OnePlusUI 1.0.1, then verify Refresh and disclosure interaction and
  complete-frame timing. Report `w10-fix17-panels.md`.
- Memory: see Cross-tool open verification.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | T099-T101: compact System Care help and actions; trace the Tasks underline. T102: readable history columns. | `ca9a17bb`, `fb6619b8`: Safety 36pt and Maintenance 48pt shorter; matching 34pt history rows. | Installed Tasks capture discrepancy, real help, confirmations, disabled actions, all panel scan states. |
| Verify | T102 core: readable Mole history summaries with separate time and result. | `7b606373` parses session counts and targets; no cleanup command runs. | Hosted regression; signed dark/light history interaction. Report `w3-syscare-core.md`. |
| Verify | S1 five-destination window (Cleanup, Storage, Applications, Maintenance Tasks/History, Settings) and compact cleanup panel; old routes stay aliases. Approved design: `tmp/redesign/syscare/syscare-mock.html` and `syscare-spec.txt`. | `7e0404c4`, `3e1161c0`, `28a94dd8`, `26145e12`: native tables, cached icons, paired inspector actions, verified Mole guards. | Hosted tests; every page and panel state in both appearances, keyboard, VoiceOver, confirmations, controlled Trash, Finder and Quick Look, exact Terminal actions. Report `w2-syscare-ui.md`. |
| Verify | S1 lane A: trusted cleanup paths, frozen Trash IDs, work ownership, coverage, bounded Mole reads, exact application identity. | `a2962a86`, `7082f3fe`, `13b1701e`, `65cbbf59`, `366b1eee`, `3ffa6c7a`, `15e9a1bb`, `198055e4`. | Hosted `SystemCareTests`; folder access and denial, cancel, controlled Trash and Finder Put Back, exact Terminal actions. Report `w2-syscare-core.md`. |
| Verify | Startup-disk usage before a cleanup scan (Used, Purgeable, Free in one bar). | Bounded-capacity regression compiles. | Hosted run; unavailable, unscanned, empty, populated, loading, failure, cancel, confirmed Trash states. |
| Verify | Cleanup panel with storage bar and prepared category rows. | Rows prepared off the main thread; Analyze, Clear Scan, selection, Trash remain. | Hosted checks; signed scan, selection, expansion, Trash confirmation. |
| Verify | Round 6 capture review (Overview, Applications, Mole footer). | No owned source change. | Live row scrolling, size-error selection and Retry Size, native confirmations, focus, idle CPU, latency. |
| Verify | Explain application size errors; correct round 3 metadata layout. | `285fdf1`: reason text, cancellable Retry Size. | Inspect error recovery and Applications/Mole alignment. |
| Verify | Round 5 fixes (recursive sizes and icons on four utility tasks, inspector fill, neutral healthy states). | Source built. | Capture all pages; exercise search, selection, cleanup, storage, Mole actions. |
| Verify | Round 3 fixed regions and one gutter on every page. | Lazy rows scroll inside cards; strings load on utility tasks. | Measure page switching; inspect all pages. |
| Verify | One System Care settings card stack for the window and main window. | `SystemCareSettingsCards(mode:)`. | Confirm the dispatcher uses it directly and the old copy in `ToolPreferences.swift` is gone; inspect both hosts. |
| Verify | Round 2 corrections (metric value and unit split, neutral Storage action, no grain on non-metric cards). | `117f6b6`. | Recapture all pages. |
| Verify | Center the pre-scan tray empty state. | `7504bc2`. | Inspect the signed tray. |
| Verify | New System Care cleanup-tray icon. | 512px RGBA asset. | Inspect launcher and Dock. |

Done:

| Request | Evidence |
|---|---|
| Large interface for Mole and native cleanup. | `a073a35` |
| Storage drill-down (ring, breadcrumbs, folder rows actionable, file rows plain). | `855a250` |
| Mole install and update actions. | Homebrew detection |
| Privileged and interactive Mole work stays visible in Terminal; no password collected. | Terminal actions |
| Native cleanup safe and recoverable (approved roots, no symlinks, Trash). | Path-safety tests |
| Scan is the primary Cleanup action. | `6fb2d41` |
| Work status at the bottom; top actions aligned. | `1666d71`, `6247587` |
| Persistent, selectable tray scan with guarded Move to Trash. | `35241ea`, `275d5d5` |
| Real-data check: 100 candidates, Put Back restore, Mole 1.52.0 previews. | `631facd` |

## Task Manager (formerly System Monitor)

Open verification:

- Source fixes committed, signed acceptance open: round 11 window fixes
  (T056-T063, T105-T106: `af2303d8`, `602733ff`, `cdaee324`, Fan exit
  `45faea7d`, `a9673394`, `fb19e9eb`). Needs hosted tests, physical Fan
  writes, sleep/wake, route changes. Report `w3-tm-window.md`.
- Process icons (`f0eaaacd`): real bundle icons in window and panel, terminal
  glyph for command-line processes. Hosted app tests and signed review.
- CPU and Memory capacity (`054a6be7`): hosted run, signed heights, both
  appearances. Report `w13-fix18-app.md`.
- Header action rows (run 57), table traits (`e25d7c99`: 33pt headers, 34pt
  rows, alternating rows), metric traits (`e14b7e38`: 27pt values, caption
  colors, wave texture), scroll edges, header picks (`bd2e0963`), menu-panel
  radius (8pt, shared presenter), status readings (T050 stale marks), shared
  focus policy, and glyph pass (`91d9a538`): signed pixel captures, scrolling,
  sorting, selection, focus, pointer hover, and menu crowding checks.
- Retained pages (`58932d0c`, `027ea904`, `e0432849`): signed times for
  Overview, Settings, and panel tab switches; complete frames. Previous signed
  maxima: Overview 126ms, Settings 141ms; open items P1, P3, P4, P5.
- T014-T016: presented covered windows can sample; hidden and minimized stop.
  Signed native close and minimize, inactive Space, detail redraw, menu-metric
  independence, quiet CPU, wakeups, energy, App Nap, physical footprint.
- Panel height callback and diagnostics routes (foundation rounds 10 and 11):
  signed short and tall tab frames, latency, panel route comparison.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Round 12 critique: process sort feedback, app icons, compact Overview text, unique Disk details. | `23d1a768`: native sort indicator, bundle icons off-main, 11pt/9.5pt roles, one 100pt Volume panel. | Hosted `SystemMonitorTests`; signed sort clicks, icons, Overview inks, Disk in both appearances. |
| Open | Panel latency: warm open within 100ms, cold within 250ms, tab switch within 100ms (P1, P4, P5, P6). | Signed `43ce0eb9` medians: opens 16.1/38.1/79.0ms (Main, Task Manager, Portman), tabs 66.8/128.2/84.4ms. `547b5586` stops panel diagnostics matching the Task Manager scene. | Install the integrated fix; run the same collector and require warm opens and tabs at most 100ms. Keep open: cold complete frames, enabled separate items, saved-host edits, closed-panel CPU, hosted run. Report `w3-perf-panels.md`. |
| Open | T001-T008, T051, T110: panel latency and native behavior; display sizing before measurement; accessible status names; T108 Settings hooks. | `b7e222d7`, `8801bfd9`, `0fa0407d`, `073f2874`, `07728304`, `63daa7e9`, `a5d188f1`. | Clean install; pointer and keyboard timing, complete frames, Escape chains, foreground preservation, runtime owners, Control-click parity. A background diagnostic profile once changed Chrome to MacPowerToys as foreground; recheck with the scene fix. |
| Verify | Remote window controls, stable saved-host and error frames, complete panel readings (T053-T055). | `f44b9584`, `20cb65c7`, `3dcf0c69`, `b22323cb`. | `SystemMonitorRemoteTests`; cold first and later frames, help and context menus, host controls, Terminal, Open App, keyboard, both appearances. |
| Verify | Repair Remote Stats host editing, SSH sampling, lifecycle, window and panel actions (B8). | `c0dd4b4b`, `e901bac6`, `2dc04d43`; bounded `oci2` probe and two real samples pass. | Hosted `SystemMonitorRemoteTests`; host edits, Return, interval, Manual refresh, all close paths, Terminal, host selection, layouts; live macOS and Windows sampling. Report `w1-remote.md`. |
| Verify | All nine panel tabs dense, responsive, and complete before presentation (B7, A7, P5, S5, T096-T098). | `4ed82b8f`, `556945c9`, `63daa7e9`, `5075da8e`, `bb62bd07`: full-tile histories, 4 Hz publish limit, prepared text, full Processes list, no duplicate readings. | Hosted app tests; all nine tabs and actions, remote Connect/Disconnect, Open SSH and Open App, Home labels, chart contrast, natural heights, first frames, timing, idle work. For T098 collect at least 120 real samples and check long Network rates, complete RAM, Disk help. `tm-window` owns Fan hardware checks; `perf-panels` owns the open path. Report `w3-panel-tm.md`. |
| Verify | Audit the window and apply the density correction (guarded process actions, 30-second endpoint interval, cached chart text, independent Auto, hidden-window gating). | `8edb9428`, `1840152d`, `6ea5d560`, `549fb0f4`, `08a8dad2`, `267d4182`, `704dc1fe`, `90e86b85`. | Hosted tests; recheck the r10 background-open pending-data failure, warm reopen, close and minimize, every route, helper state, process confirmation, export, Settings, appearance, timing. Report `w1-tm-window.md`. |
| Verify | Task Manager title paint matches page titles; native traffic-light hover tracking works. | `0a034305`, `e303571b`, `54720f52`. | Title paint, routes, close and minimize hover glyphs, key changes, restore, appearance changes. |
| Verify | Round 8 layout: 203pt process lane, no empty hero captions, content-height info cards, 1pt chart rules, decimal disk units in status items. | `2f628330`, `bf697770`, `ec0aac3c`, `a6251a74`, `05f2bfc7`. | Card tops, Battery power states, info cards, guides, native disk labels in both appearances; hosted tests, focus, first frames, identity colors, idle CPU. Report `30r11-tm.md`. |
| Verify | Center every compact chart scale on its grid ticks. | `0b9bd503`, `29b37b19`; plots 64pt, 6pt endpoint space. | Raise the hosted CPU height cap from 410pt to 422pt and run it; verify tick centers, endpoint clearance, natural heights in both appearances. Report `30r11-panels.md`. |
| Verify | Decimal disk units throughout the window; RAM stays binary. | `f89207a7`, `testDiskByteFormatterUsesDecimalUnits`. | Hosted test; compare window and panels from one disk sample, including Remote Stats storage and native labels. |
| Verify | Round 7 window and embedded Settings (grid labels, sole-heading removal, unavailable cells, format picker width, Export trigger). | `6931d232`, `6d920782`, `b149c41d`, `dddd2931`, `4e5ebf33`. | Both appearances, endpoint clearance, report sections, host cards, both Settings widths, Text and JSON exports; hosted render tests; 1,000-row scrolling. Report `27r10-tm.md`. |
| Verify | Round 7 panel (numeric MB/s ticks, decimal Disk, no repeated Sensors card, offline remote cells). | Source built. | Hosted geometry tests; Home, Disk, Network, Sensors in both appearances. Report `27r10-panels.md`. |
| Verify | Round 6 panel (all three Fan presets visible, 64pt plots, no offline placeholders, hidden Fan polling released). | `1973ae7f`, `6000ec26`, `0d6074b9`, `78c89171`, `5dfa42c2`. | Dark/light geometry, Auto recovery, focus modes, heights, first frames, hosted regressions. Report `25r9-menus.md`. |
| Verify | Real and diagnostic panels follow app Appearance. | `b671917`. | Review status-item and diagnostic panels, popups, sheets; change appearance while visible. |
| Verify | Round 5 plot bounds and inherited focus policy. | `4acd760`, `a513f1f`. | Hosted bitmap regression; Fan Auto state, focus modes, heights, identity colors, latency, 1,000-row scrolling. |
| Verify | Round 4 critique and no competing menu height estimates. | `93fd6de3`, `ecb56a69`. | Hosted native short, tall, and async-profile regression and page renders; intermediate frames and latency. |
| Verify | Round 8 panel pages (natural-height cards, scale labels, legends, search kept across tabs, 28pt rows). | Source built. | All nine pages in both appearances; tab latency. |
| Verify | Round 3 capture findings (120 samples per metric, one-second window sampling, paired cards, Fan state, remote layout). | `d6f2d38`, `0cb5d86`, `246f1e2`, `fab56d8`, `3e33086`, `30bf1b2`, `e66fbd9`, `a8c9215`. | Signed dark and light review and interactions. |
| Verify | Profiler round 4 fixes without behavior change (final row IDs, no page identity transition, panel height owned by `OnePlusMenuPanel`). | `a839811`, `9638806`, `36dce94`. | Remeasure page switching and process scrolling. |
| Verify | Round 3 fixed regions and one gutter on every page and the panel. | Shared page host; filter, sort, formatting on utility tasks. | Measure 100ms page switch; 1,000-row scrolling; every route and panel tab. |
| Verify | One settings content view for the window and main-window embedding (`SystemMonitorSettingsContent()`). | Two cards in a 16pt stack; Settings route owns the sole `OnePlusPage`. | Confirm `ToolSettingsContent` dispatches `system-monitor` to it; shared signed review. |
| Verify | Round 2 corrections (app appearance, 34pt settings row, header Add host, 28pt tables, 10pt gaps, dual-series labels). | Source built. | Recapture every page and panel in light and dark; exercise process, remote, Fan, and menu settings. |
| Verify | Rebuild as the fixed 1080 x 660 window and a 356pt panel, keeping all pages, process actions, Remote Stats, Fan, menu metrics, and saved navigation. | Compact 200pt sidebar, stable page IDs, drag and keyboard metric reorder, shared panel parts. | Exact-build window, panel, sheet, menu, keyboard, and sampling checks. Confirm the foundation `tab` query connects to `systemMonitor.trayPage`. |
| Open | B3: Fan below Awake on combined Home; keep Fan on Task Manager Home and Sensors. | `42cf6c02` reuses `FanControlView(owner: "main-tray-home", compact: true)` while Task Manager is enabled. | Hosted Fan ownership checks; all locations, hidden polling, disabled-tool state; protected writes on physical hardware after macOS approval, in an isolated session. Report `w1-panel-main.md`. |
| Verify | Bare Fan warning glyph; Auto, Cool, Max stay visible; release stale keyboard outlines on outside click. | Hosted AppKit regression passed; installed from clean source. | Keyboard and pointer focus in a hosted UI interaction. |
| Verify | Remote Stats refresh from 5 seconds; menu-bar readings stay visible when the interval or placement changes; no control shifts. | Fixed-size picker and value-retention regressions passed. | Final signed build, native item position, live connected layout. |
| Verify | Useful, live process details (Copy Path, sample time, virtual-address help, ports, hierarchy that keeps every PID). | Hosted hierarchy, endpoint parser, two-sample refresh regressions passed. | Live detail, copy, hierarchy, endpoints in a signed app. |
| Verify | Remote Stats naming; keyboard-usable SSH settings (Return connects, interval restarts polling, Manual stops, Open Terminal). | Hosted run passed; one bounded SSH sample returned the protocol marker. | Return, cadence, Terminal handoff, connected visuals with Linux, macOS, and Windows hosts in an isolated session. |
| Verify | On-demand activity manager: full searchable process list, sortable headers that persist, rich details, guarded Quit. | Sampler runs only on Processes; `ps` fallback capped at 2 MB and 5 seconds. | Sorting, large-list scrolling, details, guarded actions in the signed app. |
| Open | Stats breadth without World Clocks or Bluetooth pages. | Overview and tray show CPU, GPU, memory, disk, network, battery, thermal, load, fans. | Add first-party temperature sensors where supported; verify light and dark. |
| Verify | Read fan RPM without another installed app. | Bundled native SMC reader showed two fans at 3,472 RPM average on Mac16,7; the signed helper shares the SMC layout for guarded writes. | Inspect live RPM and guarded Auto and Max writes after macOS approval, in an isolated session. |
| Verify | Tools built in any language install through the Marketplace. | `docs/MARKETPLACE_TOOLS.md`; Monitor no longer owns plugin discovery. | Signed, notarized third-party tool from a custom catalog, end to end. |
| Verify | Monitor Linux, macOS, and Windows hosts only while connected, with conservative sampling (default 30 seconds). | Bounded SSH reads after Connect; no daemon; three parsers pass. | Live hosts on all three systems; sampling stops after disconnect. |
| Verify | Reuse the Remote Stats SSH connection (private ControlMaster socket, explicit exit on disconnect). | `ssh -G` resolves the options; regression passes. | Hosted regression; confirm no socket or SSH master remains after disconnect. |
| Verify | Combined, Separate, Off placement in each metric page title bar. | Per-metric saved placement; legacy migration; saved positions preserved. | Icon positions and restoration in the signed app after relaunch. |
| Verify | M02 Scope trace as the Task Manager icon. | App and Raycast PNGs match the owner file. | Dock display in the signed app. |
| Verify | Enable and reorder the seven menu metrics independently. | `b1d532e`, `b53bc23`, `8acd4ac`; removing the last metric turns the menu off, re-enabling restores RAM. | Signed Command-drag, relaunch, position preserved, final-metric disable. |
| Verify | Per-item icon, style, interval, and metric format (schema version 2). | `79ee403`, `74d7335`. | Check the minimum-width layout for clipping. |

Done:

| Request | Evidence |
|---|---|
| Task Manager window chrome: fixed 1080 x 660 content, three traffic lights on the 40pt centerline, 220pt sidebar and clipped workspace paint, Remote Stats actions in one compact cluster. | `4838fb0`, `a07a8d1`, `9e39d61`, `b872a4b`, `d288343` |
| Reusable OnePlusUI package and showcase. | `0ddbae8` |
| Rename to Task Manager and reproduce `task-manager.html` (telemetry, 356 x 536 menu, saved Remote Stats hosts, System Report, process sheet, horizontal remote instances, grain assets). | `556751e` to `7b28ae0`; screenshots in `docs/screenshots/task-manager*.png` |
| Remove graph insets; 1-minute Load value; `...` while readings are pending. | `dc97280` |
| Remove redundant Overview history cards. | `d06c96c` |
| CPU, memory, GPU, disk, network, battery, thermal, load data. | `cfa8832`, `b1d532e` |
| Dense live tray overview from the 120-sample history, independent detailed-sampling owners. | `04f5227`, `275d5d5` |
| Detailed collection only while the window is open. | Appear and disappear hooks |
| Live values, menu layouts, timing, and shutdown checked. | `29fcbd0` |
| One due-driven sampler; zero timers and status items when no surface needs it. | `b1d532e`, `3a76cfe`, `bd746e2` |
| Update settings and menu items only when rendered state changes. | `cc5a1ba` |
| Whole-app background work returns to baseline (25 cycles, 11 surfaces, 23 owner counts). | `5a3f745`, `75cd9d9` |

## Shared window behavior

Open: none beyond the cross-tool list above. The shared UI quality checklist
(`~/.codex/rules/ui-quality-checklist.md`) stays ongoing: append each new
recurring owner correction and apply it before every UI handoff.

| Status | Request | Evidence |
|---|---|---|
| Done | Correct sidebar width family: 220pt compact for Input Devices and Task Manager, 240pt data for System Care. | Shared top edge and inner padding |
| Done | Remember window position, display, and size for the three tools. | `WindowAccessor`, `WindowStateManager` |
| Done | Enforce minimum sizes for the launcher and every workspace. | `9a390a8` |
| Done | Keep short metadata inline; two columns on sparse wide pages. | `f44fc7a`, `29fcbd0`, `8f4b6dd`, `631facd` |
| Done | Restore on multiple displays. | `cf5c975` |
| Done | Quiet structural dividers and compact aligned top actions. | `81de8b1`, `6247587` |
| Done | Launcher detail tabs: 6pt top inset, 18pt leading inset. | Layout regression |

## Reference and dependency boundaries

NetToys implements the scanner workflow independently. Do not copy or adapt
Angry IP Scanner Java or SWT source, tests, strings, translations, layouts,
artwork, plugin ABI, serialized preferences, or bundled vendor data. Use
native APIs, system OpenSSH, and MacPowerToys-owned fixtures and formats. The
reference is behavior only. IPv6 and Java plugins stay outside the native
scope. The native app uses configurable fetchers and openers, and validated
GUI prefills instead of a headless scan program.

Mole is an optional external CLI. Detect its installed binary and use visible
Terminal actions for interactive or privileged work. Never scrape ANSI or TUI
output into a native destructive plan, and never collect a sudo password. Do
not bundle its GPL payload by default. A Mole-derived fork needs a separate
license, trademark, source-distribution, signing, and update review. Use
System Care as the product name and credit Mole CLI as the dependency.

Native input control uses event characteristics, not guaranteed per-device
scroll provenance. Detailed collectors follow their visible owners; opt-in
background features keep only their required work. Do not restore the old
monitor interval, the three-page NetToys layout, the no-Location plan, the
external fan helper, or material styling.
