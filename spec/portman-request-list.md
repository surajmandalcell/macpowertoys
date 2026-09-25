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
| In progress | Route every Portman entry point to one full menu-bar panel, with a count-bearing status item. | The source has one dedicated 400-point panel and status item. The launcher and deep link route there; a Raycast command builds offline, and Xcode extracted a discoverable Spotlight App Shortcut. The separate window and shallow combined tab are gone. | Verify all entry routes, count, and dismissal in the final signed app. |
| In progress | Recreate the reference's connected overview and detail states in the menu bar. | The panel has a whole-Mac segmented memory bar, stable port colors, linked row/bar hover, sparklines, expandable metadata and process tree, ten-minute history with a threshold line, and shared memory/CPU chart hover. Hovering a memory segment now changes the heading, large memory amount, RAM share, and CPU while row hover only highlights the segment. The scan hides system and GUI listeners by default, retains CLI runtimes packaged inside an app bundle, and can show all listeners. The hosted one-server render at `f0f820c` confirms the Memory scope label and server row fit. It also exposed a clipped footer; the added height and singular count passed hosted tests at `cc3f465` and saved a new render for visual review. | Inspect the latest footer render, then default, segment/row hover, detail, disclosure, and light/dark states in an isolated macOS session. |
| In progress | Preserve the reference's cleanup and process-tree actions, with protection and accurate reclaimed-memory preview. | Stop checks same-user identity and process start before SIGTERM, and checks child identity and parent before signaling. The cleanup estimate deduplicates process identities, suggests only observed idle or deleted-folder servers, and leaves alerting servers unselected. Detail offers Restart only when the same process still exposes a runnable executable, arguments, environment, and folder. Restart rechecks identity, waits for the listener to release, and writes output to a Portman log. Hosted run `36107019320` captured the rclone server's environment and successfully relaunched its listener on the same port. | Verify selected cleanup estimate and confirmation in the final signed UI. |
| In progress | Preserve alerts, settings, and applicable session/preview links from the reference. | The panel has active and snoozed alert states, adjustable memory/growth limits, scan range and interval (two seconds by default), protected process names, listener scope, idle threshold, and a configurable global shortcut. Notifications are opt-in with permission status, an actionable snooze, and hysteresis before a repeated alert. An opt-in detail link reads the exact Claude Code session ID from the process environment or labels a recent Codex folder match; it only copies a resume command. A separate opt-in checks public GitHub pull requests and successful preview deployments over an ephemeral, credential-free connection; verified links appear in detail. | Verify session, preview, notification, alert, and settings states in isolation. Private repository lookups require a future credential-safe design. |
| In progress | Discover remote listening ports over existing SSH aliases and forward selected ports to localhost. | The SSH scan parses `ss` or `lsof`, accepts manual ports, and starts key-only `ssh -N -L` processes bound to 127.0.0.1. The scan uses the shared bounded SSH runner. A tunnel becomes Running only after `lsof` confirms that its own SSH process opened the local listener; a failed or stalled start keeps an error. The applet exposes local-port mappings, tunnel status, stop, and open actions. Disabling Portman closes its tunnels so they do not remain hidden. Hosted run `36107019320` passed a real SSH tunnel from a local rclone server through loopback, including an HTTP response. | Verify a private host, occupied local-port error, dropped connection, and final signed UI. |
| In progress | Keep menu-bar server count, alert indication, and tunnel status current without high idle cost. | A dedicated Portman item owns monitoring while enabled and turns amber for active alerts. Its right-click menu opens the applet, refreshes, or opens a listed localhost port. The tunnel page puts running/failed forwards first and offers stop, open, and retry. The open panel uses the chosen scan interval; the closed menu item uses a 30-second minimum interval, and reopening restarts sampling immediately. The policy test passed in hosted run `36108595241`. Read-only command probes measured about 0.08 CPU seconds for the two `lsof` scans and one full process-table read on this Mac, so the idle cadence avoids most of that cost. | Verify live status changes, closed-menu idle cost, and tunnel recovery in the final signed app. |

The owner requested that verification leave the active desktop alone after
Xcode tests coincided with macOS privacy and Gatekeeper prompts. Build-only and
static checks are allowed here; executable interaction checks require an
isolated macOS account or VM.

The hosted macOS unit-test run [36108595241](https://github.com/surajmandalcell/macpowertoys/actions/runs/36108595241)
passed at `cc3f465`, including an actual local SSH tunnel carrying HTTP traffic,
the listener-restart and idle-scan tests, scanner and alert-policy tests, and a
saved Portman dark-panel attachment. The local build-for-testing passed without
launching either bundle. The ad-hoc signed universal Release app passed
`codesign --verify --deep --strict`. Its embedded source revision must match
the final committed `HEAD` before installation.
The installed `/Applications` copy is older; installation and live UI review
remain deferred under the focus-preserving verification rule.
