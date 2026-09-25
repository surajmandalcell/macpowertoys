# Portman request list

The owner requested a MacPowerToys tool based on the detailed WhatThePort
showcase at `/Users/surajmandal/tmp/what-the-port-showcase/README.md`, adapted
to MacPowerToys' native design. The added requirement is SSH local forwarding:
select listening ports on a private server and access them through loopback on
this Mac. This list records the product scope and verification still needed.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| In progress | Add Portman to the launcher, compact window, and combined menu-bar tab. | The tool registry, scene, window restoration, tray route, and matching icon are implemented. | Confirm all three surfaces in the final signed app. |
| In progress | Show local development ports with process context, memory, CPU, recent charts, and browser action. | The on-demand scanner reads listening ports 3000–9999 and process stats; the applet shows an overview and detail, loads folder/project/branch context on selection, flags memory threshold/growth, and charts recent memory and CPU with a shared hover time. A live socket test passed before the owner requested build-only verification. | Add whole-Mac memory breakdown and final signed UI checks. |
| In progress | Preserve the reference's stop, restart, and cleanup flows, with process protection and accurate reclaimed-memory preview. | Stop checks same-user ownership and exact process start before sending SIGTERM. Cleanup selects process identities, deduplicates memory and signals, and shows memory and CPU for the selection. Batch Stop now confirms the captured process list before signaling. A stale-PID safety test passed before the owner requested build-only verification. | Add safe whole-tree handling and restart where launch context exists; inspect cleanup and stop in the final signed UI. |
| Pending | Preserve relevant alerts, settings, and optional session/preview links from the reference. | The current window has no alert center or external integrations. | Add only verifiable integrations and test their failure states. |
| In progress | Discover remote listening ports over existing SSH aliases and forward selected ports to localhost. | The SSH scan parses `ss` or `lsof`, accepts manual ports, and starts key-only `ssh -N -L` processes bound to 127.0.0.1. The applet exposes local-port mappings, tunnel status, stop, and open actions. Focused parser and argument tests passed before focus-preserving verification; `ssh -G` confirmed the loopback binding and security flags without connecting. | Verify a real private host and port, occupied local-port error, dropped connection, and final signed UI. |
| In progress | Keep menu-bar server count and tunnel status current without unnecessary background work. | The Portman tab scans while visible and the window scans while open; tunnels persist while the app runs. | Add a count-bearing status item for full reference parity without scanning while unused. |

The final source passed a compile-only macOS build. The owner requested that
verification leave the active desktop alone after Xcode tests coincided with
macOS privacy and Gatekeeper prompts. No further app or test runner launch is
part of this verification pass.
