# Diskman Troubleshooting

## Detail Footer Hidden From Accessibility

- **Symptom:** Hosted run `36162099059` rendered the detail row below each
  chart, but the UI test could not find `diskExplorer.treemapDetails`.
- **Cause:** The treemap put its accessibility label and identifier on the
  enclosing view, so macOS exposed the plot and footer as one element.
- **Invariant:** Expose the plot and its reserved footer as separate elements.
  The hovered item's name must appear in the footer, and the footer's frame
  must begin below the plot in both chart modes.
- **Check:** The hosted Diskman UI test locates both rows, compares their
  frames with the plots, and matches each hover name to the footer text.

## Partial Scan Rearranges The Map

- **Symptom:** Treemap boxes appear, disappear, and snap into new places as
  partial scan sizes change. A hover card covers the map and scan status
  changes the available body height.
- **Cause:** The original Canvas chart sorted by current size, changed its
  split groups, and hid zero-weight entries. The later SwiftUI chart animated
  frames but still ranked its bounded entries by changing measured size, so
  items crossed the 80-tile or 24-segment cutoff during a scan.
- **Invariant:** Keep entries visible from the first folder skeleton, select
  and order the chart's bounded set by stable path, split by count, and
  interpolate each tile or ring segment as measured weights arrive. Keep hover
  details and scan status in reserved rows outside the plotted region. Reduce
  Motion stays immediate.
- **Check:** `testTreemapKeepsTileGroupsWhenMeasuredSizesCross` fails with the
  prior weight-based grouping. `testLiveChartsKeepVisibleItemsWhenMeasuredSizesCross`
  covers the 80-tile and 24-segment cutoffs. Hosted chart navigation and
  motion captures must confirm stable live transitions in both appearances.

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

## Shallow Rings And Crowded Results

- **Symptom:** The chart competed with a permanent Contents pane, file counts
  used scarce body height, and a two-level ring used only part of its canvas.
- **Cause:** The old layout kept both panes in one row, and rings reserved
  fixed widths for three levels even when the tree had fewer levels.
- **Invariant:** Visualization uses the result width. Contents starts closed
  and can be opened. Largest Files has its own tab; counts sit in a header
  popover. Ring bands adapt to the visible tree depth, and chart hover shows
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
- **Invariant:** Pair each plain or borderless custom action with
  `.focusEffectDisabled()` and keep its accessible name and hover help.
- **Check:**
  `FocusEffectTests.testCustomButtonStylesSuppressTheMismatchedSystemOutline`
  passed in hosted run `36138597977`.
