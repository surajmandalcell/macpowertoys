# UI Troubleshooting

`AGENTS.md` and `CLAUDE.md` both load this file. Update it when a corrected UI
defect is likely to recur. Keep each entry concrete: symptom, cause, invariant,
and a runtime check. Promote stable design values to `DESIGN.md`.

## Tab Strips and Content Gutters

- **Symptom:** The leading selected tab's background starts left of the fields,
  cards, or rows below it even though the tab label appears aligned.
- **Cause:** The strip gutter was reduced by the tab's internal padding, so the
  label hit the gutter while the visible selected pill crossed it.
- **Invariant:** Align the tab strip by its leading pill boundary. Never outdent
  the strip merely to align inset label text, and never move tabs on selection.
- **Check:** Inspect every selected state in the running app. Compare the
  leading pill boundary with the first content surface and confirm tab frames
  do not move when selection changes.

## Handoff Check

- Inspect default, hover, selected, disabled, and settings states in the running
  app when the change touches them.
- Compare adjacent controls by visible frame and text baseline, not source
  padding values.
- Add another entry here when a visual defect recurs or reveals a reusable rule.
