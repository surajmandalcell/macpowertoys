# Diskman Troubleshooting

## Device Caption Units And Entity Height, Run 68, 2026-10-01

- **Symptom:** The sidebar shows `disk0 · 500.28…` without its unit.
  Device rows use 56pt instead of the 44pt entity height.
- **Cause:** The sidebar copies the detailed size formatter. The shared
  device row hard-codes extra vertical space.
- **Invariant:** Use whole decimal capacities only in device captions.
  Keep precise sizes and full byte counts in row help and accessibility.
  Preserve detailed table and inspector formatting. Device rows use the
  shared 44pt token, existing two-line spacing and full-row hover/actions.
- **Check:** App `53b31541` passes all 21 DiskExplorerViewTests, including
  unit visibility in the 106pt lane and unchanged detailed formatting.
  Shared `7dbcb3f` passes the device height and hover check in both densities
  and appearances. The orchestrator must tag, adopt and inspect the build.
  Report: `tmp/redesign/logs/w10-fix17-panels.md`.

## External app and source disks can be unlocked, 2026-10-01

- **Symptom:** An external disk that holds the running app or repository was
  eligible for writes after unlock. The startup disk could be absent from
  Modify because macOS reports its physical kind as Unknown.
- **Cause:** Manageability checked internal and removable flags alone. It did
  not map protected mounted volumes to their physical APFS stores.
- **Invariant:** Resolve the startup, app, and available source volume before
  inventory. Protect every backing physical disk and display its reason.
  Refuse writes when that mapping cannot be verified. Keep read-only Verify
  available and repeat identity, protection, and lock checks before execution.
- **Check:** The live standalone check protects disk0 and disk6 while allowing
  the authorized SD. Removing the protected-volume result makes it fail.
  The regression covers APFS stores, snapshots, malformed stores, internal
  media, images, protection reasons, and preview execution. Run it on CI.

## Device progress and failure refresh are incomplete, 2026-10-01

- **Symptom:** Progress could scroll away, failed eject retained an old list,
  and an unmounted ExFAT volume lost its format label.
- **Cause:** Progress lived in the scroll content, eject refreshed only after
  success, and format detection depended on a mounted Foundation volume.
- **Invariant:** Keep action and target progress in the fixed page footer.
  Refresh after success and failure and report refresh failure explicitly.
  Read native diskutil filesystem metadata when a volume is unmounted.
  Show both proposed partitions and the full erase consequence before review.
- **Check:** The native SD run covered every supported operation. The source
  harness retained ExFAT while unmounted. A blocked eject named the owned tail
  PID and succeeded after it closed. The final one-volume DISKMAN ExFAT layout
  passed filesystem verification and was safely ejected. The logging wrapper
  failed after native zero-fill completion; the subsequent format and checks
  passed. Signed progress, errors, review, and blocker controls remain open.

## Stopped scan loses file paths, 2026-10-01

- **Symptom:** After cancellation, a top-level file's URL becomes relative to
  the process working directory. Results and Largest files can point elsewhere.
- **Cause:** Partial snapshots share file and completed-folder nodes with the
  scanner tree. Those nodes have weak parents. The scanner releases its root
  when it stops, while the partial result remains visible.
- **Invariant:** A snapshot root retains the source root for shared nodes.
  Keep weak parent links and compact IDs. Do not rebuild full file URLs or
  copy the complete tree at each progress update.
- **Check:** Scan a temporary folder, cancel after the first nonempty snapshot,
  then compare Results and Largest files paths after scanner release. The
  standalone check fails on the prior source and passes with root retention.
  Execute the focused XCTest on hosted CI and inspect signed Stop actions.

## Live chart hides folded files, 2026-10-01

- **Symptom:** The live treemap folds the scanner aggregate into Other when
  its ID sorts outside the bounded prefix.
- **Cause:** Live selection returned the prefix before reserving aggregate
  membership. The earlier test's aggregate happened to fall inside it.
- **Invariant:** Reserve aggregate membership in both live and complete
  selection. Keep the other live members stable and retain measured totals.
- **Check:** Put an aggregate beyond the old cutoff and check Space, Files,
  and Age. All three fail on the prior source and pass after the fix. Run
  the strengthened view test on hosted CI and inspect signed charts.

## Review repeats a selected descendant, 2026-10-01

- **Symptom:** Selecting `a`, `a-sibling`, and `a/nested` includes all three
  in review and can attempt the nested removal after removing its parent.
- **Cause:** Lexical sorting puts the sibling between the parent and child.
  Filtering compared only the last retained entry.
- **Invariant:** Compare ancestor paths with the complete selected-path set.
  Keep siblings and exclude every descendant already covered by selection.
- **Check:** The temporary-folder check fails on the prior source and passes
  after the fix. A changed temporary file is rejected on the Trash path
  before the system Trash service is called. Execute focused tests on CI.

## Quick Look Drops Additional Selected Files, 2026-10-01

- **Symptom:** Space and the context menu preview only one selected file.
- **Cause:** Both callers reduce the selection to one entry. The window uses
  the single-URL native Quick Look overload.
- **Invariant:** Pass all selected real URLs and the initial URL to the native
  collection overload. Keep table order for Space. Never preview aggregates.
  Single-item chart and inspector previews use the same collection path.
- **Check:** The selection regression covers two real entries with a leading
  aggregate and an aggregate-only selection. Compile locally, execute on CI,
  and verify native multi-file navigation and dismissal on the signed app.

## Live Inspector Facts Reset During Scan Updates

- **Symptom:** Signed round 6 Home shows 0 inspector folders and no child
  rows while the breadcrumb reports 135 folders. The inspector path is blank.
- **Cause:** Each new scan revision rejected the prepared inspector projection
  and substituted an empty projection whose folder count was zero.
- **Invariant:** Retain prepared facts for the same entry and measure while
  the replacement prepares off the main actor. Show a dash for pending facts
  on a new selection. Replace path, folder count, and child rows together.
  A measured zero remains zero. Keep the 260 pt inspector and fixed actions.
- **Check:** The compiled regression covers revision retention, changed entry
  and measure, no selection, and pending versus measured zero. Execute it on
  hosted CI. Inspect several signed live updates and a new selection in both
  appearances. The original frame does not establish lost scan data.

## Live Root Rings Leave Empty Wedges During Updates

- **Symptom:** Signed round 5 Home captures show blank root-band wedges while
  the inspector lists positive sizes. Later Rings captures cover the circle.
- **Cause:** The membership animation interpolated retained sector angles
  while sectors entered, left, or changed storage colors. Prepared segment
  arrays were complete, but the rendered transition could leave gaps.
- **Invariant:** Keep the previous prepared ring while the next layout is
  prepared off the main actor. Swap the full segment array without membership
  or inherited geometry animation. Angles, membership, masks, and colors must
  describe the same prepared layout. Keep hover, hit testing, and storage hues.
- **Check:** The render regression replaces a top-five folder and samples the
  root band during five early frames in both appearances. Compile locally.
  Execute on hosted CI and inspect several signed live updates. Compilation
  alone does not prove rendered coverage or the original failing transition.

## First Snapshot Replaces The Tab And Tiny Rings Draw Spokes

- **Symptom:** Before the first scan snapshot, one loading card replaces the
  map and inspector or the file table controls. Breadcrumbs stick to the top
  of the map header. Tiny live ring sectors draw long bright radial lines.
- **Cause:** The page switched its entire content when the current folder was
  nil. The horizontal breadcrumb viewport had no height bound. A 1 pt outline
  covered sectors whose inner arc was narrower than the outline.
- **Invariant:** Keep the selected tab's structure while scanning, including
  its map header, 260 pt inspector, or table toolbar and column headers.
  Use pending values before a snapshot. Put scan notices in the page footer.
  Center a 24 pt breadcrumb viewport inside the 40 pt header. Keep tiny live
  sectors and their measured weights, but suppress their degenerate outlines.
  Do not add a local gutter workaround for shared page or scroller defects.
- **Check:** Debug and build-for-testing pass. The ring regression checks tiny
  sector membership, outline suppression, total angle, and hit testing.
  Round 5 signed captures confirm centered breadcrumbs and faint live-sector
  boundaries. Loaded notices retain the 24 pt bottom gutter. The shared layout
  now omits empty footer gaps; its signed pending-state replay remains open.

## Native Redesign And Folded File Rows

- **Symptom:** The web-style layout had uneven edges and did not use native
  file selection. Folded scanner children could look like real files.
- **Cause:** Diskman used separate page chrome and drew file rows itself.
- **Invariant:** Use the fixed 1440 x 900 OnePlusUI shell, 216 pt sidebar,
  27 pt sidebar centerline, 16 pt page title top, and 24 pt page gutter.
  Pair short Display and Scanning Settings cards in equal-width columns
  with a 16 pt gap and top alignment. Keep their natural heights and leave
  the Enable row outside the cards. Both Settings hosts use the shared view.
  First launch asks for a
  location. Analyze uses live summary cards, three tabs, map breadcrumbs,
  and a 260 pt inspector. Click selects; double-click enters a folder.
  Native tables supply multiple selection, sorting, file menus, and drag-out.
  `.aggregate` displays `fileCount` as `N smaller files` and remains visible
  in bounded charts. Its synthetic URL never becomes a file action or drag.
  Keep scan membership, count-based splits, cancellation, and partial-result
  removal gates. Keep every disk command, write lock, media identity check,
  protected EFI check, typed review, and blocked-eject check.
  This recipe replaces the older Contents toggle, statistics popover,
  warning-button placement, and single-click drill rules below.
- **Check:** Debug compilation passes. Added view checks cover aggregate
  retention, byte sorting, breadcrumb boundaries, and keyboard selection.
  Hosted UI checks cover the new controls without executing disk writes.
  Render tests use the fixed canvas and cover both table tabs and charts in
  both appearances. Execution, signed captures, and idle CPU measurement
  remain with the redesign orchestrator.

## Large Scans Stop At 250,000 Entries

- **Symptom:** Diskman stops normal home-folder and startup-disk scans after
  250,000 entries, even when the scan can continue safely.
- **Cause:** The scan tree kept one class and one full URL for every file. A
  hard entry limit bounded that storage by truncating the scan.
- **Invariant:** A scan never stops because of an entry count. Store one named
  node for every directory and compute its URL from its parent. Keep only the
  64 largest file nodes in each directory. Fold its other files into one
  aggregate with exact allocated bytes, apparent bytes, count, and newest
  modification date. Keep the global 100 largest files in a bounded heap,
  including files folded out of their directory. Preserve progressive results,
  cancellation, shallow estimates, volume boundaries, firmlinks, and hard-link
  accounting.
- **Check:** The in-memory 10,000-file fixture keeps 64 file nodes and one
  9,936-file aggregate, with folded and unfolded totals equal. A read-only
  `/Applications` scan completed 402,496 entries and matched `du` at
  40,884,506,624 allocated bytes. Peak RSS fell from 262.95 MiB with the
  pre-limit scanner to 76.72 MiB with the compact tree. The Debug app and
  desktop test bundles compile without launching them.

## Page Switching Rebuilds Every Entry Path And Chart Segment

- **Symptom:** Switching Diskman tabs can block the main thread for more than
  two seconds after a large scan.
- **Cause:** Entry identity and path access both walked the parent chain during
  SwiftUI updates. Tables rebuilt sorted rows and AppKit row values during
  render. Charts sorted and laid out every segment again, then installed four
  animations on each ring segment. The first cache still prepared a missed
  chart layout in a main-actor view task. Every partial scan snapshot also
  invalidated the visible model, including while its window was hidden.
- **Invariant:** Store one compact 64-bit identity when each node is created;
  do not restore a full URL on each compact-tree node. Derive a URL only for a
  file action. Cache table projections by scan revision, page, query, and sort.
  Cache chart layouts by scan revision, chart tab, measure, folder, completion
  state, and rounded plot size. Prepare missed treemap and ring layouts in a
  detached task from one immutable scan snapshot. Build inspector facts outside
  render. Keep a stable table identity and no per-segment ring animations.
  Coalesce live presentation to at most four updates per second. While the
  shared window-visibility value is false, retain only the latest snapshot and
  do not change observable chart or table state; present it after the window
  becomes visible again.
- **Check:** The 97-node Debug harness completed 9,700 stored-ID reads in
  1.18 ms and the same parent-derived URL reads in 1,378.90 ms. Focused checks
  cover compact identity, chart cache separation, detached chart preparation,
  and the quarter-second presentation gate. Debug and build-for-testing compile
  without launching the app. Repeat the signed Time Profiler page-switch trace
  with Diskman visible, occluded, and minimized before closing the 100 ms speed
  gate.

## Live Rings Collapse Into Other

- **Symptom:** A live Home scan shows one dominant Other ring while the
  inspector lists several large top-level folders.
- **Cause:** Live ring membership used the first stable entry IDs instead of
  the largest measured root children. Large folders outside that prefix were
  folded into Other.
- **Invariant:** Rank the root ring by the selected measure on each scan
  revision. Show the inspector's five largest children in storage-series
  order. Keep deeper live bands stable. Fold only the remaining children into
  a neutral Other segment.
- **Check:** The view regression creates large root children outside the old
  ID prefix and requires both to remain visible beside Other. Replay a signed
  live Home scan and compare first-band proportions with the inspector.

## Live File Table Blanks Between Snapshots

- **Symptom:** Largest files reports a nonzero count but replaces its rows
  with ruled blank space and a spinner during a live scan.
- **Cause:** Each scan revision used a new projection key. The view discarded
  the prior projection before the detached sort and formatting task returned.
- **Invariant:** Keep the last projection when source, query, sort, measure,
  and columns match. Swap the new rows and entry lookup together without an
  animation. Before the first projection, show a named loading empty state.
- **Check:** The request regression permits only a revision change to reuse a
  projection. Inspect Largest files through several signed live snapshots.

## Shallow Estimates, Full-Height Charts, And Sidebar Eject

- **Symptom:** The first chart showed zero-size folder skeletons, then a fixed
  520-point plot left usable vertical space idle. A 40-point hover prompt and
  unreadable-item banner took more height. Modify had a redundant Manage Disks
  row and no direct disk eject control.
- **Cause:** The walker descended into the first top-level folders before
  measuring every sibling's immediate files. The page used a scroll container
  with a fixed chart height. Eject lived only among Modify action cards.
- **Invariant:** Publish the skeleton, then measure immediate children of every
  top-level folder once before deep walking them. Label partial sizes as
  measured so far; they are estimates until completion. Let the plot fill the
  remaining workspace height. Show hover details in the map footer and
  accessibility labels. Put the unreadable warning below the map card.
  A physical disk row opens Modify and offers Eject.
  On a blocked eject, list open processes and offer normal close, deliberate
  force quit, and Cancel. Recheck the disk, lock, and process identity before
  signaling; never force-eject.
- **Check:** Compile the app and test bundles locally without launching them.
  Hosted UI checks exercise the sidebar, plot, and blocker sheet; hosted renders
  cover the warning icon. A fixture checks shallow partial sizes against a
  final `du` result.

## Modify Device Scope And Write Locks

- **Symptom:** Modify had a second disk rail inside its body, APFS child rows had
  no connector, and disk-wide actions stayed available while a partition was
  selected. EFI looked like an ordinary deletable partition.
- **Cause:** Disk selection lived only in `DiskModifyView`; its body owned the
  device list, and partition rows used padding without drawing a hierarchy.
  The command path checked device identity but had no saved write lock.
- **Invariant:** One selection drives the main sidebar and Modify. Whole disk
  is a visible target, and its actions require that target. EFI shows an ESP
  protection label and cannot be edited as a partition. Every newly seen media
  instance starts locked; Diskman's command path checks the saved lock before
  running a modifying command. Verify stays read-only. Refresh the read-only
  inventory when Diskman opens and select the first available disk in the
  shared model, so opening Modify after inventory is already loaded has a
  target.
- **Check:** Hosted run `36243581713` passed the Modify sidebar, three-column
  actions, EFI accessibility, lock unit tests, and light/dark APFS hierarchy
  renders, plus the proactive-inventory selection regression. Read-only
  inventory identifies `disk6` as
  the 1 TB `External1TB` disk and `disk10` as
  the authorized 15,634,268,160-byte SD card with serial `0x19302912`.

## Modify Review Has Two Buttons With The Same Title

- **Symptom:** Hosted UI checks found the merge warning and selection, then
  failed when querying `Merge with next` because both the action card and the
  review button matched. Earlier text queries also missed visible SwiftUI
  warnings whose accessibility labels were not exposed as expected.
- **Cause:** A visible title is not a unique control identifier, and SwiftUI
  can expose styled text under a different accessibility element type.
- **Invariant:** Give the review execution button, selected target, merge
  consequence, and partition controls stable identifiers. Expose the target
  and consequence as spoken labels. Query the exact review control when
  checking that destructive execution is disabled.
- **Check:** Hosted run `36216183313` passed the Modify action, merge review,
  map selection, and whole-disk return test. Its review capture shows the
  ExFAT data-loss warning and a disabled execution button on the read-only
  preview device.

## Same Reader Can Hold A Different Card

- **Symptom:** A disk number, bus, size, and partition layout can remain the
  same when removable media is replaced in one reader, so those fields alone
  cannot prove that a reviewed write still targets the selected card.
- **Cause:** The original device identity covered the reader and disk layout,
  but not the active I/O Registry media instance.
- **Invariant:** Record the whole disk's I/O Registry media instance in Modify.
  Allow writes only when that instance resolves, and compare it again with the
  reviewed disk immediately before executing a command. Keep read-only
  verification available when an instance cannot be resolved.
- **Check:** `IOBSDNameMatching` returned the same instance on two read-only
  probes of the authorized SD card. The hosted replacement-media regression
  and focused Diskman UI, unit, and render jobs passed in `36189567926`.
  Physical hot-swap remains untested.

## Analyze Scan Status Leaks Into Modify

- **Symptom:** The normal-mode Modify page showed Analyze's “chart updates live”
  footer while it was listing physical disks.
- **Cause:** The scan status inset belonged to every page in the Diskman window,
  and switching pages did not cancel the Analyze scan.
- **Invariant:** Reserve the scan footer only on Analyze. Cancel an active scan
  when leaving Analyze; selecting an Analyze source starts a fresh scan.
- **Check:** Hosted normal-mode run `36173007922` passed the Modify assertion
  that the Analyze scan text is absent. Its Modify capture shows only the disk
  inventory's own progress state.

## Partial Scan Rearranges The Map Or Hides A Final Large Item

- **Symptom:** Treemap boxes appear, disappear, and snap into new places as
  partial scan sizes change. A hover card covers the map and scan status
  changes the available body height. A later path-only cutoff kept a large
  item inside Other even after the scan finished.
- **Cause:** The original Canvas chart sorted by current size, changed its
  split groups, and hid zero-weight entries. The later SwiftUI chart animated
  frames but still ranked its bounded entries by changing measured size, so
  items crossed the 80-tile or 24-segment cutoff during a scan. Choosing only
  by path prevented that churn but could exclude the largest completed item.
- **Invariant:** Keep entries visible from the first folder skeleton and use a
  stable path-based bounded set while scanning. After completion, select the
  largest measured entries once and retain path order within that set.
  Split by count and interpolate treemap tiles as measured weights arrive.
  Rings swap complete prepared segment arrays without geometry or membership
  animation. Keep scan status outside the plotted region;
  hovered names and sizes use the map's existing footer caption.
  Reduce Motion stays immediate.
  Reserve all three ring bands during scanning so discovery cannot change
  the band width. A large Other segment is valid while the path cutoff
  hides late-named folders. On completion, merge targets smaller than a
  control into Other, preserving their measured total. Keep scanner file
  aggregates explicit. Keyboard selection follows the visible targets.
- **Check:** `testTreemapKeepsTileGroupsWhenMeasuredSizesCross` fails with the
  prior weight-based grouping. `testLiveChartsKeepVisibleItemsWhenMeasuredSizesCross`
  covers the 80-tile and 24-segment live cutoffs plus final selection of a
  late-named largest item. Hosted chart navigation and motion captures must
  confirm stable live transitions in both appearances.

## Hosted Modify Inventory Fails To Decode

- **Symptom:** The hosted UI test reaches Modify but shows No Physical Disks
  alongside a plist-format error.
- **Cause:** The command runner merged `diskutil` diagnostics into stdout;
  any diagnostic corrupts a valid plist before the inventory parser reads it.
- **Invariant:** Parse stdout alone for inventory commands, keep useful merged
  diagnostics for write operations, and show the empty state only without a
  read error. Keep virtual disks out of the writable device list.
- **Check:** The hosted workflow validates `diskutil list -plist`, and the UI
  check rejects an inventory error when no physical disk row exists.
  `testModifyLayoutInBothAppearances` captures a populated SD layout without
  launching it on the owner desktop. Actual writes stay on the identified SD.

## Hosted Mac Has No Writable Physical Test Disk

- **Symptom:** The hosted UI runner can open Modify, but its physical disk
  inventory does not provide a removable device on which to inspect partition
  selection and review controls.
- **Cause:** Hosted Macs have no authorized 16 GB SD card, and attaching a
  writable device to CI would make a UI navigation test destructive.
- **Invariant:** Only Debug builds launched with `MACPOWERTOYS_UI_TEST=1` may
  show a synthetic SD layout. Mark it as preview data and disable execution in
  the review sheet. Normal launches use `diskutil` inventory; Release builds
  exclude the fixture.
- **Check:** Run `36216183313` passed normal launch and preview selection.
  Its merge review capture shows both ExFAT partitions, the typed-device
  field, and a disabled execution button. The authorized physical SD card was
  exercised separately with `diskutil` and restored to ExFAT.

## Disk Repair Requests An Interactive Whole-Disk Prompt

- **Symptom:** `diskutil repairDisk disk10` prints a question about erasing an
  EFI partition, then exits with "Repair canceled" when run noninteractively.
- **Cause:** Whole-disk repair can ask for input and its usage warns that other
  whole disks might be touched.
- **Invariant:** Modify exposes noninteractive `repairVolume` only for a
  selected volume on a guarded removable/external physical disk. Whole-disk
  verification remains read-only. Never auto-answer a repair prompt.
- **Check:** The SD card's HFS+ partition passed `repairVolume`; a command
  construction test rejects whole-disk repair.

## Scan Count Advances But The Chart Stays Empty

- **Symptom:** A scan reports checked items while the treemap and rings stay
  blank until the full walk completes.
- **Cause:** The scanner previously sent only the item count during its walk;
  it returned the tree after all top-level folders finished.
- **Invariant:** Publish an immediate folder skeleton and measured partial
  trees at most five times per second. Keep a stopped partial result visible,
  label it clearly, and allow removal only from a completed scan.
- **Check:** The scanner fixture receives a nonempty partial tree before the
  final result, final allocated bytes match `du`, and the model rejects marks
  from partial results. The `/Applications` fixture produced its first nonempty
  snapshot in 0.01 seconds during a 4.95-second scan of 327,550 entries.

## Nonfinite Chart Clip Geometry

- **Symptom:** The 2026-09-29 08:26:48 crash report shows a NaN layer
  position in SwiftUI mask layout while Diskman Home opens.
- **Finding:** The report does not identify the originating view or input.
  Diskman's old ring math could produce a negative outer radius in a tiny
  canvas. Treemap layout accepted nonfinite bounds before clipping.
- **Invariant:** Reject nonfinite or nonpositive chart bounds before drawing.
  Validate inset rectangles, ring radii, angles, and label positions before
  clipping or masking. Share and partition fractions must remain within
  zero and one, including when the denominator is zero. Keep zero-byte live
  skeletons, stable membership, and fixed live ring bands.
- **Check:** `DiskExplorerViewTests` covers empty and zero-total trees in
  both scan states and every measure. It also covers invalid bounds, tiny
  ring radii, invalid arc paths, safe fractions, and partition widths.
  Compile locally; execute on hosted CI and replay the signed Home route.
  The report alone does not establish the original crash input.

## Shallow Rings And Crowded Results

- **Symptom:** The chart competed with a permanent Contents pane, file counts
  used scarce body height, and a two-level ring used only part of its canvas.
- **Cause:** The old layout kept both panes in one row, and rings reserved
  fixed widths for three levels even when the tree had fewer levels.
- **Invariant:** Visualization fills the space beside the inspector. Results
  and Largest files have their own tabs; counts sit in the summary card.
  Ring bands adapt to the visible tree depth, and chart hover shows
  the item name and size. Respect Reduce Motion for navigation.
- **Check:** Hosted run `36138597977` passed the focused scanner, render, and
  focus checks. Its 1120 × 760 renders cover both appearances and both charts;
  the UI route exercised Scan, Contents, tabs, and statistics without touching
  the owner desktop. Keep hover and drill actions in the hosted UI check.

## Ring Hover Targets The Center Label

- **Symptom:** A hosted pointer move over a visible ring left its center label
  unchanged, while treemap hover and folder drill worked.
- **Cause:** Accessibility exposed the ring's center text as the chart element;
  UI automation positioned its pointer relative to that small text frame.
- **Invariant:** Expose the ring canvas as one chart element with the full chart
  frame, dynamic hovered-item value, and its existing label and hint.
- **Check:** Run `36140917852` established the failure with a pointer aimed
  through the center-text frame. Run `36141822640` passed the ring-hover UI
  assertion and captured a highlighted segment with a matching center label.

## Plain File Actions Show A Mismatched Focus Outline

- **Symptom:** Hosted `FocusEffectTests` reported the new Largest Files action
  buttons as using a mismatched native focus outline.
- **Cause:** Their plain button style lacked the shared focus-effect override.
- **Invariant:** Inherit the shared OnePlusUI root focus policy without local
  overrides. Show focus only with Full Keyboard Access or VoiceOver. Mouse
  selection must not force chart focus. Keep accessible names, keyboard
  operation, and hover help.
- **Check:**
  `FocusEffectTests.testCustomButtonStylesSuppressTheMismatchedSystemOutline`
  passed in hosted run `36138597977`.

## Forced ExFAT Merge Can Report Success After Cancellation

- **Symptom:** `diskutil mergePartitions force ExFAT` prints “Merge canceled”
  when its format prompt receives no answer, yet exits with status 0.
- **Cause:** `force` chooses the erase path but does not answer diskutil's
  separate confirmation prompt. A detached app process has no interactive
  stdin, so exit status alone is not proof of a completed merge.
- **Invariant:** Diskman sends `y` to that command only after the user reviews
  both partition IDs and types the physical disk ID. Other diskutil commands
  receive null stdin. Treat “Merge canceled” as an error, retain the disk list,
  and refresh inventory after the command.
- **Check:** On the authorized 16 GB SD card, the unconfirmed command canceled
  with status 0 and left both ExFAT partitions. Supplying `y` completed the
  merge, erased the marker on the first partition, and passed `verifyVolume`.
  The card was restored to one mounted `DISKMAN` ExFAT volume.


## Blocker Labels And Review Scrolling, 2026-09-30

- **Symptom:** The blocker PID read `12,345`, and review clicks missed the map.
- **Cause:** SwiftUI localized the interpolated PID. The test scrolled the
  sidebar, and offscreen map buttons could still report as hittable.
- **Invariant:** Expose one combined process and verbatim PID label. Scroll
  the Modify body until the target is inside its viewport before clicking.
- **Check:** Hosted run `36703912801` passes blocker dismissal, partition and
  whole-disk selection, merge review, chart selection, hover, and drill-in.


## Chart Cache Keeps Closed Scan Subtrees, 2026-10-01

- **Symptom:** Closing Diskman clears the model but its chart cache can keep
  completed folder entries and their full descendants alive.
- **Cause:** Treemap tiles and ring segments hold strong DiskEntry references.
  The window kept its cache across close and replacement scans.
- **Invariant:** Clear both cached layouts when the window disappears and
  before a replacement scan. Stop still keeps partial results and paths.
- **Check:** `00ff0e21` adds the weak-reference XCTest. A source-derived
  400,001-node check fails without clearing and releases every node with it.
  Footprint falls from 110.95 MB to 56.95 MB; freed malloc pages can remain
  reusable. One app/test compile gate passes. `cd49d097` commits both shared
  window hooks and the header row. Signed replay and recovery remain open.
