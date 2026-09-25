# Disk Explorer request list

Requested on 2026-09-25, using [disktree](https://github.com/tobi/disktree) and
[DaisyDisk](https://daisydiskapp.com/) as behavior references. This is an
independent Swift and SwiftUI implementation in MacPowerToys.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Add a separate, on-demand disk tool. | `DiskExplorerTool` is in the built-in registry; its own SwiftUI window has a stable restoration ID, launcher settings, and deep-link routing. The Debug app builds. | Verify the final signed window and position restoration. |
| Done | Scan a whole volume or chosen folder quickly. | The POSIX walker uses `readdir` and `fstatat` off the main actor, with four top-level workers, cancellation, hidden-file choice, volume boundaries, hard-link deduplication, and unreadable counts. A 392,508-entry `/Applications` scan completed in 4.81 seconds on this Mac. A fixture matches `/usr/bin/du` and verifies symlink-loop handling. | Measure startup-disk behavior with the final signed app and report inaccessible paths. |
| Done | Offer both treemap and circular disk views and remember the choice. | The shared `diskExplorer.chartStyle` preference drives the window picker and launcher settings. Both charts navigate the same scan tree. | Inspect both charts in the final signed app. |
| Done | Include core exploration and removal actions. | The workspace has volume and folder selection, breadcrumbs, size and count summaries, search, sort, Quick Look, Finder reveal, marking, review, Trash, and separately confirmed permanent deletion. Removal checks the scan root and each entry's device and inode before acting. | Exercise the non-destructive UI flow in the final signed app. |
| Verify | Show when a scan cannot see protected files. | The scan reports unreadable items and opens Full Disk Access settings. Apple requires the user to grant this access in System Settings. | Check the denied and allowed states on the final installed app. |
| Pending choice | Use a selected final tool icon. | Six light and dark SVG options are in `tmp/disk-explorer/index.index2.html`; the tool uses an SF Symbol until one is chosen. | Owner selects an option; then promote it to the asset catalog, Dock, and Raycast command. |

The scan reports `st_blocks × 512` allocated bytes and counts hard links once.
APFS clones may share physical blocks, so a marked item's size is not a promise
of space recovered after removal. Startup-disk results are incomplete when macOS
denies access to protected locations; the app displays that condition.
