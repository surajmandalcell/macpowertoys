# UI Chrome Troubleshooting

## Applet Settings Placement

- **Symptom:** A compact applet wastes titlebar space on a settings gear or
  restores settings to the top-right after it was moved.
- **Cause:** An older titlebar rule or shared icon component was treated as the
  source of truth after the product requirement changed.
- **Invariant:** Compact applet titlebars contain the text title and primary
  actions only. A 24pt `gearshape` settings button floats 8pt from the
  bottom-right window edges, remains visible on the settings page, and toggles
  back to the applet's home content.
- **Check:** Inventory compact titlebar actions with `rg`, then open every applet
  that owns settings. Confirm no titlebar gear exists and the floating gear is
  visible, clickable, and 8pt from the bottom-right window edges on home and
  settings pages.

## Compact Titlebar Structure

- **Symptom:** Title text becomes large, rounded, grouped, gains a redundant
  icon, or actions merge into one accented control.
- **Cause:** Native toolbar grouping, system titlebar defaults, or mixed custom
  actions were used without inspecting their rendered result.
- **Invariant:** Use the shared custom compact titlebar. Titles are text-only,
  13pt medium. Actions are flat and discrete; only the primary action receives
  accent fill. Compact titlebars have no bottom separator.
- **Check:** Inspect initial focus, hover, disabled, and active states in the
  running app. Confirm the title and every action retain separate visible
  boundaries without transient focus chrome.

## Compact Titlebar Vertical Alignment

- **Symptom:** Compact titlebar items sit too high, the traffic lights feel
  cramped, the green zoom control remains, or an applet can be resized.
- **Cause:** The custom bar copied the native 32pt centerline while AppKit kept
  its default window controls and resizable style.
- **Invariant:** Use one 40pt titlebar. Center its title and 24pt actions 20pt
  below the window top, leaving 8pt above and below actions. Move close and
  minimize controls 4pt down to that centerline, hide zoom, and remove the
  resizable window style for every compact applet.
- **Check:** Compare accessibility frame midpoints for the close button, title,
  and actions in every compact applet. They stay within 1pt of window-top +
  20pt. Confirm only close and minimize are visible and manual resizing fails.

## Body Gutters and Floating Controls

- **Symptom:** Tabs, cards, fields, or a floating control start on different
  horizontal edges.
- **Cause:** A global inset was assumed without checking the applet's local
  layout token, or label text was aligned instead of the control boundary.
- **Invariant:** Inspect the current applet layout token first. Align tab pill
  boundaries and content surfaces to the same body gutter. Anchor the floating
  settings control 8pt from the bottom-right window edges. Reserve enough
  scroll-bottom space that it never covers the final row or card.
- **Check:** Compare rendered boundaries, not source padding. Scroll to the last
  item and confirm it remains fully readable and clickable above the control.

## Settings Page Replacement

- **Symptom:** Home tabs remain above settings or settings gains a false top
  margin.
- **Cause:** Home navigation was rendered outside the page switch.
- **Invariant:** Settings replaces applet home navigation and begins directly
  below the titlebar. The floating settings control remains available to exit.
- **Check:** Enter settings from every home page, confirm home navigation is
  absent, then toggle back and confirm home state returns.

## Awake Window Controls

- **Symptom:** The Awake window can be enlarged, or `Keep Display On` cannot be
  changed while the selected mode is Passive.
- **Cause:** The scene was freely resizable and the display option was disabled
  whenever Awake was not actively holding a power assertion.
- **Invariant:** Awake has a fixed 560pt by 500pt content size. Its existing
  `Keep Display On` titlebar switch remains configurable in Passive mode; do not
  add a separate titlebar on/off action.
- **Check:** In Passive mode, toggle `Keep Display On` on and off, then drag a
  window edge and confirm the content size remains unchanged.

## Awake Titlebar Appearance

- **Symptom:** Awake opens with a large focus outline around `Keep Display On`,
  a bottom titlebar rule, or a title that lacks the requested emphasis.
- **Cause:** macOS selected the titlebar switch as the first responder, the
  shared titlebar retained a separator, or Awake inherited the default weight.
- **Invariant:** Awake uses a bold 13pt title, no titlebar bottom separator, and
  no transient focus outline around its existing display switch.
- **Check:** Open Awake from a fresh launch and inspect the titlebar before
  interacting with it. Tab to and toggle `Keep Display On` to confirm keyboard
  control still works.
