# Disk Explorer Troubleshooting

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
- **Check:** Run the hosted ring-hover UI assertion and inspect its screenshot
  for a highlighted segment and matching center label. Run `36140917852`
  established the failure with a pointer aimed through the center-text frame.

## Plain File Actions Show A Mismatched Focus Outline

- **Symptom:** Hosted `FocusEffectTests` reported the new Largest Files action
  buttons as using a mismatched native focus outline.
- **Cause:** Their plain button style lacked the shared focus-effect override.
- **Invariant:** Pair each plain or borderless custom action with
  `.focusEffectDisabled()` and keep its accessible name and hover help.
- **Check:**
  `FocusEffectTests.testCustomButtonStylesSuppressTheMismatchedSystemOutline`
  passed in hosted run `36138597977`.
