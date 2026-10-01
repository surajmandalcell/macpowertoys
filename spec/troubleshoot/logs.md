# Logs Troubleshooting

## Internal and System Log Boundaries

- **Symptom:** Product logs and macOS diagnostics appear as one undifferentiated
  stream, or opening Logs caches a large slice of the unified log.
- **Cause:** One viewer and persistence policy were applied to unrelated log
  sources.
- **Invariant:** Logs exposes visibly separate Internal Logs and System Issues
  sources. Internal Logs retain the app's level filters and persistence rules.
  System Issues reads only macOS errors and faults on demand for an explicit
  time range, keeps at most 500 lightweight rows in memory, and never persists
  them through `LogManager` or SwiftData.
- **Check:** Open Internal Logs and verify its level filters and Clear action.
  Switch to System Issues, refresh each time range, confirm only errors/faults
  appear newest-first, then close and reopen Logs and confirm system rows are
  fetched again rather than restored from app storage.

## Shared Table Column Geometry

- **Symptom:** Long Source text meets Message text, and table headings do not
  align with record text in either appearance.
- **Cause:** Logs did not pass the new shared column models to the native table
  skin or its cells. The header and body therefore used different insets.
- **Invariant:** Define each column once. Pass those models to
  `onePlusNativeTable(columns:)` and apply `onePlusTableCell(_:position:)` to
  every cell. Keep 12pt adjoining insets, a 116pt Time column, and a 215pt
  Source column. Give Level a fixed glyph lane and the same header label inset.
  Truncate Source in its padded bounds. Keep full text in the detail sheet.
- **Check:** The shared column geometry regression checks header and cell
  origins in both appearances. Run it on hosted CI. Compile the desktop targets
  without launching them on the owner's session.
  Recapture long system sources and Warning rows in the signed installed app.
  Confirm 24pt text clearance and heading alignment. The separate 1pt System
  Issues appearance offset remains shared native table work.


## Embedded settings rows, 2026-10-01

- **Symptom:** Main window > Logs > Settings gives Retention and System
  issues caption-size titles and values above the row center.
- **Cause:** Two custom stacks wrap `OnePlusKeyValueRow`, whose label is a
  caption and whose minimum height is 28pt, beside another caption line.
- **Invariant:** Both settings hosts use the same `LogsSettingsView`.
  Retention and System issues use `OnePlusSettingRow` with a title and a
  trailing value. Help uses the shared glyph tooltip, following the owner's
  density correction. Retention reads `LogManager.retentionDays`. The final
  row has no separator. The content owns only its grouped settings card.
- **Check:** Both installed baseline appearances reproduce the defect at
  `tmp/redesign/captures/r9/main/tool_logs-{dark,light}.png`. Source now uses
  the shared rows. The orchestrator must recapture the installed fix and
  check title size, vertical centers, trailing edges, and help tooltips.

## Horizontal density and instant changes, 2026-10-01

- **Symptom:** Counts and date ranges consume a second header line; settings
  explain their policies inline; loading and empty views sit in empty cards.
- **Cause:** Metadata and help were treated as stacked content, and cards
  wrapped single states rather than groups of records.
- **Invariant:** Counts and ranges trail the source filter on its page row.
  Detail source text trails its label and wraps without truncation. Settings
  help and the system read limit use glyph tooltips. Only the table and
  grouped settings keep cards. Logs owns no animation or transition; shared
  controls must apply the current DESIGN.md instant color-only feedback.
- **Check:** Source contains no local motion modifiers. The orchestrator
  must inspect both appearances, long ranges and sources, empty/loading
  states, hover, press, and page switches on the installed current build.

## Reads, startup loading, retention, and export, 2026-10-01

- **Symptom:** Leaving System issues cancels its owner but its detached read
  continues. Startup loading replaces entries created while the store loads.
  A save failure drops the pending batch. Retention runs only at startup.
  Export writes on the main actor and reports failures only in internal logs.
- **Cause:** Detached cancellation is not forwarded. Loading assigns the old
  snapshot. Persistence ignores errors. Export uses a blocking modal panel.
- **Invariant:** Forward cancellation to the detached system read, cancel on
  page exit, and discard system rows on window close. Merge persisted and
  current internal entries by identity and retain the newest 1,000. Failed
  saves roll back and retain their batch for the next flush. Surface storage
  errors. Prune at startup and after successful flushes without an idle
  timer. Source, search, and level filters compose. Export uses a sheet and
  an atomic utility-task write with a visible failure alert. Detail source
  and message text stay selectable in a bounded native scroller.
- **Check:** Source-derived shell checks pass merge, filtering, and retention.
  Real unified-log reads pass all three ranges, ordering, and the 500-row cap.
  Detached cancellation passes with the fix and fails when forwarding is
  removed. Focused XCTest regressions cover these paths and an in-memory
  SwiftData round trip. Hosted execution and signed interaction remain open.
