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
