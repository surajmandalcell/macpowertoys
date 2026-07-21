# Text Extractor Troubleshooting

## Icon Identity

- **Symptom:** The icon drifts from the selected design, adds content inside the
  lens, or gives each wave a competing accent color.
- **Cause:** Broad icon explorations were applied without locking the approved
  geometry and color hierarchy.
- **Invariant:** Use the selected Cobalt 051 icon: low-right ivory loupe, empty
  powder-blue lens, and two muted sand waves on cobalt. The waves use one hue
  family and the lens contains no glyph or decoration.
- **Check:** Render the asset at 512pt and confirm its silhouette and colors
  match Cobalt 051 before building the asset catalog.

## Window Information Architecture

- **Symptom:** Recognition controls occupy the home view, a redundant Ready
  state appears, or the empty prompt remains when detections exist.
- **Cause:** Setup, status, and history were combined instead of using explicit
  page and empty states.
- **Invariant:** History is the default body. Show "Select text anywhere" only
  when history is empty. The settings page replaces home content and owns both
  the global shortcut controls (enable toggle plus a click-to-record shortcut
  field, default ⇧⌘2) and the recognition options. The titlebar holds only the
  title and `Extract Text`; no shortcut menu lives there. Do not show Ready.
- **Check:** Open with empty and populated history, then enter and exit settings.

## Selection Feedback

- **Symptom:** Extract Text starts capture but the pointer does not communicate
  that the user must drag a region.
- **Cause:** Capture state changed without changing pointer affordance.
- **Invariant:** Selection mode uses a large crosshair until selection completes
  or is cancelled.
- **Check:** Start extraction, move across multiple apps, cancel with Escape,
  and confirm the normal pointer returns.

## History and Detail

- **Symptom:** Large recognized text is cramped, timestamps expose seconds, or
  the detail window cannot be dismissed with Escape.
- **Cause:** Every extraction used the compact row and raw high-resolution time
  output.
- **Invariant:** Compact rows show exactly one preview line and coarse relative
  time with no seconds. Large text opens in its own selectable detail view.
  Escape closes dismissible detail and sheet views.
- **Check:** Open short and large detections, copy text, inspect timestamps, and
  dismiss the detail view with Escape.
