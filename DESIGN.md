---
version: 15
name: MacPowerToys
description: Design language for MacPowerToys and its child tools (OnePlusUI)
appearance: { default: dark, options: [dark, light, automatic] }
colors:
  window: { dark: "#161616", light: "#F5F5F5" }
  sidebar: { dark: "#1D1D1D", light: "#E7E7E7" }
  panel: { dark: "#202020", light: "#FAFAFA" }
  table-alternate: { dark: "#242424", light: "#F2F2F2" }
  panel-hover: { dark: "#262626", light: "#FFFFFF" }
  raised: { dark: "#292929", light: "#FFFFFF" }
  raised-hover: { dark: "#303030", light: "#F0F0F0" }
  pressed: { dark: "#252525", light: "#E4E4E4" }
  field: { dark: "#252525", light: "#F2F2F2" }
  field-focus: { dark: "#2B2B2B", light: "#EAEAEA" }
  track: { dark: "#181818", light: "#E4E4E4" }
  selection: { dark: "#343434", light: "#D4D4D4" }
  selection-inactive: { dark: "#292929", light: "#E0E0E0" }
  selected-control: { dark: "#424242", light: "#FFFFFF" }
  line: { dark: "#343434", light: "#D1D1D1" }
  line-soft: { dark: "#2B2B2B", light: "#E1E1E1" }
  ink: { dark: "#EDEDED", light: "#242424" }
  secondary: { dark: "#C8C8C8", light: "#4B4B4B" }
  muted: { dark: "#BCBCBC", light: "#565656" }  # at least 4.5:1 on every fill
  metric-caption: { dark: "#A0A0A0", light: "#5B5B5B" }
  control-ink: { dark: "#DEDEDE", light: "#343434" }
  accent: { dark: "#EE5B50", light: "#D94F45" }
  data-blue: { dark: "#8AAEEA", light: "#3564A4" } # RSync UI progress and network data
  accent-primary-ink: { dark: "#FFFFFF", light: "#FFFFFF" }
  accent-primary-hover: { dark: "#E65A4F", light: "#D34E44" }
  accent-primary-pressed: { dark: "#DE584E", light: "#CD4D43" }
  primary-fill: { dark: "#DDDDDD", light: "#383838" }
  primary-ink: { dark: "#252525", light: "#FFFFFF" }
  ok: { dark: "#7FA889", light: "#3F7A4E" }
  warn: { dark: "#FFC09A", light: "#74390F" }
  danger: { dark: "#FFB6AC", light: "#872E25" }
  danger-fill: { dark: "#382624", light: "#FBE9E7" }
  danger-line: { dark: "#6D4541", light: "#E3B3AD" }
  temperature-warm: { dark: "#F2C94C", light: "#A67C00" }     # CPU 56-69 °C
  temperature-hot: { dark: "#F59A4A", light: "#CC610C" }      # CPU 70-84 °C
  temperature-very-hot: { dark: "#FF7466", light: "#D03A2C" } # CPU 85-94 °C
  temperature-critical: { dark: "#FF3B30", light: "#9A1717" } # CPU 95 °C and up
  fan-tile: { dark: "#3A82D6", light: "#2F7FD8" }             # Fan page icon tile, white glyph
high-contrast:
  ink: { dark: "#FFFFFF", light: "#000000" }
  secondary-and-muted: { dark: "#DADADA", light: "#444444" }
  metric-caption: { dark: "#DADADA", light: "#444444" }
  control-ink: { dark: "#FFFFFF", light: "#000000" }
  warn: { dark: "#FFE0C0", light: "#6B3208" }
  danger: { dark: "#FFCCC6", light: "#792820" }
  line: { dark: "#A0A0A0", light: "#707070" }
  line-soft: { dark: "#919191", light: "#777777" }
  danger-line: { dark: "#E99B91", light: "#872E25" }
  focus: { dark: "#C0C0C0", light: "#505050" }
  selection: { dark: "#3D3D3D", light: "#C8C8C8" }
  selection-inactive: { dark: "#2B2B2B", light: "#DDDDDD" }
typography:
  regular: { sidebar-title: 12.5, nav: 12.5, caption-upper: 9, page-title: 24, subtitle: 12.5, tab: 12, section-title: 13, card-title: 12, row: 12, control: 12, caption: 10.5, metric-caption: 10.5, table-header: 9, mono: 11, metric: 27, unit: 12 }
  compact: { sidebar-title: 12.5, nav: 11.5, caption-upper: 9, page-title: 20, subtitle: 10.5, tab: 11, section-title: 12, card-title: 11, row: 10.5, control: 10.5, caption: 9.5, metric-caption: 9.5, table-header: 8.5, mono: 9.5, metric: 27, unit: 10 }
  metric: { weight: 550, line-height: 30.24 }
rounded: { segment: 3, nav-row: 5, icon-button: 5, control: 6, menu-tile: 6, card: 8, window: 13 }
spacing: { scale: [2, 4, 6, 8, 10, 12, 16, 20, 24, 28], gutter: 24, card-gap: 16, card-padding: 16, content-top: 20 }
geometry:
  title-row: 54
  centerline: 27            # traffic lights and sidebar title only
  content-top: 20           # title paint and header control tops (Top B); sidebar content starts at 54
  applet-titlebar: 40
  applet-centerline: 22
  traffic-light-leading-inset: 13
  sidebar-title-gap-after-zoom: 14
  search: { height: 32, inset-x: 12, below: 14 }
  nav-row: { regular: 32, compact: 29, gap: 2, container-inset: 10, padding: 10, icon: 15, icon-gap: 10 }
  card-header: 40
  table: { header: 33, row: 34 }
  setting-row: 44
  control: { height: 28, compact-height: 24, column: 160, wide-column: 180, stepper-width: 160 }
  tab-strip: { height: 36, gap: 22, underline: 2 }
windows:
  main: { size: [820, 660], sidebar: 215, density: regular, resizable: false, sidebar-icon: 16, row-icon: 24, hero-icon: 48 }
  rclone: { size: [1240, 840], sidebar: 216, density: regular, resizable: false }
  mac-tweaks: { size: [820, 660], sidebar: 200, density: regular, resizable: false }
  logs: { size: [1080, 660], sidebar: 200, density: regular, resizable: false }
  input-devices: { size: [820, 660], sidebar: 200, density: regular, resizable: false }
  color-picker: { width: 420, height: [250, 460], applet: true }
  text-extractor: { width: 480, height: [270, 462], applet: true }
menu-panel: { status-icon: 14, status-icon-ink: 11.2, width: 356, max-height-fraction: 0.9 }
popup-menu: { padding: 5, radius: 7, item: 28, item-compact: 24, item-radius: 4, item-padding: 9, max-visible-items: 12 }
performance: { page-switch-ms: 100, table-rows-smooth: 1000 }
---

# MacPowerToys Design Language

The complete visual and window-structure contract for every window, menu-bar
panel, sheet, and settings page. Tool icon rules are in `spec/icons.md`.
Version 15 (Linear style, owner picks 2026-11-16 to 2026-11-19) covers every
window, menu-bar panel, sheet, and applet.

## Sources of truth

1. The owner's newest direct instruction.
2. This file.
3. The `OnePlusUI` package (`surajmandalcell/oneplus-ui`, checkout
   `../oneplus-ui`, consumed by exact version tag). A view never restyles a
   OnePlusUI component locally; add a named variant to the package.
4. Reference renders in `docs/design/v15/`; screenshots in
   `docs/screenshots/`.

## Version 15 picks

All shipped; the rules live in the sections below.

- Style "Linear": 13 pt body, compact rows, quiet 1 pt borders, no window
  texture, one coral accent.
- Main window "Editorial list", "Launch tile" header with the "Key tile",
  "Checklist" How to use, "Raised keys" controls, "Soft spring" motion,
  "Inset, gray glyphs" settings groups, bordered reset block.
- Combined panel "Instrument" with "Toolbar" parts, "Fill steps" surface,
  "Floating tiles with wash", "Soft keys" tabs, the "Ink key" Open key, and
  "Live instrument" motion.
- Applets "Filled groups" shell, "Quiet Raised" controls, plain red
  destructive text, "Native snap" motion.
- Portman "Hero ring", "Two lines with a port chip", "Right-click only".
- Panel bars "A. Bell with a red dot" attention key.
- Apps by Sam: two cover cards, the Pro banner, sidebar glyph "Heart".
- Fan: row thermometer "Five shades, before the switch", page "Big chart",
  label "Cool until edited, then Custom".
- Nine tools: Color Picker, Text Extractor, Ruler, Awake, Mac Tweaks, Input
  Devices, Portman, RSync UI, Event Viewer. Task Manager, Partition Manager,
  System Cleaner, and NetToys are separate "Sam's" apps.

## Overview

A premium, quiet instrument that feels like a Mac app: real traffic lights,
menus, text fields, sheets, scroll views, and keyboard behavior. Custom
drawing is limited to identity: charts, dot titles, tiles, and the shells of
controls whose behavior stays native. Alignment
is the first quality bar: one leading edge per container, one height and
baseline per control row. Speed is part of the look. Nothing moves while
idle.

## Appearance

- One Appearance setting: Dark (default), Light, Automatic. It sets
  `NSApp.appearance`; every window and panel follows it.
- Every OnePlusUI color is dynamic. Views never branch on the color scheme.
- Open surfaces follow accessibility contrast, locale, calendar, and time
  zone changes once per system notification, never by polling.
- No raw colors in app code. Hex values live only in OnePlusUI tokens,
  chart series, and icon assets.
- Accent marks one thing at a time (selected tab underline, active data
  point, alert) and never fills a large surface. Text on an accent fill is
  white.
- Status never relies on color alone. Healthy states stay neutral. Offline
  is a hollow dot and muted text, never red.
- Chart series: neutral steps `#BCBCBC`, `#8A8A8A`, `#626262`, `#454545`;
  gray line `#BEBEBE`; accent line `accent`; grid `#343434`.
- Text selection: accent at 28% with primary text.
- Contrast uses APCA: Lc 60 for row, body, control, and button labels; Lc 45
  for captions and metadata. Disabled text and placeholders are exempt.
  Neutral gray text tokens keep 4.5:1 WCAG 2 on `window`, `sidebar`, and
  `panel`. Check text on hover, selected, and tile fills too.
- Menus, icon buttons, drag handles, and shortcut hints use `controlInk` or
  `secondary`, never the system accent tint.

## Typography

San Francisco only; SF Mono for aligned numbers, paths, and code. Live
numbers use `.monospacedDigit()`. Sizes are in the front matter. Regular
density: main window, Mac Tweaks, RSync UI, Event Viewer, Input Devices,
applets, sheets. Compact density: every menu-bar panel.

| Role | Weight | Tracking | Color |
|---|---|---|---|
| Sidebar title | semibold | -0.16 | `ink` |
| Nav row | regular | 0 | `secondary`, selected `ink` |
| Nav caption, table header | medium uppercase | +1 / +0.4 | `muted` |
| Page title | semibold | -0.7 | `ink` |
| Subtitle, description, metric unit | regular | 0 | `secondary` |
| Tab label | regular | 0 | `secondary`, hover and selected `ink` |
| Section and card title | semibold | -0.1 | `ink` |
| Row label | regular | 0 | `ink` |
| Control text | regular | 0 | `controlInk` |
| Caption, metadata | regular | 0 | `muted` |
| Mono value | regular SF Mono | 0 | `secondary` |
| Metric caption | regular | 0 | `metricCaption` |
| Metric value | 550, line 30.24 | -1 | `ink` |

## Geometry

- Centerline: a window with a sidebar has a 54 pt title row. The traffic
  lights (zoom visible and disabled) and the sidebar title center on
  `C = 27`. The title starts 14 pt after the zoom button. The workspace side
  is an empty drag area. The version 15 main window uses a 44 pt toolbar and
  `C = 22` (see "Main window").
- Top line "Top B": the title's cap top, the 40 pt tool icon, and every
  header control top sit on y = 20. In a header action row only the tallest
  control sits on y = 20; the rest center on it and share one text
  baseline, 12 pt apart.
- Traffic-light inset "Inset B": the close button's left edge is 13 pt from
  the window edge in every window and applet.
- The subtitle sits 2 pt below the title line; content starts 16 pt below
  the header or tab strip. Sidebar content starts at 54.
- Applets: a 40 pt row with lights, title caps, and actions on `C = 22`;
  24 pt action frames run y 10 to 34; the untabbed body starts at y 56.
  Sheet headers keep a 44 pt Top B row.
- Spacing only from the scale; radii 3 (segment in a track), 5 (nav rows,
  icon buttons, menu tabs), 6 (controls, fields), 8 (cards), 13 (window,
  system). Capsules only for switches, progress tracks, and count badges.
  Lines are 1 pt, inside the shape.
- No window is resizable; zoom is disabled. Sizes are the visible window and
  fit a 1920 x 1080 display with the Dock and a 1728 x 1117 laptop. A window
  opens at its saved position, clamped to its display, never a saved size.

## Window anatomy

### Shell

- `.windowStyle(.hiddenTitleBar)`, full-size content, one single-instance
  `Window` scene, no tabbing, restoration disabled.
- Root: the `window` fill, then the sidebar and the workspace. No texture
  or translucency.
- `OnePlusFixedWindowChrome` fixes the size, disables zoom and full screen,
  keeps the three lights visible, and re-centers them after every layout
  pass and on key.
- Empty header and sidebar background drags the window.

### Tool windows (`LinearToolWindow`)

RSync UI, Event Viewer, Mac Tweaks, and Input Devices use the main window's
sidebar, 44 pt pane toolbar, and back and forward keys (see Main window).
RSync UI and Event Viewer pass `editorial: true`, which turns on the
editorial body, "Raised keys" controls, and "Inset, gray glyphs" groups:

- Pages: `OnePlusLinearEditorialBody` for settings, and
  `OnePlusLinearEditorialFixedBody` for pages whose own list or table
  scrolls. Spacing comes from `OnePlusLinearSpace` (2, 4, 6, 8, 12, 16, 20,
  24) and the control column from `OnePlusLinearControlWidth` (160, 180).
- Live data: Transfers opens with the Home tiles (`CloudSyncTiles`,
  `OnePlusLinearBento` with `.instrument` tiles under `.fillSteps`), then
  one group of transfer rows.
- Rows: `linearGroupRowHover(selected:)` paints the radius 8 `hover` fill
  past the row content; nothing moves.
- Tables: under editorial, `onePlusTableRow` and `OnePlusNativeTable` draw
  the group fill, sentence-case headers, `lineSoft` row lines, and the
  `selection` fill, with no zebra stripes.
- Banners: `OnePlusLinearBanner` (`.info`, `.warning`, `.error`); its text is
  selectable.
- Sheets: `OnePlusLinearSheet` (title row, close key, groups, trailing
  footer keys) inside SwiftUI's `.sheet`.
- Log lines, paths, and messages stay selectable text.

### Rows and the control column

- The control sits in a right-aligned 160 pt column (180 pt when one value
  needs it, one width per group). A reset glyph never moves the column.
  Labels never wrap.
- Help and navigation chevrons show on row hover or focus; their width is
  reserved at rest.
- Hover highlights the complete row rectangle, never only the text.
- Controls apply at once; an invalid value stays with an error caption and
  never clamps silently.
- Process and server rows draw the app's real icon at the full slot (16 pt
  in panels), with no padded tile, ring, or wrapper. An app with only a
  legacy `.icns` icon uses its own `.icns` art, because macOS 26 wraps it in
  a gray tile. A command-line process uses the terminal glyph. No generic
  placeholder; the slot is kept so names align.

## Components (OnePlusUI)

| Component | Spec |
|---|---|
| `OnePlusButtonStyle(.neutral)` | 28 pt, radius 6, 1 pt `line`, `raised`, 10 pt padding, 12 pt `controlInk`; hover `raisedHover`, pressed `pressed`. |
| `.primary` / `.accentPrimary` | Same geometry; `primaryFill` or `accent` with medium text. One per view state. |
| `.ghost` | No fill until hover (`raised`); `secondary`, hover `ink`. |
| `.destructive` | `dangerFill`, `dangerLine`, `danger` text, always with a confirmation. |
| `.icon` | 28 pt square, radius 5, transparent until hover; needs `.help` and an accessibility label. |
| `.link` | Text plus a 10 pt arrow, `secondary`, hover `ink`. |
| `.small` | 24 pt, 11 pt text, radius 5, for compact and panel headers. |
| `OnePlusSwitchStyle` | 29 x 17 capsule, 11 pt knob; off `selection` track, on `primaryFill`. |
| `OnePlusSegmented` | 28 pt (24 compact), 2 pt inset and gaps, radius 6 / 3, `track` fill, selected `selectedControl`. |
| `OnePlusSelect` | 28 pt trigger, radius 6, `raised`, trailing chevron; opens `OnePlusPopupMenu`. |
| `OnePlusPopupMenu` | Borderless panel below the trigger (above without room), at least the trigger width and wide enough for the longest item; 5 pt padding, radius 7, `raised`, one soft shadow; 28 pt items (24 compact), radius 4, checkmark column, `selection` highlight. Long titles truncate in the middle with the full title as help. Arrows, Return, Escape, type-select. Scrolls after 12 items, only for the wheel or arrow keys at an edge, never for pointer hover. Closes on outside click, Escape, window move, or deactivation. Context menus stay native. |
| `OnePlusMenuButton` | Ghost or neutral button with a chevron that opens the popup with actions. |
| `OnePlusStepperField` | One text field with minus and plus. Every stepper is one control column wide (160 pt) in every look; the value and its unit right-align, so "4 hours", "3 days", and "3 sec" line up. A value without a unit right-aligns too. |
| `OnePlusTextField` / `OnePlusSearchField` | Native field in a 28 pt `field` bezel (32 pt search in sidebars), radius 6; focus `fieldFocus` with an inset line, no ring, no size change; error `dangerLine` plus a caption. Escape clears search first. |
| `OnePlusTextEditor` | `NSTextView` in `NSScrollView`, `track`, radius 6, 11 x 12 padding, SF Mono for code. |
| `OnePlusCard`, `OnePlusCardHeader`, `OnePlusSettingRow`, `OnePlusPageHeader`, `OnePlusTabStrip`, `OnePlusSidebar`, `OnePlusNavRow` | As above. |
| `OnePlusMetricTile`, `OnePlusSparkline`, `OnePlusAreaChart` | Cached `Canvas` paths, 1.2 pt stroke, static while values hold. |
| `OnePlusUsageBar`, `OnePlusSegmentBar` | 5 pt capsule track, neutral fill, 2 pt segment gaps. |
| `OnePlusStatus`, `OnePlusBadge` | 4 pt dot and text (hollow offline); 9 pt SF Mono counts. |
| `OnePlusTable` | Fixed columns, 33 / 34 pt rows, native arrows, sort, context menus, type-select. |
| `OnePlusKeyValueRow`, `OnePlusEmptyState`, `OnePlusToast`, `OnePlusSheet` | Muted label and trailing value; centered 26 pt glyph, title, caption; non-focusable toast 20 pt above the bottom with an announcement; native sheet, 40 pt header, widths 420, 560, 700. |
| `OnePlusLinearIconButton(busy:)` | While work runs, the glyph becomes a small spinner in the same frame; the accessibility label is the busy text ("Scanning"). |

- Button labels center vertically. A glyph uses the label's size and weight
  and shares its center line.
- States: hover changes only fill, line, or text color. Press is one darker
  step and never moves. Disabled is 0.38 opacity. Loading and error keep the
  bounds.
- Every control that sits in one row with others (field, select, stepper,
  button) has one height and one radius from the active look.
- Focus: no focus ring or outline, ever (owner rule). Every scene, panel,
  popover, and sheet root uses `onePlusFocusPolicy()`. With Full Keyboard
  Access or VoiceOver on, keyboard focus shows only the style's own subtle
  fill, with no layout change.
  Tables keep first responder after a row click. Reactivation keeps a valid
  responder; only detached, hidden, disabled, or clipped ones clear.

## Horizontal density and native feel

- Use the width first: metadata (time, count, size, status) trails on the
  same row. Related actions sit side by side.
- No inline provenance or help text; use an info glyph with a tooltip.
- Page toolbars sit on the page in one row, never inside a padded card. A
  card groups rows; it never wraps one control or one line.
- Token paddings only. No pill badges on every row, hover lifts, or
  web-style space.
- Nothing clips abruptly: shadows, hover surfaces, popups, and text keep
  their shape. A scroll view clips only at its real edge; bottom gutters
  are padding inside the scroll content.
- No control floats over scrolling content.

## Native behavior contract

- Selects and menu buttons use `OnePlusPopupMenu`; context menus and the
  app menu bar stay native `NSMenu`.
- Native text input: selection, undo, IME, Return commits, Escape cancels.
  Spell checking off in code and rule editors.
- Lists: arrows, Return opens, Space Quick Look, Delete asks, type-select,
  multiple selection where useful, drag-out, context menu.
- Keyboard: Tab in visual order, Command-F search, Command-1 to 9 pages,
  Command-comma settings, Command-W close, Escape dismisses sheets. Custom
  key handlers act only in their window and pass other keys on.
- Restore only promised page and tab state; validate saved IDs; an explicit
  route wins. Search text stays transient. Windows restore on a surviving
  screen with the titlebar reachable.
- Sheets attach to their window; no in-window dimmed overlays.
- `.help` tooltips; every icon-only control has an accessibility label.
- Files use the system services (Reveal, Copy Path, Open With, Quick Look,
  Trash). Destructive actions use a native confirmation.

## Motion

"Native snap" (`OnePlusMotion`; ease-out cubic-bezier(0.25, 1, 0.5, 1),
ease-in cubic-bezier(0.4, 0, 1, 1)):

- Panel open 140 ms ease-out fade plus 4 pt down, first frame in final
  layout; close 100 ms ease-in fade.
- Hover fill fades in 60 ms, out 150 ms; press is instant. Nothing moves or
  scales on hover or press, except the owner-picked main panel tiles and
  keys and the main window Key tile (below).
- Sidebar selection: 120 ms crossfade. Pane tab underline slides 180 ms;
  segment thumb 160 ms; switch 140 ms. Panel tab keys change at once.
- Page switches, numbers, and popup items change at once. Spinners run only
  during real work.
- Reduce Motion: everything instant, except a 100 ms panel fade.

### Panel motion (combined panel)

"Live instrument" (`OnePlusMotion`, `OnePlusNumberPace`):

- First open of each tab after launch: numbers count up from 0 and bars grow over
  600 ms; chart lines draw in over 450 ms, 30 ms apart. Later opens show
  values as they are.
- Charts scroll at one constant speed; a new top value eases the scale over
  400 ms.
- Numbers roll only changed digits (spring damping 0.9). Paces (response,
  interval, offset): Network 0.25 s, every sample, 0; CPU 0.45 s, 2 s,
  0.15 s; GPU 0.45 s, 2 s, 0.30 s; Memory 0.6 s, 4 s, 0.45 s; Disk 0.6 s,
  5 s, 0.60 s; Battery 0.6 s, 5 s, 0.75 s; process rows 0.5 s, every 2 s.
- Hover: a tile rises 1 pt and its wash is 1.8 times stronger (160 ms in,
  240 ms out); row fills fade 90 / 200 ms; action keys rise 1 pt (120 ms)
  and sit 0.5 pt down while pressed.
- Reduce Motion: no count-up or draw-in, one scroll step per sample,
  150 ms number crossfade, color-only hover. A closed panel runs nothing.

## Menu-bar panels

### All panels

- 356 pt wide. Height is the natural height of the current tab, capped at
  90% of the visible screen. A short tab never opens tall.
- A tab switch shows the final layout in the first frame: measure before the
  swap and resize in the same transaction.
- Each panel keeps its identity color for key data (Portman's port colors,
  the combined panel's metric colors, RSync UI's blue progress). Chrome
  stays neutral. Only the body scrolls. One opaque surface, no blur.
- Status icon: the outline flexed-arm template (`MenuBarIcon`), 16 pt
  canvas, 13.6 pt ink, 1.24 pt lines. Tool status items match Portman's
  size (14 pt image, 11.2 pt ink). Sidebar and panel glyphs come from each
  tool's own icon; no two tools share one. Custom glyphs are 32 x 32
  template SVGs with 2.5 strokes.
- Left click toggles the panel; right click and Control-click open the same
  native menu. Neither activates the app; only Open App does. Measure on
  the clicked item's display before the first frame.
- Busy work (such as a Portman scan) shows on the top-bar gear: the gear
  becomes a spinner in the same frame. Body controls never move aside for a
  spinner.
- Attention bell (`AttentionBell`): a `bell` icon button left of the gear
  in every panel bar. A 7 pt `destructiveText` dot, 4 pt in from the top
  right, shows while an item needs attention. A click opens a 312 pt
  popover: a "Needs attention" caption, then one warning banner per item
  with one plain line and a compact `Fix` key (Accessibility for custom
  scrolling, then the fan helper). Windows have no gear, so no bell.

### Fill steps shell (combined panel and Portman)

`OnePlusLinearPanel(style: .fillSteps)`; values are the package tokens.

- No lines anywhere: parts separate by fill step and spacing (`fillShell`,
  `fillGroup`, `fillRowHover`, `fillTrack`, `fillThumb`). Shell radius 12;
  body padding 2 below the bar, 10 at the sides, 12 at the bottom; blocks
  10 pt apart.
- Top bar, 46 pt, 10 pt inset. Leading "Soft keys": 26 pt icon tabs, 13 pt
  glyphs, 2 pt apart, in a sunken radius 8 track; the selected tab is a
  raised radius 6 key. Dark: deep track, `#313136` to `#28282C` key, a 1 pt
  fading `softKeyDivider` between two unselected tabs only. Context menu
  Move Left and Move Right reorder tool tabs. Trailing, 2 pt apart: the
  28 pt gear (opens Settings), then the 26 pt "Ink key" `Open MacPowerToys`
  (dark key and white label in Light, light key and `#141416` label in
  Dark), radius 8, 10 pt padding, 12 pt medium text centered on its cap
  height. Quit stays in the status item menu.
- Groups: `fillGroup`, radius 10, 4 pt top and bottom padding, no
  separators. Row hover is a radius 6 `fillRowHover` step 4 pt inside the
  group sides and 1 pt off the row edges.

### Combined panel

- Home, top to bottom, no header row:
  - Bento "Floating tiles with wash": six `fillGroup` tiles, radius 8, 7 pt
    apart, 10 pt padding, 266 pt tall, one shared shadow layer, a wash of
    the tile's data color fading out at 75% height. Left: CPU (140 pt, user
    and system, history chart), Disk (56 pt, free and a 5 pt bar), Battery
    (56 pt, percent, time left, bar). Right: GPU (84 pt, 30 pt chart),
    Memory (84 pt, percent, used and total, bar), Network (84 pt, down and
    up, two-series chart). Values 26 pt light in their data color; icons
    `secondary`. Charts: the last 60 samples as a 1 pt line, a dot at the
    current point, a gradient fade, the left edge fading over 16 pt.
  - A missing battery or GPU hides its tile; the column's chart tile takes
    the height. Missing readings show a dash.
  - One group with the Fan row (32 pt, RPM, a CPU thermometer, and the
    Auto, Cool, Max segmented control: `fillTrack` radius 7, `fillThumb`
    radius 5) and the Awake row (state text and a 32 x 18 switch, accent
    on). No fans hides the Fan row; only a segment click writes.
  - Fan segments are `.snug` (40 pt min), so "Custom" never cuts the RPM.
    Cool reads "Custom" while the curve differs from the standard one.
  - 12 pt `thermometer.medium` before the segments, by Apple silicon
    thermals: under 56 °C `panelMuted`, 56-69 warm, 70-84 hot, 85-94 very
    hot, 95+ critical. Help "CPU 62 °C · warm".
  - "Top processes": five 30 pt rows, 12 pt text: icon (16 pt), name, CPU
    percent in `cpuText` (40 pt column), memory (68 pt column). A click
    selects by PID. Right-click: Quit Process… (Quit, Force Quit, Cancel),
    then Open in Task Manager Pro, or Classic when only Classic is
    installed; with neither, the menu links to Apps by Sam.
  - Actions for the enabled tools among Pick Color, Extract Text, Ruler:
    equal 32 pt keys, radius 8, 4 pt apart. Light: white keys with one 1 pt
    edge at 12% black, regular labels. Dark: flat `fillGroup`, medium
    labels.
- Speed: metrics sample off the main thread every second while Home shows,
  every 5 seconds otherwise; the first sample on open comes at once.
  Processes refresh every 2 seconds only while Home shows. Text formats off
  the main thread.
- Tool tabs (RSync UI, Input Devices) use Home's parts: a pair of 56 pt
  tiles, `fillGroup` groups 10 pt apart, 24 pt section headers, 32 pt rows
  with the Home row hover, and the action keys last.
  - Input Devices: Mouse and Trackpad tiles (lowest battery as a bar, else
    the device name and control state); the custom scrolling switch and the
    Accessibility row with a 24 pt Grant key; one group per Mouse,
    Trackpad, and Scroll device profile, each opened by a disclosure row
    (glyph, name, detail, chevron) that keeps its open state.
  - RSync UI: a warning banner with Retry when the engine stops; Transfers
    and Speed tiles; Remotes, Active, and Recent groups; transfer rows with
    a chevron, state text, a 22 pt icon key, and a 5 pt progress bar;
    New Transfer and Open RSync UI keys.

### Portman

Fill steps shell with the Soft keys tabs Servers and Forward, the gear, and
the Open key. Parts: `PortmanOverviewParts.swift`,
`PortmanForwardParts.swift`.

- Servers, no header row and no bottom bar:
  - Hero ring: one `fillGroup` card, 16 pt vertical padding, a 132 pt ring
    (9 pt track) of each process's memory share in its port color. Center:
    total MB (26 pt light, rolling digits) over "N% of RAM" or "N selected".
    20 pt below: Servers, CPU (`cpuText`), and Longest up as 15 pt medium
    values over muted captions, split by fading 30 pt dividers.
  - One `OnePlusLinearList(style: .panel)` of 40 pt rows: the port chip
    (`:8787` in the port color on a 14% wash, radius 5), the app icon or
    terminal glyph, the name over branch and uptime, a 32 pt sparkline, and
    memory in a 52 pt column. Hover is the fill step only; nothing moves.
    Open and Stop replace the sparkline on hover.
  - A click opens details. Right-click: Open localhost, Show Details, Stop
    Process Tree…, then Sort by, Refresh Servers, Clean Up. No action
    buttons. Clean up shows checkboxes and one Cancel and Stop row.
  - Steady height (`onePlusSteadyRows`): room for at least 3 rows; grows at
    once; shrinks only when the count drops 2 or more below the reserve.
  - Motion: the first open counts the ring up; a new row opens over 250 ms
    and fades in after 70 ms; a removed row fades 150 ms and closes 250 ms.
- Forward: every control is a 28 pt "Raised keys" control (radius 7):
  sunken wells for fields and the Hosts select, raised keys for buttons.
  Every row is 40 pt on the 10 pt row inset. All right-hand keys and the
  local-port fields share one 88 pt column and one right edge; the fields
  share one left edge.
  1. Input group: host field, Hosts select (76 pt, when saved hosts
     exist), and Scan (Cancel while scanning); then Remote port and Add
     port.
  2. Scan group, after a scan or with added ports: a header row with the
     select-all checkbox, the status line ("oc1 · 28 ports"), and Clear;
     one row per port (checkbox, port chip, name, disclosure chevron, local
     port field); a footer row with "N selected" and Forward.
  3. Forwarded group: "Forwarded ports · N active", then one row per tunnel
     (state glyph, mono `:local → host:remote`, state text, 22 pt icon
     actions).
  The scan spinner is the gear spinner; nothing in the body moves.
- Server details (Home's parts): a fixed header row (back icon, name,
  `:port` in the port color, open-link icon); an instrument bento with
  Memory and CPU tiles and their 10 min history; the server group (Server
  row with compact Restart and Stop keys, label-value rows with 22 pt copy
  or open accessories, a Details disclosure row); the Processes group (a
  disclosure row, then 40 pt rows with a usage bar); an action bar (Editor,
  Finder, Copy URL, Preview). Errors are a warning banner.

### Separate tool panels

`OnePlusLinearMenuPanel`: the combined panel's shell and 46 pt top bar (a
one-key icon track and the tool name; the gear and `Open App` trailing),
with the same height reporting. The body is the tool-tab content: RSync UI
and Input Devices without their Open key, Awake as one group, Color Picker
and Text Extractor as one action key.

## Applets

Color Picker and Text Extractor are compact applets. Awake has no window:
its panel row and main window page are enough.

- Shell "Filled groups": the title area has the body color, no separator; a
  caption above each group; a group is a borderless filled surface, radius
  10, rows with hairline separators.
- 40 pt titlebar: lights on `C = 22`, the 12.5 semibold title 14 pt after
  zoom, actions trailing 16 pt from the edge. Body gutter 16 pt; bottom
  gutter 24 pt inside the scroll content.
- The gear is `OnePlusAppletSettingsButton` (ghost 24 pt `gearshape`, left
  of the primary action). It opens the tool's main window page, where simple
  settings live; Command-comma does the same. An applet keeps only its real
  work (Color Picker keeps History and Projects).
- Primary button: soft gray fill, no border (`#EBEBED` / `#2C2C30`; hover
  `#E2E2E5` / `#34343A`; pressed `#D8D8DC` / `#3C3C42`).
- Controls "Quiet Raised": quiet sunken tracks, one solid knob with one soft
  shadow, coral only for "on". A field beside a 24 pt button uses
  `.quietRaisedActionRow` (24 pt field), so the row has one height. Segment labels center; short fading dividers
  separate unselected segments.
- Destructive: plain red text, no fill or border, with a native
  confirmation. Never a tinted red pill.

## Main window

Linear style, OnePlusUI `OnePlusLinear*` parts. Reference:
`docs/design/v15/main-window-*.png`.

- 820 x 660, 215 pt sidebar, no texture or translucency. Lights center on
  `C = 22`, the center of the 44 pt toolbar. Sidebar `#101012` / `#F5F5F6`
  with a 1 pt trailing `line`; pane `#141416` / `#FCFCFD`.
- Sidebar: a 44 pt drag row with the window title on `C = 22`, 14 pt after
  zoom; a 28 pt search field (`⌘K` chip, 8 pt insets; Command-K and
  Command-F focus it); `All tools`; one group per category (System,
  Developer, then the rest), tools sorted by name length. 28 pt captions
  (11.5 pt medium `muted`). 28 pt rows: 16 pt one-color `SidebarGlyph`
  (`secondary`, `ink` when selected; marketplace tools use their art), 8 pt
  gap, 13 pt name. A disabled tool name is `muted`. Selection: `selection`
  fill, radius 6, medium `ink` name, no movement. Bottom group: Fan
  (`SidebarGlyphFan`, owner pick "Open blades": three outlined blades and a
  hub dot), Apps by Sam (`heart`), Settings (`⌘,`), Exit (`⌘Q`), 13 pt medium symbols and
  shortcut hints.
- Command-1 All tools; Command-2 to 9 follow the sidebar; Command-[ and
  Command-] go back and forward; Command-O opens the selected tool.
- Pane toolbar: 44 pt with its 1 pt bottom `line`, drags the window. Back
  and forward 24 pt icons 4 pt apart, 16 pt from the edge, then the 13 pt
  semibold title. Trailing text tabs end 24 pt from the edge: each pads its
  label and 12 pt `muted` count by 8 pt; the padded boxes touch; the
  selected tab draws the 2 pt accent underline across its box and never
  changes weight or position. All tools: `All N`, `Enabled N`,
  `Favorites N`. Settings: General, Marketplace, About. A tool page shows
  `Enabled` and the tool's enable switch instead.
- Editorial body: one scroll view, 20 pt top, 32 pt gutters, 20 pt between
  blocks, 24 pt bottom. Controls "Raised keys": every control is 28 pt,
  radius 7; fields, steppers, selects, search, and segment tracks are
  sunken wells; buttons, segment thumbs, and stepper arrows are raised
  keys. Keyboard focus fills the whole control softly. Motion "Soft spring":
  row hover fades on a 0.12 s spring and nudges the chevron 2 pt; a page
  switch fades 6 pt up and in (0.2 s); the switch knob springs (0.3, 0.72).
  Reduce Motion makes it instant.
- All tools: `OnePlusLinearPageTitle` ("All tools", "N tools, M on"), then
  captioned groups (13 pt semibold) with no fill: a `line` hairline on top,
  `lineSoft` between rows, faded at both ends over 12%. 48 pt rows: 24 pt
  icon (45% when off), 13 pt medium name over a one-line summary, then
  12 pt apart: `Off` (name `secondary`, summary `muted`) or the shortcut in
  one `OnePlusLinearKeyChip` (18 pt, `kbd` fill, radius 4, 11 pt `muted`;
  Awake shows `⌃⌥⌘A`), the 16 pt star column at one x (on hover, focus, or
  when set; accent when set), and a 10 pt chevron. No switch. Hover: a
  radius 8 `hover` fill 8 pt past the content, 2 pt inside the row edges.
  Context menu: Settings, Open, Enable, Favorite.
- Tool page: `OnePlusLinearToolHeader` "Launch tile": 48 pt icon over the
  24 pt name and description; right, the 176 x 108 "Key tile" (radius 12)
  with `Open` and an arrow over the shortcut caps and action name, or the
  tool name. Hover lifts it 2 pt; press sinks and scales to 98% (springs).
  Awake's tile shows `⌃⌥⌘A` over "Show in menu bar" and opens the panel on
  Home without activating the app; the Awake row then shows the row mark
  (dotted 1 pt accent line at 40%, 5% accent fill, radius 6, fades in 0.2 s
  after 0.3 s, holds 1.2 s, fades out 0.5 s).
- Then the `Menu bar icon` row (None, Combined, Separate) where supported,
  then the tool's settings inline. Groups "Inset, gray glyphs": `fillGroup`,
  radius 10, 1 pt `line` ring, rows at least 40 pt with 12 pt padding, an
  optional 13 pt `secondary` SF Symbol in a 20 pt slot, `lineSoft`
  separators from the label, 12 pt semibold `secondary` captions 6 pt
  above. A reset or clear is `.resetBlock`: one full-width 40 pt inset row
  with red text, its own block after the last group. Ruler shows its
  defaults for new rulers bound to FreeRuler `prefs`.
- `How to use` is the footer "Checklist" below the free space: one
  `OnePlusLinearChecklist` card per manual section (radius 12, `fillGroup`,
  tile shadows): 40 pt step rows with a 13 pt accent glyph, 36 pt shortcut
  rows with key caps, note rows with an info glyph. Steps are short plain
  sentences.
- Apps by Sam (`OnePlusLinearAppShelf`): the title, the Task Manager Pro
  banner (radius 12, 96 pt icon, 20 pt name, raised `Paid` key), "More
  apps" with the Hushpen and Switch cover cards side by side (118 pt
  covers, 40 pt icon, 15 pt name), then one open row per other app (64 pt
  icon). Every app has the App Store capsule: OPEN when installed, else GET,
  or GET disabled with "Not available yet".
- Fan page: tool header with the 56 pt `FanLogo` icon (owner pick
  "Neutral fan", 2026-11-20: five swept blades, Midnight in Light,
  Porcelain in Dark), then "Cool curve": a 240 pt chart (30-100 °C, 0-100%,
  `line` grid, 10 pt `secondary` labels, 1.75 pt `ink` monotone cubic line,
  accent dot at the current CPU temperature), a fixed safety band (90 °C
  ramp to full at 95 °C, `temperature-critical` 10% fill, dashed edge, label
  above), a `tertiary` hint line, a "Now" row, and the reset block. Points:
  12 pt quiet knobs, 24 pt hits, `ink` ring on hover or select, 2-8 points.
  Drag stays between neighbors; double-click a point edits it; right-click
  adds or removes; Delete removes; double-click space adds.
- Settings uses `OnePlusLinearPaneBody`: 14 pt top, 24 pt gutters, 16 pt
  between sections, 20 pt `muted` captions, lists with radius 8, a 1 pt
  ring, and `lineSoft` separators. General: Appearance and windows, Launch
  and iCloud, Quick Access shortcut. About: header row with icon, update
  status, and `Check for Updates`, then details, links, acknowledgements,
  manuals.
- Enablement, placement, runtime state, and window visibility stay separate
  states. Each tool exposes one settings content view that returns only its
  groups (no page, scroll view, padding, header, `Spacer`, or max height);
  `ToolSettingsContent` only dispatches by tool id.

## Other surfaces

- Mac Tweaks and Input Devices: 820 x 660, 200 pt sidebar, one full-width
  column of cards on every page, no preview artwork. Input Devices keeps the
  Scroll device footer fixed; its panel tab embeds the same stacked cards.
- RSync UI and Event Viewer: editorial tool windows (see Tool windows);
  settings are a sidebar page.
- Ruler: the FreeRuler overlay keeps its pinned visuals. Ruler Settings and
  Defaults keep native titlebars and use OnePlusUI tokens for their bodies.

## Quality gates

Accept a window, panel, or sheet only after all of these pass in both
appearances:

1. Lights and title share their centerline; the title top sits on the top
   line.
2. One leading edge per container.
3. Controls in one row share height, radius, and baseline; the control
   column never shifts.
4. Nothing touches a window edge; content starts 16 pt below the header.
5. No clipped or overlapping text; long values truncate with a tooltip.
6. Every state renders: rest, hover, pressed, selected, disabled, focus,
   loading, empty, error, permission needed.
7. The native behavior contract holds.
8. No idle CPU: an open window with unchanged data adds no timers.
9. Speed: a page switch commits within 100 ms; 1,000-row tables scroll
   without dropped frames; hidden or closed surfaces stop redrawing; live
   charts update at most 4 times a second; a warm panel opens within
   100 ms, a cold panel or window within 250 ms, measured to the final
   frame. Keep file, process, and network work off input and termination
   callbacks. Startup failures are recoverable; shutdown is time-bound.
10. Fixed regions stay put while rows scroll.
11. A capture of the signed build matches the reference at the same scale.
