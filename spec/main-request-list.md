# Main Task Request List

Reviewed against current source and Git history on 2026-07-14. This list covers
requests made in the original main task. Dedicated applet tasks own their own
lists where noted below.

Update a status only after checking current source and, for visible behavior,
the latest normal signed build.

## Open or Needs Verification

| Status | Request | Current evidence | Remaining work |
|---|---|---|---|
| Open | Put transfer priority on individual files instead of the whole transfer. | The transfer-level picker was removed, but `TransferPriority` and job-level queue ordering remain in the model. `FileProgressRow` has no priority control. | Define and implement safe per-file ordering. rclone does not expose live active-file reprioritization, so this must not pretend to change an already active file. |
| Partial | Audit local changes, and audit both sides when a true two-way setup exists. | `LocalChangeHistory` records the latest 100 events per transfer from a watched local source. Cloud Sync currently exposes one-way Copy, Sync, and Move, not rclone bisync. | If a two-way mode is added, watch and label changes from both local roots. |
| Verify | Double-clicking the menu-bar icon opens the main window without opening the popover. | `a79807a` intercepts the status-item mouse-down event and delays the single click. Unit checks prove the second click cancels the popover action. | Exercise a single click and double-click in the latest normal installed build. |
| Verify | Give the menu-bar icon a separate right-click menu containing only Open and Quit with icons. | The status item now intercepts right mouse-down and builds an exact two-item native menu with SF Symbol icons. Focused checks pass. | Exercise the right-click menu in the latest normal installed build. |
| Platform limit | Restore every window to its last position, monitor, and Space. | `WindowStateManager` stores size, position, and display identity for every built-in window. Apple's supported state restoration can restore window configuration only by reopening windows that were open at quit. macOS exposes no public API for assigning an independently reopened window to a Space. | Keep the current position and monitor restoration. Do not use private window-server APIs or re-enable automatic window reopening, which would regress the requirement that Cloud Sync and other tools stay closed unless explicitly opened. |
| Verify | Keep recent applet titlebars compact, borderless, consistently aligned, and free of focus outlines. | The shared row gives the title and actions equal 24pt frames, applies one 4pt top inset, uses a 22pt centerline, aligns traffic lights with a 6pt shift, gives titlebar controls a 6pt radius, routes initial focus away from controls, and starts titles at 60pt after hiding zoom. | Fresh-open Awake, Text Extractor, Ruler, and Color Picker in the latest normal build. Compare title, traffic-light, and action midpoints; then change focus and confirm no outline remains. |
| Pending | Always use the latest committed build across concurrent tasks. | The troubleshooting rule and `Makefile` reject dirty or stale installs. Concurrent audit-only commits have advanced `HEAD` beyond the currently running bundle. | Do not open that stale bundle. Install and verify the final clean `HEAD` after active tasks finish and Cloud Sync is idle. |
| Pending | Make the app production ready and publish the next release only at the end. | The production-readiness goal is now active. Version `1.7.0` was tagged, but later work remains under `Unreleased`. `docs/PUBLIC_RELEASE_CHECKLIST.md` still has unresolved distribution gates. | Close the audited gaps, run release checks, refresh screenshots if the UI changed, then version, tag, and push the next release. |

## Implemented or Resolved

| Status | Request | Evidence |
|---|---|---|
| Done | Calculate the transfer plan first and prevent retries or resumed bytes from inflating its total. | `CheckFirst` is enabled, planned progress is separate from network-attempt bytes, and retry baselines preserve only completed work. |
| Done | Recalculate a transfer without shrinking its original plan, increasing it only for newly found work. | `TransferJob.applyRecalculatedPlan` adds only positive deltas, and Transfer Details exposes Recalculate with an rclone dry-run explanation. |
| Done | Keep the latest 100 changed-file audit entries for each transfer. | `LocalChangeHistory` limits records per job to 100, and Transfer Details contains the Changes tab. |
| Done | Offer continuous sync beside Remove after a local-folder transfer completes. | Completed transfer rows show the continuous-sync control beside Remove. A local watcher waits for a 30-second quiet period before requeueing changed work. |
| Done | Credit rclone properly. | App Settings > About links to rclone, names its contributors, and links its MIT licence. |
| Done | Use the compact labels `Comparing`, right-side ETA, and one-line byte/file totals. | Transfer rows render `Comparing`, put ETA in the right state badge, and keep metrics fixed-size on one row. |
| Accepted | Explain the aggregate speed even when visible file rows do not sum to it. | The aggregate comes from rclone statistics and can include work not represented by the visible file subset. The user accepted this behavior. |
| Done | Open the launcher on All Tools instead of opening Cloud Sync by default. | `HomeView` initializes selection to `all-tools`; only the tray remembers its own selected tool tab. |
| Done | Make closing the main window after opening a tool configurable and default it off. | App Settings contains `Close MacPowerToys after opening a tool`; both launcher paths honor it. |
| Done | Compact the tray footer and give it balanced top and bottom padding. | The footer uses one 5pt vertical inset and compact icon buttons. |
| Done | Replace blurry scale effects with simple slide or color-and-shadow feedback. | The tray uses directional move transitions. No `scaleEffect` remains, and launcher cards only change background, border, and shadow. |
| Done | Sign local builds with the personal Apple Development identity and remove GitHub signing CI. | `Makefile` uses the configured development team. No GitHub Actions workflow builds, signs, or publishes the app. |
| Done | Remove the legacy PowerToys installation after adopting MacPowerToys. | Only `/Applications/MacPowerToys.app` is installed. Legacy identity support remains solely for safe data migration and deep-link compatibility. |
| Done | Enforce one app process and one utility window. | `AppInstanceCoordinator` uses running-app checks plus a process lock, and `ToolActionRouter` raises an existing utility window before creating one. |
| Done | Remember window size, position, and monitor for every built-in app window. | Every built-in window uses `WindowAccessor`; `WindowStateManager` has stable identifiers for all eight windows. Space restoration remains listed above. |
| Done | Align launcher cards with the sidebar search start and remove the body vertical mismatch. | `6d69af9` aligned the main content start and grid gutter with the launcher chrome. |
| Done | Remove excess top space from Logs and use thin overlay scrollbars. | Logs begins directly under its compact header and configures a mini overlay scroller. |
| Done | Expose only MacPowerToys and its sub-app launchers in Raycast. | The Raycast manifest contains eight no-view launchers and no action commands. |
| Done | Consolidate troubleshooting knowledge and always verify the latest normal build. | `spec/troubleshoot/troubleshoot.md` is the only index and routes current-build, UI, verification, and shared-worktree rules. |
| Done | Preserve unexplained changes from other tasks instead of reverting whole files. | `spec/troubleshoot/shared-worktree.md` now requires inspecting history, identifying and asking the owner when possible, and preserving unknown work without explicit approval. |
| Done | Update README screenshots and publish the 1.7.0 checkpoint. | `README.md` uses the refreshed launcher and Text Extractor screenshots; annotated tag `v1.7.0` is pushed. Later work belongs to the pending next release. |
| Done | Prevent unsigned UI-runner Gatekeeper dialogs and correct the claim that the runner was killed. | Verification rules prohibit launching unsigned UI runners and require distinguishing a runner bootstrap failure from a killed process or product failure. |

## Dedicated Applet Audits

- Cloud Sync: `spec/cloud-sync-request-list.md`
- Awake: `spec/awake-request-list.md`
- Color Picker: `spec/color-picker-request-list.md`
- Text Extractor: `spec/text-extractor-request-list.md`
- Ruler: `spec/ruler-request-list.md`

The dedicated lists do not override newer cross-app requirements recorded in
this main list or in the troubleshooting index.
