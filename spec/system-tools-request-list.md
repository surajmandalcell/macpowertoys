# System Tools Request List

Scope: Input Devices, the main panel's metrics, top processes, and Fan, and
the window behavior these tools share.

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
  pass for every scene root. Open on the signed build: close and reopen,
  Dock reopen, menu Open App, launcher Open, full-screen, and lock/unlock,
  with the frontmost app unchanged. Guarded native tests need a quiet desktop.
- Hosted tests: run `InputDevicesTests`, `SystemMonitorTests`, and
  `FanControlTests` with `tmp/redesign/tools/xtest.sh` while no game or
  full-screen app is in front.
- Performance (DESIGN quality gate 9): warm panel open at most 100ms, cold
  panel and window open at most 250ms, page and tab switch at most 100ms,
  measured to the complete final frame. Later fixes need a signed rerun.
  Evidence: `tmp/redesign/perf/w1-windows.md`.
- Shared OnePlusUI: adopt the next tag (`7dbcb3f`, `10b09f5`, `68c91bf`,
  `716ad8b`, `a02d43d`). The app pins 1.0.0, so two corrected applet Settings
  height assertions wait for the tag.
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
| Verify | Smooth wheel feels like a native Mac scroll. | Display-linked frames on the pointer's screen, 70 ms exponential ease-out, notches add to the motion, reversal cancels at once, whole-pixel carry, every event continuous and phase-less; `testSmoothingEasesOutCarriesFractionsAndCancelsOnReversal`. | Real wheel in Safari, Chrome, Xcode, and Finder at 1x and 3x, on a 120 Hz and a 60 Hz screen. |
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

## Panel metrics, top processes, and Fan

The Task Manager tool (window, pages, own panel, menu-bar metric items,
Remote Stats) was removed on 2026-11-16. It continues as a separate product.
What stays in MacPowerToys serves the main panel.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Version 15 combined panel: footer tabs, gear, and Open App; Home Instrument card (CPU, Disk, Battery; GPU, Memory, Network) with ticker charts, Fan and Awake card, five top processes, joined action bar. | `MainPanelShell.swift`, `MainPanelHome.swift`. `MainPanelTests` cover 1 s sampling while Home is visible and 5 s in the background, the 2 s process cadence and release, equal bento columns without Battery or GPU, and the 600 pt natural Home height. Offscreen renders in `tmp/redesign/captures/v15-menu-panel/`. | Signed install; live data, hover, tab switch, and timing in both appearances. |
| Open | Panel latency: warm open within 100ms, cold within 250ms, tab switch within 100ms. | Last signed medians before the removal: Main opens 16.1ms, tabs 66.8ms. | Rerun the collector on the signed build. |
| Verify | Fan first in the Home control card, above Awake; hidden on a Mac with no fans. | `FanControlView(owner: "main-tray-home")`; writes only on a segment click. | Hidden polling stops; protected writes on physical hardware after macOS approval, in an isolated session. |
| Verify | Fan warning glyph; Auto, Cool, Max stay visible. | Hosted AppKit regression passed. | Keyboard and pointer focus in a hosted UI interaction. |
| Verify | Read fan RPM without another installed app. | Native SMC reader read two fans; the signed fan helper shares the SMC layout for guarded writes. | Live RPM and guarded Auto and Max writes after macOS approval, in an isolated session. |
| Verify | Fan page reset (owner picks "Hint row" and "Coral text", 2026-11-20): one "Reset Curve" text button at the right end of the hint row under the chart, in coral `destructiveText` at the hint's caption size (`OnePlusLinearButtonStyle(.inlineDestructive)`). It is the only reset control; disabled unless Custom holds an edited curve. | `FanPageView.swift`. | Live hover, press, and reset in both appearances. |
| Verify | Fan chart look (owner pick "Heat line", 2026-11-20): the curve is a 3 pt line colored by temperature (`temperature-cool` to `temperature-very-hot`) over the same colors fading to clear, three dotted guides at 0, 50 and 100%, 10 pt `tertiary` labels, white points ringed in their temperature color, and the current CPU as a filled dot on the curve with an "N °C · N RPM" chip above it. | `FanPageView.swift`, `OnePlusLinearColor.temperatureCool`. | Light and Dark on the installed app. |
| Verify | Fan presets (owner picks "Curve cards" and "By sound", 2026-11-20): five cards under the chart, each with a small picture of its curve: Silent, Quiet, Steady, Hold N °C, Custom. Picking a curve card saves `fan.curvePreset` and clears `fan.keepCelsius`; picking Hold sets `fan.keepCelsius`; dragging or typing a point saves Custom and clears both. Curves stay quiet at idle and never let the CPU sit near 90 °C. macOS Auto on this Mac keeps the fans at the minimum, about 1,350 RPM, even at 86-96 °C (the app's "from [..] RPM, CPU N °C" log lines), so every preset starts at that minimum and ramps before the locked end. Silent: minimum to 75 °C, 30% at 85 °C. Quiet: minimum to 68 °C, 20% at 78 °C, 45% at 85 °C. Steady: minimum to 60 °C, 20% at 70 °C, 45% at 80 °C, 70% at 86 °C. All reach full speed at 90 °C. | `FanCurvePreset` in `FanCurve.swift`, `FanPageView.swift`. `FanControlTests` cover the pick rules. | Live pick of each card in both appearances. |
| Open | Fan input (owner pick "CPU and GPU averages, 20 s", 2026-11-21): the curve follows the average of all CPU die sensors and, separately, the average of the GPU die sensors, each over a 20 s average with dropout readings (-4, 0, 40) filtered out; each goes through the curve and the higher fan request wins. The hottest single core no longer drives the curve; it only forces full speed after 10 s in a row at 90 °C or more. On the 2026-11-21 loaded trace this cut speed jumps over 200 RPM from 45 to 8 and still answered a burst in 4 s. Presets by sound (owner): Silent and Quiet start the fans early at low, quiet speeds so the chip never heats up enough to need a loud spin-up; full speed should almost never happen in them. Steady is the aggressive curve. Presets, Hold range, and the chart's temperature scale move to the average's scale (it reads about 10 °C under the hottest core). | `FanDriver`, `FanCurve`, `FanPageView`. | Replay of the trace per preset; real load on the installed app. |
| Verify | Locked top of the Cool curve (owner, 2026-11-20): no red safety band. Points cannot be dragged, typed, or added at or above 90 °C. The curve always ends in one fixed end point, full speed from 90 °C, drawn as an ink dot with a lock, unlike the user's points. The fans run at full speed at 90 °C and above whatever the curve says. | `FanCurve.lockedEnd`, `FanPageView.swift`, `FanDriver.coolTarget`. | Drag a point into the locked zone; real hot-CPU check. |
| Verify | Keep X °C is a real target loop, not a curve: a PI controller on the smoothed CPU temperature (gain 0.05 per °C, learning 0.002 per °C a second, frozen while the speed is pinned at 0 or 100% so it never winds up), speed change at most 3% of the range a second, then Cool's 300/150 RPM steps; full speed from 90 °C always wins. Deadband (owner, 2026-11-20): inside the target ±2 °C the speed and the learned value stay frozen, so the fans hold one steady speed; it corrects only outside that band. It starts from the fans' current speed, and a new target keeps the learned speed. The Hold card draws the target line with its ±2 °C band; the chart shows the same band, and one line under the cards says "Holds N °C, give or take 2 °C, with a steady fan speed" beside the 70-85 °C stepper. Range 70-85 °C: in normal use on 2026-11-20 the hottest core read 50-78 °C, median 67 °C. | `FanHold` in `FanCurve.swift`, `FanDriver.keepTarget`, `FanPageView.swift`. `FanControlTests` cover the ramp, anti-windup, rest at minimum, the 90 °C override, no dip when taking over hot fans, a temperature wandering inside the band never changing the speed, and settling inside the band on a simple heat model. | Real hold under load. |
| Verify | Real and diagnostic panels follow app Appearance. | Source committed. | Change appearance while panels, popups, and sheets are visible. |
| Verify | Tools built in any language install through the Marketplace. | `docs/MARKETPLACE_TOOLS.md`. | Signed, notarized third-party tool from a custom catalog, end to end. |

Done:

| Request | Evidence |
|---|---|
| Reusable OnePlusUI package and showcase. | `0ddbae8` |
| One sampler on a utility queue; sampling only while an owner is visible; zero timers when unused; baseline after 25 cycles. | `SystemMonitorTests` |

## Helper daemon and permissions

Design (owner pick, "Fan daemon + Permission center"): one root daemon for
privileged work only (fan presets and Restart audio), and one
`PermissionCenter` as the single source of permission state. The daemon
installs with SMJobBless: one admin password, no Login Items (owner,
2026-11-19). Details and checks: `spec/troubleshoot/system-tools.md`.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Install the helper with SMJobBless on the first Cool or Max click (or Install Helper): one password, no System Settings; bless again only when the bundled `CFBundleVersion` is newer; unsigned builds stay read only; launch removes the old SMAppService daemon and login item. | Signed `make build`: the helper satisfies `SMPrivilegedExecutables`, the app satisfies `SMAuthorizedClients`, a wrong team fails; both plist sections are in the binary. | The owner's first real install, Cool, Max, and Auto, then `launchctl print system/com.surajmandal.macpowertoys.helper`. |
| Verify | Restart audio through the daemon, no password; osascript fallback when the daemon is off or fails. | `restartAudio` XPC call, no arguments; helper target compiles. | A real Restart audio with the blessed helper. |
| Verify | `PermissionCenter`: prompt-free reads, refresh on activation and the Accessibility-list notification, 2 s poll only while a visible row shows a missing permission. | `PermissionCenterTests` compiles. | Run the test; a real Accessibility grant with Settings, Input Devices, and Command-Shift-3. |
| Verify | Fan Check Again re-reads the helper status. | Awaits `FanHelperService.refresh()`. | Check Again after the install. |
| Verify | Input Devices asks only for Accessibility and updates by itself after a grant. | No Input Monitoring call or usage string. | Real grant. |
| Verify | Notifications asked once, at the first sleep warning or quit error. | `allowNotifications()`. | First real notification. |
| Done | Remove the Location entitlement and the smctl path; no re-registration on update. | Grep found no live use. | None. |

## Shared window behavior

Open: none beyond the cross-tool list above.

| Status | Request | Evidence |
|---|---|---|
| Done | Sidebar width family per `DESIGN.md`. | Shared top edge and inner padding |
| Done | Remember window position and display; restore on multiple displays. | `WindowAccessor`, `WindowStateManager`, `cf5c975` |
| Done | Minimum sizes for the launcher and every workspace. | `9a390a8` |
| Done | Short metadata inline; quiet dividers; compact aligned top actions. | `631facd`, `6247587` |

## Reference and dependency boundaries

Native input control uses event characteristics, not guaranteed per-device
scroll provenance. Detailed collectors follow their visible owners; opt-in
background features keep only their required work. Do not restore the old
monitor interval, a third-party fan helper, or material styling.
