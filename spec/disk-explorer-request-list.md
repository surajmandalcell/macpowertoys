# Diskman request list

Round 17 sidebar repair, run 68, 2026-10-01: app `53b31541` shows compact
device capacities such as `disk0 · 500 GB` in the existing 106pt lane.
Row help and accessibility retain precise capacity and full byte counts.
Detailed table and inspector formatters keep their existing precision.
All 21 DiskExplorerViewTests pass through the foreground guard.
Shared `7dbcb3f` uses the 44pt entity-row token and passes the height and
full-row hover check in both densities and appearances. `10b09f5` is the
latest shared checkpoint from this lane. Request OnePlusUI 1.0.1 containing
both commits; the orchestrator owns tagging, adoption and installation.
The app and test bundles compile against 1.0.0. The 44pt device geometry,
lock/eject targets and precise help require the new signed build.
Report: `tmp/redesign/logs/w10-fix17-panels.md`.

Local verification, run 63, 2026-10-01: all 45 DiskExplorer and
DiskManagement app tests pass through the guarded wrapper. This includes
chart-cache release and scan regressions. The full run later aborts on focus.
`cd49d097` commits reviewed header and cache hooks. Installed controls,
physical devices, memory recovery, and signed captures remain open.
Report: `tmp/redesign/logs/w7-local-tests.md`.

Recap Pro table traits H, I, 2026-10-01: `e25d7c99` gives native file
tables, partition rows, and Review rows 33pt headers and 34pt bodies in
both densities, alternating surfaces, and full-row hover/selection.
`8eeb2a0f` puts Review paths and sizes beside names; full paths remain in
help. All 13 package table checks pass in Light and Dark; each source
batch's single app/test compile gate passes. Installed sorting, selection,
scrolling, and Review checks remain with the orchestrator.
Report: `tmp/redesign/logs/w4-traits-tables.md`.

Requested on 2026-09-25, using [disktree](https://github.com/tobi/disktree) and
[DaisyDisk](https://daisydiskapp.com/) as behavior references. This is an
independent Swift and SwiftUI implementation in MacPowerToys.

## Production partition audit, 2026-10-01

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Logic verified; signed review pending | Protect the startup disk, running app, repository, and internal disks. | `bcdb3f43` resolves each protected volume to its physical APFS stores and records a visible refusal reason. The live source harness protects disk0 and the repository/app disk6 while allowing only the test SD. Removing protected-volume lookup makes that check fail. EFI repair and preview execution are rejected. `228370aa` disables protected sidebar unlock and explains eject protection. | Run the compiled safety regressions on hosted CI. Check protected banners, disabled locks, and refusal copy in the signed app. |
| Source updated; signed review pending | Keep progress visible, refresh after failures, and make review complete. | `bcdb3f43` keeps action and target progress in the fixed footer, refreshes after both run and eject results, reports refresh errors, retains ExFAT while unmounted, and shows both proposed partitions plus the erase warning. | Exercise progress, errors, selection after refresh, typed review, confirmation and Cancel on the signed build. |
| SD verified; signed review pending | Exercise every supported native device operation safely. | `sdcard-guard.sh` checks the physical SD media, Secure Digital bus, removable flag, and size before each device write. Erase, split, mixed APFS/ExFAT layout, rename, mount/unmount, repair, zero-fill, add/delete, shrink/grow, HFS+ preservation merge, confirmed ExFAT merge, and eject passed. A real blocked eject identified only the owned tail process. The raw command log and final state are in `tmp/redesign/logs/w1-diskman-partition.md`. | The card was verified as one ExFAT data volume named DISKMAN, then safely ejected. Reinsert it for signed interaction. No physical hot-swap or owner process quit was tested. |

The orchestrator owns the clean signed install, source-stamp and running-path
checks, installed controls, both appearances, and hosted test execution.
Six shared build attempts stopped only in unowned files. The final attempt
fails in `NetToysScannerView.swift:1029` while type-checking the Response column.
Diskman source checks pass; the full app and test build remains an integration
gate. Exact commands and logs are in the partition report.

## Scan memory follow-up, 2026-10-01

`00ff0e21` adds chart-cache clearing and a regression for subtree release.
`cd49d097` commits the window-close and replacement-scan hooks with the
shared header row after review. Both `chartLayouts.clear()` calls compile.
A source-derived 400,001-node check fails without clearing and passes with
it; footprint falls from 110.95 MB to 56.95 MB and all nodes release.
One tests-mode gate compiles the app and both test bundles. A signed
`76ed9b89` replay shows 983,230 retained scan nodes after Stop. Stop must keep
partial results and valid paths. The orchestrator owns clean installation,
closed-window recovery, full replay, and the under-250 MB gate.
Report: `tmp/redesign/logs/w4-memory2.md`.

## Production analysis audit, 2026-10-01

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Logic verified; signed review pending | Preserve file paths after stopping a scan. | A partial snapshot retains the source root that owns shared entries' weak parents. The standalone temporary-folder check fails on the prior scanner and passes after the fix. A focused XCTest checks both Results and Largest files paths after scanner release. | Execute hosted tests. Check Stop, Quick Look, Copy Path, and Reveal in Finder on the signed build. |
| Logic verified; signed review pending | Keep folded files visible in every live chart measure. | Live bounded selection reserves space for the scanner aggregate. An adversarial aggregate beyond the old cutoff fails in Space, Files, and Age on the prior source and passes after the fix. The existing view test now checks that boundary and preserves all shown plus hidden identities. | Execute hosted tests. Inspect live and completed charts in both appearances. |
| Logic verified; signed review pending | Review each selected subtree once. | Removal filtering checks every selected ancestor path instead of only the adjacent sorted row. A temporary-folder fixture catches a similarly named sibling between parent and child. Changed-file Trash rejection passes without calling the Trash service. | Execute hosted tests. Check review totals, confirmation, cancellation, and unmarking. Never Trash owner data during this audit. |
| Source updated; signed review pending | Use shared More controls and full-row review hover, and keep both manuals accurate. | The header uses OnePlusMenuButton. Review rows use onePlusTableRow, with full-row hover and a separator. About and the launcher use the same corrected first-run and double-click instructions. | Check the popup, row hover, two-line review rows, and both manuals in the signed build. |
| Source updated; signed review pending | Apply the owner's horizontal density and instant motion correction. | Scan statistics, folder status, chart labels, inspector sizes and review totals use horizontal rows. Results search and review controls sit directly on the page. Enable and unreadable rows have no card wrapper. Scanning settings group two content rows in one card. Help uses tooltips. Browse and Cancel share the sheet footer. Treemap membership and frame animations are removed, including unused animation state and the old metric label. | Capture pending, live and completed Analyze, both table tabs, Choose Folder, Settings and About. Check label truncation, tooltips and instant updates in both appearances. The 2026-10-01 owner correction replaces earlier paired single-row cards and chart interpolation requirements. |

The fifth shared build gate compiles the Debug app and both test bundles.
The safe temporary-folder checks pass. Hosted test execution and signed
interaction remain open. The feature inventory and build logs are in
`tmp/redesign/logs/w1-audit-diskman.md`. The orchestrator owns installation,
deep-link captures, live controls, both appearances, and the latency gate.
Devices, partitions, format, erase, eject, and write locks stay with
`diskman-partition`.

## Round 11 analysis review, 2026-10-01

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Source fixed; signed review pending | T092: Keep Space used in accent ink. | `965f451d` passes the accent to the mono text modifier. The horizontal 28 pt summary stays on the page. | Check both signed appearances. |
| Source fixed; signed review pending | T093: Align the standalone Enable row. | `965f451d` sets card padding to zero on that row only. Its 44 pt height, 16 pt next-card gap, and real card insets stay intact. | Check Settings in both hosts and appearances. |
| Source fixed; hosted and signed review pending | T094: Quick Look the complete real-file selection. | `965f451d` passes ordered table selections and context-menu collections to native Quick Look. Aggregates have no preview URL. A focused regression is in the app test bundle. | Run hosted tests. Use Space and the context menu for one, many, mixed aggregate, and aggregate-only selections. Check dismissal and existing file actions. |
| Package verified; signed review pending | T123 / O9: Compare item sizes inside the native Size column. | `04c02b3a` adds 55 x 3 pt neutral bars beside byte text, normalized after filtering. All 11 focused native table tests pass, including geometry, fractional updates, invalid inputs, selection, and plain cells. | Run hosted projection tests. Check filtered and unfiltered Results and Largest files, sorting, hover, selection, and both appearances. |
| Source fixed; hosted and signed review pending | T118 / O4: Restore validated page and result-tab IDs. | `04e5c182` restores IDs before rendering, rejects unknown IDs, and falls back from Modify when no device is available. Search stays transient. `c5ca5a2d` starts Analyze after restored Settings without changing the selected tab. Existing explicit page routes still override saved choices. | Run hosted regressions. Check close/reopen, relaunch, invalid IDs, unavailable devices, and each explicit route. |

All 12 round 10 Diskman captures were reviewed. No additional demonstrated
layout defect was found. New signed captures and native interactions remain
with the orchestrator. The one batch compile gate fails only on concurrent
MainToolCard catalog-token references, with no Diskman diagnostic. The updated
queue rule prevents a second gate. Catalog tokens are now in `6c097371`.
See `tmp/redesign/logs/w3-audit-diskman.md` for remaining acceptance checks.

## Round 12 Settings review, 2026-10-01

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Source fixed; signed review pending | R11 critique item 1: Pair short Display and Scanning cards. | `6f387aa3` places both existing cards in the shared Settings view's equal-width, top-aligned HStack with a 16 pt gap. The standalone Enable row and natural 172/128 pt card heights remain. Source parse and whitespace checks pass. The one tests-mode gate passes at source stamp `d0c3d0e4` and compiles the Debug app and both test bundles without running hosted tests. | Check 580 pt widths at the 1440 pt canvas, both Settings hosts, and both signed appearances. |

## Native redesign, 2026-09-29

`DESIGN.md` version 14 controls the native shell and alignment. The HTML
reference supplies content and storage chart texture. The surface worker
does not install or launch the app; the redesign orchestrator owns that gate.

Round 2 requires equal columns for the short Scanning and Disk access cards.
The inspector share bar and more menu use the shared neutral control style.
Completed charts group targets smaller than a control into Other; folded
file aggregates remain explicit, non-drillable items. Live treemaps keep their
path-based membership. Live root rings rank measured children by the selected
measure so their first band matches the inspector; the remainder is a neutral
Other segment.
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
All Diskman pages use the shared page header so foundation owns the 16 pt top
line. Table sorting and row formatting must run outside SwiftUI body work.

Round 5 keeps the inspector within the fixed visualization region by using
28 pt child rows. Largest files and Results retain their last projected rows
while the next live scan revision is prepared. Device inventory also retains
the last known rows while a new Diskman window refreshes them.

The third screenshot review keeps the selected tab's structure before the
first scan snapshot. Visualization retains its map header and 260 pt inspector.
The tables retain their search, review controls, and column headers. Pending
values use a dash. Scan notices use the shared page's fixed footer. Breadcrumb
viewports use the 24 pt compact height inside the 40 pt map header. Live ring
sectors keep their weights and membership but omit outlines when their inner
arc is narrower than the 1 pt separator.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Retain prepared inspector facts during live scan revisions. | The inspector keeps its prior path, count, and top children for the same entry and measure. A new selection uses dashes until preparation completes. One state assignment replaces all prepared facts. The compiled regression separates pending counts from measured zero and checks revision, selection, and measure changes. | Execute the regression on hosted CI. Capture several signed live updates and a new selection in both appearances. Keep the inspector 260 pt wide. |
| Verify | Keep live ring geometry, membership, and colors in one prepared frame. | The membership animation and its duplicate ID state are removed. Ring rendering disables inherited animations and retains the last prepared array during detached preparation. A render regression samples the root band as a different folder enters the top five, in both appearances. | Execute the regression on hosted CI, prove it fails with the prior animation, and capture several signed live updates. |
| Verify | Inherit the shared accessibility focus policy. | Treemap, Rings, partition tiles, and More actions no longer override focus visuals locally. Chart clicks select without forcing keyboard focus. The shared window root handles both Full Keyboard Access and VoiceOver. | Check opening, mouse clicks, keyboard selection, Return, Space, and both accessibility focus modes in the signed build. |
| Verify | Switch live file-table tabs without a native crash. | `1d4c1f1` rebuilds native column identities before cell updates. Native diagnostics from `36717899137` prove the old action-column index was outside the row bounds. The add/remove-column regression passed in `36723274846`. Diskman `36723718557` passed the focused units and all four UI cases, including Command-F. | Complete signed tab checks. |
| Verify | Keep the first scan inside the final tab bounds. | Signed round 4 captures retain the pending map, 260 pt inspector, and table controls. Round 5 loaded notices end at y=876 in both appearances. The shared fixed-region layout now omits an empty footer's gap. | Capture the pending and empty-footer states after the shared fix. Keep real notices fixed and retain the 24 pt bottom bound. |
| Verify | Center breadcrumbs and remove tiny-sector spokes. | Signed round 4 captures show breadcrumb and folder-count ink in the same y=290-298 band. The bright tiny-sector spokes are gone in the captured live rings. A compiled regression checks sector membership, total angle, and hit testing. | Execute the regression on hosted CI. Inspect completed Treemap and Rings, selection, and hover in both appearances. |
| Verify | Complete shared table, sidebar, and About geometry. | Signed round 5 About cards end at x=1416. Native table icons now use the shared 16 pt slot and derive NAME header placement from it. Repeated ellipses are absent at rest. | Inspect hover, selection, and keyboard exposure of the shared 28 pt action, plus native context menus. Long accessory-free sidebar labels remain unverified. |
| Verify | Keep tabs stable while the largest-file count fills. | The shared tab strip now reserves three count digits by default. All eight signed round 5 scan captures place Results near x=450 with count 100. Diskman passes the actual count. | Check the 0-to-100 transition and selected underline in the signed build. Preserve the 6 pt label gap and 22 pt tab gap. |
| Verify | Keep Visualization inside the 900 pt canvas. | The inspector child list now uses a 28 pt pitch and consumes only its available fixed region. The map, inspector, stats, tabs, and notices do not add a page scroll view. | Foundation owns top-pinning the shared fixed-window root. Inspect Home and Rings in the next signed capture. |
| Verify | Make live Rings agree with the inspector. | The root ring uses the inspector's five largest measured children in storage-series order and folds only the remainder into a neutral Other segment. A regression covers large children outside the old stable-ID prefix. | Run the regression and inspect a large live Home scan in both appearances. |
| Verify | Keep live rows and device bounds stable during refresh. | File tables retain the prior matching projection across scan revisions and show a named loading state only before their first projection. New Diskman windows seed device rows from the last successful in-process inventory while the detached refresh runs. | Inspect Largest files during a live scan and reopen Home during inventory refresh. |
| Verify | Keep page controls fixed and align titles with the shared 16 pt top line. | Analyze and Modify use `OnePlusPageHeader` directly. Signed round 5 titles follow T=16. Analyze keeps stats, tabs, map header, inspector, chart footer, search row, and notices fixed. Native file tables own row scrolling. Modify keeps its header outside the scrolling card stack. | Inspect scrolling, every page, and both accessibility focus modes in the signed build. |
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
| Verify | Use neutral inspector and more-menu controls. | The share bar uses the shared neutral fill. The header More action uses the shared OnePlusMenuButton and popup. File context menus stay native. | Capture rest, hover, and open-menu states in both appearances. |
| Verify | Keep completed charts readable on a large home folder. | Tiny final targets fold into Other with their measured totals. Folded scanner aggregates stay explicit. Live ring bands stay fixed. Keyboard selection uses the visible layout, and grouped ring IDs cannot collide with real paths. Compiled regressions cover grouping, totals, hover hits, and live band widths. | Execute hosted checks and inspect completed treemap/rings, selection, and hover in both appearances. |
| Verify | Route home, largest-files, results, rings, choose-folder, settings, about, and device/bsd-name pages. | The window handles every page through `.onOpenToolPage`; the shared parser now accepts nested device paths. Volume metadata loads off the main actor, and appearance does not restart a scan started by a pending page link. | Capture the first home page in dark and light and measure opening time; verify all links. |

The round 2 desktop test build compiles both bundles, including Diskman unit,
render, and UI sources. Three attempts stopped in other agents' active edits;
the fourth passed. The render fixture covers a completed 133-folder home tree
and 100 largest files. Signed visual review and hosted execution remain open;
compilation does not prove interaction, opening time, or appearance.


| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Make each physical disk the Modify entry and place Eject in its sidebar row. | The separate Manage Disks row is removed. Eject keeps the existing per-media write lock and identity checks. A failed normal eject can list open processes; Close sends a normal app quit or TERM, while Force Quit sends KILL only after a separate button press. Both recheck the disk and process identity. Hosted run `36279617042` passed sidebar selection and the blocked-eject preview, including disabled quit actions in test mode. | The 2026-10-01 partition audit verified a real blocked eject and successful retry after the owned process closed. Check the installed blocker sheet and quit controls after reinserting the card. |
| Verify | Publish a shallow size estimate before the deep scan and use the full chart height. | The scanner reads immediate children of each top-level folder once, publishes their allocated-size floor, then reuses that listing for exact traversal. Hosted run `36279617042` passed the progressive-scan unit check and UI navigation. Its light/dark renders show the chart using the available height, without the idle footer, and the unreadable count in a dim yellow button beside View. Hover details appear in the existing header line. | Inspect the final signed installed window when app-scoped control is available. |
| Done | Make Modify a direct partition workspace and test native merge safety. | The disk rail, textured partition map, volume rows, and grouped action cards expose operations without an action picker. Selection shows the adjacent merge target and data-loss outcome before review; disabled actions explain why. ExFAT resize is unavailable; HFS+ and APFS resize sheets read macOS limits before review. Destructive actions require the reviewed disk ID and recheck media identity before execution. Hosted run `36216183313` passed Modify navigation, merge review, selection, focused safety tests, and light/dark renders. On the authorized 16 GB SD card (serial `0x19302912`), HFS+ shrank and grew while a 1 MB marker retained SHA-256 `30e14955...`; an adjacent HFS+ merge preserved it. Add/delete partition and forced ExFAT merge succeeded; the latter erased its marker as warned. A dry forced merge returned exit 0 with “Merge canceled”, so the runner now sends confirmation after typed review and rejects canceled output. The card is restored to one mounted `DISKMAN` ExFAT volume and passed `fsck_exfat`. The signed app and helper at `562d019` passed strict signature and source-stamp checks; the `/Applications` app launched in the background. | Native installed-window inspection remains subject to Computer Use approval. |
| Done | Add a separate, on-demand disk tool. | `DiskExplorerTool` is in the built-in registry; its own SwiftUI window has a stable restoration ID, launcher settings, deep-link routing, and the shared Reduce Motion-aware page transition. The Debug app builds. | Verify the final signed window and position restoration. |
| Done | Scan a whole volume or chosen folder quickly. | First run asks for a location. A selected source can resume on appearance. The POSIX walker uses `readdir` and `fstatat` off the main actor, with four top-level workers, cancellation, hidden-file choice, volume boundaries, hard-link deduplication, and unreadable counts. A 392,508-entry `/Applications` scan took 5.36–6.17 seconds in two runs on this Mac. A fixture matches `/usr/bin/du` and verifies symlink-loop handling. | Measure startup-disk behavior with the final signed app and report inaccessible paths. |
| Done | Offer both treemap and circular disk views and remember the choice. | Shared preferences drive the window and launcher pickers. Both charts navigate the same scan tree and can show disk use, file count, or recency of changes. | Inspect both charts and measures in the final signed app. |
| Done | Include core exploration and removal actions. | The workspace has volume and folder selection, breadcrumbs, size and count summaries, search, sort, Quick Look, Finder reveal, marking, review, Trash, and separately confirmed permanent deletion. Removal checks the scan root and each entry's device and inode before acting. | Exercise the non-destructive UI flow in the final signed app. |
| Verify | Show when a scan cannot see protected files. | The scan reports unreadable items and opens Full Disk Access settings. Apple requires the user to grant this access in System Settings. | Check the denied and allowed states on the final installed app. |
| Verify | Use the selected Disk Explorer icon. | Option 02, Sector platter, is now `DiskExplorerLogo`, used by the tool registry, Dock routing, and Raycast command. The 512px asset and 64px/16px previews keep the selected composition; focused icon tests and Raycast checks pass. | Inspect it in the final signed launcher and Dock. |
| Verify | Make scans useful before they finish. | The scanner publishes measured folder sizes and a growing top-100 file list while it walks; partial scans cannot mark files for removal. A 327,550-entry `/Applications` scan showed its first nonempty chart snapshot in 0.01 seconds and finished in 4.95 seconds. The new scanner and safety tests passed in the hosted unit run. Hosted UI run `36137580518` captured a populated treemap at 365,603 checked items and a top-100 list while scanning. | Confirm cancellation and protected paths in the final signed window. |
| Verify | Give the visualization room and the largest files a real page. | Visualization and Largest Files have separate tabs. The chart takes the body width; Contents is toggleable and initially closed; counts sit in a header popover. Largest Files shows up to 100 size-sorted files with search. Hosted run `36138597977` passed Contents and tab navigation and captured the statistics popover with used space, file count, and folder count. | Inspect the final signed window. |
| Verify | Make charts readable and responsive to interaction. | Treemap and ring hover highlight the target and show its name and size in the header line, including tiny segments; the old reserved footer is removed. The ring center retains the current folder. Chart navigation crossfades and scales, with Reduce Motion support. Hosted run `36279617042` passed hover, drill, and tab checks, and captured both hovered names and sizes. | Inspect motion and interaction in the final signed window. |
| Verify | Keep Diskman responsive after a large scan. | Compact entries now store a stable 64-bit identity while URLs remain parent-derived only for actions. Tables cache projected rows and native row values by revision, page, query, and sort. Treemap and ring cache misses prepare immutable layouts in detached tasks keyed by revision, tab, measure, folder, completion state, and plot size. Live scan presentation is coalesced to four updates per second, and hidden or minimized Diskman windows retain only the latest snapshot without changing observable chart or table state. Ring segments no longer install four geometry animations each. A Debug harness measured 9,700 identity reads at 1.18 ms versus 1,378.90 ms for parent-derived URLs. | Repeat the signed Time Profiler page-switch trace with Diskman visible, occluded, and minimized; confirm the 100 ms speed gate. |

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
| Verify | Stop live boxes snapping and let charts fill the workspace. | Treemap tile identity, its bounded item set, and split topology stay stable as weights cross during a scan; individual frames interpolate and zero-size skeleton entries appear in the first snapshot. Rings keep deeper live membership stable, rank root children by measured weight, and swap complete prepared arcs without animation. Completed charts select the largest measured entries. Hovered name and size use the existing chart detail line and accessibility labels. | Confirm full root-band coverage, stable live updates, and the final height in the signed app. |
| Verify | Match the app's restrained chrome and update the chart palette. | The chart uses a muted blue, green, coral, violet, and gold set inspired by Apple, Google, and Anthropic, with the shared neutral background and existing button/spacing components. The scan status reserves a constant height. Hover now brightens only the focused item, so other colors stay clear. Hosted run `36193151541` passed; its dark ring render shows soft dividers instead of black gaps, and light-mode hover captures keep the selected item legible. | Inspect the final installed app. |
| Done | Rename the product to Diskman and organize the sidebar around Analyze and Modify. | Launcher, window, Raycast label, and manual say Diskman. Analyze groups folders and mounted volumes; Modify opens physical disk management. The prior route ID and saved settings are preserved. | Verify final signed UI. |
| Verify | Keep Analyze's scan separate from Modify. | A page switch cancels the Analyze scan and removes its status footer. Hosted normal-mode run `36173007922` passed the Modify assertion and captured the disk inventory's own progress state without the scan footer. A separate normal-launch capture from run `36171513372` showed the visualization without an unsolicited event-access prompt. | Inspect the final signed window and its permission-dependent states. |
| Verify | Add safe native disk and partition management. | Modify lists physical media and partition/volume structure. Native actions include verification, selected-volume repair, mount/unmount/eject, rename, erase volume/disk, repartition, add/delete/resize partitions, APFS volume and container operations, and zero-fill. Writes are limited to writable removable/external physical media with a resolvable I/O Registry media instance; the app compares that instance and the disk layout again immediately before execution and requires typed device-ID review for data-loss actions. APFS operations exclude shared-store containers and reject a changed container reference. Hosted run `36189567926` passed the replacement-media identity regression, other safety tests, Modify UI, and light/dark renders. Two read-only lookups of the authorized SD card returned the same media instance. | Inspect the updated signed app; a physical hot-swap was not performed. |
| Verify | Show the actual mounted file system in Modify. | The SD partition type is `Microsoft Basic Data`, but macOS reports its mounted file system as ExFAT. Modify now reads the native volume-format description and shows ExFAT; APFS stores and volumes have explicit labels. The authorized card returned `ExFAT` in a direct Foundation metadata probe. Hosted run `36192321303` passed and its light and dark Modify renders both show ExFAT. | Inspect the final signed app. |
| Done | Test destructive operations only on the authorized 16 GB SD card. | The test harness checked Secure Digital bus, 15,634,268,160-byte size, `disk10`, and card serial `0x19302912` before every operation. Erase, verify, repartition, rename, mount/unmount, partition delete/add, volume format, HFS+ resize, volume repair, zero-fill, and APFS add/delete/shrink/grow succeeded. The card was restored to one mounted ExFAT volume named `DISKMAN`; `fsck_exfat` reports it is OK. | The 2026-10-01 partition audit repeated these operations and verified both blocked and successful eject. The restored card is now safely ejected; reinsert it for installed interaction. |
| Open | Add exact disk-image backup and restore if native device access can be granted safely. | `diskutil image create from disk10` and `disk10s2` both returned `Operation not permitted` because the current account cannot read raw device nodes. Imaging the mounted folder succeeded, but made a small APFS image of its files, not an exact ExFAT disk or partition clone. No clone control is exposed. The current SD state is recorded in the production partition audit. | Design a supported privileged read/restore path and verify both operations on only the authorized SD card before exposing them. |

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
