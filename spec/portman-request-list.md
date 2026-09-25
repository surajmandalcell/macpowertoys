# Portman request list

The owner requested a MacPowerToys tool based on the detailed WhatThePort
showcase at `/Users/surajmandal/tmp/what-the-port-showcase/README.md`, adapted
to MacPowerToys' native design. Portman is a menu-bar-only applet: the launcher,
Raycast, Spotlight, and deep links open its full menu-bar panel, with no separate
Portman window or reduced duplicate tab. Its status item shows the server count
and attention state. SSH local forwarding lets selected ports on a private
server appear on loopback on this Mac. The native reference's overview, detail,
cleanup, alerts, settings, and contextual actions are the design and behavior
targets, not just a port list.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| In progress | Route every Portman entry point to one full menu-bar panel, with a count-bearing status item. | The source has one dedicated 400-point panel and status item. The launcher Open action and deep link route there; a Raycast command builds offline, and Xcode extracted a discoverable Spotlight App Shortcut. The separate window, shallow combined tab, and duplicate launcher settings form are gone; the launcher detail now shows only the tool guide. | Verify all entry routes, count, and dismissal in the final signed app. |
| In progress | Recreate the reference's connected overview and detail states in the menu bar. | The panel has a whole-Mac segmented memory bar, stable port colors, linked row/bar hover, sparklines, expandable metadata and process tree, ten-minute history with a threshold line, and shared memory/CPU chart hover. Hovering a memory segment now changes the heading, large memory amount, RAM share, and CPU while row hover only highlights the segment. The scan hides system and GUI listeners by default, retains CLI runtimes packaged inside an app bundle, and can show all listeners. Hosted run `36118434106` saved a one-server overview and light/dark detail at 400 points; its memory axis reads GB/MB and its history spans ten minutes. On the short hosted screen the detail footer sat below the fold; source now uses tighter spacing and chart heights, pending a fresh render. | Inspect compact detail, then segment/row hover, disclosure, and dismissal states in the final signed app. |
| In progress | Preserve the reference's cleanup and process-tree actions, with protection and accurate reclaimed-memory preview. | Stop checks same-user identity and process start before SIGTERM, and checks child identity and parent before signaling. After a configurable three-second grace period, it sends SIGKILL only to still-running processes with the original start time and user. Restart uses the same grace policy. The cleanup estimate deduplicates process identities and leaves alerting servers unselected. Cleanup suggestions cover deleted folders, four observed idle hours, and three running days by default. Off hides suggestions, Ask announces fresh suggestions when Mac notifications are enabled, and opt-in Automatic sends stop requests for fresh eligible processes without selecting warnings or protected processes. Manual stopping still requires confirmation. Detail offers Restart only when the same process still exposes a runnable executable, arguments, environment, and folder. Restart rechecks identity, waits for the listener to release, and writes output to a Portman log. Hosted run `36111474606` passed the cleanup policy and changed-process force-stop tests; run `36107019320` relaunched a real rclone listener. Run `36118434106` saved selected-cleanup renders in both appearances and confirmed the memory estimate and footer fit; review found a gray destructive button, now explicitly styled red in source pending a new render. | Inspect final destructive styling, then verify confirmation and process-tree behavior in the signed UI. |
| In progress | Preserve alerts, settings, and applicable session/preview links from the reference. | The panel has active and snoozed alert states, adjustable memory/growth limits, scan range and interval (two seconds by default), protected process names, listener scope, idle threshold, a configurable global shortcut, and an installed-editor preference with Finder fallback. The detail menu opens a discovered project folder in that editor. Notifications are opt-in with permission status, an actionable snooze, and hysteresis before a repeated alert. An opt-in detail link reads the exact Claude Code session ID from the process environment or labels a recent Codex folder match; it only copies a resume command. A separate opt-in checks public GitHub pull requests and successful preview deployments over an ephemeral, credential-free connection; verified links appear in detail. | Verify editor, session, preview, notification, alert, and settings states in isolation. Private repository lookups require a future credential-safe design. |
| In progress | Discover remote listening ports over existing SSH aliases and forward selected ports to localhost. | The SSH scan parses `ss` or `lsof`, accepts manual ports, and starts key-only `ssh -N -L` processes bound to 127.0.0.1. The scan uses the shared bounded SSH runner. A tunnel becomes Running only after `lsof` confirms that its own SSH process opened the local listener; a failed or stalled start keeps an error. The applet exposes local-port mappings, tunnel status, stop, and open actions. Disabling Portman closes its tunnels so they do not remain hidden. Hosted run `36117442936` exercised the real Portman service against an isolated sshd and HTTP server: remote scan, Running state, HTTP response through loopback, duplicate Portman mapping, stop, and an occupied port owned by another listener all passed. Its active-forward screenshots show readable ungrouped ports and no stale unnamed scan results on reopen. | Verify a private host, dropped connection, and final signed UI. |
| In progress | Keep menu-bar server count, alert indication, and tunnel status current without high idle cost. | A dedicated Portman item owns monitoring while enabled and turns amber for active alerts. Its right-click menu opens the applet, refreshes, or opens a listed localhost port. The tunnel page puts running/failed forwards first and offers stop, open, and retry. The open panel uses the chosen scan interval; the closed menu item uses a 30-second minimum interval, and reopening restarts sampling immediately. The policy test passed in hosted run `36108595241`. Read-only command probes measured about 0.08 CPU seconds for the two `lsof` scans and one full process-table read on this Mac, so the idle cadence avoids most of that cost. | Verify live status changes, closed-menu idle cost, and tunnel recovery in the final signed app. |

The owner requested that verification leave the active desktop alone after
Xcode tests coincided with macOS privacy and Gatekeeper prompts. Build-only and
static checks are allowed here; executable interaction checks require an
isolated macOS account or VM.

The hosted macOS unit-test run [36118434106](https://github.com/surajmandalcell/macpowertoys/actions/runs/36118434106)
passed at `5e876b4` with 864 passed, five skipped, and zero failures. It ran
Portman's actual SSH scan and tunnel service against a disposable sshd and
HTTP server, including occupied-port failure, listener restart, idle-scan,
alert and cleanup policy, and process-identity force-stop tests. Its Portman
overview, Forward, active tunnel, detail, selected cleanup, and Settings images
were inspected at the panel's actual hosted height. The red cleanup action and
compact detail changes after that run are compile-verified and await a fresh
hosted review.
The local build-for-testing passed without launching either bundle. The
ad-hoc signed universal Release app and helper passed
`codesign --verify --deep --strict` and embedded `5e876b4` at build time;
the final source revision will need a fresh Release build.
The installed `/Applications` copy is older; installation and live UI review
remain deferred under the focus-preserving verification rule.
