# Diskman request list

Requested on 2026-09-25, using [disktree](https://github.com/tobi/disktree) and
[DaisyDisk](https://daisydiskapp.com/) as behavior references. This is an
independent Swift and SwiftUI implementation in MacPowerToys.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Make Modify a direct partition workspace and test native merge safety. | The disk rail, textured partition map, volume rows, and grouped action cards expose operations without an action picker. Selection shows the adjacent merge target and data-loss outcome before review; disabled actions explain why. ExFAT resize is unavailable; HFS+ and APFS resize sheets read macOS limits before review. Destructive actions require the reviewed disk ID and recheck media identity before execution. Hosted run `36216183313` passed Modify navigation, merge review, selection, focused safety tests, and light/dark renders. On the authorized 16 GB SD card (serial `0x19302912`), HFS+ shrank and grew while a 1 MB marker retained SHA-256 `30e14955...`; an adjacent HFS+ merge preserved it. Add/delete partition and forced ExFAT merge succeeded; the latter erased its marker as warned. A dry forced merge returned exit 0 with “Merge canceled”, so the runner now sends confirmation after typed review and rejects canceled output. The card is restored to one mounted `DISKMAN` ExFAT volume and passed `fsck_exfat`. The signed app and helper at `562d019` passed strict signature and source-stamp checks; the `/Applications` app launched in the background. | Native installed-window inspection remains subject to Computer Use approval. |
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

### Modify redesign correction, 2026-09-26

The owner rejected the Modify screen's single Action picker and sparse card
layout. Replace them with direct, grouped operations beside an interactive disk
map and partition list. A selected disk or partition must make its available
actions and unsupported actions clear without opening a catch-all menu. Keep
before/after review and device-identity checks before writes. Adapt the ordered
dither, subtle color bloom, and tactile selection of
[Dither Kit](https://www.tripwire.sh/dither-kit) to native SwiftUI without making
the map harder to read. Verify format, delete, resize, and merge behavior on
only the authorized 16 GB SD card, then restore its usable ExFAT state.

[MiniTool's main-window guide](https://www.partitionwizard.com/help/partition-wizard-main-window.html),
[KDE Partition Manager](https://docs.kde.org/stable_kf6/en/partitionmanager/partitionmanager/usermanual.html),
and [GParted](https://gparted.org/display-doc.php?name=help-manual) all put
device navigation, a disk map, a partition list, and direct actions in the main
workspace. `diskutil resizeVolume` supports Journaled HFS+ only on this Mac;
the authorized ExFAT volume returned “file system format does not support
resizing” for a read-only limits request. `diskutil mergePartitions` preserves
the first partition only when its file system is resizable. Its other source
partitions lose data; forcing a merge erases the first one too. The UI must
state these limits, not claim MiniTool's data-preserving NTFS merge behavior.

### Modify navigation and write lock correction, 2026-09-26

Place physical disks under Modify in Diskman's main sidebar and keep Analyze's
sources separate. Show APFS parent-child connector lines and label EFI as a
protected system partition. Give each direct action a one-line title and up to
two lines of explanation in a uniform three-column grid. Make whole-disk
selection explicit. Add a persistent disk lock in the sidebar context menu and
beside Refresh. Diskman's command layer must reject every modifying operation
against a locked disk, including a request built outside the UI. The 1 TB
external disk starts locked. Only the authorized 16 GB SD card may be used for
destructive physical tests. Use the restrained depth and spacing of OnePlus
OxygenOS with Dither Kit's ordered texture.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Move Modify devices into the main sidebar and make the selected scope obvious. | The shared Modify model drives sidebar rows, the disk map, and direct actions. The map has a persistent Whole disk target; disk-wide actions ask for it when a partition is selected. APFS child rows have linked stems, EFI is labeled `ESP · PROTECTED`, and action cards use three uniform columns with one-line titles. Hosted run `36243071361` passed UI navigation, action scope, and light/dark APFS renders. The later proactive sidebar-inventory fix compiles and has a selection regression check. | Run the hosted check on the final inventory change; inspect the signed installed window when app-scoped control is available. |
| Verify | Keep the 1 TB disk locked by default and enforce locks below the UI. | Newly seen media defaults locked. Sidebar context menus and the Modify titlebar can change the per-media setting. `DiskManagement.run` checks the lock before inventory and again before executing a modifying command; Verify remains read-only. Hosted run `36243071361` passed the lock persistence, changed-media, and command-rejection check. Read-only inventory identified the authorized SD card at `disk10` (15,634,268,160 bytes, serial `0x19302912`) and the 1 TB external disk at `disk6`. | Inspect the locked state in the final signed installed app when app-scoped control is available. |
| Verify | Stop live boxes snapping and keep the hover detail below the chart. | Treemap tile identity, its bounded item set, and split topology stay stable as weights cross during a scan; individual frames interpolate and zero-size skeleton entries appear in the first snapshot. Rings use the same live membership rule and animated arcs. On completion, both views select the largest measured entries once and animate the change, so a large late-named item is not trapped in Other. Both charts reserve a 40-point detail row below the plot. Hosted run `36168349745` passed the cutoff regression, UI navigation, and light and dark renders. | Confirm motion in the final signed app. |
| Verify | Match the app's restrained chrome and update the chart palette. | The chart uses a muted blue, green, coral, violet, and gold set inspired by Apple, Google, and Anthropic, with the shared neutral background and existing button/spacing components. The scan status reserves a constant height. Hover now brightens only the focused item, so other colors stay clear. Hosted run `36193151541` passed; its dark ring render shows soft dividers instead of black gaps, and light-mode hover captures keep the selected item legible. | Inspect the final installed app. |
| Done | Rename the product to Diskman and organize the sidebar around Analyze and Modify. | Launcher, window, Raycast label, and manual say Diskman. Analyze groups folders and mounted volumes; Modify opens physical disk management. The prior route ID and saved settings are preserved. | Verify final signed UI. |
| Verify | Keep Analyze's scan separate from Modify. | A page switch cancels the Analyze scan and removes its status footer. Hosted normal-mode run `36173007922` passed the Modify assertion and captured the disk inventory's own progress state without the scan footer. A separate normal-launch capture from run `36171513372` showed the visualization without an unsolicited event-access prompt. | Inspect the final signed window and its permission-dependent states. |
| Verify | Add safe native disk and partition management. | Modify lists physical media and partition/volume structure. Native actions include verification, selected-volume repair, mount/unmount/eject, rename, erase volume/disk, repartition, add/delete/resize partitions, APFS volume and container operations, and zero-fill. Writes are limited to writable removable/external physical media with a resolvable I/O Registry media instance; the app compares that instance and the disk layout again immediately before execution and requires typed device-ID review for data-loss actions. APFS operations exclude shared-store containers and reject a changed container reference. Hosted run `36189567926` passed the replacement-media identity regression, other safety tests, Modify UI, and light/dark renders. Two read-only lookups of the authorized SD card returned the same media instance. | Inspect the updated signed app; a physical hot-swap was not performed. |
| Verify | Show the actual mounted file system in Modify. | The SD partition type is `Microsoft Basic Data`, but macOS reports its mounted file system as ExFAT. Modify now reads the native volume-format description and shows ExFAT; APFS stores and volumes have explicit labels. The authorized card returned `ExFAT` in a direct Foundation metadata probe. Hosted run `36192321303` passed and its light and dark Modify renders both show ExFAT. | Inspect the final signed app. |
| Done | Test destructive operations only on the authorized 16 GB SD card. | The test harness checked Secure Digital bus, 15,634,268,160-byte size, `disk10`, and card serial `0x19302912` before every operation. Erase, verify, repartition, rename, mount/unmount, partition delete/add, volume format, HFS+ resize, volume repair, zero-fill, and APFS add/delete/shrink/grow succeeded. The card was restored to one mounted ExFAT volume named `DISKMAN`; `fsck_exfat` reports it is OK. | Eject was left untested so the card remains available without physical reinsertion. |
| Open | Add exact disk-image backup and restore if native device access can be granted safely. | `diskutil image create from disk10` and `disk10s2` both returned `Operation not permitted` because the current account cannot read raw device nodes. Imaging the mounted folder succeeded, but made a small APFS image of its files, not an exact ExFAT disk or partition clone. No clone control is exposed. The SD card remains mounted as ExFAT. | Design a supported privileged read/restore path and verify both operations on only the authorized SD card before exposing them. |

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

Diskman's latest focused hosted run `36193151541` passed its unit and UI jobs,
including progressive scans, chart hover and navigation, Modify inventory,
the review sheet, media identity, and light/dark renders. Full hosted run
`36193151569` passed after the final dark-ring divider change. The clean
`9f7b419` Release app and embedded network helper passed strict code-sign
verification with team `GF57JXJF5A`, were installed, and launched from
`/Applications/MacPowerToys.app` in the background. Direct inspection of the
installed window was blocked by Computer Use access to MacPowerToys; hosted UI
captures provide the interaction evidence above.
