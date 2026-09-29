# Diskman request list

Requested on 2026-09-25, using [disktree](https://github.com/tobi/disktree) and
[DaisyDisk](https://daisydiskapp.com/) as behavior references. This is an
independent Swift and SwiftUI implementation in MacPowerToys.

## Native redesign, 2026-09-29

`DESIGN.md` version 14 controls the native shell and alignment. The HTML
reference supplies content and storage chart texture. The surface worker
does not install or launch the app; the redesign orchestrator owns that gate.

Round 2 requires equal columns for the short Scanning and Disk access cards.
The inspector share bar and more menu use the shared neutral control style.
Completed charts group targets smaller than a control into Other; folded
file aggregates remain explicit, non-drillable items. Live charts keep their
path-based membership and measured proportions until the scan completes.
Opening a page must not wait for mounted-volume metadata. Read that sidebar
state off the main actor and discard it if the window task is cancelled.

Round 3 keeps one embeddable settings view with cards and 16 pt gaps. The
standalone Settings page owns its page wrapper; the main window owns its
scroll container. Chart bounds and fractions must stay finite for empty
scans, zero totals, and transient zero-size layouts. Invalid geometry must
produce no clipped chart content.

Round 3 keeps every Diskman toolbar, search row, inspector, footer, status
row, and page header outside page scrolling. The analysis page never scrolls;
its charts fill the map card. Native tables keep their header fixed and scroll
only their rows. Modify, Settings, and About scroll only their card stacks.
All Diskman pages use the shared page header so foundation owns the 58 pt top
line. Table sorting and row formatting must run outside SwiftUI body work.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Keep page controls fixed and align content with the shared 58 pt header. | Analyze and Modify now use `OnePlusPageHeader` directly. Analyze already uses a non-scrolling page; its stats, tabs, map header, inspector, chart footer, search row, and notices stay fixed. Native file tables own row scrolling. The inspector no longer contains a nested scroll view. Modify keeps its header outside the scrolling card stack. Debug and build-for-testing compile. | Inspect every page on the signed build. |
| Verify | Commit page switches within 100 ms and keep file tables smooth. | Largest files and Results build sorted, filtered, formatted row projections in a detached task. SwiftUI body only maps cached strings into native reusable table rows. Modify reads write-lock preferences with device inventory off the main actor and uses an in-memory state lookup while drawing. Per-cell tooltips were removed from partition and review rows. The regression compiles in the desktop test bundle. | Measure page switches and table frames in the signed build. Compilation does not prove the 100 ms gate. |
| Verify | Expose one settings content view without page chrome or scrolling. | `DiskExplorerSettingsView(unreadableCount: Int? = nil)` has an explicit initializer and remains the single implementation. It inherits the caller's density, keeps the short cards in equal columns, and is dispatched by the main window. Both build targets compile. | Inspect both hosts on the signed build. |
| Verify | Reject invalid geometry before chart clipping or masking. | Treemap bounds and insets, ring canvases, arcs and label rectangles, inspector shares, and partition widths now reject invalid geometry. Both new regressions compile for empty trees, zero totals, all measures and scan states, NaN, infinity, tiny canvases, and arithmetic overflow. | Execute the hosted checks and replay the signed Home route. The crash trace alone does not establish its originating view or input. |
| Verify | Use the fixed 1440 x 900 OnePlusUI shell, 216 pt sidebar, 27 pt centerline, and 24 pt gutter. | Diskman uses the shared window root, header, sidebar, cards, tabs, and settings rows. Debug builds with no Diskman warnings. | Inspect both appearances on the signed build. |
| Verify | Separate selection from navigation and show storage details beside the map. | Single click selects; double-click opens folders. The map has breadcrumbs and a 260 pt inspector. Back, forward, Quick Look, file menus, drag-out, and search have native paths. | Run interaction checks on the installed build. |
| Verify | Show folded files without treating them as a real file. | `.aggregate` uses `fileCount` for `N smaller files`. Charts retain its tile; Results uses a grouped row. No file URL, drill, preview, or removal action is exposed. The new view regression compiles. | Run the aggregate view regression on hosted CI. |
| Verify | Keep Largest files and Results in the same native table language. | Both use the additive OnePlusUI native table with sorting, multiple selection, keyboard actions, context menus, and drag-out. Removal enters review and a native confirmation. | Verify sorting, selection, menus, drag-out, and confirmations in both appearances. |
| Verify | Keep disk write protections while changing Modify's layout. | Device header, partition map, partition rows, direct action groups, and staged review use OnePlusUI. Command checks still bind to media identity and enforce the write lock, EFI protection, and typed review. | Run hosted safety and review tests. Do not write to physical disks during redesign review. |
| Verify | Provide first-run, scanning, completed, stopped, unreadable, and error states. | The stats update from scanner snapshots. Stable chart membership and count-based splits remain. Choose Folder is a 460 pt native sheet; unreadable rows link to Full Disk Access. | Capture each state and inspect all page deep links. |
| Verify | Restyle Settings and About without losing preferences or guidance. | Shared cards retain chart, measure, apparent-size, hidden-file, enable, and disk-access controls. Scanning and Disk access now share equal columns with a 16 pt gap. About includes the guide and keyboard shortcuts. | Inspect the paired cards and saved settings in both appearances. |
| Verify | Use neutral inspector and more-menu controls. | The share bar uses the shared neutral fill. The native menu uses the shared icon label. | Capture rest, hover, and open-menu states in both appearances. |
| Verify | Keep completed charts readable on a large home folder. | Tiny final targets fold into Other with their measured totals. Folded scanner aggregates stay explicit. Live ring bands stay fixed. Keyboard selection uses the visible layout, and grouped ring IDs cannot collide with real paths. Compiled regressions cover grouping, totals, hover hits, and live band widths. | Execute hosted checks and inspect completed treemap/rings, selection, and hover in both appearances. |
| Verify | Route home, largest-files, results, rings, choose-folder, settings, about, and device/bsd-name pages. | The window handles every page through `.onOpenToolPage`; the shared parser now accepts nested device paths. Volume metadata loads off the main actor, and appearance does not restart a scan started by a pending page link. | Capture the first home page in dark and light and measure opening time; verify all links. |

The round 2 desktop test build compiles both bundles, including Diskman unit,
render, and UI sources. Three attempts stopped in other agents' active edits;
the fourth passed. The render fixture covers a completed 133-folder home tree
and 100 largest files. Signed visual review and hosted execution remain open;
compilation does not prove interaction, opening time, or appearance.


| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Make each physical disk the Modify entry and place Eject in its sidebar row. | The separate Manage Disks row is removed. Eject keeps the existing per-media write lock and identity checks. A failed normal eject can list open processes; Close sends a normal app quit or TERM, while Force Quit sends KILL only after a separate button press. Both recheck the disk and process identity. Hosted run `36279617042` passed sidebar selection and the blocked-eject preview, including disabled quit actions in test mode. | A real process-blocked eject remains untested: the authorized 16 GB card is absent from the current disk inventory. |
| Verify | Publish a shallow size estimate before the deep scan and use the full chart height. | The scanner reads immediate children of each top-level folder once, publishes their allocated-size floor, then reuses that listing for exact traversal. Hosted run `36279617042` passed the progressive-scan unit check and UI navigation. Its light/dark renders show the chart using the available height, without the idle footer, and the unreadable count in a dim yellow button beside View. Hover details appear in the existing header line. | Inspect the final signed installed window when app-scoped control is available. |
| Done | Make Modify a direct partition workspace and test native merge safety. | The disk rail, textured partition map, volume rows, and grouped action cards expose operations without an action picker. Selection shows the adjacent merge target and data-loss outcome before review; disabled actions explain why. ExFAT resize is unavailable; HFS+ and APFS resize sheets read macOS limits before review. Destructive actions require the reviewed disk ID and recheck media identity before execution. Hosted run `36216183313` passed Modify navigation, merge review, selection, focused safety tests, and light/dark renders. On the authorized 16 GB SD card (serial `0x19302912`), HFS+ shrank and grew while a 1 MB marker retained SHA-256 `30e14955...`; an adjacent HFS+ merge preserved it. Add/delete partition and forced ExFAT merge succeeded; the latter erased its marker as warned. A dry forced merge returned exit 0 with “Merge canceled”, so the runner now sends confirmation after typed review and rejects canceled output. The card is restored to one mounted `DISKMAN` ExFAT volume and passed `fsck_exfat`. The signed app and helper at `562d019` passed strict signature and source-stamp checks; the `/Applications` app launched in the background. | Native installed-window inspection remains subject to Computer Use approval. |
| Done | Add a separate, on-demand disk tool. | `DiskExplorerTool` is in the built-in registry; its own SwiftUI window has a stable restoration ID, launcher settings, deep-link routing, and the shared Reduce Motion-aware page transition. The Debug app builds. | Verify the final signed window and position restoration. |
| Done | Scan a whole volume or chosen folder quickly. | Home scans on opening. The POSIX walker uses `readdir` and `fstatat` off the main actor, with four top-level workers, cancellation, hidden-file choice, volume boundaries, hard-link deduplication, and unreadable counts. A 392,508-entry `/Applications` scan took 5.36–6.17 seconds in two runs on this Mac. A fixture matches `/usr/bin/du` and verifies symlink-loop handling. | Measure startup-disk behavior with the final signed app and report inaccessible paths. |
| Done | Offer both treemap and circular disk views and remember the choice. | Shared preferences drive the window and launcher pickers. Both charts navigate the same scan tree and can show disk use, file count, or recency of changes. | Inspect both charts and measures in the final signed app. |
| Done | Include core exploration and removal actions. | The workspace has volume and folder selection, breadcrumbs, size and count summaries, search, sort, Quick Look, Finder reveal, marking, review, Trash, and separately confirmed permanent deletion. Removal checks the scan root and each entry's device and inode before acting. | Exercise the non-destructive UI flow in the final signed app. |
| Verify | Show when a scan cannot see protected files. | The scan reports unreadable items and opens Full Disk Access settings. Apple requires the user to grant this access in System Settings. | Check the denied and allowed states on the final installed app. |
| Verify | Use the selected Disk Explorer icon. | Option 02, Sector platter, is now `DiskExplorerLogo`, used by the tool registry, Dock routing, and Raycast command. The 512px asset and 64px/16px previews keep the selected composition; focused icon tests and Raycast checks pass. | Inspect it in the final signed launcher and Dock. |
| Verify | Make scans useful before they finish. | The scanner publishes measured folder sizes and a growing top-100 file list while it walks; partial scans cannot mark files for removal. A 327,550-entry `/Applications` scan showed its first nonempty chart snapshot in 0.01 seconds and finished in 4.95 seconds. The new scanner and safety tests passed in the hosted unit run. Hosted UI run `36137580518` captured a populated treemap at 365,603 checked items and a top-100 list while scanning. | Confirm cancellation and protected paths in the final signed window. |
| Verify | Give the visualization room and the largest files a real page. | Visualization and Largest Files have separate tabs. The chart takes the body width; Contents is toggleable and initially closed; counts sit in a header popover. Largest Files shows up to 100 size-sorted files with search. Hosted run `36138597977` passed Contents and tab navigation and captured the statistics popover with used space, file count, and folder count. | Inspect the final signed window. |
| Verify | Make charts readable and responsive to interaction. | Treemap and ring hover highlight the target and show its name and size in the header line, including tiny segments; the old reserved footer is removed. The ring center retains the current folder. Chart navigation crossfades and scales, with Reduce Motion support. Hosted run `36279617042` passed hover, drill, and tab checks, and captured both hovered names and sizes. | Inspect motion and interaction in the final signed window. |
| Verify | Keep Diskman responsive after a large scan. | Compact entries now store a stable 64-bit identity while URLs remain parent-derived only for actions. Tables cache projected rows and native row values by revision, page, query, and sort. Treemaps and rings cache layouts by revision, tab, measure, folder, completion state, and plot size. Ring segments no longer install four geometry animations each. A Debug harness measured 9,700 identity reads at 1.18 ms versus 1,378.90 ms for parent-derived URLs. | Repeat the signed Time Profiler page-switch trace and confirm the 100 ms speed gate. |

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

### Analyze and eject correction, 2026-09-27

Remove the redundant Manage Disks sidebar row. Each physical disk row opens
Modify and has an Eject control. If a normal eject fails because files remain
open, list the blocking processes and offer a deliberate quit-and-retry path
or Cancel. Preserve device identity and write-lock checks, and do not force
eject or close unrelated/system processes. Analyze should first show a shallow,
measured estimate for every top-level folder, then replace it with exact sizes
as the deeper walk completes. Charts should fill the remaining workspace
height. Remove the idle hover prompt and place the unreadable-item warning in
a subdued yellow button next to View, with details on demand.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Move Modify devices into the main sidebar and make the selected scope obvious. | The shared Modify model drives sidebar rows, the disk map, and direct actions. The map has a persistent Whole disk target; disk-wide actions ask for it when a partition is selected. APFS child rows have linked stems, EFI is labeled `ESP · PROTECTED`, and action cards use three uniform columns with one-line titles. Hosted run `36243581713` passed UI navigation, action scope, selection after inventory refresh, and light/dark APFS renders. | Inspect the signed installed window when app-scoped control is available. |
| Verify | Keep the 1 TB disk locked by default and enforce locks below the UI. | Newly seen media defaults locked. Sidebar context menus and the Modify titlebar can change the per-media setting. `DiskManagement.run` checks the lock before inventory and again before executing a modifying command; Verify remains read-only. Hosted run `36243581713` passed lock persistence, changed-media, and command-rejection checks. Read-only inventory identified the authorized SD card at `disk10` (15,634,268,160 bytes, serial `0x19302912`) and the 1 TB external disk at `disk6`. | Inspect the locked state in the final signed installed app when app-scoped control is available. |
| Verify | Stop live boxes snapping and let charts fill the workspace. | Treemap tile identity, its bounded item set, and split topology stay stable as weights cross during a scan; individual frames interpolate and zero-size skeleton entries appear in the first snapshot. Rings use the same live membership rule and animated arcs. On completion, both views select the largest measured entries once and animate the change. The newer layout removes the 40-point idle detail row so the plot can fill available height; hovered name and size appear in the existing breadcrumb line and accessibility labels. | Confirm motion and the final height in the signed app. |
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

Diskman's latest focused hosted run `36279617042` passed its unit and UI jobs,
including progressive scans, chart hover and navigation, Modify inventory,
the blocked-eject preview, the review sheet, media identity, and light/dark
renders. Direct inspection of the installed window remains subject to the
prior automatic Computer Use rejection; hosted UI captures provide the
interaction evidence above.
