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

- **Symptom:** Title text becomes large, grouped, gains a redundant icon, leaves
  an empty zoom-button gap, or actions differ in size, radius, or focus chrome.
- **Cause:** Native toolbar defaults and locally styled menus bypassed the shared
  titlebar control label, while the title still reserved all three traffic-light
  positions after zoom was hidden.
- **Invariant:** Use the shared custom compact titlebar. Titles are text-only,
  13pt medium and begin 60pt from the left when traffic lights are present.
  Actions are flat, discrete, 24pt high, and use the titlebar-only 6pt radius;
  only the primary action receives accent fill. Compact titlebars have no
  bottom separator.
- **Check:** Inspect initial focus, hover, disabled, and active states in the
  running app. Confirm the title uses the former zoom space and every action
  retains a separate boundary without transient or persistent focus chrome.

## Compact Titlebar Vertical Alignment

- **Symptom:** Compact titlebar items sit too high, the traffic lights feel
  cramped, the app name appears independently padded, the green zoom control
  remains, or an applet can be resized.
- **Cause:** The title used its intrinsic text height while actions used 24pt
  frames inside a taller row, or traffic lights followed a different offset.
- **Invariant:** Use one 40pt titlebar. Apply one 4pt top inset to the complete
  row and no vertical padding to individual row items. Give the title and
  action container equal 24pt frames. They share a 22pt centerline. Move close
  and minimize controls 6pt down to that centerline, hide zoom, and remove the
  resizable window style for every compact applet. Give each applet an explicit
  fixed root frame and use SwiftUI content-size window resizability. Reapply the
  traffic-light offset after delayed layout; never stack relative offsets.
- **Check:** Compare accessibility frame midpoints for the close button, title,
  and actions in every compact applet. They stay within 1pt of window-top +
  22pt. Confirm only close and minimize are visible and manual resizing fails.

## Compact Titlebar Initial Focus

- **Symptom:** A titlebar button or menu opens with an outline that persists
  after the window or control loses focus.
- **Cause:** Only Awake redirected initial focus, and locally styled titlebar
  menus did not consistently disable the SwiftUI focus effect.
- **Invariant:** Every compact applet initially focuses its invisible window
  accessor. Every titlebar button, menu, and switch disables its focus effect
  without disabling keyboard interaction.
- **Check:** Fresh-open Awake, Text Extractor, Ruler, and Color Picker. Before
  interaction and after changing window focus, confirm no titlebar outline is
  visible. Tab to each control and confirm keyboard activation still works.

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
