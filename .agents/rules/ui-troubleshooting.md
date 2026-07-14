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

## Titlebar Actions Merging

- **Symptom:** Plain text, primary, and icon actions appear as one continuous
  accented pill in the titlebar.
- **Cause:** Mixed-style controls were nested inside one `ToolbarItem`, so the
  toolbar treated the entire view as one semantic action.
- **Invariant:** Put one semantic action in each `ToolbarItem`. Never wrap mixed
  plain, prominent, and icon actions in one titlebar `HStack`; only the primary
  action receives the accent fill.
- **Check:** Inspect default, hover, disabled, and active states in the running
  app. Every action keeps a separate visible boundary and hit target.

## Compact Titlebar Chrome

- **Symptom:** A tool title has a redundant icon, a line appears under the
  titlebar, or a button gains an outline when the window opens.
- **Cause:** Decorative title content and a divider were added to the shared
  titlebar, or a raw titlebar button retained the system focus effect.
- **Invariant:** Compact titlebars contain a text-only title, no bottom
  separator, and only custom actions with their focus effect disabled.
- **Check:** Open every compact tool and inspect the initial focused state plus
  hover. Confirm there is no title icon, separator, shared pill, or focus ring.

## Settings Replacing Home Navigation

- **Symptom:** Homepage tabs remain visible above Settings, creating a false
  top margin and implying those tabs belong to the settings hierarchy.
- **Cause:** Navigation was rendered outside the page switch, so it appeared on
  every page.
- **Invariant:** Homepage navigation renders only for home pages. Settings
  replaces it and begins directly below the titlebar without top padding.
- **Check:** Open Settings from each home tab, confirm all home tabs disappear,
  then close Settings and confirm the prior home navigation returns.

## Handoff Check

- Inspect default, hover, selected, disabled, and settings states in the running
  app when the change touches them.
- Compare adjacent controls by visible frame and text baseline, not source
  padding values.
- Add another entry here when a visual defect recurs or reveals a reusable rule.
