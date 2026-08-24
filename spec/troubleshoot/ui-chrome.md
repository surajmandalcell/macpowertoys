# UI Chrome Troubleshooting

## Tool Icon Tile Template

- **Symptom:** One tool icon has sharper corners, different cutoffs, or a
  different tile silhouette from the other tool icons.
- **Cause:** One SVG appearance bypassed the shared outer tile template, or a
  rendering path trusted asset clipping instead of applying the shared mask.
  A stale installed build can preserve the same defect after source changes.
- **Invariant:** Every active light and dark tool-icon SVG uses a `512 × 512`
  view box, a full-canvas `clipPath id="tile"` rectangle with `rx="112"`, and a
  group that clips the ground and all artwork to that path. This rule applies to
  every tool. Every launcher, sidebar, grid, and tray rendering path also uses
  `toolIconTile(size:)`, with a corner radius of `size × 112 ÷ 512`. No tool,
  appearance, or rendering path is a special case.
- **Check:** Enumerate every active named tool-logo asset and every SVG in each
  asset. The source-template, asset-corner, and shared-renderer tests must pass.
  Confirm the installed source commit equals `HEAD`, then inspect the launcher,
  sidebar, tray, and Dock at normal and small sizes.

## Compact Workspace Hierarchy

- **Symptom:** Workspace sidebars, selected rows, page headings, buttons, and
  option cards look like oversized web controls and hide the primary action.
- **Cause:** New workspaces copied local 22pt scroll-body headers and custom
  card controls instead of the shared compact workspace shell.
- **Invariant:** Use 220pt simple, 240pt data, or 260pt conversation sidebars.
  Use 28pt full-width rows with native emphasized or unemphasized selection;
  labels and SF Symbols use the native selected foreground, while branded icon
  artwork keeps its original colors. Use the shared 40pt page strip, 13pt
  destination title, optional 11pt subtitle, 12pt body inset, native controls,
  related multi-column rows, and one accent primary action.
- **Check:** Inspect launcher, Logs, Cloud Sync, AI History, Input Devices,
  System Care, and System Monitor at default and minimum widths. No workspace has
  a 22pt body title, a second 32pt top gap, or mismatched selected icon and text.

## Workspace Actions And Bottom Status

- **Symptom:** A menu and adjacent button have different visible heights or
  baselines, or a work-status card floats above a large empty area.
- **Cause:** Controls relied on different intrinsic sizes, or a status card was
  appended to scroll content instead of anchored to the content pane.
- **Invariant:** Give every workspace top-strip action the native small control
  size and a shared 24pt minimum height. Put pane-wide work status in one bottom
  safe-area inset. Do not repeat it inside page scroll content.
- **Check:** Inspect every workspace top strip at minimum and default widths.
  Menus and buttons share one centerline. Start System Care work on every page
  and confirm the status stays at the bottom without unused space below it.

## Inline Metadata And Sparse Pages

- **Symptom:** A short category, path, count, kind, time, or total consumes a
  second row, while independent cards occupy one narrow column in a wide pane.
- **Cause:** Every secondary value used a vertical stack, and card groups used
  a fixed single-column layout.
- **Invariant:** Put short related title and metadata pairs in a first-baseline
  row with a 6pt to 8pt gap. Give the primary text truncation priority and keep
  the short secondary value fixed. Use a trailing spacer when the value belongs
  at the far edge. Use an adaptive grid with a 320pt minimum for independent
  cards. Keep help text, errors, previews, commands, and long paths on their own
  lines.
- **Check:** Audit every leading stack with 0pt to 4pt spacing. Inspect launcher
  details, page strips, devices, projects, history, sources, storage rows, and
  sparse settings at default and minimum widths. Wide panes use two columns
  where useful. Narrow panes use one column without clipping.

## Quiet Structural Separators

- **Symptom:** Hairlines divide the interface more strongly than the content.
- **Cause:** Visual `Divider` views used the full native separator strength.
- **Invariant:** Route visual pane, card, row, tab, header, and sheet hairlines
  through `QuietDivider`. Use 0.35 opacity normally and 0.55 with Increased
  Contrast. Keep command-menu and context-menu dividers native.
- **Check:** Search every SwiftUI view for `Divider()`. Only the shared divider
  implementation and native menu or command separators can remain.

## Layout Motion

- **Symptom:** Pages, result sets, status surfaces, or window-height changes
  snap, or Reduce Motion still permits a fade or numeric transition.
- **Cause:** Layout state changed without the shared motion policy, or a local
  animation bypassed the accessibility environment.
- **Invariant:** Use a 0.16-second ease-in-out transition only for layout or
  content changes. Apply the root motion policy to every window and menu-bar
  panel. Reduce Motion makes all state changes immediate.
- **Check:** Change pages and load results in every app family. Repeat with
  Reduce Motion enabled. Normal mode uses short crossfades. Reduce Motion uses
  no movement, fade, pulse, or numeric animation.

## Settings Row Alignment

- **Symptom:** Toggles, pickers, and option groups float in the middle of a card
  or start on different horizontal edges from one row to the next.
- **Cause:** Intrinsic-width controls were placed in a centered stack or grid
  cells retained their default alignment.
- **Invariant:** Settings stacks align leading. A labeled settings row spans the
  card with its control trailing, or every control starts on one shared leading
  grid column. Center only deliberate empty states and hero compositions.
- **Check:** Inspect every settings card and workspace form at default and
  minimum widths. Labels share a leading edge, controls share their row or
  control-column edge, and no compact control floats at the card midpoint.

## Product Copy Boundary

- **Symptom:** A task screen shows implementation tradeoffs, API limits,
  research notes, or text copied from a design conversation.
- **Cause:** Engineering rationale was used as persistent interface help.
- **Invariant:** Task screens show names, values, state, and recovery actions.
  Put a technical limit in About only when it changes a person's decision.
- **Check:** Search visible strings for rationale terms such as `public API`,
  `does not expose`, `not bundled`, `intentionally`, and `never captures`.

## Workspace Traffic-Light Spacing

- **Symptom:** Workspace traffic lights sit off-center, the sidebar title feels
  detached from them, or the search/navigation leaves a second titlebar gap.
- **Cause:** AppKit kept its native 32pt titlebar centerline while the sidebar
  used a 40pt visual strip and a title inset sized only to clear the buttons.
- **Invariant:** Center all three workspace traffic lights at 20pt in the 40pt
  strip. `UtilityLayout` is the single source for the 84pt title leading edge
  and 44pt content top edge, leaving at least 12pt after the zoom button and one
  4pt gap below the strip. Reapply the vertical offset when the window becomes
  key and never move the native horizontal button positions.
- **Check:** In every workspace, compare the top and bottom traffic-light gaps
  and the gap before the title. Unit-check all workspace window identifiers.

## Workspace Sidebar Geometry

- **Symptom:** A sidebar is too narrow for its navigation, rows touch the pane
  edge, or one app invents different title, control, and content offsets.
- **Cause:** A workspace chose local width or padding literals instead of its
  shared sidebar family and layout metrics.
- **Invariant:** Launcher, Logs, and Input Devices use the 220pt compact family;
  Cloud Sync, System Care, and System Monitor use the 240pt data family; AI History
  uses the 260pt conversation family. Navigation groups have 12pt horizontal
  pane padding. All workspace titles and first controls use the shared 84pt and
  44pt edges.
- **Check:** Search the complete workspace class for sidebar width, top padding,
  and title-leading literals. Open all seven sidebars at default and minimum
  sizes; selected rows keep equal left and right pane clearance.

## Launcher Detail Geometry

- **Symptom:** Tool names are small or heavy, Open is undersized, tabs begin on
  the wrong edge, an empty settings page floats in the middle, or a sidebar
  double-click only selects a tool.
- **Cause:** Launcher detail controls used compact defaults and empty settings
  content was allowed to choose its own vertical placement.
- **Invariant:** Launcher detail names are 17pt medium, Open uses regular native
  control size, and the first detail tab uses an 18pt leading inset and a 6pt
  top inset. The Input Devices intro/settings footer is bottom-anchored. A
  double-click on an enabled launcher tool row opens that tool; one click only
  selects it.
- **Check:** Inspect every built-in detail page, then single- and double-click
  launcher rows. Confirm Input Devices keeps its description and menu-bar toggle
  at the bottom with no unused space beneath it.

## Applet Settings Placement

- **Symptom:** A compact applet wastes titlebar space on a settings gear or
  restores settings to the top-right after it was moved.
- **Cause:** An older titlebar rule or shared icon component was treated as the
  source of truth after the product requirement changed.
- **Invariant:** Compact applet titlebars contain the text title and primary
  actions only. A 24pt circular `gearshape` settings button floats 8pt from the
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

- **Symptom:** Compact titlebar items sit too high, traffic lights initially
  align but later jump 6pt upward, the app name appears independently padded,
  the green zoom control remains, or an applet can be resized.
- **Cause:** The title used its intrinsic text height while actions used 24pt
  frames inside a taller row. Separately, AppKit can restore its native 16pt
  traffic-light centerline after the two startup alignment passes.
- **Invariant:** Use one 40pt titlebar. Apply one 4pt top inset to the complete
  row and no vertical padding to individual row items. Give the title and
  action container equal 24pt frames. They share a 22pt centerline. Move close
  and minimize controls 6pt down to that centerline, hide zoom, and remove the
  resizable window style for every compact applet. Give each applet an explicit
  fixed root frame and use SwiftUI content-size window resizability. Reapply the
  traffic-light offset after delayed layout and whenever the window becomes
  key; never stack relative offsets.
- **Check:** Compare accessibility frame midpoints for the close button, title,
  and actions in every compact applet before and after switching focus. They
  stay within 1pt of window-top + 22pt. In the unit seam, restore the native
  16pt centerline after startup, post the key-window transition, and confirm the
  22pt centerline is restored. Confirm only close and minimize are visible and
  manual resizing fails.

## Compact Titlebar Initial Focus

- **Symptom:** A titlebar button or menu opens with an outline that persists
  after the window or control loses focus.
- **Cause:** Only Awake redirected initial focus, and locally styled titlebar
  menus did not consistently disable the SwiftUI focus effect.
- **Invariant:** Every compact applet initially focuses its invisible window
  accessor. Every titlebar button, menu, and switch disables its focus effect
  without disabling keyboard interaction.
- **Check:** Fresh-open Awake, Text Extractor, and Color Picker. Before
  interaction and after changing window focus, confirm no titlebar outline is
  visible. Tab to each control and confirm keyboard activation still works.

## Custom Control Focus Chrome

- **Symptom:** A custom sidebar row, card, icon action, or borderless menu shows
  a large blue rectangular outline that does not match its shape.
- **Cause:** A plain or borderless SwiftUI control kept the default focus effect
  after it replaced the native control surface.
- **Invariant:** Every custom plain and borderless button or menu disables only
  its focus effect. Keep the control focusable, named, and keyboard-operable.
  Native text fields and standard controls keep their native editing state.
- **Check:** Search every SwiftUI source for plain and borderless button styles.
  Each custom control must apply `focusEffectDisabled()`. Tab through every
  window, sheet, popover, and sidebar. Confirm no blue rectangular outline and
  confirm that Return or Space still activates each control.

## Compact Applet Window Height

- **Symptom:** Every compact applet has a 32pt material strip below its fixed
  root, leaving a bottom-right floating control 40pt above the window edge.
- **Cause:** SwiftUI composites a hidden-titlebar window with the native 32pt
  titled-frame height below its fixed root. Because the root ignores the top
  safe area, the surplus appears below it. `NSWindow.frame` and Accessibility
  can report only the root height, so clamping that logical frame does not move
  the visible bottom edge.
- **Invariant:** Position bottom overlays through the composited surplus using
  the native titled-frame height from `NSWindow.frameRect`, rather than trusting
  the logical window frame or repeatedly resizing the window.
- **Check:** Screenshot the installed window itself, not only its Accessibility
  bounds. On Color Picker and Text Extractor, the 24pt settings button must be
  8pt from the visible material's bottom and right edges on both pages.

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

## Thin Scroll Indicators

- **Symptom:** A scrollable view reserves a thick track or shows a full-size
  indicator while the rest of the app uses thin overlay scrollbars.
- **Cause:** A visible `ScrollView`, `Form`, `TextEditor`, or AppKit
  `NSScrollView` bypassed the shared thin-indicator configuration.
- **Invariant:** Every SwiftUI `ScrollView`, `Form`, `TextEditor`, `List`, and
  `Table` uses `.thinScrollIndicators()`. Native scroll views call
  `configureThinScrollIndicators()`. Never hide an indicator.
- **Check:** Inventory every scrolling source with `rg`. The surface count must
  equal the shared-modifier count, and `showsIndicators: false` must be absent.
  Exercise long content in every app family, sheet, editor, and horizontal
  strip. Indicators autohide, overlay content, and use mini control size.

## Workspace Pane Seams

- **Symptom:** A line or clear-looking gap appears between a workspace sidebar
  and its body.
- **Cause:** A workspace root inserted a divider between two panes that already
  meet with zero stack spacing.
- **Invariant:** Workspace roots place the sidebar and opaque body directly next
  to each other in a zero-spacing stack. Do not add a divider or spacer at the
  pane boundary.
- **Check:** Inspect every sidebar workspace root. The sidebar and body are
  adjacent, and no window background appears between them.

## Settings Page Replacement

- **Symptom:** Home tabs remain above settings or settings gains a false top
  margin.
- **Cause:** Home navigation was rendered outside the page switch.
- **Invariant:** Settings replaces applet home navigation and begins directly
  below the titlebar. The floating settings control remains available to exit.
- **Check:** Enter settings from every home page, confirm home navigation is
  absent, then toggle back and confirm home state returns.

## Global Shortcut Recording

- **Symptom:** Recording Command-Shift-3 appears as `⇧⌘#`, or displays correctly
  but macOS takes the screenshot and the app action never runs.
- **Cause:** `charactersIgnoringModifiers` preserves Shift for number-row keys.
  Separately, macOS reserves Command-Shift-3 through its screenshot service, so
  a normal Carbon hotkey cannot reliably override it.
- **Invariant:** Every custom shortcut flow uses `ShortcutRecorderField`, which
  normalizes number-row key codes to `0` through `9` before persisting and
  displaying the shortcut. Color Picker defaults to `⇧⌘3`; Text Extractor
  defaults to `⇧⌘2`. Reserved screenshot chords use a suppressing session event
  tap. When Accessibility permission is missing, show an explicit access action
  beside the recorder instead of silently accepting a nonfunctional shortcut.
- **Check:** Feed the shared recorder a Command-Shift key event whose characters
  contain the shifted symbol and confirm its shortcut retains the physical
  number label. Then record shortcuts in both applet settings pages and invoke
  Command-Shift-3 from another app. Color Picker must open without taking a
  screenshot.

## Awake Window Controls

- **Symptom:** The Awake window can be enlarged, the off state is exposed as
  `Passive`, or `Keep Display On` cannot be changed while Awake is off.
- **Cause:** The scene was freely resizable and the display option was disabled
  whenever Awake was not actively holding a power assertion.
- **Invariant:** Awake has a fixed 560pt by 500pt content size. The persisted
  internal `.passive` case is always labeled `Off` in user-facing copy. Its
  existing `Keep Display On` titlebar switch remains configurable while off;
  do not add a separate titlebar on/off action. The tray's four modes fill the
  available width at regular native control size.
- **Check:** With Off selected, toggle `Keep Display On` on and off, confirm all
  four tray segments share the available width, then drag a
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
