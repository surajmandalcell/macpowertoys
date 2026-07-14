# Text Extractor Request List

Reviewed against the current app source on 2026-07-14. Update this list when a
direct user correction or verified result changes a status.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Create 20 visually different handwritten-loupe icon options in `tmp/textextractor.html`. | The page defines and renders exactly 20 named color and material variants. | None. |
| Done | Use the chosen "Clay Studio" icon in the app. | `TextExtractorLogo.imageset/icon.svg` uses the Clay Studio terracotta, espresso, sand, and handwritten-loupe geometry from the option page. | None. |
| Verify | Fix Text Extractor so region selection, OCR, and automatic clipboard copy work. | `05acf1c` made the overlay panel key, first-responder, and first-click capable. The current service captures with ScreenCaptureKit, recognizes with Vision, records history, and copies to the pasteboard. | Prove selection, recognition, clipboard copy, permission failure, and cancellation end-to-end in the normal installed app. |
| Verify | Put the compact title, shortcut, and primary `Extract Text` action in one consistent titlebar row. | `TextExtractorView` uses the shared 40pt row, 24pt controls, 6pt titlebar radius, 4pt complete-row inset, and one primary accent fill. | Fresh-open the normal build and compare all row midpoints and focus states. |
| Done | Use History as the default body and show `Select text anywhere` only when history is empty. | The history page is the initial state, and `capturePrompt` renders only inside `service.history.isEmpty`. | None. |
| Done | Remove the redundant `Ready` status. | The status banner renders only recognizing and failure states. | None. |
| Done | Open large extracted text in a separate selectable detail view. | `needsExpandedView` routes large rows to `TextExtractionDetailView`, whose text selection is enabled. | None. |
| Done | Move recognition options to their own page. | The floating settings control replaces History with the recognition settings page. | None. |
| Superseded | Put the settings cog beside `Extract Text`, then later at the bottom-left. | The newest correction places settings at the bottom-right edge. | Keep the current bottom-right placement. |
| Done | Put the small settings control at the bottom-right edge in every applicable applet. | Text Extractor and Color Picker use the shared 24pt `FloatingSettingsButton` with an 8pt bottom-right inset. Ruler is already a settings surface; Awake has no separate settings page. | None. |
| Done | Omit seconds from detection timestamps. | `relativeTimestamp` returns `Just now` below one minute and abbreviated coarser units afterward; `CoreModelTests` rejects second-based output. | None. |
| Done | Show exactly one preview line in each history row. | `TextExtractionRow.summary` uses `.lineLimit(1)`. | None. |
| Done | Show a large crosshair while selecting text and restore normal input when selection ends or is cancelled. | The overlay owns the crosshair cursor, draws a 36pt high-contrast crosshair, and closes all selection panels on finish or cancel. | None. |
| Done | Let Escape cancel region selection and close extracted-text detail. | The AppKit selection view handles Escape key code 53; the detail view uses `.onExitCommand`. | None. |
| Verify | Remove compact-titlebar bottom borders and app icons throughout the applets. | The shared `CompactTitlebar` still renders no separator or icon and is used by Text Extractor, Color Picker, Awake, and Ruler. | Confirm the borderless result in all four windows. |
| Verify | Vertically align the complete titlebar row with the traffic lights. | The 40pt titlebar applies one 4pt row inset; titles and 24pt actions use a 22pt centerline, and close/minimize move down 6pt. | Compare rendered midpoints within 1pt in the latest normal build. |
| Verify | Remove the green traffic light, reuse its space for the app name, and prevent resizing. | `WindowAccessor` hides zoom and removes resizing; the title now begins at 60pt instead of reserving the former 84pt three-button span. | Confirm only close and minimize remain, no empty third-control gap remains, and resizing fails. |
| Done | Record the compact-titlebar rules and keep troubleshooting as the first-loaded knowledge base. | `DESIGN.md`, the design tokens, and `spec/troubleshoot/ui-chrome.md` contain the binding chrome rules; `AGENTS.md` loads the troubleshooting index first. | None. |
