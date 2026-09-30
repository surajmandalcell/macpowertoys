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
