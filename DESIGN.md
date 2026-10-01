---
version: 14
name: MacPowerToys
description: Design language for MacPowerToys and its child tools (OnePlusUI, 2026-09-29)
appearance: { default: dark, options: [dark, light, automatic] }
colors:
  window: { dark: "#161616", light: "#F5F5F5" }
  sidebar: { dark: "#1D1D1D", light: "#E7E7E7" }
  panel: { dark: "#202020", light: "#FAFAFA" }
  panel-hover: { dark: "#262626", light: "#FFFFFF" }
  raised: { dark: "#292929", light: "#FFFFFF" }
  raised-hover: { dark: "#303030", light: "#F0F0F0" }
  pressed: { dark: "#252525", light: "#E4E4E4" }
  field: { dark: "#252525", light: "#F2F2F2" }
  field-focus: { dark: "#2B2B2B", light: "#EAEAEA" }
  track: { dark: "#181818", light: "#E4E4E4" }
  selection: { dark: "#343434", light: "#D4D4D4" }
  selected-control: { dark: "#424242", light: "#FFFFFF" }
  line: { dark: "#343434", light: "#D1D1D1" }
  line-soft: { dark: "#2B2B2B", light: "#E1E1E1" }
  ink: { dark: "#EDEDED", light: "#242424" }
  secondary: { dark: "#A3A3A3", light: "#656565" }
  muted: { dark: "#8A8A8A", light: "#707070" }  # at least 4.5:1 on panel and window
  control-ink: { dark: "#DEDEDE", light: "#343434" }
  accent: { dark: "#EE5B50", light: "#D94F45" }
  data-blue: { dark: "#8AAEEA", light: "#3564A4" } # Cloud Sync progress and network data
  accent-primary-ink: { dark: "#161616", light: "#000000" }
  accent-primary-hover: { dark: "#E65A4F", light: "#D34E44" }
  accent-primary-pressed: { dark: "#DE584E", light: "#CD4D43" }
  primary-fill: { dark: "#DDDDDD", light: "#383838" }
  primary-ink: { dark: "#252525", light: "#FFFFFF" }
  ok: { dark: "#7FA889", light: "#3F7A4E" }
  warn: { dark: "#F29A68", light: "#C06A32" }
  danger: { dark: "#E99B91", light: "#B8463B" }
  danger-fill: { dark: "#382624", light: "#FBE9E7" }
  danger-line: { dark: "#6D4541", light: "#E3B3AD" }
typography:
  regular: { sidebar-title: 12.5, nav: 12.5, caption-upper: 9, page-title: 24, subtitle: 12.5, tab: 12, section-title: 13, card-title: 12, row: 12, control: 12, caption: 10.5, table-header: 9, mono: 11, metric: 27, unit: 12 }
  compact: { sidebar-title: 12.5, nav: 11.5, caption-upper: 9, page-title: 20, subtitle: 10.5, tab: 11, section-title: 12, card-title: 11, row: 10.5, control: 10.5, caption: 9.5, table-header: 8.5, mono: 9.5, metric: 21, unit: 10 }
rounded: { segment: 3, nav-row: 5, icon-button: 5, control: 6, menu-tile: 6, card: 8, window: 13 }
spacing: { scale: [2, 4, 6, 8, 10, 12, 16, 20, 24, 28], gutter: 24, task-manager-gutter: 20, card-gap: 16, card-padding: 16, content-top: 16 }
geometry:
  title-row: 54
  centerline: 27            # traffic lights and sidebar title only
  content-top: 16           # page title first line box top (owner 2026-09-30); sidebar content starts at 54
  dot-title-cap-offset: 1   # optical offset within the regular page-title line box
  applet-titlebar: 40
  applet-centerline: 22
  sidebar-title-gap-after-zoom: 14
  search: { height: 32, inset-x: 12, below: 14 }
  nav-row: { regular: 32, compact: 29, gap: 2, container-inset: 10, padding: 10, icon: 15, icon-gap: 10 }
  card-header: 40
  setting-row: 44
  control: { height: 28, compact-height: 24, column: 160, wide-column: 180 }
  tab-strip: { height: 36, gap: 22, underline: 2 }
windows:
  main: { size: [1240, 840], sidebar: 216, density: regular, resizable: false }
  disk-explorer: { size: [1440, 900], sidebar: 216, density: regular, resizable: false }
  nettoys: { size: [1440, 900], sidebar: 200, density: regular, resizable: false }
  rclone: { size: [1240, 840], sidebar: 216, density: regular, resizable: false }
  system-care: { size: [1240, 840], sidebar: 200, density: regular, resizable: false }
  switch: { size: [1240, 840], sidebar: 200, density: regular, resizable: false }
  mac-tweaks: { size: [1120, 826], sidebar: 200, density: regular, resizable: false }
  system-monitor: { size: [1080, 660], sidebar: 200, density: compact, resizable: false }
  logs: { size: [1080, 660], sidebar: 200, density: regular, resizable: false }
  input-devices: { size: [1080, 660], sidebar: 200, density: regular, resizable: false }
  awake: { size: [560, 500], applet: true }
  color-picker: { width: 420, height: [250, 460], applet: true }
  text-extractor: { width: 480, height: [270, 462], applet: true }
menu-panel: { status-icon: 14, status-icon-ink: 11.2, width: 356, max-height-fraction: 0.9, top-bar-padding: [10, 8, 6], tab-group-radius: 7, tab: 26, tab-gap: 2, body-inset: 8, tile-radius: 6, tile-gap: 5, columns: 3, action-button-height: 32 }
popup-menu: { padding: 5, radius: 7, item: 28, item-compact: 24, item-radius: 4, item-padding: 9, max-visible-items: 12 }
performance: { page-switch-ms: 100, table-rows-smooth: 1000 }
texture: { ribbon: [700, 220], ribbon-drawn: [630, 198], ribbon-opacity-dark: 0.20, ribbon-opacity-light: 0.10, grain: [240, 150], card-grain: 0.14, menu-grain: 0.11, chart-dot-cell: 4 }
motion: { hover: 0, selection: 0, content: 0, idle-animation: none }
---

# MacPowerToys Design Language

Version 14 (OnePlusUI), adopted 2026-09-29. It replaces the earlier
material-based contract. It is the complete visual and window-structure
contract for every window, menu-bar panel, sheet, and settings page. Tool icon
rules are in [App and tool icons](#app-and-tool-icons).

## Overview

MacPowerToys looks like one premium, quiet, dark instrument. Surfaces are flat
near-black planes separated by one-point lines. Type is small, exact, and
aligned. One coral accent marks selection and alerts. A fixed ordered-dither
texture gives each window depth without decoration. Nothing moves while idle.

It must also feel like a Mac app: real traffic lights, real menus, real text
fields, real sheets, real scroll views, and real keyboard behavior. Custom
drawing is limited to identity: texture, charts, dot titles, and the visual
shell of controls whose behavior stays native.

Alignment is the first quality bar. Every container has one leading edge.
Controls that share a row have one height and one text baseline. Every window
aligns its traffic lights and sidebar title on one horizontal centerline, and
starts its sidebar content and its page content on one shared top line.

Speed is part of the look. A sidebar page switch shows the new page in the
next frame, and every table scrolls smoothly with thousands of rows.

## Sources of truth

Resolve conflicts in this order:

1. The owner's newest direct instruction.
2. This file.
3. The `OnePlusUI` package (`Packages/OnePlusUI`), which implements this file.
   A view never restyles a OnePlusUI component locally. Add a named variant to
   the package instead.
4. The HTML references (kept outside the repository): `task-manager.html`
   (Task Manager window and the menu-bar panel pattern),
   `macpowertoys-repaired.html` (main window), `mac-tweaks-design.html`
   (settings rows and controls), and `diskman-fixed.html` (storage charts).
5. Current screenshots in `docs/screenshots/`.

## Appearance

- The app has one Appearance setting in app Settings: Dark (default), Light,
  and Automatic. It sets `NSApp.appearance`. Every window and panel follows it.
- Every OnePlusUI color is a dynamic color with the dark and light values in
  the front matter. Views never branch on the color scheme to pick a color.
- Tool icons keep their approved artwork in both appearances.
- Open surfaces follow changes to accessibility contrast, locale, calendar,
  and time zone. Invalidate affected colors and cached formats once per
  system notification. Do not poll.

Color rules:

- No raw colors in app code. Hex values live only in OnePlusUI tokens, chart
  series, and icon assets.
- Accent never fills a large surface. It marks one thing at a time: the
  selected tab underline, an active data point, an alert.
- Status never relies on color alone. Pair it with text, a glyph, or a shape.
- Connected or healthy states stay neutral. Offline uses a hollow dot and
  muted text, never red.
- Chart series: neutral steps `#BCBCBC`, `#8A8A8A`, `#626262`, `#454545`;
  gray line `#BEBEBE`; accent line uses `accent`; grid `#343434`. Diskman keeps
  its storage series (see the Diskman recipe).
- Text selection uses accent at 28% with primary text.
- Every text token reaches at least 4.5:1 contrast on `window`, `sidebar`,
  and `panel` in its appearance. Small captions never go below `muted`.
- Check text contrast on its actual hover, selected, and textured fill too.
  Ordinary selected metadata uses a readable selected-text role.
- Menus, menu buttons, icon buttons, drag handles, and shortcut hints use
  `controlInk` or `secondary`, never the system accent tint.

## Typography

San Francisco only. SF Mono for numbers that must align, paths, and code. Live
numbers use `.monospacedDigit()`. Point sizes are fixed because every window
is a fixed canvas. Two densities exist, and a window uses one density
everywhere.

| Role | Regular | Compact | Weight | Tracking | Color |
|---|---|---|---|---|---|
| Sidebar title | 12.5 | 12.5 | semibold | -0.16 | `ink` |
| Nav row | 12.5 | 11.5 | regular | 0 | `secondary`, selected `ink` |
| Nav section caption | 9 uppercase | 9 uppercase | medium | +1 | `muted` |
| Page title | 24 | 20 dot matrix | semibold | -0.7 | `ink` |
| Page subtitle | 12.5 | 10.5 | regular | 0 | `secondary` |
| Tab label | 12 | 11 | regular | 0 | `secondary`, hover and selected `ink` |
| Section title | 13 | 12 | semibold | -0.1 | `ink` |
| Card title | 12 | 11 | semibold | -0.1 | `ink` |
| Row label | 12 | 10.5 | regular | 0 | `ink` |
| Control text | 12 | 10.5 | regular | 0 | `controlInk` |
| Caption | 10.5 | 9.5 | regular | 0 | `muted` |
| Table header | 9 uppercase | 8.5 uppercase | medium | +0.4 | `muted` |
| Mono value | 11 SF Mono | 9.5 SF Mono | regular | 0 | `secondary` |
| Metric value | 27 | 21 | semibold | -1 | `ink` |
| Metric unit | 12 | 10 | regular | 0 | `secondary` |

- Regular density: main window, Mac Tweaks, Diskman, Cloud Sync, Logs, Input
  Devices, System Care, NetToys, Switch, compact applets, and sheets.
- Compact density: the Task Manager window and every menu-bar panel.
- Descriptions and metric units use `secondary`. Supporting captions and metadata use
  `muted`. These roles must stay visibly separate from primary values.
- The dot-matrix title is Task Manager's identity only. It is drawn from the
  5 x 7 glyph table as one cached path with one accessibility label. The Task
  Manager sidebar title uses the normal system role.

## Geometry

### The centerline rule

Every window with a sidebar has a 54 pt title row. Its centerline is
`C = 27` pt below the window's top edge. These items center on `C`:

- the native close, minimize, and zoom buttons (zoom stays visible and
  disabled because windows are fixed);
- the sidebar title, which starts 14 pt after the zoom button.

The workspace side of the title row stays empty: it is a drag area where
the window texture shows. Owner correction (2026-09-29): page content must
not stick to the window top.

### The content top line

`T = 16` pt below the window's top edge (owner decision 2026-09-30, "top edge
on titlebar"). The page title's first line box starts at `T`, so the title's
top edge lines up with the top of the traffic lights and the sidebar title:
the title reads as part of the titlebar row and never pokes above it.
(Centering a 24 pt title on `C` put it too high; starting it at 58 put it too
low.) Task Manager's dot-matrix title has no ascender space, so its glyph
top aligns with the cap top of the text titles in the other windows, never
above it (owner correction 2026-10-01: its header sat above the sidebar
title row). Center the 20 pt dot canvas in the regular 28.8 pt title line
box with the 1 pt optical cap offset. Measure the painted pixels, not the
frames.
The subtitle follows 2 pt below the title line, tabs follow, and the
first content element starts 16 pt below them (about y = 80 on a page with a
subtitle and tabs). Header actions center on the page title's first line.
The sidebar keeps its own layout: title on `C`, first element at 54.

Compact applets keep their 40 pt titlebar with `C = 22`.

### Spacing and radius scales

- Spacing values: 2, 4, 6, 8, 10, 12, 16, 20, 24, 28. No other values.
- Radius values: 3 (a segment inside a track), 5 (nav rows, icon buttons,
  menu tabs), 6 (controls, fields, menu tiles), 8 (cards and panels), and 13
  (window, drawn by the system). Capsules only for switches, progress tracks,
  and count badges.
- Lines are exactly 1 pt, drawn inside the shape.

### Fixed window sizes

No window is resizable. Zoom is disabled. Each size fits a 1920 x 1080
display with the Dock and a 1728 x 1117 laptop display. The size is the
visible window, including the hidden titlebar area: a 1080 x 660 canvas is a
1080 x 660 window on screen, not 1080 x 692. The front matter
lists every size, sidebar width, and density. Each window opens at its saved
position, never a saved size, clamped to the visible frame of its display.

## Window anatomy

### Shell

- `.windowStyle(.hiddenTitleBar)`, full-size content, one single-instance
  `Window` scene, `tabbingMode = .disallowed`, and restoration disabled.
- The root is one `ZStack`: the `window` fill, then the window texture, then
  the sidebar and the workspace. The system owns the 13 pt corner radius and
  the shadow.
- `OnePlusFixedWindowChrome` fixes the content size, disables zoom and full
  screen, keeps all three traffic lights visible, and re-centers them on `C`
  after every native layout pass and whenever the window becomes key.
- Unoccupied header and sidebar background drags the window. Double-click
  follows the system titlebar preference.

### Window texture

One noninteractive texture layer per window, drawn once in window coordinates
at the window root. It never scrolls, never repeats per region, and is never
clipped to a header, tab strip, or scroll view.

- Workspace ribbon: the 700 x 220 ordered-dither ribbon drawn at 630 x 198,
  top -8, right -16, at the front-matter opacity, with a horizontal alpha
  fade (0%, 26%, 82%, 100%).
- Corner grain: cards marked `textured` draw the 240 x 150 grain in their
  top-right corner at 0.14 (metric tiles) or 0.11 (menu tiles), clipped to
  the card. Text, icons, controls, rows, and list views
  never carry texture.
- Grain stays above the fill and below all content. It never overlays text
  or controls.
- Chart dither: ordered 4 x 4 pt dots under area charts, masked to the chart,
  one cached pattern, never one view per dot.
- Textures change luminance only. They never tint semantic color. They are
  hidden from accessibility and hit testing, and they redraw only when size,
  appearance, or backing scale changes.

### Sidebar

```text
x=0                                  x=200 (216)
+------------------------------------+
| (o)(o)(o)  Title            C=27   |  54 pt title row
| [ Search              cmd K ]      |  32 pt field, 12 pt side margins, 14 below
|  SECTION CAPTION                   |  20 pt slot
| [#] Nav row                   12   |  32 pt rows, 2 pt gaps
| [#] Nav row (selected)             |
|                                    |
|------------------------------------|  1 pt lineSoft, only when needed
| [#] Modified / Settings / About    |  bottom nav, 10 top, 12 bottom
+------------------------------------+
```

- Background `sidebar` with a 1 pt `line` on the trailing edge. No material
  and no vibrancy.
- Nav container inset 10, row padding 10, 15 pt SF Symbol at regular weight,
  and a 10 pt icon-to-label gap. Section captions start at the icon's x.
- Rest: transparent with `secondary` text. Hover: `raised`. Selected:
  `selection` fill with `ink` text and icon. Selection never changes weight,
  icon, or geometry. No side stripe.
- Count badges are 9 pt SF Mono `muted` text on the trailing edge.
- Compact density uses 29 pt rows and 11.5 pt text. Everything else is equal.
- Entity rows that need a second line (accounts, devices) are 44 pt with the
  second line in the caption role. Plain destinations stay one line.

### Page

```text
T=16  Page title                          [action] [action]
C=27  (traffic lights and sidebar title center here; title top aligns with their top)
      Subtitle (optional)
      Tab   Tab 12   Tab                         [trailing tab tools]
      ------------------------------------------------------------ lineSoft
      16 pt
      [ toolbar: search, filters ]   (fixed)
      [ card ]  16  [ card ]         (scrolls)
      [ footer / status row ]        (fixed)
```

- Content gutter: 24 pt on both sides (Task Manager uses 20). Every body
  element, including embedded settings, starts on the page title's leading
  edge. Nothing adds a second inset.
- The first line box of the page title starts at `T`. The subtitle sits 2 pt
  below the title line. Header actions center on the title's first line and
  end 24 pt from the edge.
- Fixed regions: header, subtitle, tabs, page toolbars (search, filter, and
  action rows), inspectors, and footers or status rows. Scrolling region:
  on settings and card pages, the card stack; on table and list pages, only
  the rows inside the table card, while its header row stays fixed. A page
  never scrolls its inspector, toolbar, or footer together with its rows.
- Tab strip: 36 pt high below the header, 22 pt between tabs, labels start on
  the gutter, a 2 pt accent underline under the selected tab only, counts in
  9 pt SF Mono 6 pt after the label, and one full-width `lineSoft` bottom
  line. Selection never moves tabs. Trailing tab tools center in the strip.
  Hover (owner correction 2026-10-01): the label turns `ink` and a `raised`
  surface with radius 5 appears. The surface extends 8 pt beyond the label
  and count on each side and 4 pt above and below the text. It is drawn
  behind the tab and never changes layout, tab positions, or the underline.
- The first content element starts 16 pt below the header block or tab strip.
- Content never touches the header. No second page header inside content.
- Page scroll views always use overlay scrollers, even when the system
  setting shows legacy scroll bars, so the right gutter stays 24 pt.
- Buttons default to the window's density: 28 pt in regular windows, 24 pt
  in compact windows and menu panels.

### Cards, rows, and the control column

- Card: `panel` fill, 1 pt `line`, radius 8, clipped. Cards are 16 pt apart.
- Card header: exactly 40 pt, 16 pt horizontal padding, optional 13 pt icon,
  8 pt icon gap, card title, optional trailing accessory, and a 1 pt
  `lineSoft` bottom line.
- Setting row: exactly 44 pt, 16 pt horizontal padding, and 1 pt `lineSoft`
  separators between rows. The label and an optional help or reset glyph
  lead. The control sits in a right-aligned control column, 160 pt wide
  (180 pt only when the card's longest value needs it; one width per card). A
  reset glyph that appears never moves the column.
- Help and reset glyphs sit beside the label, before the control column.
  Optional help uses a reserved slot shown on row hover or keyboard focus.
  The label also exposes tooltip and accessibility help. A help popover
  uses a labeled button. Keep required instructions and real errors visible.
- Navigation chevrons appear on row hover or keyboard focus only. Reserve
  their width at rest so text never moves. Persistent menu chevrons remain.
- A setting that needs an explanation puts one caption line under the label
  and grows the row to 56 pt. Never wrap a label inside 44 pt.
- Cards pair in two equal columns when both are short. Long cards take the
  full width. Paired cards keep their natural heights, top-aligned.
- A row with a title and a secondary line stacks them with a 2 pt gap and
  centers the block vertically. A card or tile with one row centers that
  row vertically.
- Hover on any list row, table row, or menu-panel row highlights the
  complete row rectangle, including values, actions, and charts. Never
  highlight only the text (owner correction 2026-10-01).
- Controls apply immediately. There is no Apply or Discard bar. An invalid
  text value stays in its field with an error caption; it never clamps
  silently.

## Components (OnePlusUI)

Use only these. Names are the package API.

| Component | Spec |
|---|---|
| `OnePlusButtonStyle(.neutral)` | 28 pt high, radius 6, 1 pt `line`, `raised` fill, 10 pt padding, 6 pt icon gap, 12 pt `controlInk`. Hover `raisedHover`, pressed `pressed`. |
| `.primary` | Same geometry, `primaryFill` with `primaryInk`, medium weight. One per view state. |
| `.accentPrimary` | Opt-in accent primary action. Same geometry and medium weight, `accent` fill with `accentPrimaryInk`; use its hover and pressed tokens. |
| `.ghost` | Same geometry, no fill or line until hover (`raised`). Text `secondary`, hover `ink`. |
| `.destructive` | `dangerFill`, `dangerLine`, and `danger` text. Always paired with a confirmation. |
| `.icon` | 28 pt square, radius 5, control-role glyph size and weight, transparent until hover. Needs `.help` and an accessibility label. |
| `.link` | Text plus a trailing 10 pt arrow ("Manage", "View all"), `secondary`, hover `ink`, no fill. |
| `.small` size | 24 pt high, 11 pt text, radius 5. For compact and menu-panel headers. |
| `OnePlusSwitchStyle` | A `Toggle` style. 29 x 17 capsule, 1 pt line, 11 pt knob, 12 pt travel. Off: `selection` track and `secondary` knob. On: `primaryFill` track and `primaryInk` knob. |
| `OnePlusSegmented` | Radio group. 28 pt high (24 compact), 2 pt inset, 2 pt gaps, radius 6 outer and 3 inner, `track` fill, 1 pt `line`, selected segment `selectedControl` with `ink` text. Supports the `Default (value) / On / Off` pattern. |
| `OnePlusSelect` | A styled trigger (28 pt, radius 6, `raised`, 1 pt `line`, 10 pt padding, trailing chevron) that opens `OnePlusPopupMenu`. Its width follows the control column. |
| `OnePlusPopupMenu` | Custom dark popup for selects and menu buttons (owner correction: native glass menus do not fit). A borderless panel below the trigger (above when there is no room), at least the trigger width, 5 pt padding, radius 7, `raised` fill, 1 pt `line`, one soft shadow. Items 28 pt (24 compact), radius 4, 9 pt horizontal padding, checkmark column for the selected value, hover and keyboard highlight `selection`, disabled items at 0.38, section captions and separators. Keyboard: arrows, Return, Escape, type-select. Scrolls after 12 items. Closes on outside click, Escape, window move, or app deactivation. Right-click context menus stay native. |
| `OnePlusMenuButton` | A ghost or neutral button with a trailing chevron that opens `OnePlusPopupMenu` with actions ("More", "Export", "Presets"). |
| `OnePlusStepperField` | A native text field with native stepper behavior in one 28 pt frame, an optional 9 pt SF Mono unit, and a 17 pt arrow column behind a 1 pt separator. |
| `OnePlusTextField` | Native `TextField` in a 28 pt `field` bezel, radius 6, 1 pt `line`, 8 pt padding. Focus: `fieldFocus` fill and a 1 pt inset neutral line, no outer ring, no size change. Error: `dangerLine` plus a caption below. |
| `OnePlusSearchField` | Native search field in the same bezel with a leading 13 pt magnifier, a clear button, and an optional trailing shortcut hint. 32 pt in sidebars, 28 pt in pages. Escape clears first. |
| `OnePlusTextEditor` | `NSTextView` in `NSScrollView`, `track` fill, radius 6, 1 pt `line`, 11 x 12 padding, 11 pt SF Mono for code and rules. |
| `OnePlusCard`, `OnePlusCardHeader`, `OnePlusSettingRow` | As defined in "Cards, rows, and the control column". |
| `OnePlusPageHeader`, `OnePlusTabStrip` | As defined in "Page". |
| `OnePlusSidebar`, `OnePlusNavRow`, `OnePlusNavCaption` | As defined in "Sidebar". |
| `OnePlusMetricTile` | Label row (13 pt icon, card title role), value with unit, caption, and an optional sparkline or bar. Textured corner. Hover `panelHover` and a trailing chevron when it navigates. |
| `OnePlusSparkline`, `OnePlusAreaChart` | Cached `Canvas` paths, 1.2 pt stroke, chart dither under area charts. Static while values do not change. |
| `OnePlusUsageBar`, `OnePlusSegmentBar` | 5 pt capsule track (`line`) with a neutral fill. Segmented bars use 2 pt gaps. |
| `OnePlusStatus` | A 4 pt dot and text. Hollow dot for offline. |
| `OnePlusBadge` | 9 pt SF Mono count. A filled pending badge only for actionable counts. |
| `OnePlusTable` | Fixed columns, a 9 pt uppercase header row on `sidebar` fill, 34 pt rows (28 compact), `lineSoft` separators, hover `raised`, selection `selection`. Native behavior: arrow keys, sort, context menus, type-select. |
| `OnePlusKeyValueRow` | Label leading in `muted`, value trailing in `ink` or SF Mono. |
| `OnePlusEmptyState` | A centered 26 pt glyph, 13 pt medium title, one caption sentence, and an optional neutral button, with at least 40 pt vertical padding. |
| `OnePlusToast` | A non-focusable overlay 20 pt above the content bottom, radius 6, `raised` at 96%, 1 pt `line`, 11 pt text. It also posts an accessibility announcement. |
| `OnePlusSheet` | A native `.sheet` with a 40 pt header (title, optional close), 20 pt body padding, and a footer with trailing actions (Cancel ghost, confirm primary or destructive). Widths 420, 560, or 700. |
| `OnePlusDotTitle` | The Task Manager dot-matrix title. |
| `OnePlusWindowTexture` | The window texture layer. |
| Menu-panel parts | See "Menu-bar panels". |

Button content (owner correction 2026-10-01): the label is vertically
centered in the button frame. A glyph and its label share one center line.
The glyph uses the label's point size and weight, never a larger size, so
the glyph never dominates the text. This applies to every button style and
every custom action tile, including the menu-panel Home actions.

States everywhere: hover changes only fill, line, or text color. Pressed uses
one darker surface step and never moves. Disabled is 0.38 opacity with no
hover. Loading keeps the final bounds. Errors keep the bounds and add a
caption.

Focus (owner correction, repeated, binding): no focus ring, outline, or focus
fill is ever drawn, and no control takes focus when a window or panel opens
or when it is clicked with the mouse, unless the system asks for keyboard
focus visuals: Full Keyboard Access (keyboard navigation) is on, or
VoiceOver is running. Only then do controls show the 1 pt inset neutral
focus line, which never changes layout or gets clipped. Text fields show
only the caret when the person clicks into them. Keyboard operation keeps
working in every case.

## Horizontal density and native feel

Owner correction 2026-10-01: surfaces stacked content into extra rows while
horizontal space stayed empty, and wrapped controls in padded cards, so the
apps felt like a Tailwind web app, not a Mac app.

- Use the width first. Put metadata (time, date, count, size, status) on
  the trailing side of the same row, not on a new line below.
- Related actions sit side by side in one row (for example Review
  Leftovers and Uninstall), never stacked one per row.
- Do not show provenance or help text inline, such as "Updated by NetToys
  Helper". Drop it, or put it behind a small info glyph with a tooltip or
  popover.
- Page toolbars (target fields, search, filters, presets, primary action)
  sit directly on the page in one row. Never wrap a toolbar or a single row
  of controls in a card with padding.
- Cards group rows of content. A card never wraps one control, one value,
  or one line of text. Use the least chrome that keeps groups clear:
  a section title and rows first, a card only when a group needs a boundary.
- Paddings stay at the token values. No oversized inner padding, pill
  badges on every row, hover lifts, or web-style empty space.

## Native behavior contract

A surface fails review if any of these is missing where it applies:

- Select popups and menu buttons use `OnePlusPopupMenu` (custom, with full
  keyboard behavior). Context menus on every list row, tile, and file item,
  and the app's menu bar commands, stay native `NSMenu`s.
- Text input is native: selection, undo, IME, Return commits, and Escape
  cancels or clears. Spell checking is off in code and rule editors.
  External updates wait until marked text commits. Preserve selection and
  undo for the same resource; separate undo state when the resource changes.
- Lists and tables: arrow-key selection, Return opens, Space shows Quick Look
  for files, Delete asks before removing, type-select, multiple selection
  where it helps, drag-out for files, and a context menu.
- Keyboard: Tab traversal in visual order, Command-F focuses search,
  Command-1 to Command-9 select sidebar pages in order, Command-comma opens
  the tool's settings page, Command-W closes the window, and Escape dismisses
  sheets.
- Custom key handlers act only in their owning window and on supported
  modifier combinations. Pass unhandled keys to the native responder.
  Reactivation retains a valid responder; it never resets keyboard work.
- Restore only page and tab state promised by the tool. Validate saved IDs;
  an explicit route overrides saved state. Search text stays transient
  unless the owner approves persistence. Restore windows inside a surviving
  screen, with the titlebar reachable.
- Sheets attach to their window. No web-style centered overlays with a
  dimmed backdrop inside the window.
- Tooltips use `.help`. Every icon-only control has an accessibility label.
- Files: Reveal in Finder, Copy Path, Open With, Quick Look, and Move to
  Trash use the system services.
- Scroll views are native with thin overlay scrollers and never reserve a
  gutter.
- Destructive actions use a native confirmation with the destructive role.

## Motion

Owner correction 2026-10-01: the motion felt web-like and bad. Native Mac
controls do not move on hover.

- Hover and press change only fill, line, or text color, at once, with no
  animation. Nothing moves, nudges, scales, or slides on hover or press
  (no arrow nudge, no lift, no offset).
- Page, tab, and content changes are instant. No opacity, move, or scale
  transitions on content, rows, cards, or panels. Selection indicators
  (tab underline, segment) move at once.
- Sheets, popovers, menus, and window open use system motion only.
- Nothing animates while idle. Spinners, pulses, and indeterminate bars run
  only during real work and stop on completion, error, cancel, or dismissal.
- No scale, bounce, slide, shimmer, parallax, or lifted hover panels.
- Reduce Motion removes nonessential animation and keeps layout identical.

## Menu-bar panels

The Task Manager panel is the pattern for every menu-bar panel: the combined
MacPowerToys panel, the Task Manager panel, the Portman panel, and any
separate tool panel.

- Shell: 356 pt wide. Its height is always the natural height of the
  current tab's content; 90% of the visible screen is only a ceiling for
  content that is taller (owner correction: a short tab must never open as a
  tall, mostly empty panel).
- Tab switching (owner correction): the new tab appears in its final layout
  in the first frame. No intermediate layout, no animated resize that shows
  a broken layout, no content jump. Measure the new content before the
  swap, resize the panel in the same transaction, and keep switching under
  one frame budget.
- Identity and flair (owner correction: panels must not look stale): each
  panel keeps its tool's identity color for its key data, for example
  Portman's blue port numbers and memory bar, Task Manager's coral alert and
  chart line, Cloud Sync's blue transfer progress. Live values use
  sparklines and bars, not only text. Neutral chrome stays neutral.
  Only the body scrolls. One opaque `sidebar` surface. No blur, glass, or
  stacked shells.
- Top bar: padding 10 top, 8 horizontal, 6 bottom (owner correction: more
  room at the top). An icon tab group on the leading side: the tabs sit in
  one container (`track` fill, 1 pt `line`, radius 7, 2 pt inset), 26 pt
  square tabs, 2 pt gaps, radius 5, 13 pt glyphs. Rest `secondary`; hover
  `ink` on a faint fill; selected `ink` on `selection`. Trailing: `Open App`
  as a small ghost text button (70 x 24, the main panel's text style), then
  optional small ghost icon buttons (Settings, Quit).
- Action buttons (Pick Color, Extract Text, Ruler): one row of equal
  buttons, 32 pt high, glyph and label on the same line, centered, radius 6,
  tile fill and line. Never stack the glyph above the label.
- Body: padding 3 top, 8 horizontal, 8 bottom. Content width 338.
- Tiles (`OnePlusMenuTile`): radius 6, one step above `panel` (`#262626`
  dark), 1 pt `line`, 7 x 8 padding, grain 0.11, 5 pt grid gaps, three
  109.33 pt columns. Wide tiles span two columns. A metric tile with history
  (CPU, GPU, Memory) draws it as a quiet area chart behind the whole tile,
  under the text, never as a small chart beside the value.
- Status-item icons use the same modest visual size as the Portman icon.
  A Task Manager item that shows only one metric uses the Task Manager
  glyph, not the metric glyph.
- Sidebar and panel glyphs mirror each tool's icon metaphor (for example a
  slanted ruler, an emergency-stop button for Switch). No two tools share a
  glyph.
- Control rows (Fan, Awake): 30 pt, a leading 13 pt glyph, 10.5 pt label, and
  SF Mono status, with a trailing 24 pt segmented control.
- Section header: a 1 pt `line` divider, 7 pt top padding, a 9.5 pt section
  title, and a trailing link action.
- Instance or item cards: radius 7, a 20 pt header row on a slightly raised
  fill, metric cells separated by 1 pt lines, and a trailing 84 pt action
  column.
- Each panel reopens on its last selected tab. Short pages size to content.
- Status-item left click toggles the panel. Right click and Control-click
  open the same native context menu. Neither path activates the app; an
  explicit Open App action does.
- Measure and cap the panel on the clicked status item's display before
  its first frame. Unrelated history restoration never delays that path.

## Compact applets

Awake, Color Picker, and Text Extractor stay compact applets with the same
tokens, fixed sizes, and components.

- One `window` surface with the ribbon texture, and a 40 pt custom titlebar:
  traffic lights (close, minimize, disabled zoom) centered on `C = 22`, the
  text title at 12.5 semibold 14 pt after the zoom button, and persistent page
  actions trailing 16 pt from the edge.
- Body gutter 16 pt. Sections use `OnePlusCard` and `OnePlusSettingRow`.
- The floating 24 pt round settings button 8 pt from the bottom-right corner
  stays. It toggles Home and Settings. Settings replaces the body.

## Surface recipes

### Main window

Follows `macpowertoys-repaired.html` and its handoff comment.

- Sidebar: the `MacPowerToys` title, search (`Search`, hint `cmd K`), `All
  tools`, the caption `YOUR TOOLS`, one row per registered tool in registry
  order, and bottom nav `Modified` (disabled when nothing differs from
  defaults), `Settings`, and `Exit`.
- All tools: the title `All tools`, the subtitle `Your Mac, a little more
  capable.`, tabs `All tools N`, `Enabled N`, and `Favorites N`, a trailing
  sort select (Default order, Name, Category), and a grid or list toggle.
  Grid: four columns and 12 pt gaps. Card height follows content, with
  equal heights in each grid row. Keep a 40 pt tool icon, name, category
  caption, favorite star (visible on hover or when set), and a reserved
  two-line description. Put the footer row 12 pt below the description,
  with an unlabeled enable switch and a ghost `Open` text button
  without an arrow. Catalog cards have no grain texture (owner correction
  2026-10-01: the page looked too busy). List: 52 pt rows with the same
  parts.
- Tool page: a header with the 40 pt icon, tool name, description, and a
  trailing enable switch. `Open <Tool>` is the primary action: a primary
  button in a fixed action bar at the bottom of the page, right-aligned on
  the 24 pt gutter, above a 1 pt `lineSoft` line. Tabs `Settings`
  and `How to use`, with a trailing `Menu bar` segmented control (None,
  Combined, Separate) for tools that support placement. Settings renders the
  tool's shared settings view built from OnePlusUI cards. How to use renders
  the manual as cards.
- Settings: tabs General, Marketplace, and About. General holds Appearance,
  Windows, Launch, and iCloud. Modified lists every changed setting with its
  tool, value, and default and a reset action. Reset all asks first.
- Enablement, menu-bar placement, runtime state, and window visibility stay
  separate states.
- Settings embedding contract: each tool exposes one settings content view
  that returns only its cards (a `VStack` of `OnePlusCard`s with 16 pt gaps):
  no `OnePlusPage`, no scroll view, no outer padding, no page header, no
  `Spacer`, and no maximum-height frame. The tool's own Settings page wraps
  it in `OnePlusPage`; the main window's tool page places it inside its
  single scrolling page. `ToolSettingsContent` only dispatches by tool id.

### Task Manager

Follows `task-manager.html` with the owner's corrections: fixed 1080 x 660,
the normal system sidebar title, dot-matrix page titles, the 54 pt title row
with the centerline rule (more room above the page title than before),
compact density, and the HTML's spacing and tightness. Pages: Overview,
Processes, CPU, GPU, Memory, Network, Disk, Battery, Sensors, Remote stats,
System Report, About, and Settings. The Task Manager menu panel follows the
HTML panel exactly, except `Open App`, which uses the ghost style.

### Diskman

Uses `diskman-fixed.html` for content, normalized to this file so it feels
native: 1440 x 900, a 216 pt sidebar with ANALYZE (locations and Choose
Folder) and DEVICES sections, the location name as the page title on `C` with
its path as a mono subtitle, header actions (Rescan as primary, a more menu),
a stats card (Space used in accent, Files, Folders, Last scan), tabs
Visualization, Largest files N, and Results with a trailing Treemap or Rings
segmented control and a sort select, a map card with a 260 pt inspector card,
and the unreadable notice as a card row with its action. Treemap tiles use
the storage series `#66504A #4C6272 #6C5A43 #48645E #68546C #745047 #455D70
#706048 #435E60 #5B4E67 #536149`, radius 4, a 1 pt translucent line, and
grain 0.17 (0.22 selected). Native behaviors: double-click drills in, the
breadcrumb and Command-[ go back, Space shows Quick Look, context menus,
drag-out, and Command-R rescans. Modify keeps its write lock and staged
review in the same card and row language. Destructive steps use a native
confirmation.

### Mac Tweaks

Follows `mac-tweaks-design.html`, normalized to the 54 pt title row and the
shared components. Preview artwork stays scoped to Mac Tweaks.

### Other workspaces

Cloud Sync, Logs, Input Devices, System Care, NetToys, and Switch use the
same sidebar, page, card, row, and table anatomy with no tool-specific
chrome. Operational rows (transfers, scan results, log lines) use
`OnePlusTable` or dense cards with the same radii and lines. Settings are a
sidebar page, never a separate window or dialog.

### Portman

The Portman menu panel keeps its current home layout and look. Its other
tabs use the menu-panel parts and OnePlusUI controls.

### Ruler

The FreeRuler overlay keeps its pinned visuals. Ruler Settings and Ruler
Defaults keep native titlebars and use OnePlusUI tokens, cards, rows, and
controls for their bodies.

## Quality gates

A window, panel, or sheet is accepted only after it passes all of these in
both appearances:

1. Top lines: traffic lights and the sidebar title share `C`; the page
   title's first line box starts at `T = 16`, its top edge level with the
   top of the traffic lights.
2. One leading edge per container. Tab labels, section titles, and card
   edges share the gutter.
3. Controls in one row share height and baseline. The control column never
   shifts.
4. Nothing touches a window edge. The first content row starts 16 pt below
   the header block.
5. No clipped or overlapping text at the fixed size. Long values truncate
   with a tooltip.
6. Every state renders: rest, hover, pressed, selected, disabled, focus,
   loading, empty, error, and permission needed.
7. Every native behavior contract item that applies is present.
8. No idle CPU: with the window open and data unchanged, the process stays
   near 0% CPU and adds no timers.
9. Speed: a sidebar page switch commits its new page within 100 ms (no
   blocking work on the main thread in `body`, `onAppear`, or `init`; data
   loads off the main thread and fills in); tables with 1,000 or more rows
   scroll without dropped frames (native row reuse, no per-row tooltips,
   overlays, GeometryReaders, or formatters created in `body`). All windows
   share one main thread, so a window that is occluded, minimized, or not
   showing a live page, and a menu panel that is closed, stops redrawing
   live data (samplers may keep collecting; views stop observing). Live
   charts and progress update the UI at most 4 times per second.
   A warm panel opens within 100 ms, a cold panel within 250 ms, and a
   window within 250 ms. Measure input to the complete final-size frame;
   display submission alone is not proof. Keep synchronous file, process,
   and network work out of input and termination callbacks.
   Startup failures show a recoverable error and preserve user data.
   Shutdown has a time bound and reports critical save failures.
10. Fixed regions: toolbars, inspectors, and footers stay put while rows
    scroll.
11. A capture of the running signed build, compared at the same scale with
   the reference, shows no material difference in spacing, alignment, or
   density.


## App and tool icons

Icons follow the bold, friendly-flat language of current independent macOS
utilities. Each tool gets one oversized metaphor and enough personality to
remain recognizable without a label. The family has three approved treatments:
the tool's **Chosen Color** identity plus the neutral **Midnight** and
**Porcelain** appearance families.

### Appearance strategy

The neutral appearance rule is intentionally inverted against the surrounding
desktop for stronger Dock separation:

- **Light macOS appearance uses Midnight.** The dark tile remains clearly bounded
  against a light desktop and light launcher surfaces.
- **Dark macOS appearance uses Porcelain.** The light tile remains clearly bounded
  against a dark desktop and dark launcher surfaces.
- A tool may explicitly keep its Chosen Color identity in one or both
  appearances. These exceptions are product decisions, not automatic palette
  substitutions.
- Appearance changes are implemented through asset-catalog luminosity variants.
  SwiftUI and AppKit always request the same named image. Do not add per-view or
  per-window theme branches.

#### Neutral palette

| Family | Ground | Echo | Primary glyph | Contrast detail |
|---|---|---|---|---|
| Midnight | `#1C1D22` | `#5B5D66` | `#F4F4F5` | `#25262B` |
| Porcelain | `#E7E7EA` | `#A6A8AF` | `#25262B` | `#F4F4F5` |

Contrast detail is the optional opposing-color mark inside the primary glyph,
such as a cutout, screen, or graduation. It is never a ground, outline, or
second echo. Omit it when the metaphor does not need an internal detail.

Use these exact neutral shades. They are not aliases of the warmer Chosen Color
ink `#23272E` and paper `#F7F5F0`. Mixing the two neutral families within one
variant weakens the deliberate temperature and contrast difference.

#### Tool appearance matrix

| Tool | Light appearance | Dark appearance | Decision |
|---|---|---|---|
| Cloud Sync | Midnight | Chosen Color | Preserve the blue cloud echo in dark mode |
| Logs | Midnight | Porcelain | Use the neutral contrast inversion without an exception |
| Ruler | Chosen Color | Chosen Color | Orange identity is fixed in both appearances |
| Awake | Chosen Color | Chosen Color | Yellow eye identity is fixed in both appearances |
| Color Picker | Chosen Color | Chosen Color | Eyedropper with attached color samples |
| Text Extractor | Chosen Color | Chosen Color | Capture card with a selected text strip |
| Input Devices | Chosen Color | Chosen Color | Ivory mouse with a violet scroll wheel |
| System Care | Chosen Color | Chosen Color | Cleanup tray with one removable block |
| Disk Explorer | Chosen Color | Chosen Color | Owner-selected Sector platter |
| Task Manager | Chosen Color | Chosen Color | Midnight-blue display-and-metrics identity is fixed |
| NetToys | Chosen Color | Chosen Color | Network module with a connected coral port |
| Portman | Midnight | Porcelain | Neutral network-port glyph in both appearances |
| Switch | Chosen Color | Chosen Color | Owner-selected 01-refined emergency-stop switch on an ivory tile |
| Mac Tweaks | Chosen Color | Chosen Color | Owner-selected 01 Faders in both appearances |

Switch uses the same emergency-stop artwork in both appearances and in the
standalone app. Its MacPowerToys image set contains a 512px copy of the
standalone 1024px master. The original mark remains available for the tiny
menu-bar template, where the physical switch would lose detail.

The 2026-09-25 owner request in `spec/icon-refresh-request-list.md` replaces
the prior identities for these six tools. They use 512px PNG image sets with
transparent rounded corners and one universal appearance. Their detailed
material finish follows the owner-selected Sector platter. All remaining tool
icons continue to follow the SVG construction rules below.

For SVG tools, the base `icon.svg` entry is the light-appearance asset. Add `icon-dark.svg`
with a `luminosity: dark` appearance only when the matrix calls for a different
dark asset. Tools that use Chosen Color in both modes keep one universal SVG.

Every new plugin adds its approved light and dark treatment to this matrix
before icon work begins. If its product brief has no approved Chosen Color
identity, use Midnight in light appearance and Porcelain in dark appearance.
An absent matrix row is a blocking metadata defect, never permission to guess a
palette or reuse another tool's semantic hue.

### Construction

- Every active SVG tool-icon appearance uses the same outer SVG template. This
  applies to every remaining SVG tool and light and dark variant.
- Use a `512 × 512` SVG view box and a full-canvas tile.
- Define `clipPath id="tile"` with a `512 × 512` rectangle and `rx="112"`.
  Wrap the ground and all artwork in `<g clip-path="url(#tile)">`.
- Every launcher, sidebar, grid, and tray rendering path also applies the shared
  `toolIconTile(size:)` mask. Its corner radius is `size × 112 ÷ 512`.
- Do not use a local corner radius or rely on the ground shape to clip later
  artwork. A bleeding glyph or band must never replace a rounded corner with a
  sharp one.
- Let the glyph occupy 60–72% of the tile width. Structural elements may bleed
  through the tile edge so the subject feels large instead of sticker-like.
- Build one literal metaphor from the fewest recognizable shapes. Prefer broad
  closed silhouettes and 28–64pt bands over detailed illustration or floating
  linework.
- Every exposed stroke uses `stroke-linecap="round"` and
  `stroke-linejoin="round"`. Round the ends of filled shapes too.
- Chosen Color icons normally create depth with meaningful overlap, such as one
  object passing behind another. Midnight and Porcelain use the approved solid
  echo construction below.
- Use punch-through details sparingly and only when they clearly read as a
  physical cutout. Never use one for a catchlight or decorative control.
- New Chosen Color icons use warm off-white `#F7F5F0` and charcoal `#23272E`,
  never pure white or black. The Chosen Color palette table is the binding
  legacy exception: Cloud Sync and Logs retain their listed
  `#FFFFFF` foregrounds. Neutral Midnight/Porcelain assets always use their own
  closed glyph tokens rather than either white.
- SVG icons use no decorative outline, gloss, blur, rim light, or soft drop
  shadow. A gradient is allowed only when color itself is the metaphor or part
  of an approved legacy Chosen Color asset. The six bitmap icons above keep
  their shallow material lighting from the approved visual direction.

The base application icon is the deliberate exception to the tool/plugin SVG
construction rules above. `powertoys/AppIcon.icon` uses Icon Composer's
`1024 × 1024` layered source canvas and solid document fill; its SVG layers
must not bake in the rounded-square ground or any lighting effect. The symbol
uses the same Lucide-derived outline flexed-arm geometry as the menu-bar glyph,
centered at roughly 58% of the source-canvas width so it remains clear at Dock
and Raycast sizes. Its secondary layer keeps the `52px` right/down echo offset
at that scale (`26px` on a 512 canvas), rather than adopting the tool-icon
`18 × 22` echo. Icon Composer supplies the system enclosure, lighting, and
prior-generation fallback.

### Solid echo construction

Midnight and Porcelain derive their depth from one flat copy of the semantic
glyph behind the foreground:

1. Construct the complete semantic foreground silhouette first.
2. Duplicate that silhouette once and place the copy behind the foreground.
3. Offset the echo by exactly `18px` right and `22px` down with
   `transform="translate(18 22)"`.
4. Fill or stroke the complete echo with the family echo token. Neutral echoes
   are fully opaque. They never use blur, gradients, blend modes, or multiple
   offsets.
5. Keep the echo's geometry, scale, rotation, line caps, and line joins identical
   to the foreground. Only its position and color differ.
6. The echo may be clipped by the rounded-square ground. Do not shrink the glyph
   merely to keep the echo inside the tile.

Compound glyphs must behave as one silhouette. Put all echo pieces inside one
`<g>` with one shared fill or stroke. When a Chosen Color legacy icon uses a
translucent semantic echo, apply `opacity` to the group, never to overlapping
children. This prevents darker seams where parts overlap.

At 32px the echo should read as a narrow lower-right depth cue, not a duplicate
icon. If it becomes a second symbol, the foreground is too small or the offset
has been changed.

### Chosen color palette

| Tool | Ground | Foreground | Semantic accent |
|---|---|---|---|
| Cloud Sync | `#1C1D22` | `#FFFFFF` at `.92` | `#5B8DEF` cloud echo at `.30` |
| Logs | `#475569` to `#0F172A` | `#FFFFFF` | Terminal prompt |
| Ruler | `#F04E23` | `#23272E` | Cream graduation cutouts |
| Awake | `#F5B71E` | `#23272E`, `#F7F5F0` | Cream eye catchlight |
| Task Manager | `#002B26` | `#E0FFF8` | M02 Scope trace identity |
| Mac Tweaks | `#25262B` and `#32333A` panel | `#F7F5F0` faders | `#AC86E8` center handle |

The six bitmap identities in the appearance matrix take their colors from
their approved `icon.png` assets, rather than this SVG palette table.

New Chosen Color tools should receive their own semantic hue unless a documented
product decision deliberately links them to an existing color. Neutral
appearance variants always use the closed Midnight or Porcelain palette instead
of inventing tool-specific grays.

### Asset catalog structure

An image set with different appearance assets uses this shape:

```json
{
  "images": [
    {
      "filename": "icon.svg",
      "idiom": "universal"
    },
    {
      "appearances": [
        {
          "appearance": "luminosity",
          "value": "dark"
        }
      ],
      "filename": "icon-dark.svg",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "preserves-vector-representation": true
  }
}
```

- `icon.svg` is always the light-appearance result from the matrix.
- `icon-dark.svg` is always the dark-appearance result from the matrix.
- Both files remain vector SVGs at a `512 × 512` view box.
- Keep `preserves-vector-representation` enabled for appearance-aware image
  sets.
- If both appearances use the same Chosen Color icon, keep a single universal
  image entry (`icon.svg` or an approved `icon.png`). Do not duplicate an
  identical dark file.
- Launcher cards and the Dock use the same named asset. Do not create a separate
  Dock-only color treatment.

### Generation workflow

The steps below apply to SVG tool icons. The six bitmap icons named in the
appearance matrix use 512px RGBA PNG sources, one universal image entry per
image set, transparent corners, and 512/64/32/16px visual checks.

1. Pick one literal object or action for the tool. Do not combine metaphors.
2. Sketch and approve one master semantic glyph at 512px using rounded filled
   shapes and broad round-capped bands. Make it larger than feels initially
   comfortable. Geometry is approved independently of its appearance palette.
3. Look up the tool in the appearance matrix. For a new plugin, add the required
   row using the rule above before continuing. Never assume every tool receives
   both neutral families.
4. Follow the matrix branch. If Chosen Color is approved, apply its documented
   palette to the master glyph. For each Midnight or Porcelain result, preserve
   the same master geometry and apply only the closed neutral palette plus the
   `18 × 22` solid echo. A neutral-only plugin produces Midnight and Porcelain
   directly and has no Chosen Color asset or invented semantic hue. Never
   redesign the metaphor between appearances.
5. Save the light result as
   `Assets.xcassets/<Tool>Logo.imageset/icon.svg`. Add `icon-dark.svg` and the
   luminosity appearance entry only when the dark result differs.
6. Validate every referenced SVG and preview each appearance from the repository
   root:

   ```sh
   xmllint --noout powertoys/Assets.xcassets/<Tool>Logo.imageset/icon.svg
   xmllint --noout powertoys/Assets.xcassets/<Tool>Logo.imageset/icon-dark.svg
   sips -s format png powertoys/Assets.xcassets/<Tool>Logo.imageset/icon.svg \
     --out /tmp/<Tool>-icon-light.png
   sips -s format png powertoys/Assets.xcassets/<Tool>Logo.imageset/icon-dark.svg \
     --out /tmp/<Tool>-icon-dark.png
   ```

7. Inspect every active appearance at 512, 64, 32, and 16px. The metaphor must
   still read at 32px, and the echo must remain a depth cue. At 16px the glyph
   may simplify, but it must not collapse into visual noise.
8. Build the app so `actool` validates `Contents.json`, both luminosity slots,
   and vector preservation. Check the icon once on a light desktop and once on a
   dark desktop before release.

Menu bar icons are the exception: use a single-color template silhouette of the
same metaphor because macOS controls their tint.
