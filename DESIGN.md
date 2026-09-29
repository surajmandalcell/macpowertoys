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
  content-top: 58           # page title first line box; sidebar content starts at 54
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
menu-panel: { width: 356, max-height-fraction: 0.9, top-bar-padding: [10, 8, 6], tab-group-radius: 7, tab: 26, tab-gap: 2, body-inset: 8, tile-radius: 6, tile-gap: 5, columns: 3, action-button-height: 32 }
popup-menu: { padding: 5, radius: 7, item: 28, item-compact: 24, item-radius: 4, item-padding: 9, max-visible-items: 12 }
performance: { page-switch-ms: 100, table-rows-smooth: 1000 }
texture: { ribbon: [700, 220], ribbon-drawn: [630, 198], ribbon-opacity-dark: 0.20, ribbon-opacity-light: 0.10, grain: [240, 150], card-grain: 0.14, menu-grain: 0.11, chart-dot-cell: 4 }
motion: { hover: 0.10, selection: 0.14, content: 0.12, idle-animation: none }
---

# MacPowerToys Design Language

Version 14 (OnePlusUI), adopted 2026-09-29. It replaces the earlier
material-based contract. It is the complete visual and window-structure
contract for every window, menu-bar panel, sheet, and settings page. Tool icon
rules live in [spec/design/icons.md](spec/design/icons.md).

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
| Tab label | 12 | 11 | regular | 0 | `muted`, selected `ink` |
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

`T = 58` pt below the window's top edge. The sidebar's first element (search
field or first navigation row) starts at 54. The page header's first line
box starts at `T`, 4 pt lower, so the body never sits higher than the
sidebar. Header actions center on the page title's first line.

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
  top-right corner at 0.14 (catalog cards and metric tiles) or 0.11 (menu
  tiles), clipped to the card. Text, icons, controls, rows, and list views
  never carry texture.
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
C=27  (empty drag area, texture only)
T=58  Page title                          [action] [action]
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
- A setting that needs an explanation puts one caption line under the label
  and grows the row to 56 pt. Never wrap a label inside 44 pt.
- Cards pair in two equal columns when both are short. Long cards take the
  full width.
- Controls apply immediately. There is no Apply or Discard bar. An invalid
  text value stays in its field with an error caption; it never clamps
  silently.

## Components (OnePlusUI)

Use only these. Names are the package API.

| Component | Spec |
|---|---|
| `OnePlusButtonStyle(.neutral)` | 28 pt high, radius 6, 1 pt `line`, `raised` fill, 10 pt padding, 6 pt icon gap, 12 pt `controlInk`. Hover `raisedHover`, pressed `pressed`. |
| `.primary` | Same geometry, `primaryFill` with `primaryInk`, medium weight. One per view state. |
| `.ghost` | Same geometry, no fill or line until hover (`raised`). Text `secondary`, hover `ink`. |
| `.destructive` | `dangerFill`, `dangerLine`, and `danger` text. Always paired with a confirmation. |
| `.icon` | 28 pt square, radius 5, 14 pt glyph, transparent until hover. Needs `.help` and an accessibility label. |
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

States everywhere: hover changes only fill, line, or text color. Pressed uses
one darker surface step and never moves. Disabled is 0.38 opacity with no
hover. Focus is a fill change plus a 1 pt inset neutral line; Full Keyboard
Access keeps the system ring. Loading keeps the final bounds. Errors keep the
bounds and add a caption.

## Native behavior contract

A surface fails review if any of these is missing where it applies:

- Select popups and menu buttons use `OnePlusPopupMenu` (custom, with full
  keyboard behavior). Context menus on every list row, tile, and file item,
  and the app's menu bar commands, stay native `NSMenu`s.
- Text input is native: selection, undo, IME, Return commits, and Escape
  cancels or clears. Spell checking is off in code and rule editors.
- Lists and tables: arrow-key selection, Return opens, Space shows Quick Look
  for files, Delete asks before removing, type-select, multiple selection
  where it helps, drag-out for files, and a context menu.
- Keyboard: Tab traversal in visual order, Command-F focuses search,
  Command-1 to Command-9 select sidebar pages in order, Command-comma opens
  the tool's settings page, Command-W closes the window, and Escape dismisses
  sheets.
- Sheets attach to their window. No web-style centered overlays with a
  dimmed backdrop inside the window.
- Tooltips use `.help`. Every icon-only control has an accessibility label.
- Files: Reveal in Finder, Copy Path, Open With, Quick Look, and Move to
  Trash use the system services.
- Scroll views are native with thin overlay scrollers and never reserve a
  gutter.
- Destructive actions use a native confirmation with the destructive role.

## Motion

- Hover and press: 0.10 s ease. Selection and segment indicator: 0.14 s.
  Content swap: 0.12 s opacity. Sheets and popovers: system motion.
- Nothing animates while idle. Spinners, pulses, and indeterminate bars run
  only during real work and stop on completion, error, cancel, or dismissal.
- No scale, bounce, slide, shimmer, parallax, or lifted hover panels.
- Reduce Motion removes nonessential animation and keeps layout identical.

## Menu-bar panels

The Task Manager panel is the pattern for every menu-bar panel: the combined
MacPowerToys panel, the Task Manager panel, the Portman panel, and any
separate tool panel.

- Shell: 356 pt wide, content-sized, capped at 90% of the visible screen
  height (owner correction: never cut content short to keep a panel small).
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
  109.33 pt columns. Wide tiles span two columns.
- Control rows (Fan, Awake): 30 pt, a leading 13 pt glyph, 10.5 pt label, and
  SF Mono status, with a trailing 24 pt segmented control.
- Section header: a 1 pt `line` divider, 7 pt top padding, a 9.5 pt section
  title, and a trailing link action.
- Instance or item cards: radius 7, a 20 pt header row on a slightly raised
  fill, metric cells separated by 1 pt lines, and a trailing 84 pt action
  column.
- Each panel reopens on its last selected tab. Short pages size to content.

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
  Grid: four columns, 12 pt gaps, 151 pt cards with a 40 pt tool icon, name,
  category caption, favorite star (visible on hover or when set), two-line
  description, enable switch with an `Enabled` caption, and `Open` with an
  arrow. List: 52 pt rows with the same parts.
- Tool page: a header with the 40 pt icon, tool name, description, and a
  trailing enable switch and `Open` (neutral small, 26 pt). Tabs `Settings`
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
   title's first line box starts at `T`, never above the sidebar's first
   element.
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
10. Fixed regions: toolbars, inspectors, and footers stay put while rows
    scroll.
11. A capture of the running signed build, compared at the same scale with
   the reference, shows no material difference in spacing, alignment, or
   density.
