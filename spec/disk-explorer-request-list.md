# Diskman request list

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
| Verify | Make charts readable and responsive to interaction. | Treemap and ring hover highlight the target and show its name and size in a reserved footer below the plot, including tiny segments. The ring center retains the current folder. Chart navigation crossfades and scales, with Reduce Motion support. Hosted run `36165658638` passed the revised footer, hover, drill, and tab checks; its captures show both footers below their plots. | Inspect motion and interaction in the final signed window. |

The scan reports `st_blocks × 512` allocated bytes and counts hard links once.
APFS clones may share physical blocks, so a marked item's size is not a promise
of space recovered after removal. Startup-disk results are incomplete when macOS
denies access to protected locations; the app displays that condition.

## Diskman Analyze and Modify expansion

Requested on 2026-09-25. The internal `disk-explorer` route and saved chart
preferences remain compatible with existing launchers and user settings; the
product name is Diskman.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Stop live boxes snapping and keep the hover detail below the chart. | Treemap tile identity, its bounded item set, and split topology stay stable as weights cross during a scan; individual frames interpolate and zero-size skeleton entries appear in the first snapshot. Rings use the same live membership rule and animated arcs. On completion, both views select the largest measured entries once and animate the change, so a large late-named item is not trapped in Other. Both charts reserve a 40-point detail row below the plot. The revised regression compiles locally; hosted validation is pending. | Run the hosted final-selection check, then confirm motion in the final signed app. |
| Verify | Match the app's restrained chrome and update the chart palette. | The chart uses a muted blue, green, coral, violet, and gold set inspired by Apple, Google, and Anthropic, with the shared neutral background and existing button/spacing components. The scan status reserves a constant height. Light and dark chart renders and the refreshed hover captures from `36156271971` were inspected after reducing washout. | Inspect the final installed app. |
| Done | Rename the product to Diskman and organize the sidebar around Analyze and Modify. | Launcher, window, Raycast label, and manual say Diskman. Analyze groups folders and mounted volumes; Modify opens physical disk management. The prior route ID and saved settings are preserved. | Verify final signed UI. |
| Verify | Add safe native disk and partition management. | Modify lists physical media and partition/volume structure. Native actions include verification, selected-volume repair, mount/unmount/eject, rename, erase volume/disk, repartition, add/delete/resize partitions, APFS volume and container operations, and zero-fill. Writes are limited to writable removable/external physical media, with an identity recheck immediately before execution and typed device-ID review for data-loss actions. APFS operations exclude shared-store containers and reject a changed container reference. Hosted run `36162099059` passed the command and safety tests and populated SD-layout renders. | Inspect the installed signed app. |
| Done | Test destructive operations only on the authorized 16 GB SD card. | The test harness checked Secure Digital bus, 15,634,268,160-byte size, `disk10`, and card serial `0x19302912` before every operation. Erase, verify, repartition, rename, mount/unmount, partition delete/add, volume format, HFS+ resize, volume repair, zero-fill, and APFS add/delete/shrink/grow succeeded. The card was restored to one mounted ExFAT volume named `DISKMAN`; `fsck_exfat` reports it is OK. | Eject was left untested so the card remains available without physical reinsertion. |

MiniTool's Windows-specific operations such as BitLocker, drive letters,
NTFS/FAT conversion, dynamic disks, and MBR repair have no equivalent safe
macOS operation here. Diskman does not claim to perform them. macOS native
disk operations and safety boundaries follow [Apple's partitioning guide](https://support.apple.com/en-mk/guide/disk-utility/dskutl14027)
and [First Aid guidance](https://support.apple.com/en-us/102611); the feature
inventory was compared with [MiniTool's official guide](https://www.partitionwizard.com/help/).

The interaction pass draws on [DaisyDisk's map and hover navigation](https://daisydiskapp.com/guide/4/en/UnderstandingSunburst/),
[GrandPerspective's selection and background scan](https://grandperspectiv.sourceforge.net/),
[QDirStat's linked treemap and details](https://github.com/shundhammer/qdirstat/blob/master/doc/Treemap.md),
and [disktree's zoom and removal workflow](https://github.com/tobi/disktree).
These are behavior references. The scanner, layout, and drawing remain native
Swift implementations.

Diskman's focused hosted run `36156271971` passed its unit and UI checks,
including progressive scans, chart hover and navigation, Modify inventory,
and populated light and dark renders. Full hosted run `36156271937` passed.
The locally installed app and embedded network helper passed strict code-sign
verification with team `GF57JXJF5A`, matched the committed source stamp, and
the app ran from `/Applications/MacPowerToys.app`. Direct inspection of that
installed window was blocked by Computer Use access to MacPowerToys; hosted
UI captures provide the interaction evidence above.
