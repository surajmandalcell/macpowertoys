# Main Task Request List

Reviewed against current source and Git history on 2026-08-23. This list covers
requests made in the original main task. Dedicated applet tasks own their own
lists where noted below.

Update a status only after checking current source and, for visible behavior,
the latest normal signed build.

## Open or Needs Verification

| Status | Request | Current evidence | Remaining work |
|---|---|---|---|
| Done | Put transfer priority on individual files instead of the whole transfer. | Exact file jobs show a native five-level priority menu. Queue sorting and snapshots apply priority only to file jobs. Directory jobs always use normal priority. A running file continues without interruption, and its new priority applies only if it enters the queue again. Focused model tests pass. | None for individually queued files. |
| Platform limit | Change the priority of an active file inside a directory transfer. | The official rclone order controls support name, size, or modification date before a directory transfer starts. rclone has no supported live per-file priority API. | Keep active files running unless rclone adds a supported API. |
| Done | Audit local changes, and audit both sides when a true two-way setup exists. | `LocalChangeHistory` records the latest 100 events per transfer from the watched local source. Cloud Sync has only one-way Copy, Sync, and Move modes. A future two-way mode must watch and label both local roots. | None for the current transfer modes. |
| Verify | Double-clicking the menu-bar icon opens the main window without opening the popover. | `a79807a` intercepts the status-item mouse-down event and delays the single click. Unit checks prove the second click cancels the popover action. | Exercise a single click and double-click in the latest normal installed build. |
| Verify | Give the menu-bar icon a separate right-click menu containing only Open and Quit with icons. | The status item now intercepts right mouse-down and builds an exact two-item native menu with SF Symbol icons. Focused checks pass. | Exercise the right-click menu in the latest normal installed build. |
| Verify | Align and space the menu-bar popover items consistently. | The tray now uses an 18pt icon column, 24pt status/recent rows, 8–14pt section spacing, aligned transfer progress, and roomier tab/footer gutters. | Inspect Cloud Sync and Awake tabs in the latest installed build. |
| Platform limit | Restore every window to its last position, monitor, and Space. | `WindowStateManager` stores size, position, and display identity for every built-in window. Apple's supported state restoration can restore window configuration only by reopening windows that were open at quit. macOS exposes no public API for assigning an independently reopened window to a Space. | Keep the current position and monitor restoration. Do not use private window-server APIs or re-enable automatic window reopening, which would regress the requirement that Cloud Sync and other tools stay closed unless explicitly opened. |
| Done | Keep recent applet titlebars compact, borderless, consistently aligned, and free of focus outlines. | The shared row gives the title and actions equal 24pt frames on a 22pt centerline. `WindowAccessor` restores the 6pt traffic-light shift after delayed layout and every key-window transition; regression coverage forces a late native reset and verifies recovery in all four applets. Controls use a 6pt radius, initial focus stays off controls, and titles start at 60pt after hiding zoom. | None. |
| Done | Always use the latest committed build across concurrent tasks. | The troubleshooting rule and `Makefile` reject dirty or stale installs. A normal signed Release build was installed from a clean `HEAD` after all 395 unit tests passed. The installed source matched `HEAD`, and strict code-sign verification passed. | Repeat this gate after a later source change. |
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
- Input Devices, System Care, and Power Stats: `spec/system-tools-request-list.md`

The dedicated lists do not override newer cross-app requirements recorded in
this main list or in the troubleshooting index.
