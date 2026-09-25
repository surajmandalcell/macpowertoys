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
| Verify | Make scans useful before they finish. | The scanner publishes measured folder sizes and a growing top-100 file list while it walks; partial scans cannot mark files for removal. A 327,550-entry `/Applications` scan showed its first nonempty chart snapshot in 0.01 seconds and finished in 4.95 seconds. The new scanner and safety tests passed in the hosted unit run. Hosted UI run `36137580518` captured a populated treemap at 365,603 checked items and a top-100 list while scanning. | Confirm cancellation and protected paths in the final signed window. |
| Verify | Give the visualization room and the largest files a real page. | Visualization and Largest Files have separate tabs. The chart takes the body width; Contents is toggleable and initially closed; counts sit in a header popover. Largest Files shows up to 100 size-sorted files with search. Hosted run `36138597977` passed Contents and tab navigation and captured the statistics popover with used space, file count, and folder count. | Inspect the final signed window. |
| Verify | Make charts readable and responsive to interaction. | Treemap hover shows the name, size, and share even for tiny blocks. Rings highlight hovered segments and show names in the center. Chart navigation crossfades and scales, with Reduce Motion support. Run `36138597977` passed focused unit and focus tests; its dark and light renders show shallow rings using the chart height. Run `36139795497` captured the active treemap hover with its file name, size, share, dimmed peers, and outline. | Complete the hosted folder-drill and ring-hover checks after narrowing an ambiguous XCTest chart query. |

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
