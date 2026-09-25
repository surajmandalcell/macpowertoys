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
| In progress | Recreate the reference's connected overview and detail states in the menu bar. | The panel now has a whole-Mac segmented memory bar, stable port colors, linked row/bar hover, sparklines, expandable metadata and process tree, ten-minute history with a threshold line, and shared memory/CPU chart hover. The scan hides system and GUI listeners by default but can show all. The app and test bundle compile without launch. | Inspect default, hover, detail, disclosure, and light/dark states in an isolated macOS session. |
| In progress | Preserve the reference's cleanup and process-tree actions, with protection and accurate reclaimed-memory preview. | Stop checks same-user identity and process start before SIGTERM, and checks child identity and parent before signaling. The cleanup estimate deduplicates process identities, suggests only observed idle or deleted-folder servers, and leaves alerting servers unselected. | Verify selected estimate and termination in isolation; support restart only when the complete launch context is recoverable. |
| In progress | Preserve alerts, settings, and applicable session/preview links from the reference. | The panel has active and snoozed alert states, adjustable memory/growth limits, scan range and interval, protected process names, listener scope, idle threshold, and a configurable global shortcut. Notifications are opt-in with permission status, an actionable snooze, and hysteresis before a repeated alert. | Add verifiable session/preview integrations; verify notification, alert, and settings states in isolation. |
| In progress | Discover remote listening ports over existing SSH aliases and forward selected ports to localhost. | The SSH scan parses `ss` or `lsof`, accepts manual ports, and starts key-only `ssh -N -L` processes bound to 127.0.0.1. The scan uses the shared bounded SSH runner. A tunnel becomes Running only after `lsof` confirms that its own SSH process opened the local listener; a failed or stalled start keeps an error. The applet exposes local-port mappings, tunnel status, stop, and open actions. The updated app and test bundle compile without launching. A read-only `lsof` probe confirmed the listener query; earlier parser and argument tests passed before focus-preserving verification. | Verify a real private host and port, occupied local-port error, dropped connection, and final signed UI. |
| In progress | Keep menu-bar server count, alert indication, and tunnel status current. | A dedicated Portman item owns monitoring while enabled and turns amber for active alerts. Its right-click menu opens the applet, refreshes, or opens a listed localhost port. The tunnel page puts running/failed forwards first and offers stop, open, and retry. Read-only command probes took 0.05 s for each `lsof` query and 0.03 s for `ps` on this Mac. | Verify live status changes, long-running monitor cost, and tunnel recovery in the final signed app. |

The owner requested that verification leave the active desktop alone after
Xcode tests coincided with macOS privacy and Gatekeeper prompts. Build-only and
static checks are allowed here; executable interaction checks require an
isolated macOS account or VM.
