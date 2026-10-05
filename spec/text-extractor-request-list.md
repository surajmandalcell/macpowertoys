# Text Extractor Request List

Round 17 applet correction, run 68, 2026-10-01: OnePlusUI `a02d43d`
restores the 40pt row and C22. The title and Extract Text action share
that center; its 24pt frame spans y10..34. Untabbed content starts at
y56. All 21 focused package checks pass in both appearances at 1x/2x.
The app and test bundles compile. The orchestrator must tag and adopt
OnePlusUI, then verify signed History, Settings, and action states.
Report: `tmp/redesign/logs/w10-fix17-applets.md`.

Scroll edges, 2026-10-01: the shared floating gear overlays the full body.
Its 52pt reserve is inside scroll content. History reaches the card's bottom;
Settings reaches the window bottom. All 15 focused package checks pass,
including both gear states at the applet's minimum and maximum heights.
The four old-source regressions fail. Signed scrolling and gear interaction
remain with the orchestrator. Report: `tmp/redesign/logs/w4-scroll-edges.md`.

Round 48 header picks, 2026-10-01: `bd2e0963` implements Inset B
(close x13, title 14pt after zoom) and Top B (title caps, icons, and action
tops at y20). Applet and sheet header rows are 44pt; applet lights use C=27.
Header switches retain their 24pt hit frame with the capsule at the top.
The body moves down 4pt with its existing gaps. Offscreen render and native
geometry checks pass (42 checks) in both appearances at 1x/2x. One
app/test compile gate passes. Cap strokes allow one physical pixel for
antialiasing; action frames are exact. Signed pixel captures
and real light hover remain with the orchestrator after installation.
Report: `tmp/redesign/logs/w4-chrome.md`.

Reviewed against the current app source on 2026-08-31. Update this list when a
direct user correction or verified result changes a status.

Window performance: signed `198055e4` History measured 326ms in the
orchestrator replay and 282ms on a later changed-page replay. The wait profile
found a shared launcher Login Items query after unrelated defaults writes.
`da3146a3` filters these writes and moves the query off the main thread.
The actual preference-observer check and both compile gates pass. No Text
Extractor view changed. Signed after timings and complete first/late frames
remain; open <=250ms and page <=100ms stay open. Exact commands and evidence:
`tmp/redesign/perf/w1-windows.md`.

## Round 11 audit, 2026-10-01

| Status | Task | Evidence | Remaining work |
|---|---|---|---|
| Source fixed | T075: Fit ordinary Settings and remove duplicate titlebar chrome. | `df0a2f5a` uses a plain shortcut heading and one switch/160pt recorder row, includes languages in Recognition, and places 28pt Clear history 8pt below. `b8fc89fa` supplies the 160pt quality-segment width. Native font metrics give 336pt of the 354pt content budget. Extract Text keeps chord help. | Signed Settings in both hosts; scroll extra permission/error content. |
| Source fixed | T077: Keep separators within 44pt history rows. | `8fa61fbd` draws 1pt bottom overlays inside rows. | Signed row centers, actions, hover, and scrolling. |
| Measured; timing change rejected | T079: Measure the existing one-shot OCR warmup. | Fresh-process generated-image Fast OCR takes 630ms cold and 31ms after warmup. RSS after extraction is 43.9MiB cold and 52.5MiB warm. Background warmup takes 47.1s; an immediate extraction in the later fresh process takes 457ms. Fixture setup takes 71ms cold and 24ms warm. OS caches affect these comparisons. Display discovery is excluded. | Retain current prewarm because its measured recognition gain is material. Signed app launch/footprint and real extraction checks remain with the orchestrator. No permission request is made. |
| Source fixed | T080: Undo history deletion and clearing. | `b8fc89fa` registers named inverses with the owning window UndoManager. Native fixture checks restore order and records, retain later arrivals, redo only affected records, and persist results. Confirmation remains. | Hosted AppletHistoryUndoTests and signed Edit menu/confirmation checks. |

## Production audit, 2026-10-01

Both shared build modes pass for the Debug app and both desktop test bundles.
The new regression tests compile. Hosted tests and signed checks remain open.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Highlight each full extraction row, including actions and gutters. | `8252798d` uses the shared row hover helper on the outer HStack. The full-row surface remains in the compact 44pt layout from `c03f046d`. | Verify row hover, preview truncation, Copy, Open link, Delete, and keyboard focus in both appearances. |
| Verify | Keep only Extract Text in the titlebar and edit shortcuts in Settings. | `df0a2f5a` removes the duplicate titlebar menu. Settings keeps enablement and recording; Extract Text remains a 24pt primary action with chord help. | Verify toggle, settings navigation, recording, chord help, and disabled extraction states in the signed app. |
| Verify | Audit permission recovery, region selection, Escape, multi-display coordinates, OCR quality and fallback, languages, codes, clipboard-before-cue ordering, history, detail, links, persistence, and settings. | All service and view paths were traced. Source-derived URL, timestamp, detail-threshold, and legacy-settings checks passed. Existing History was captured without activation. No capture or user-data mutation was performed. Existing CoreModelTests cover injected permission, private pasteboard, generated OCR, QR, and language seams. | Run tests on CI. Current-source installation, real selection, cue, permission recovery, and history interactions belong to the orchestrator. S5 and A4-A7 remain open. |
| Verify | Apply the horizontal density and instant-motion correction. | `c03f046d` removes repeated Screen selection provenance and the Languages and History control cards. History rows are 44pt with trailing timestamps. Help uses tooltips and content animation is disabled. The source-derived compact height check passes. | Review both pages, short and long previews, help, settings controls, and instant hover after installation. |


## OnePlusUI redesign, 2026-09-29

Round 3a uses one cards-only TextExtractorSettingsView. The applet supplies
OnePlusPage; the launcher supplies its existing page, gutters, and scrolling.

Round 3 keeps capture status and the History heading fixed. Only extraction
rows scroll. Row timestamps and detected links are prepared off the main actor.

Round 5 uses one history card with 1pt separators and centers timestamps with
row actions. Destructive history clearing now lives in Settings with a native
confirmation. The titlebar Extract Text action is 24pt.

Round 6 starts History 16pt below the titlebar. Pure timestamp and URL helpers
are nonisolated, so cached row preparation stays off the main actor without
concurrency warnings.

Round 2 requires neutral shortcut hints, equal 16pt Settings gutters,
and a protected floating settings area on both pages.

Round 2 verification: Debug and build-for-testing pass with shared fixes B
and I. Tests were compiled, not executed. Signed screenshot review remains.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Preserve full History row width in light appearance and fill the shortcut column. | Signed `8cf8c02` round 4 captures show equal 16pt outer gutters. Light History retains a 17pt inner reservation despite the shared scroll modifier. The shared recorder still paints a 116pt bezel with mono type. | Foundation must fix nested native clip/document width and supply the fill-width control-role recorder. Recapture both pages and verify scrolling and recording. |
| Verify | Use one history list card and keep destructive clearing in Settings. | History rows share one `OnePlusCard` and stable ids. Settings owns the Clear history row and confirmation. | Verify row alignment, scrolling, and clearing in the signed build. |
| Verify | Keep Text Extractor status and the History heading fixed while rows scroll. | The history page owns one row-only `ScrollView`. Lightweight rows receive prepared timestamps and links instead of observing the complete service. | Verify smooth scrolling and page switches within 100ms in the signed build. |
| Verify | Embed one shared settings view without nested scrolling or gutters. | `TextExtractorSettingsView()` owns a direct shortcut row, the multi-row Recognition card including languages, and a direct Clear history action. The applet supplies OnePlusPage with 16pt gutters. The permission notice remains visible when needed. Build verification is recorded per round above. | Verify embedded and applet Settings in the signed build. |
| Verify | Keep the floating settings button clear of History and Settings. | Round 2 applies the shared 52pt body inset before the gear overlay and removes the old inner 44pt padding. The gear keeps its 8pt edge inset and Command-comma action. | Verify both pages and their scroll limits in the next signed capture. |
| Verify | Keep Settings cards full width inside equal 16pt gutters. | Round 2 explicitly expands the settings stack before the body insets. Shared fix B removes the scroller gutter. Both compile checks pass. | Inspect both appearances in the next signed capture. |
| Verify | Use the 480pt applet with 270 to 462pt height, persistent Extract Text, history preview/time/copy, and replacing Settings with shortcut and language rows. | Debug build passes. DESIGN.md v14 supersedes the older material and two-light rules below. Routes are `history` and `settings`. | Review both appearances, capture states, and recognition controls in the orchestrator's installed build. |

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Remove the 10–30 second cold extraction delay and eliminate the lagging second selection cursor. | Live signed verification found that the old blank-image warmup still left the first extraction at 25.2 seconds. A fresh Accurate + automatic-language + barcode Vision request then reproduced the real cold load at 31.048 seconds. `954081d` now runs that configured request against representative generated text at app launch, retains and awaits the one warmup task, and prewarms ScreenCaptureKit only after permission already exists. The exact signed installed build contains no `.mlmodel`, `.mlmodelc`, or `.mlpackage`, produced real history entries, and settled near 49 MB RSS after warmup. The event-redrawn second crosshair is replaced by one compositor-driven AppKit cursor. | None. |
| Done | Make Text Extractor fast and reliable for ordinary small UI text. | `67d148f` passes the native screen scale through capture, avoids the unconditional redraw, caches Vision language support, runs barcode and text recognition in one handler pass, and applies Lanczos/contrast/sharpening only below 2x density. The new 1x regression failed on the old pipeline and now passes in 0.014 seconds; focused unsupported-language, QR, and enhancement checks pass in 0.078, 0.060, and 0.037 seconds. | None. |
| Done | Choose no Text Extractor menu item, the combined popover, or a separate icon. | The shared launcher selector stores None, Combined, or Separate. Focused tests cover each mode, the exact `MacPowerToys.text-extractor` autosave name, the Extract Text route, disabled state, legacy migration, combined-tab support, and no-op item refresh. | None. The shared five-tool physical placement, relaunch, and click matrix remains in the main request list. |
| Done | Keep extraction times on the related text row and reduce row height. | The signed `4662560` build showed short and long history text in compact rows. Each time stayed on its text row. Long text truncated before the time and action controls. | None. |
| Done | Create 20 visually different handwritten-loupe icon options in `tmp/textextractor.html`. | The page defines and renders exactly 20 named color and material variants. | None. |
| Superseded | Use the selected "Cobalt 051" icon in the app. | The earlier loupe icon was replaced by the 2026-09-25 icon refresh request. | The new icon row below owns the current result. |
| Superseded | Use the new Text Extractor capture-card icon. | The owner requested ten new Text Extractor icon choices on 2026-09-25. | Replaced by the selected T01 Scan beam below. |
| Verify | Use T01 Scan beam as the Text Extractor icon. | The app and Raycast PNGs match the owner's original T01 file byte for byte. Hosted run `36124794622` passed and shows it at native launcher size in dark and light. | Verify Dock display in the final signed installed app when desktop interaction is available. |
| Done | Fix Text Extractor so region selection, OCR, automatic clipboard copy, blank-selection recovery, and cancellation work. | In the signed `4662560` build on two displays, two consecutive selections copied recognized text and added the same text as the first history row. Escape returned in 1.56 seconds and did not change the clipboard. A blank region showed a clear error, kept the history count unchanged, and did not change the clipboard. | None. |
| Done | Show the correct recovery path when Screen Recording permission is denied. | `9bd56e2` gives permission denial a typed recovery state. Text Extractor opens instead of starting selection and shows the Privacy Settings action. The denial and cancellation tests inject both results without changing the user's macOS permission and verify the distinct recovery paths. | None. |
| Done | Make OCR feel immediate, never stage the screenshot on the clipboard, and play a cue after recognized text is copied. | In the signed `4662560` build, the two recognition runs completed 1.55 seconds and 0.59 seconds after release. The pasteboard contained only `NSStringPboardType` and `public.utf8-plain-text`. `4662560` loads the system Tink file directly, the sound loaded and accepted playback, and the unit seam proves that playback follows the text copy. | None. |
| Done | Put the compact title and primary `Extract Text` action in one consistent titlebar row. | `TextExtractorView` uses the shared 40pt row, 24pt controls, 6pt titlebar radius, 4pt complete-row inset, and one primary accent fill. The normal signed `98f35f6` build showed one aligned row without a launch outline. | None. |
| Done | Use History as the default body and show `Select text anywhere` only when history is empty. | The history page is the initial state, and `capturePrompt` renders only inside `service.history.isEmpty`. | None. |
| Done | Remove the redundant `Ready` status. | The status banner renders only recognizing and failure states. | None. |
| Done | Open large extracted text in a separate selectable detail view. | `needsExpandedView` routes large rows to `TextExtractionDetailView`, whose text selection is enabled. | None. |
| Done | Move recognition options to their own page. | The floating settings control replaces History with the recognition settings page. | None. |
| Done | Put the small settings control at the bottom-right edge in every applicable applet. | Text Extractor and Color Picker use the shared 24pt `FloatingSettingsButton` with an 8pt bottom-right inset. Awake has no separate settings page. | None. |
| Done | Omit seconds from detection timestamps. | `relativeTimestamp` returns `Just now` below one minute and abbreviated coarser units afterward; `CoreModelTests` rejects second-based output. | None. |
| Done | Show exactly one preview line in each history row. | `TextExtractionRow.summary` uses `.lineLimit(1)`. | None. |
| Done | Show a large crosshair while selecting text and restore normal input when selection ends or is cancelled. | The overlay owns the crosshair cursor, draws a 36pt high-contrast crosshair, and closes all selection panels on finish or cancel. | None. |
| Done | Let Escape cancel region selection and close extracted-text detail. | The AppKit selection view handles Escape key code 53; the detail view uses `.onExitCommand`. | None. |
| Done | Remove compact-titlebar bottom borders and app icons throughout the applets. | The shared `CompactTitlebar` renders no separator or icon and is used by Text Extractor, Color Picker, and Awake. The normal signed `98f35f6` build confirmed the borderless result in all three windows. | None. |
| Done | Vertically align the complete titlebar row with the traffic lights. | The 40pt titlebar applies one 4pt row inset; titles and 24pt actions use a 22pt centerline, and close/minimize move down 6pt. `WindowAccessor` reapplies the alignment on every key-window transition; regression coverage forces a late AppKit reset and verifies recovery. | None. |
| Done | Remove the green traffic light, reuse its space for the app name, and prevent resizing. | `WindowAccessor` hides zoom and removes resizing; the title begins at 60pt instead of reserving the former 84pt three-button span. Unit coverage and the normal signed `98f35f6` accessibility tree confirmed fixed two-light chrome with reclaimed title space. | None. |
| Done | Record the compact-titlebar rules and keep troubleshooting as the first-loaded knowledge base. | `DESIGN.md`, the design tokens, and `spec/troubleshoot/ui-chrome.md` contain the binding chrome rules; `AGENTS.md` loads the troubleshooting index first. | None. |
| Done | Use quiet settings dividers and animate page, status, history, and height changes without ignoring Reduce Motion. | The normal signed `d1cf9e2` build confirmed quiet dividers and compact controls in populated History and Settings. Text Extractor uses the shared transition and window-height policy for every status. The Reduce Motion regression test passes. | None. |
