# Disk Explorer request list

Requested on 2026-09-25, using [disktree](https://github.com/tobi/disktree) and
[DaisyDisk](https://daisydiskapp.com/) as behavior references. This is an
independent Swift and SwiftUI implementation in MacPowerToys.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Add a separate, on-demand disk tool. | `DiskExplorerTool` is in the built-in registry; its own SwiftUI window has a stable restoration ID, launcher settings, deep-link routing, and the shared Reduce Motion-aware page transition. The Debug app builds. | Verify the final signed window and position restoration. |
| Done | Scan a whole volume or chosen folder quickly. | Home scans on opening. The POSIX walker uses `readdir` and `fstatat` off the main actor, with four top-level workers, cancellation, hidden-file choice, volume boundaries, hard-link deduplication, and unreadable counts. A 392,508-entry `/Applications` scan took 5.36–6.17 seconds in two runs on this Mac. A fixture matches `/usr/bin/du` and verifies symlink-loop handling. | Measure startup-disk behavior with the final signed app and report inaccessible paths. |
| Done | Offer both treemap and circular disk views and remember the choice. | Shared preferences drive the window and launcher pickers. Both charts navigate the same scan tree and can show disk use, file count, or recency of changes. | Inspect both charts and measures in the final signed app. |
| Done | Include core exploration and removal actions. | The workspace has volume and folder selection, breadcrumbs, size and count summaries, search, sort, Quick Look, Finder reveal, marking, review, Trash, and separately confirmed permanent deletion. Removal checks the scan root and each entry's device and inode before acting. | Exercise the non-destructive UI flow in the final signed app. |
| Verify | Show when a scan cannot see protected files. | The scan reports unreadable items and opens Full Disk Access settings. Apple requires the user to grant this access in System Settings. | Check the denied and allowed states on the final installed app. |
| Verify | Use the selected Disk Explorer icon. | Option 02, Sector platter, is now `DiskExplorerLogo`, used by the tool registry, Dock routing, and Raycast command. The 512px asset and 64px/16px previews keep the selected composition; focused icon tests and Raycast checks pass. | Inspect it in the final signed launcher and Dock. |
| In progress | Make scans useful before they finish. | The existing scanner reports a count but publishes its tree only at completion. | Publish measured partial folder sizes and largest files during the walk, label them as partial, preserve cancellation, and keep scan actions visible. |
| In progress | Give the visualization room and the largest files a real page. | The current 480pt chart shares a row with a 340pt Contents pane, and only 12 of 20 largest files appear below it. | Use Visualization and Largest Files tabs, collapse Contents by default, put summary statistics in an information popover, and show a longer sortable file list. |
| In progress | Make charts readable and responsive to interaction. | Small treemap blocks have no visible name; both charts only respond to taps and directory navigation snaps. | Add hover readouts, clear selection, brighter related colors, and short Reduce Motion-aware drill transitions in treemap and rings. |

The scan reports `st_blocks × 512` allocated bytes and counts hard links once.
APFS clones may share physical blocks, so a marked item's size is not a promise
of space recovered after removal. Startup-disk results are incomplete when macOS
denies access to protected locations; the app displays that condition.

The interaction pass draws on [DaisyDisk's map and hover navigation](https://daisydiskapp.com/guide/4/en/UnderstandingSunburst/),
[GrandPerspective's selection and background scan](https://grandperspectiv.sourceforge.net/),
[QDirStat's linked treemap and details](https://github.com/shundhammer/qdirstat/blob/master/doc/Treemap.md),
and [disktree's zoom and removal workflow](https://github.com/tobi/disktree).
These are behavior references. The scanner, layout, and drawing remain native
Swift implementations.
