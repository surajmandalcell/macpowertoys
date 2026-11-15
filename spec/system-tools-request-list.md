# System Tools Request List

Scope: Input Devices, System Care (with Mole), NetToys, the main panel's
metrics, top processes, and Fan, and the window behavior these tools share.

Ownership: the orchestrator owns hosted tests, clean signed installation, and
installed-app interaction checks unless a row says otherwise. Status words:
Done (no work left), Verify (source built, check pending), Open (work or
publication pending). Logs live in `tmp/redesign/logs/` and
`tmp/redesign/perf/`. Update this list when a direct user correction or a
verified result changes a status.

## Cross-tool open verification

- Install: install a clean signed HEAD and check its source stamp and
  running path. See `spec/troubleshoot/verification.md`.
- Background opens: background routes order windows back without
  activation, skip other Spaces, and reuse closed scene hosts. Source probes
  pass for all 12 scene roots. Open on the signed build: close and reopen,
  Dock reopen, menu Open App, launcher Open, full-screen, and lock/unlock,
  with the frontmost app unchanged. Guarded native tests need a quiet desktop.
- Hosted tests: run `InputDevicesTests`, `SystemCareTests`,
  `SystemMonitorTests`, `FanControlTests`, and the NetToys tests with
  `tmp/redesign/tools/xtest.sh` while no game or full-screen app is in front.
- Performance (DESIGN quality gate 9): warm panel open at most 100ms, cold
  panel and window open at most 250ms, page and tab switch at most 100ms,
  measured to the complete final frame. Later fixes need a signed rerun.
  Evidence: `tmp/redesign/perf/w1-windows.md`.
- Shared OnePlusUI: adopt the next tag (`7dbcb3f`, `10b09f5`, `68c91bf`,
  `716ad8b`, `a02d43d`). The app pins 1.0.0, so two corrected applet Settings
  height assertions wait for the tag. Then verify System Care panel glyphs, and Disk geometry in both appearances.
- Both appearances: every Verify row needs a Light and Dark capture of the
  signed build, including Full Keyboard Access and VoiceOver focus modes.

### Memory and closed-window recovery

A signed build once grew to 7,055 MB from app-icon TIFFs, and another stayed
at 327.5 MiB after all windows closed. Icon, subprocess, scene-graph, panel,
glyph, and hosting-controller fixes are in source; the diagnostic
`close-window/<tool-id>` route exists.

Open: install a clean signed build, run the full route matrix, close all
surfaces, wait 30 seconds, then record heap, footprint, and reopen timing.
Goal: under 250 MB after close, with fast reopen.

## NetToys

Open verification:

- Permissions card buttons (`7c2a619`) and the Scanner stale-result note
  (`746abf9`): publish, adopt the dependency, and check every action state
  in both appearances.
- Main panel: Scan network, Copy IP, switches, saved disclosures, page routes.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Open | Run NetToys standalone and as the MacPowerToys package, with tagged OnePlusUI shared by both. | Core, views, menu, resources, and tests moved; 99 tests pass; OnePlusUI 1.0.0 pinned. | Publish both 1.0.0 tags, generate lockfiles, apply `tmp/redesign/nettoys-final.patch`, remove the in-tree OnePlusUI after remote builds. Verify clean clones, signed helper migration, both hosts, permissions, installed stamps. |
| Verify | Align Scanner cells and remove standalone row chrome (T089-T091). | Shared cell geometry in all 15 columns; empty scan is one open 44pt row. | Hosted checks, signed interaction. |
| Verify | Audit every NetToys feature; apply the horizontal density and instant-motion correction. | Settings edits, Wi-Fi subprocess bounds, scanner sort, all-down rows, import, comments, archive, history. A permitted /24 scan returned 254 rows. | Hosted tests, both appearances, a fresh signed scan. |
| Verify | Capture-review corrections: T=16, 24pt bottom bound, trailing chevrons, Scanner inset, scanner columns, Add Anchor edge, one permissions card, Automatic enrollment alignment, uptime counts outages, outage viewport, Anchor lists, subnet default, status cells, row pitch, natural short lists, "No scans in this period". | Source built. | Signed captures in both appearances, popups, focus modes, populated Scanner cells, active scrollers, latency, a live scan. |
| Verify | Keep automatic scans on the active subnet; label retained results by their completed target. | Source fixed; an old archive from another subnet was seen in capture. | Fresh signed scan: confirm archive date, target, gateway row, open ports. |
| Verify | Show current network data and quick actions in the main panel (route, SSID, IPv4, bounded gateway probe, Scan network, Copy IP), prepared off main. | Reuses the parser and cancellable runner. No poller. | Wi-Fi, wired, missing permission, no route, gateway timeout, both actions, loaded, empty, error, and expanded states. |
| Verify | Keep headers, controls, and status fixed; only rows scroll; page changes within 100 ms. | Card-owned scrolling; loads on utility tasks; cached Scanner table. | Measure page switches, profile Scanner scrolling. |
| Verify | Embed shared settings cards without a second page or gutter. | `NetToysSettingsView()` keeps Background helper, Permissions, Data in one stack. | Confirm no extra `OnePlusPage`; signed review. |
| Verify | Rebuild all NetToys pages with DESIGN.md v14. | Every page and sheet. | Captures and installed interaction. |
| Verify | Keep NetToys idle, imports light, and large exports responsive. | 0.0% idle CPU; probe tick writes no second file; import byte and entry limits; exports on utility tasks with a 32 MiB limit. | Selected-file import, large export, append, and round trip in the signed app. |
| Verify | Make NetToys useful from the tray; SSH Anchor and Wi-Fi Priority page switches before Refresh. | Global SSH Anchor gate keeps per-anchor choices and skips probes while off. | Both switches and tray controls; helper stops the request class while off. |
| Verify | Use the new NetToys network-module icon. | 512px RGBA asset. | Inspect launcher and Dock. |
| Verify | Keep the Tailscale device chooser compact (360pt, 40pt rows, 260pt cap). | Layout regression; five peers measured 257pt. | Six-or-more-peer scrolling; hover and pressed feedback. |
| Verify | Put the shared Close control in both SSH Anchor sheets. | Structure regression; Tailscale sheet verified. | Key Access sheet: Close stays visible with loading and error content. |
| Verify | Fill IP Scanner rows as each field arrives; give the table more space. | Streaming merge by IP; one-host fixture 35.1 to 1.57 seconds; default window 1,280 x 800. | Repeat at the minimum window size; real network names. |
| Verify | SSH Anchor for devices with changing IPs (2-3 second port checks, one-click enrollment, host-key identity, atomic edit). | Parser, selected-address, atomic-write, recovery tests pass. | Signed login helper across two connections; no host-key prompt after an address change. |
| Verify | Keep SSH key-only after an address change (one-use password sheet, `ssh-copy-id`, Windows ACLs). | Regressions pass; `ssh -G win1` shows stable alias, `accept-new`, `CheckHostIP no`. | Change the anchored address for `win1`; confirm key-only access. |
| Verify | Prefer a local SSH Anchor, fall back through Tailscale, switch back without flapping. | 61-test recovery class passes. | One signed anchor across a real local outage with a disposable SSH host. |
| Verify | Keep SSH Anchor compact and stable while state changes. | Stable columns and reserved widths. | Row spacing and the 1,100pt minimum width. |

Done:

| Request | Evidence |
|---|---|
| Persistent, expandable tray activity (five-item previews). | `d06c96c` |
| Clear Network History from History and Settings with one confirmation. | `3c20d0a` |
| Destinations: IP Scanner, SSH Anchor, Network History, Wi-Fi Priority. | `6b837a6`, `552f4e8` |
| Compact sidebar, scanner controls, SSH Anchor form; steppers change once per press. | `362597b`, `9cc115d`, `8eee13e` |
| Native IPv4 scanner workflow (targets, ports, progress, filters, details, comments, favorites, history, six export formats), without Angry IP Scanner source. | `13be002`, `84a8533` |
| Scanner work and sort persist across destinations and relaunch. | `4dbe863`, `a6eb399` |
| Neighbor MAC addresses with a signed on-demand daemon; permission failures explained; recovery works while the tool is off. | `e1f5f2b` to `1f7c394`, `73c6042` |
| Scanner fetchers, openers, vendor registry, import, navigation, statistics, deep-link prefills. | `ad49590` to `f2ad983` |
| Literal SSH aliases; SSH Anchor draft from a scan result; stable and randomized MAC identity; SSH config preserved except the `HostName` token. | `d346c89`, `180d425`, `6fedddd` |
| Gateway, internet, and Wi-Fi tracking by SSID; SSID uptime and outage timeline. | `1857966`, `0c5aa1d` |
| Location permission requested only from the visible action. | Explicit-action regression |
| Ordered Wi-Fi failover with iPhone hotspot fallback (macOS manages Instant Hotspot; no public API invokes it). | `552f4e8` |
| Bundled login helper required while NetToys is enabled, with source-commit handshake. | `8e648a7`, `81e7595` |
| Launcher, scene, deep link, icon, window state, Raycast integration; NetToys opens without blocking the launcher. | `b61b0b3`, `95fc954` |

## Input Devices

Open verification:

- Scroll reverse at the saved 3.0x endpoint: real wheel on the signed build,
  hosted tests.
- Tray identities (`cf56cc76`): signed hover and visual review.
- Accessibility revocation during an active tap or queued smoothing (T083):
  in an isolated session, revoke trust during wheel smoothing, require zero
  interception and visible recovery, then regrant by explicit action.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Remove direct-row card insets and the duplicate Devices header (T082). | Header renders 338 x 40pt in both appearances. | Hosted `InputDevicesTests`; shell-edge alignment, Refresh and disclosure clicks, hover, keyboard. |
| Verify | Collapsible control surface and feature audit (B6, S5). | Saved disclosures, one "Use custom scrolling" switch, HID refresh on a utility task, queued smoothing rejected on disable. | Every control, disclosure persistence, permission recovery, hardware, first frames, focus, idle CPU, timing. |
| Verify | Compact first open of the main panel. | Devices expanded and the rest collapsed when keys are unset; saved choices kept. | Fresh defaults and saved choices in the signed app. |
| Verify | Device and battery summaries before controls in the main panel. | Shared cards show names, connection, battery, state, direction, speed. | Reported and unknown batteries, Refresh, permission actions, quick switch, every expanded setting. |
| Verify | Capture-review corrections: readable rows, both profiles, fixed Scroll device footer, 56pt control row, omitted missing metadata, neutral healthy state, one page gutter, card-only row scroller, custom selects, full-width key-value rows. | Source built. | Live scrolling, keyboard, hardware, panel height, idle CPU, latency, page switching in both appearances. |
| Verify | One adaptive settings implementation for the panel and the Scrolling page. | `InputDevicesSettingsContent()` is shared. | Inspect both hosts. |
| Verify | Mac Tweaks window: one full-width column of cards on Devices, Scrolling, and About; profile cards stack. | Offscreen renders of all three pages in both appearances. | Adopt OnePlusUI with an `input-devices` canvas, then delete `ToolWindowCanvas.swift`. Inspect each route; real mouse and trackpad. |
| Verify | Use the new Input Devices mouse icon. | 512px RGBA asset. | Inspect launcher and Dock. |
| Verify | Useful hardware details per device; omit absent values. | Source built. | Inspect sparse USB and built-in devices. |
| Verify | Keep scroll control active after macOS disables the event tap. | The tap is re-enabled inside the callback. | Sustained wheel input, then lock and unlock. |
| Verify | Real mouse and trackpad control after Accessibility permission. | Unit seams cover profile selection and transformation. | Vertical, horizontal, reverse, speed, smooth wheel on real hardware. |
| Verify | One professional native tool (native controls, system focus, truncation, gated switches). | Equal cards and shared settings in the menu-bar tab. | Hover, keyboard traversal, accessibility text sizes. |

Done:

| Request | Evidence |
|---|---|
| On-demand tool with its own window, route, and icon; menu bar None, Combined, or Separate. | `cfa8832`, autosave `MacPowerToys.input-devices` |
| Scroll device selector at the bottom on the shared gutter. | `65f1c0e`, `52663c4`, `b88a40b` |
| Separate mouse and trackpad profiles with six labeled controls each, including mouse horizontal scrolling. | `e038609` |
| Live control state per device (Not controlled, Permission needed, Passthrough, Controlled). | `testControlStateFollowsPermissionAndProfile` |
| Mouse-like versus trackpad-like classification with manual override; Shift plus wheel scrolls sideways. | `d2df0ff` |
| About page shows intro and How to Use only. | `d2df0ff` |

## System Cleaner and Mole

Open verification:

- Maintenance Tasks underline: captures and source checks show it; verify
  initial entry and Tasks -> History -> Tasks in both appearances on the
  signed build.
- Panel repair: adopt OnePlusUI 1.0.1, then verify Refresh, disclosure, and
  complete-frame timing.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Compact System Care help and actions (T099-T101); readable history with separate time and result (T102). | Safety 36pt and Maintenance 48pt shorter; 34pt history rows; parser handles nested counts; no cleanup command runs. | Real help, confirmations, disabled actions, all panel scan states, history in both appearances. |
| Verify | S1 five-destination window (Cleanup, Storage, Applications, Maintenance Tasks/History, Settings) and compact panel; old routes stay aliases. Approved design: `tmp/redesign/syscare/syscare-mock.html` and `syscare-spec.txt`. | Native tables, cached icons, paired inspector actions, verified Mole guards. | Every page and panel state, keyboard, VoiceOver, confirmations, controlled Trash, Finder and Quick Look, exact Terminal actions. |
| Verify | S1 core: trusted cleanup paths, frozen Trash IDs, work ownership, coverage, bounded Mole reads, exact application identity. | Disposable fixture probes pass. | Folder access and denial, cancel, controlled Trash and Put Back, Terminal actions. |
| Verify | Startup-disk usage (Used, Purgeable, Free in one bar) and a cleanup panel with prepared rows. | Bounded-capacity regression compiles; rows prepared off main. | Unavailable, unscanned, empty, populated, loading, failure, cancel, confirmed Trash; scan, selection, expansion. |
| Verify | Capture-review corrections: application size errors with reason and Retry Size, recursive sizes and icons on utility tasks, inspector fill, neutral healthy states, fixed regions with one gutter, metric value and unit split, neutral Storage action, centered pre-scan tray state. | Source built. | Row scrolling, size-error retry, confirmations, focus, idle CPU, latency, page switching; capture all pages. |
| Verify | One System Care settings card stack for window and main window. | `SystemCareSettingsCards(mode:)`. | Confirm the old copy in `ToolPreferences.swift` is gone; inspect both hosts. |
| Verify | New System Care cleanup-tray icon. | 512px RGBA asset. | Inspect launcher and Dock. |

Done:

| Request | Evidence |
|---|---|
| Large interface for Mole and native cleanup; install and update actions. | `a073a35`, Homebrew detection |
| Storage drill-down (ring, breadcrumbs, folder rows actionable, file rows plain). | `855a250` |
| Privileged and interactive Mole work stays in Terminal; no password collected. | Terminal actions |
| Native cleanup safe and recoverable (approved roots, no symlinks, Trash). | Path-safety tests |
| Scan is the primary action; status at the bottom; persistent tray scan with guarded Move to Trash. | `6fb2d41`, `1666d71`, `275d5d5` |
| Real-data check: 100 candidates, Put Back restore, Mole previews. | `631facd` |

## Panel metrics, top processes, and Fan

The Task Manager tool (window, pages, own panel, menu-bar metric items,
Remote Stats) was removed on 2026-11-16. It continues as a separate product.
What stays in MacPowerToys serves the main panel.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Version 15 combined panel: footer tabs, gear, and Open App; Home bento (CPU, Disk, Battery; GPU, Memory, Network), Fan and Kwake card, three top processes, joined action bar. | `MainPanelShell.swift`, `MainPanelHome.swift`. `MainPanelTests` cover sampling only while Home is visible, the 2 s process cadence and release, equal bento columns without Battery or GPU, and the 602 pt natural Home height. Offscreen renders in `tmp/redesign/captures/v15-menu-panel/`. | Signed install; live data, hover, tab switch, and timing in both appearances. |
| Open | Panel latency: warm open within 100ms, cold within 250ms, tab switch within 100ms. | Last signed medians before the removal: Main opens 16.1ms, tabs 66.8ms. | Rerun the collector on the signed build. |
| Verify | Fan first in the Home control card, above Kwake; hidden on a Mac with no fans. | `FanControlView(owner: "main-tray-home")`; writes only on a segment click. | Hidden polling stops; protected writes on physical hardware after macOS approval, in an isolated session. |
| Verify | Fan warning glyph; Auto, Cool, Max stay visible. | Hosted AppKit regression passed. | Keyboard and pointer focus in a hosted UI interaction. |
| Verify | Read fan RPM without another installed app. | Native SMC reader read two fans; the signed helper shares the SMC layout for guarded writes. | Live RPM and guarded Auto and Max writes after macOS approval, in an isolated session. |
| Verify | Real and diagnostic panels follow app Appearance. | Source committed. | Change appearance while panels, popups, and sheets are visible. |
| Verify | Tools built in any language install through the Marketplace. | `docs/MARKETPLACE_TOOLS.md`. | Signed, notarized third-party tool from a custom catalog, end to end. |

Done:

| Request | Evidence |
|---|---|
| Reusable OnePlusUI package and showcase. | `0ddbae8` |
| One sampler on a utility queue; sampling only while an owner is visible; zero timers when unused; baseline after 25 cycles. | `SystemMonitorTests` |

## Shared window behavior

Open: none beyond the cross-tool list above.

| Status | Request | Evidence |
|---|---|---|
| Done | Sidebar width family per `DESIGN.md`. | Shared top edge and inner padding |
| Done | Remember window position and display; restore on multiple displays. | `WindowAccessor`, `WindowStateManager`, `cf5c975` |
| Done | Minimum sizes for the launcher and every workspace. | `9a390a8` |
| Done | Short metadata inline; quiet dividers; compact aligned top actions. | `631facd`, `6247587` |

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
