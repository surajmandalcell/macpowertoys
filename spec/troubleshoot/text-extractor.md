# Text Extractor Troubleshooting

## Icon Identity

- **Symptom:** The old loupe icon no longer matches the owner-selected crafted
  icon direction.
- **Cause:** The 2026-09-25 request replaces its previously locked Cobalt 051
  artwork with a physical capture-card metaphor.
- **Invariant:** Use the charcoal tile, ivory capture card, bold text bars, and
  violet selected strip from the icon refresh. Keep the strip legible at small
  sizes and do not add fake letters or a separate magnifier.
- **Check:** Inspect the production PNG at 512, 64, and 16px on light and dark
  surfaces, then confirm the same asset appears in launcher, Dock, and Raycast.

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
- **Invariant:** Selection mode uses one large, high-contrast AppKit cursor until
  selection completes or is cancelled. Do not draw a second crosshair from
  `mouseLocationOutsideOfEventStream`; its event-driven redraw trails the native
  pointer.
- **Check:** Start extraction, move across multiple apps, cancel with Escape,
  and confirm the normal pointer returns.

## Recognition Latency And Completion

- **Symptom:** Nothing appears to happen after region selection, the clipboard
  briefly contains captured pixels, or successful OCR has no completion cue.
- **Cause:** Display discovery and accurate recognition were both paid after the
  drag ended. A blank 32px warmup image let Vision short-circuit without loading
  the real text-recognition path, so a signed first extraction still took 25.2
  seconds even though synthetic focused tests were fast.
- **Invariant:** Text Extractor uses Apple's pretrained Vision OCR and bundles no
  model asset. When the tool is enabled, run the configured Vision requests on
  a generated image containing representative text at app launch and retain the
  warmup task until it finishes. A recognition started during warmup waits for
  that one task instead of loading the same path twice. Start ScreenCaptureKit
  shareable-content discovery at launch only when Screen Recording permission
  already exists; prewarming must never trigger the permission prompt. Reuse
  that task for the first capture, otherwise start it during selection. Default
  new settings to fast recognition, and change the pasteboard only once
  recognition has non-empty text. Put only that string on the pasteboard, then
  play the native completion cue.
- **Check:** Extract known text and confirm the pasteboard contains only the
  string, the cue follows the copy, and failure/cancellation leave it unchanged.

## Recognition Recovery And Codes

- **Symptom:** A shortcut capture appears to do nothing, a saved language tag
  breaks later recognition, or a QR code is returned as noisy OCR text.
- **Cause:** Empty results stayed in an invisible service state, Vision received
  unsupported language identifiers unchanged, and only text recognition ran.
- **Invariant:** Capture failures open Text Extractor with a visible error while
  leaving the clipboard unchanged. Unsupported saved languages fall back to
  automatic detection. Fast OCR retries once with Accurate only after an empty
  result. QR codes and barcodes are detected by default and URL results expose
  an Open action; the setting remains optional and preserves older settings.
- **Check:** Run `CoreModelTests`, including the generated high-contrast text and
  QR fixtures. Select text and a QR code from another display, then confirm the
  copied result, history row, Open action, and failure banner.

## Selection Capture Isolation

- **Symptom:** The dim selection overlay appears in the captured image, content
  inside MacPowerToys cannot be extracted, or rapid shortcut presses stack
  selectors.
- **Cause:** The entire host application was excluded to hide its selector,
  and capture sessions were not guarded at the shared service entry point.
- **Invariant:** Selector panels opt out of screen sharing themselves while the
  display capture includes all applications. Only one selection or recognition
  session may run at once. The selector on the display containing the pointer
  owns keyboard focus, including Escape.
- **Check:** Extract content inside and outside MacPowerToys on each attached
  display, press the shortcut repeatedly, cancel with Escape, and confirm one
  selector, an undimmed capture, and restored pointer behavior.

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
