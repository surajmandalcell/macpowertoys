# Cloud Sync Request List

Reviewed against current source on 2026-08-23. Installed checks remain marked Verify.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Rename "Split uploaded" to "List uploaded" and show uploaded files as a tree in the right pane. | `bb42342`; `TransferFileTreeView` uses "List uploaded" and tree rows in the uploaded column. | None. |
| Done | Vertically center Recalculate with Transfer plan and move the subtitle into an info popover. | `ebc8692`; the row is center-aligned and owns an `info.circle` popover. | None. |
| Done | Keep detail tabs aligned when the selected pill adds its 10pt inset. | `6ad4568`; the pill boundary starts at the shared 20pt gutter. `DESIGN.md` forbids tab movement on selection. | None. |
| Done | Add provider-aware transfer context-menu actions that open the source or destination folder on the provider website. | `RcloneRemote.websiteName` and `websiteFolderURL` support Google Drive and Box. The official rclone Box documentation confirms that rclone folder IDs map to Box folder URLs. OneDrive and Dropbox need provider URLs or shared-link APIs that the read-only stat path does not return. | None for providers with a stable, read-only folder URL. |
| Done | Put ETA on the right in the transfer state badge. | `59da6f6`; running jobs render `ETA ...` inside the right-side state badge. | None. |
| Verify | Pause and resume a transfer directly from the menu-bar Cloud Sync tab. | Every active transfer row now shows a state-aware Pause or Resume control wired to the existing safe job-manager actions. | Exercise both actions during a real transfer in the installed app. |
| Done | Always push verified changes and update the installed MacPowerToys app safely. | Git policy requires checkpoint pushes. The troubleshooting current-build rule and `Makefile` reject dirty or stale installs. The installed app matches the latest app-affecting commit; later commits only change rules and this audit. | Never install while a Cloud Sync transfer is active. |
| Done | Keep the connector button and dropdown the same width and ticker-scroll long labels. | `192df28`; the popover uses the trigger width and `TickerText`. | None. |
| Done | Default OAuth providers to browser login and show alternate methods as provider-specific tabs. | `2e01de5`; browser, service-account, environment, token, and custom OAuth modes are derived from rclone metadata. | None. |
| Done | Put connector search inside the dropdown and use a thin scrollbar. | `ba52600`; the popover owns `SearchField` and applies `.thinScrollIndicators()`. | None. |
