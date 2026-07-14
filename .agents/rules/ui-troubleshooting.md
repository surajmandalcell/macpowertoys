# UI Troubleshooting

`AGENTS.md` and `CLAUDE.md` both load this file. Update it when a corrected UI
defect is likely to recur. Keep each entry concrete: symptom, cause, invariant,
and a runtime check. Promote stable design values to `DESIGN.md`.

## Selected Controls and Content Gutters

- **Symptom:** A selected tab's background starts left of the fields, cards, or
  rows below it even though the tab label appears aligned.
- **Cause:** The strip gutter was reduced by the tab's internal padding, so the
  label hit the gutter while the visible selected pill crossed it.
- **Invariant:** Align stateful controls by their visible outer boundary. Never
  outdent a selected pill merely to align its inset label.
- **Check:** Inspect the selected state in the running app and compare the
  pill's outer edge with the first content surface below it.

## Handoff Check

- Inspect default, hover, selected, disabled, and settings states in the running
  app when the change touches them.
- Compare adjacent controls by visible frame and text baseline, not source
  padding values.
- Add another entry here when a visual defect recurs or reveals a reusable rule.
