# UI Chrome Troubleshooting

## Applet Settings Placement

- **Symptom:** A compact applet wastes titlebar space on a settings gear or
  restores settings to the top-right after it was moved.
- **Cause:** An older titlebar rule or shared icon component was treated as the
  source of truth after the product requirement changed.
- **Invariant:** Compact applet titlebars contain the text title and primary
  actions only. A 24pt `gearshape` settings button floats at the bottom-left of
  applet content, remains visible on the settings page, and toggles back to the
  applet's home content.
- **Check:** Inventory compact titlebar actions with `rg`, then open every applet
  that owns settings. Confirm no titlebar gear exists and the floating gear is
  visible, clickable, and aligned to that applet's body gutter on home and
  settings pages.

## Compact Titlebar Structure

- **Symptom:** Title text becomes large, rounded, grouped, gains a redundant
  icon, or actions merge into one accented control.
- **Cause:** Native toolbar grouping, system titlebar defaults, or mixed custom
  actions were used without inspecting their rendered result.
- **Invariant:** Use the shared custom compact titlebar. Titles are text-only,
  13pt medium. Actions are flat and discrete; only the primary action receives
  accent fill. Preserve applet-specific separator behavior.
- **Check:** Inspect initial focus, hover, disabled, and active states in the
  running app. Confirm the title and every action retain separate visible
  boundaries without transient focus chrome.

## Native Traffic Light Vertical Alignment

- **Symptom:** Compact title text and actions sit below the native traffic
  lights even though they are centered relative to each other.
- **Cause:** Custom controls were centered in the full 40pt titlebar while
  macOS centers traffic lights in the top 32pt control band.
- **Invariant:** Keep the titlebar 40pt high, but center its title and actions
  in the top 32pt band. Leave the remaining space below the controls before the
  optional separator. Sidebar titles already use the native traffic-light
  center and must not receive an extra offset.
- **Check:** Compare accessibility frame midpoints for the close button, title,
  and actions in every compact applet. They stay within 1pt of each other.

## Body Gutters and Floating Controls

- **Symptom:** Tabs, cards, fields, or a floating control start on different
  horizontal edges.
- **Cause:** A global inset was assumed without checking the applet's local
  layout token, or label text was aligned instead of the control boundary.
- **Invariant:** Inspect the current applet layout token first. Align tab pill
  boundaries, content surfaces, and floating controls to the same body gutter.
  Reserve enough scroll-bottom space that the floating control never covers the
  final row or card.
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
