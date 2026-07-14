# Text Extractor Troubleshooting

## Window Information Architecture

- **Symptom:** Recognition controls occupy the home view, a redundant Ready
  state appears, or the empty prompt remains when detections exist.
- **Cause:** Setup, status, and history were combined instead of using explicit
  page and empty states.
- **Invariant:** History is the default body. Show "Select text anywhere" only
  when history is empty. Recognition options replace home content on the
  settings page. Do not show Ready.
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
- **Invariant:** Compact rows show a short preview and coarse relative time with
  no seconds. Large text opens in its own selectable detail view. Escape closes
  dismissible detail and sheet views.
- **Check:** Open short and large detections, copy text, inspect timestamps, and
  dismiss the detail view with Escape.
