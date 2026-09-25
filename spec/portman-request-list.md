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
| In progress | Recreate the reference's connected overview and detail states in the menu bar. | The panel has a whole-Mac segmented memory bar, stable port colors, linked row/bar hover, sparklines, expandable metadata and process tree, ten-minute history with a threshold line, and shared memory/CPU chart hover. Hovering a memory segment now changes the heading, large memory amount, RAM share, and CPU while row hover only highlights the segment. The scan hides system and GUI listeners by default but can show all. | Inspect default, segment/row hover, detail, disclosure, and light/dark states in an isolated macOS session. |
| In progress | Preserve the reference's cleanup and process-tree actions, with protection and accurate reclaimed-memory preview. | Stop checks same-user identity and process start before SIGTERM, and checks child identity and parent before signaling. The cleanup estimate deduplicates process identities, suggests only observed idle or deleted-folder servers, and leaves alerting servers unselected. Detail offers Restart only when the same process still exposes a runnable executable, arguments, environment, and folder. Restart rechecks identity, waits for the listener to release, and writes output to a Portman log. | Verify selected estimate, termination, restart availability, and successful relaunch in isolation. |
| In progress | Preserve alerts, settings, and applicable session/preview links from the reference. | The panel has active and snoozed alert states, adjustable memory/growth limits, scan range and interval, protected process names, listener scope, idle threshold, and a configurable global shortcut. Notifications are opt-in with permission status, an actionable snooze, and hysteresis before a repeated alert. An opt-in detail link reads the exact Claude Code session ID from the process environment or labels a recent Codex folder match; it only copies a resume command. A separate opt-in checks public GitHub pull requests and successful preview deployments over an ephemeral, credential-free connection; verified links appear in detail. | Verify session, preview, notification, alert, and settings states in isolation. Private repository lookups require a future credential-safe design. |
| In progress | Discover remote listening ports over existing SSH aliases and forward selected ports to localhost. | The SSH scan parses `ss` or `lsof`, accepts manual ports, and starts key-only `ssh -N -L` processes bound to 127.0.0.1. The scan uses the shared bounded SSH runner. A tunnel becomes Running only after `lsof` confirms that its own SSH process opened the local listener; a failed or stalled start keeps an error. The applet exposes local-port mappings, tunnel status, stop, and open actions. Disabling Portman closes its tunnels so they do not remain hidden. The updated app and test bundle compile without launching. A read-only `lsof` probe confirmed the listener query; earlier parser and argument tests passed before focus-preserving verification. | Verify a real private host and port, occupied local-port error, dropped connection, and final signed UI. |
| In progress | Keep menu-bar server count, alert indication, and tunnel status current. | A dedicated Portman item owns monitoring while enabled and turns amber for active alerts. Its right-click menu opens the applet, refreshes, or opens a listed localhost port. The tunnel page puts running/failed forwards first and offers stop, open, and retry. Read-only command probes took 0.05 s for each `lsof` query and 0.03 s for `ps` on this Mac. | Verify live status changes, long-running monitor cost, and tunnel recovery in the final signed app. |

The owner requested that verification leave the active desktop alone after
Xcode tests coincided with macOS privacy and Gatekeeper prompts. Build-only and
static checks are allowed here; executable interaction checks require an
isolated macOS account or VM.

The hosted macOS unit-test run [36100785006](https://github.com/surajmandalcell/macpowertoys/actions/runs/36100785006)
passed at `6180580`, including the Portman scanner and alert-policy tests.
The local build-for-testing passed without launching either bundle. An ad-hoc
signed arm64 Release app for `6180580` passed `codesign --verify --deep --strict`.
The installed `/Applications` copy is older; installation and live UI review
remain deferred under the focus-preserving verification rule.
