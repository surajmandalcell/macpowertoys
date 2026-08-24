---
version: 11
name: MacPowerToys
description: Design language for MacPowerToys and its child tools
colors:
  hover: "Color.primary.opacity(0.06)"          # the ONLY hover background
  hover-strong: "Color.primary.opacity(0.1)"    # filled buttons only
  pressed: "Color.primary.opacity(0.1)"
  pressed-strong: "Color.primary.opacity(0.18)" # filled buttons only
  focus-ring: "Color.accentColor.opacity(0.85)"
  on-accent: "opaque black or white, chosen for >=4.5:1 contrast"
  focus-ring-on-accent: "colors.on-accent"
  disabled-opacity: 0.38
  selection-light: "Color.accentColor.opacity(0.1)"
  sidebar-selection: "native selected-content background; emphasized while key, unemphasized while inactive"
  selection-strong: "Color.accentColor"
  selection-strong-text: "opaque black or white, chosen for >=4.5:1 contrast"
  card: "Color.primary.opacity(0.03)"           # grids, subtle depth
  card-detail: "Color.primary.opacity(0.05)"    # detail/log views, softer contrast
  separator: "native separator at 0.22 opacity; 0.44 with increased contrast"
  content-background: "Color(nsColor: .windowBackgroundColor)"
  text-subdued: "Color.primary.opacity(0.75)"
  text-preview: "Color.secondary.opacity(0.6)"
  icon-ink: "#23272E"
  icon-paper: "#F7F5F0"
  icon-midnight-ground: "#1C1D22"
  icon-midnight-echo: "#5B5D66"
  icon-midnight-glyph: "#F4F4F5"
  icon-midnight-detail: "#25262B"
  icon-porcelain-ground: "#E7E7EA"
  icon-porcelain-echo: "#A6A8AF"
  icon-porcelain-glyph: "#25262B"
  icon-porcelain-detail: "#F4F4F5"
  icon-ruler: "#F04E23"
  icon-awake: "#F5B71E"
  icon-color-picker: "#23272E"
  icon-text-extractor: "#2155B0"
  icon-input-devices: "#1C1D22"
  icon-system-care: "#17181B"
  icon-system-monitor: "#002B26"
typography:
  launcher-detail-title: { size: 17, weight: medium, relative-to: headline }
  title: { size: 13, weight: medium, relative-to: body }
  body: { size: 13, weight: regular, relative-to: body }
  row: { size: 13, weight: regular, relative-to: body }
  control: { size: 12, weight: regular, relative-to: callout }
  tab: { size: 12, weight: medium, relative-to: callout }
  compact-action: { size: 11, weight: medium, relative-to: caption }
  badge: { size: 11, weight: medium, relative-to: caption }
  caption: { size: 11, weight: regular, relative-to: caption }
  section-header: { size: 10, weight: medium, relative-to: caption2, transform: uppercase, color: secondary }
  code: { size: 12, design: monospaced, relative-to: callout }
  micro: { size: 10, weight: regular, relative-to: caption2 }
rounded:
  control: 4        # toggles, small buttons
  field: 6          # text fields, icon buttons, pills, chips
  titlebar-control: 6 # compact titlebar buttons only
  row: 8            # list rows, message bubbles, tray tabs
  section-card: 10  # compact applet section cards
  card: 12          # launcher, workspace, and operational cards
spacing:
  gutter: 20        # one shared left edge for titles, tabs, headers, cards
  color-picker-body-gutter: 12
  card-padding: 14  # inner padding of section cards
  section-gap: 16
  section-label-gap: 8
  sidebar-title-leading: 84   # 12pt minimum after the zoom traffic light
  compact-title-leading: 60   # reclaims the hidden zoom position
  compact-titlebar-top: 4     # applied once to the complete row
  content-top: 44   # one 4pt gap below the 40pt top strip
  header-top: 0     # window-top strips hug the top (10pt vertical inset)
  floating-control-edge: 8
  tray-group-inset: 4
  tray-group-top: 20
  tray-group-body-gap: 6
  tray-body-top: 10
  tray-body-bottom: 14
  tray-footer-top: 8
  tray-footer-bottom: 10
windows:
  launcher: { content-width: 780, content-height: 700, sidebar-width: 220, card-min-height: 110, resizable: false }
  workspace: { min-content-width: 640, min-height: 600, sidebar-compact: 220, sidebar-data: 240, sidebar-conversation: 260, resizable: true }
  compact-applet: { width-options: [420, 480, 560], min-height: 250, max-height: 600, resizable: false }
components:
  icon-button: { size: 24, radius: 6, hover: colors.hover }
  sidebar-search: { min-height: 32, radius: 6, inset-x: 12, inner-padding: 8 }
  sidebar-row: { min-height: 28, radius: 8, icon: 16, inset-x: 8, gap: 8, selected-bg: colors.sidebar-selection, selected-text: native-selected-content-text, selected-custom-artwork: original-colors }
  sidebar-primary-action: { min-height: 34, radius: 8, inset-x: 12, bg: accent }
  tray-tab: { min-height: 28, radius: 8, inset-x: 10, gap: 4, selected-bg: colors.selection-strong }
  compact-titlebar-control: { height: 24, radius: 6, hover: colors.hover }
  workspace-action: { height: 24, control-size: small }
  structural-divider: { opacity: 0.22, increased-contrast-opacity: 0.44 }
  tab-pill: { padding-x: 10, padding-y: 5, radius: 6, selected-bg: colors.hover }
  section-card: { radius: 10, bg: colors.card-detail, padding: spacing.card-padding }
  progress-bar: { height: 6, track: "Color.primary.opacity(0.08)" }
---

# MacPowerToys Design Language

## Overview

MacPowerToys is a dense, quiet, native-feeling macOS utility. It should read like a
first-party Apple tool that a careful engineer polished: flat surfaces, one accent
color doing all the talking, small type, generous alignment discipline, zero
decoration for its own sake. Nothing bounces, glows, or gradients. When in doubt,
remove chrome rather than add it.

Animations exist only to prevent jarring layout jumps (0.15–0.18s easeInOut) —
never as ornament.

This document is the complete visual and window-structure contract. A tool's
product brief still owns its purpose, operations, data, copy, and domain states.
Do not infer those from a tool name. Given that brief, an unfamiliar designer
must be able to choose one family below, instantiate its shell without guessing,
and fill the body using the shared components and quality gates.

## Native Visual Baseline

The current app is the visual source of truth. This document explains how to
extend it; it does not authorize a new web design language. Resolve conflicts in
this order:

1. Current SwiftUI and AppKit implementation in `powertoys/Views/Components/`.
2. The current reference screenshots listed below.
3. The numeric contracts and family recipes in this file.
4. Library defaults, sample galleries, and generated mockups.

Normative native-appearance references:

| Family or control grammar | Reference |
|---|---|
| Main launcher | `docs/screenshots/macpowertoys-launcher.png` |
| Compact applet, general | `docs/screenshots/awake.png` |
| Compact tabs and search | `docs/screenshots/color-picker.png` |
| Dense native controls | `docs/screenshots/ruler.png` |
| Compact history and settings | `docs/screenshots/text-extractor.png` |

The screenshots bind density, visual weight, control morphology, surface
continuity, and named tool artwork. Source binds behavior and any detail that a
still image cannot show. Text Extractor's older screenshot may show obsolete
traffic-light geometry; the compact titlebar contract below overrides that one
detail.

MacPowerToys is native-controls-first. Use the real SwiftUI or AppKit `Button`,
`Toggle`, `Picker`, `Menu`, `TextField`, `Stepper`, `DatePicker`, `Slider`, and
`ColorPicker` whenever that control exists. Do not redraw these as outlined web
buttons, equal-width option grids, custom switches, or card-based form fields.
Custom appearance is limited to the titlebar, material shells, sidebar rows,
search surfaces, tab pills, named cards, badges, and the exact shared patterns
defined here.

## Interaction Hierarchy

Apply the relevant [Laws of UX](https://lawsofux.com/) to every new and existing
surface. Familiar native controls satisfy Jakob's Law. Compact full-row targets
satisfy Fitts's Law without mobile-sized chrome. Proximity and common region
group related controls. Hick's Law limits visible choices. The Von Restorff
effect reserves accent emphasis for the current primary action.

- Show one primary action per state. Put it in the stable top strip or the
  action row nearest its result.
- Put related controls on one row or in multiple columns while labels remain
  clear. Do not spend one full row on each small toggle, picker, or button.
- Use native bordered buttons, switches, checkboxes, menus, and segmented
  controls. Do not redraw them as large web-style rectangles or option cards.
- Use cards only for entities, results, or a group that must read as one unit.
  Use open rows for ordinary settings and actions.
- Keep product copy task-specific. Do not expose implementation tradeoffs,
  research notes, API limits, or design conversations in a task screen. Put a
  limit in About only when it changes a decision the person makes.

A browser artifact passes only after comparison beside the appropriate current
screenshot. Raw wireframes, default component-gallery examples, and generic
dashboard mockups are not fidelity evidence.

## Colors

Interactive surfaces are **opacity layers over `Color.primary` or
`Color.accentColor`**. Text uses semantic system colors, including the
contrast-aware black-or-white `on-accent` role. Never put raw hex in UI code;
hex lives only in icon assets. This keeps light and dark mode free.

- Hover is always `primary.opacity(0.06)`. Not 0.05, not 0.08. Filled buttons may
  deepen to 0.1 on hover.
- Pressed is `primary.opacity(0.1)` on an unfilled control and 0.18 on a filled
  control. Disabled controls use 0.38 opacity and do not react to hover or
  press. Filled controls keep their accent base and add the primary interaction
  layer instead of changing hue.
- Text and symbols on an accent fill use opaque black or white, whichever
  reaches at least 4.5:1 contrast against the resolved accent. The inset focus
  ring uses that same contrast-aware color and reaches at least 3:1 against the
  fill. Never assume white is readable on a person-selected accent.
- Selection-light is accent at 0.1 for selected content rows and inline choices.
  Sidebar navigation uses the native selected background and foreground.
  Branded sidebar artwork keeps its original colors in every selection state.
  Selection-strong is reserved for tray tabs. Tab pills are the quiet
  exception: their persistent selected surface is primary 0.06 with ordinary
  primary text, not an accent layer, accent text, or underline.
- Keyboard focus uses the system focus effect except for the repaired compact
  titlebar treatment defined below.
- Cards: 0.03 for grids and subtle depth; 0.05 where softer contrast is wanted
  (detail sheets, logs).
- Launcher and workspace content panes sit on
  `Color(nsColor: .windowBackgroundColor)`. Their sidebars use an
  `NSVisualEffectView` with `.sidebar` material, `.behindWindow` blending, and
  `.active` state. A compact applet is different: its complete titlebar and body
  share one `.hudWindow` material surface over a clear, non-opaque `NSWindow`.
- Status tints: green = healthy/complete, orange = retrying/attempts,
  red = failure, secondary = idle/cancelled.

## Typography

San Francisco only. The values below are the standard-appearance bases for
`.system(size:weight:)`; body, row, card, field, and sheet text feeds the base
through `@ScaledMetric(relativeTo:)` and supports the complete SwiftUI dynamic
type range through `.accessibility5`. Non-action window titles use the exact
base size and expose their full text to accessibility. Action labels scale or
relocate according to their family rule. The role scale is closed:

17 medium (launcher detail title only) · 13 medium (titles and sidebar primary
actions) · 13 regular (body/rows) · 12 regular (controls) ·
12 medium (tab labels) ·
12 monospaced (paths, patterns, code) · 11 medium (compact actions, launcher
`Open`, badges) · 11 regular (captions, metrics) ·
10 medium UPPERCASE secondary (section headers) · 10 (micro/tertiary detail).

The `relative-to` mapping is binding: 17pt detail titles use `.headline`; 13pt
titles, body, and rows use `.body`; 12pt controls, tabs, and code use `.callout`;
11pt compact actions, badges, and captions use `.caption`; and 10pt section or
micro text uses `.caption2`. Do not select a different `Font.TextStyle` per
window.

Numbers that update live get `.monospacedDigit()` and
`.contentTransition(.numericText())`.

## Layout & Spacing

**One left edge.** Within any container, titles, tab strips, section headers, and
card edges share a single leading gutter. The default content gutter is 20pt;
only the family rules may replace it with 24pt launcher-grid padding, a 16pt
dense-list gutter, a 12pt sidebar gutter, or Color Picker's 12pt body gutter.
Never invent an in-between alignment point. Align a tab strip's leading pill
boundary to the gutter, never to the pill's inset text.

- Sidebar titles: center inside a 40pt top strip and start 84pt from the window
  edge, leaving at least 12pt after the zoom traffic light.
- Search field container: `.top, 44` / `.horizontal, 12` / inner `.padding(8)`.
- Launcher content and a workspace's first body surface align near the sidebar
  search top at y=44. Workspace top strips themselves hug y=0. Compact bodies
  follow their own 40pt titlebar and 16pt internal inset.
- Use only the family-defined top coordinate. Never stack a second page, header,
  or local top offset on it.

## Elevation & Materials

Depth comes mainly from opacity layers and vibrancy. Launcher and workspace
sidebars use `.sidebar` material extending seamlessly to the window top.
Compact applets use `.hudWindow` material across the complete shell. Do not
replace either material with an opaque gray fill or a translucent layer whose
backdrop cannot show through.

The system owns the window shadow. Custom surfaces are shadowless except for a
launcher tool card while hovered: black at 0.12, radius 8, y offset 2, paired
with its documented hover stroke. Do not spread that exception to section cards,
workspace rows, titlebars, or ordinary buttons.

## Shapes

Closed radius scale — pick the smallest that fits the role:

- **4pt** small buttons, toggles
- **6pt** text fields, icon buttons, chips, tab pills
- **8pt** list rows, message bubbles, tray tabs, and the full-width sidebar
  primary action because it occupies a navigation-row slot
- **10pt** compact applet section cards
- **12pt** launcher, workspace, and operational cards

Buttons never become capsules. Capsules are reserved for progress tracks and
compact state or count badges whose changing width benefits from the shape.
Fields, chips, tab pills, and action buttons use their assigned fixed radius.

## Window Families

Every top-level `Window` scene must choose exactly one family before its layout
is designed. The family controls the window chrome, resizing, title ownership,
navigation, and content anatomy. Sheets, popovers, and transient overlays are
subordinate surfaces rather than scenes. Window families are architectural
roles, not launcher categories and not user-facing labels.

Choose the family with this decision order:

1. The one MacPowerToys catalog window is the **main launcher**.
2. A tool that needs a persistent sidebar, simultaneous list/detail context,
   large data sets, or useful user resizing is a **full workspace**.
3. A tool with one bounded primary workflow and no sidebar is a **compact
   applet**. It may use up to three local tabs that replace the same small body,
   and may replace that body with Settings. Local tabs and Settings do not count
   as workspace destinations because they never create persistent navigation or
   simultaneous panes.

Do not hybridize them. A compact applet never gains a sidebar; a full workspace
never gains `CompactTitlebar`; the launcher never hosts a tool's history,
workspace, or live operational surface. The launcher may embed the exact shared
settings view used by the tool so configuration has one implementation. If a
proposed tool does not fit, simplify its task or choose the next larger family
instead of combining chrome from two families.

| Family | Purpose | Size | Navigation | Title owner |
|---|---|---|---|---|
| Main launcher | Discover and open tools | Fixed 780×700 content | 220pt catalog sidebar | Sidebar title |
| Full workspace | Sustained, multi-context work | Resizable; content at least 640pt wide | 220–280pt tool sidebar | Sidebar title |
| Compact applet | One immediate bounded task | Fixed width and bounded height | No sidebar | 40pt compact titlebar |

All three use `.windowStyle(.hiddenTitleBar)`. Launcher and workspace sidebars
extend their material to the window top, with native traffic lights floating
over them. Compact applets draw their own titlebar inside the window. Never use
`.unifiedCompact`, native toolbar action grouping, `NavigationSplitView`,
`NavigationView`, or manually configured native titlebar content.

Each SwiftUI-owned tool opens in its own single-instance `Window` scene with
`tabbingMode = .disallowed`. Tools never auto-open at launch unless their own
start-at-launch setting is enabled. Reopening an existing tool raises that
window instead of creating a duplicate.

Hidden chrome must remain draggable. In launcher and workspace windows, the
unoccupied top background, sidebar title region, and content-strip background
drag the window; search fields, buttons, tabs, and other controls do not. In a
compact applet, the 40pt titlebar background and title drag while its actions do
not. Double-click delegates to the person's macOS titlebar preference. A fixed
applet cannot zoom, so the system may minimize it when configured or otherwise
leave it unchanged. Never implement custom double-click behavior.

### Ruler AppKit Overlay Exception

Ruler intentionally sits outside the three SwiftUI window families. Its working
surface is FreeRuler's borderless 40pt AppKit L-shaped overlay, with movable and
resizable horizontal and vertical wings. It has no `CompactTitlebar`, traffic
lights, launcher material, fixed 560×600 scene, or in-window settings page.

FreeRuler owns multiple ruler windows, settings behavior, the color panel,
units, grouping, opacity, float, shadow, keyboard commands, and persistence.
MacPowerToys owns discovery, on-demand launch, routing, orange identity, and the
visual chrome for Ruler Settings and Ruler Defaults. Preserve the pinned
FreeRuler overlay visuals and interaction behavior. Style both settings windows
with the shared utility material, gutters, section rhythm, cards, and action
hierarchy. They retain normal visible native titlebars and never use
`CompactTitlebar` or overlay chrome.

### Main Launcher

The launcher is a catalog, not a dashboard. It helps a person find a tool,
configure it, understand it, and open its own single-instance window. The
launcher closes after opening a tool. It may reuse tool settings controls, but
never displays running metrics, history, or workspace content.

Canonical anatomy:

```text
780 × 700 SwiftUI content, fixed
┌──────── sidebar 220 ────────┬──────── content 560 ─────────┐
│ traffic lights  title       │                              │
│ search at y=44              │ grid or tool detail at y=44  │
│ All Tools                   │                              │
│ CATEGORY                    │                              │
│   tool rows                 │                              │
│                             │                              │
│ Logs / Settings / Exit      │                              │
└─────────────────────────────┴──────────────────────────────┘
```

- The SwiftUI scene content and sidebar are fixed at 780×700 and 220pt. The
  current screenshot is 780×732 because the captured `NSWindow` frame adds
  32pt above that content size. Never shrink the content to force the outer
  capture to 780×700. Do not resize, collapse, or add an inspector.
- The sidebar title is `MacPowerToys`, centered in the 40pt top strip and 84pt
  from the leading window edge. It is the only app title.
- The custom search field uses 12pt sidebar insets and starts at y=44. It is at
  least 32pt high, uses `Search` as its placeholder, and filters registered tool
  names and search keywords while preserving registry category order. Never
  invent family filters such as “Quick tools” or “Workspaces”; family is not
  catalog taxonomy.
- Navigation is `All Tools`, then the registry's uppercase category headers and
  tool rows with a 28pt minimum and 4pt stack spacing. Rows use a 16pt icon,
  8pt internal leading/trailing inset, and 8pt radius. Each header starts after
  16pt and leaves 4pt before its first row. The footer has the same rows, 12pt
  outer inset and bottom padding, and contains Logs, Settings, and Exit. The
  material transition is the pane boundary; do not add a vertical divider.
- Launch opens `All Tools` with an empty search. Restore a prior selection only
  within the same running launcher session, never across a fresh app launch.
- `All Tools` content begins at y=44. It uses 24pt horizontal and bottom
  padding, an adaptive two-column grid with 220pt minimum columns, and 16pt
  row/column gaps.
- A launcher tool card is at least 110pt high at default text sizes, with 12pt outer
  padding and 12pt radius. Its anatomy is: 36pt named tool icon; 13pt medium
  name; 10pt uppercase category; two lines of 12pt secondary description; and
  an unlabeled mini enable switch bottom-leading; and a native small `Open`
  button bottom-trailing. Rest is 0.03. Hover is 0.06
  with a 1pt primary 0.06 stroke and the one allowed custom shadow: black 0.12,
  radius 8, y offset 2. Accessibility text may
  expand the complete grid row, never only one card in that row.
- Clicking a card selects its detail page. Clicking `Open` opens the tool, and
  its unlabeled enable switch changes availability without selecting or
  opening it. These actions must remain separately accessible. A disabled card
  stays selectable so the tool can be re-enabled, while `Open` is disabled.
- A tool detail page uses a 20pt gutter, 30pt named tool icon, a 17pt medium
  detail title, description, a trailing unlabeled enable switch beside a native
  regular `Open` button, and `Settings` / `How to Use` tabs whose first pill
  begins at the 20pt content edge. It opens on Settings and renders the same settings view as the
  tool window; Ruler links to its existing AppKit Settings and Defaults panels.
  How to Use keeps 12pt-radius instruction cards. Do not use the 17pt title
  elsewhere.
- Enablement has one persistent source. Every tool is enabled by default. A
  disabled tool is absent from the menu-bar tab strip, cannot be launched by
  cards, shortcuts, deep links, CLI routes, or start-at-launch, and releases
  background power/transfer work where applicable.
- Launcher cards communicate identity and discovery, not live status. Show a
  badge only for a compatibility, permission, or availability state that
  changes whether the tool can open.

Every plugin must provide a stable ID, display name, registry category,
one-line description, search keywords, named icon asset, and either the
workspace or applet family. Missing metadata is a plugin defect; the launcher
must not invent labels, categories, icons, or descriptions from implementation
details. New plugins follow stable registry ordering and the same card anatomy,
so a larger catalog scrolls rather than changing the grid language.

The built-in launcher metadata below is a preview fixture, not the product-copy
source of truth. It lets a designer reproduce the reference catalog when no
runtime registry is available. Production always uses the registry and each
tool's product brief.

| Tool | Category / family | Card description |
|---|---|---|
| AI History | Developer / workspace | Browse every Claude Code conversation on this Mac - live, searchable, and bookmarkable. |
| Cloud Sync | Files / workspace | Move files between your Mac and cloud storage with live progress, automatic retries, and ignore rules. |
| Logs | System / workspace | View application logs and diagnostics. |
| Ruler | Developer / AppKit overlay | Measure the screen with movable, resizable rulers in pixels, millimeters, or inches. |
| Awake | System / applet | Keep your Mac awake indefinitely, for a duration, or until a chosen time without changing Energy settings. |
| Color Picker | Developer / applet | Pick any onscreen color, copy it instantly, and keep a compact searchable history of useful values. |
| Text Extractor | Text / applet | Select text anywhere on screen and copy it using private, fully on-device Apple Vision recognition. |
| Input Devices | System / workspace | Tune mouse and trackpad scrolling independently, including direction, speed, horizontal movement, and wheel smoothing. |
| System Care | System / workspace | Understand storage, preview safe cleanup, remove apps, and access advanced Mole maintenance without hidden privilege prompts. |
| System Monitor | System / workspace | Watch CPU, memory, disk, network, battery, and thermal health on demand, with an optional lightweight menu-bar summary. |

### Full Workspace

A full workspace is a resizable environment for sustained work such as Cloud
Sync, AI History, or Logs. Its sidebar owns tool-level navigation; its
content pane owns the selected destination. It uses native close, minimize, and
zoom traffic lights over the sidebar and never draws a compact titlebar.

Canonical anatomy:

```text
content at least 640 wide; height at least 600; resizable
┌──── sidebar 220–260 ────┬──────── flexible content ────────┐
│ traffic lights  title   │ 40pt top strip                  │
│ search/action at y=44   ├─────────────────────────────────┤
│ destinations            │ body; first surface near y=44  │
│                         │                                 │
│ settings/footer actions │                                 │
└─────────────────────────┴─────────────────────────────────┘
```

- Use 900×600 for a simple list workspace, 1000×720 for the standard case, and
  1200×800 for a detail-heavy workspace. The person may resize it down to the
  chosen sidebar width plus 640pt of content, never below 600pt high.
- Choose 220pt for a simple workspace, 240pt for data navigation, or 260pt for
  conversation navigation. It does not resize with the window and never
  collapses into an overlay. Title position matches the launcher.
- The sidebar's primary control starts at y=44 with 12pt horizontal insets. Use
  the custom 32pt sidebar search when the navigation itself is searchable. Use a
  full-width primary workflow action there when creation is the main entry
  point. That action is at least 34pt high with 12pt internal horizontal
  padding, 8pt radius, contrast-aware label/icon, accent fill, and the filled
  interaction treatment. Never stack both controls at the top.
- Sidebar navigation groups use full-width 28pt rows and 2pt between rows.
  A new section starts after 16pt, its 10pt uppercase header has 4pt bottom
  spacing, and the final scroll group has 20pt bottom padding. Settings uses the
  same row minimum and sits 12pt from the sidebar bottom.
- The sidebar title is the tool name and is its only tool-level title. A content
  title names the current destination or selection, never repeats the tool.
- Use two top-level panes by default. A persistent inspector is allowed only
  when selected-item details must remain visible while the list stays usable,
  and only while the center content remains at least 640pt wide. Otherwise use
  a detail replacement or sheet. An inspector is part of content, not a second
  sidebar.
- At standard text size, a content top strip is 40pt high, starts at the window
  top, uses 20pt horizontal and 10pt vertical internal padding, and may have one
  hairline bottom separator. Its scalable height is
  `max(40, tallest control or line + 16)`. Keep one row with at least 12pt
  between destination context and actions. When that row no longer fits the
  available width, move the least important labeled actions into the first body
  action row; never wrap, clip, or shrink them. The body starts immediately
  after the strip. At standard size, a 12pt body inset places its first row or
  card near the sidebar search's y=44 line.
- Top-strip actions use native small controls with a shared 24pt minimum visible
  height. Menus and adjacent buttons share one vertical centerline.
- The top strip contains destination context on the left and only global page
  actions on the right. Actions remain flat and separate. Normal workspace
  controls use the 4pt/6pt radius roles; the titlebar-only radius exception does
  not apply.
- The top strip uses a 13pt medium destination title and optional 11pt
  subtitle. The 17pt launcher detail title never appears in a workspace body.
  Body content starts 12pt below the strip. Do not add a second 32pt top gap.
- Content uses one 20pt leading gutter unless a dense list uses a documented
  16pt row gutter. Headers, tabs, fields, cards, and rows within that container
  share the chosen edge.
- Settings cards use leading-aligned stacks. Every settings row spans the card:
  its label leads and its control trails, or every control starts on one shared
  leading grid column. Never let an intrinsic-width toggle, picker, or option
  group center itself. Center alignment is reserved for explicit empty states
  and deliberately composed hero content.
- Pane and top-strip hairlines are permitted where material changes do not
  provide enough separation. Visual hairlines use the shared quiet divider at
  0.22 opacity, or 0.44 with Increased Contrast. Native command-menu and context-
  menu separators keep the system appearance. Workspace cards use opacity depth
  without custom shadows; the launcher hover exception does not apply here.
- On narrow resize, preserve the sidebar and primary content, then remove an
  optional inspector. Never transform the workspace into compact applet chrome.
- Settings remain inside the tool window. They replace the content destination,
  while the sidebar remains available and marks Settings. Use full labeled rows
  and section cards; do not leave homepage tabs above settings and do not open
  a settings-only compact menu or separate settings window.

Existing workspaces fix the reference choices that general ranges leave open:

| Workspace | Default / sidebar | y=44 control and navigation | Primary content |
|---|---|---|---|
| Logs | 900×600 / 220pt | Search; level filters; Settings | Selectable dense log stream |
| Cloud Sync | 1000×720 / 240pt | `New Transfer`; filters, Activity, remotes, Settings | Transfer rows, remote browser, or activity ledger |
| AI History | 1200×800 / 260pt | Conversation search; bookmarks, projects, Settings | Selected conversation detail |
| Input Devices | 980×700 / 220pt | Devices, Scrolling, About | Device cards and scrolling profiles |
| System Care | 1180×780 / 240pt | Data destinations and Settings | Storage, cleanup, application, and Mole data |
| System Monitor | 1080×720 / 240pt | Metric destinations and menu settings | Live charts and metric grids |

A new workspace's product brief chooses destinations and data, then follows the
closest content pattern: homogeneous operational items use dense rows; grouped
configuration uses section cards; hierarchies use an outline/tree; a selected
record uses content replacement or the conditional inspector rule. Do not turn
operational metrics into a dashboard of decorative summary cards when they fit
in the top strip or relevant row.

Cloud Sync transfer rows are the operational-card reference: 14pt padding,
12pt radius, 10pt vertical internal spacing, 0.03 rest surface, and 0.06 hover.
The first line contains a 26pt operation icon, middle-truncated 12pt source and
destination paths with an arrow, and an 11pt state badge. A 6pt progress track
follows. The last line contains 11pt size, speed, and file metrics on the left
and separate 24pt icon actions on the right. Expanded per-file detail appears
below without changing the row's outer edges. Source and destination are
separate primary 0.05 path chips with 8pt horizontal and 4pt vertical padding
and 6pt corners. The state badge uses 8pt horizontal and 4pt vertical padding
in a capsule. Sidebar count badges use the same capsule logic.

Cloud Sync's current top strip is operational, not a repeated destination
title. It shows active count and aggregate speed on the left, then applicable
`Clear finished` and global pause or resume actions on the right. A future
operational workspace follows this pattern when live state is more useful than
a static page title.

Long-running workspaces must show progress and state in the relevant rows.
Status must never rely on color alone: pair the semantic tint with text or an
icon. Empty, error, offline, retrying, paused, and complete states must explain
what happened and the next available action.

### Compact Applet

A compact applet is a fixed, single-column tool for one immediate purpose, such
as Awake, Color Picker, or Text Extractor. It has no sidebar and
no second navigation rail. The person cannot resize it, though the app may
animate between explicitly bounded content heights as its state changes.

Choose the narrowest approved width that keeps labels and adjacent controls
legible: 420pt for short data, 480pt for text/history, or 560pt for dense control
rows. Total window height stays between 250pt and 600pt. If useful content does
not fit at 560×600 with scrolling, use a full workspace.

SwiftUI composites the hidden native titlebar's 32pt safe-area surplus below the
declared root. Bottom overlays offset through that native titled-frame height so
their insets are measured against the visible material, not the misleading
logical `NSWindow` or Accessibility bounds. For example, Awake declares a
560×500 root. Browser references must inspect the composited outer window.

Existing applets are concrete references, not new families:

| Applet | Frame | Titlebar actions | Home body |
|---|---|---|---|
| Awake | 560×500 | Small `Keep Display On` switch | Status, Mode, then Quick Times and Process |
| Color Picker | 420 wide, 250–460 high | `Pick Color` primary action | History / Projects tabs; 12pt gutter |
| Text Extractor | 480 wide, 270–462 high | Shortcut menu + `Extract Text` primary action | History |

These examples define shell composition and action ownership. A future applet's
domain requirements still define its labels, data, fields, and states; do not
copy Awake's information architecture into an unrelated tool.

Canonical anatomy:

```text
fixed 420 / 480 / 560 wide; 250–600 high
┌──────────────── custom titlebar 40 ─────────────────┐
│ close  minimize    title              page actions │
│ single-column body; 20pt gutter                     │
│ sections, cards, fields, rows                       │
│                                      floating gear │
└─────────────────────────────────────────────────────┘
```

- Render one custom 40pt `CompactTitlebar`. The title is text only, normally
  13pt medium, and never repeats in the body. Awake's current 13pt bold title is
  a documented existing exception, not a default for new tools. Do not show a
  tool icon or a bottom separator.
- The complete applet, including titlebar and body, is one continuous active
  `.hudWindow` material. The host `NSWindow` is clear and non-opaque. Section
  cards tint this material; they do not replace it with an opaque page canvas.
- Inside the 40pt titlebar, center a 28pt wrapper made from a 24pt row plus one
  4pt top inset. This places every 24pt item at y=10…34 with midpoint y=22.
  Do not place the row itself at y=4 and never pad the title separately.
- Move native close and minimize controls 6pt down to midpoint y=22. Reapply
  that absolute baseline after delayed native layout and whenever the window
  becomes key, because AppKit may restore its 16pt default centerline. Hide
  zoom. Start the title at x=60 so it reclaims zoom's former space.
- Give the title and action container the same 24pt height. The title truncates
  before actions; actions never wrap or shrink. The action container ends 20pt
  from the window edge, actions have 8pt between them, and the flexible spacer
  between title and actions never falls below 12pt. If localization makes the
  row too wide, move the least important action into the body.
- Titlebar actions are persistent page-level actions only. Color Picker's
  `Pick Color` and Text Extractor's `Extract Text` belong there. Awake keeps a
  small native `Keep Display On` switch there; its
  mode-specific Start or Stop actions stay in the body. Settings never belongs
  in the titlebar.
- Each action is visually discrete and flat. Only the primary action may use an
  accent fill. Buttons and menus in this titlebar alone use the 6pt titlebar
  radius. Every titlebar control suppresses the default focus effect, and
  initial focus is routed away from controls so no launch-time or stale outline
  appears. Drive the replacement ring from focus state, focus origin, and
  key-window state rather than a one-shot key event. Whenever a titlebar
  control holds non-pointer focus in the key window, draw a 1pt inset stroke at
  the same 6pt radius: use `focus-ring` on a clear control and
  `focus-ring-on-accent` on an accent-filled primary control. Hide it while the
  window is not key, restore it if that still-focused control becomes key
  again, and remove it when focus moves. Pointer focus alone does not draw it.
  This custom ring replaces, rather than removes, visible keyboard focus.
- Titlebar action labels use their scaled role while they fit the 24pt control
  and preserve the 12pt title/action spacer. As soon as either constraint fails,
  relocate the labeled action, menu, or switch into the first body group in
  visual order; every accessibility text size takes this body placement. Render
  it there with its scaled control or body role and the same action semantics.
  The fixed titlebar then contains only traffic lights, the tool title, and any
  genuinely icon-only control that still fits. Never freeze actionable text at
  11pt, shrink it, or clip it to preserve titlebar density.
- The body page begins directly after the titlebar. Use 16pt internal top
  spacing and the shared 20pt horizontal gutter; Color Picker alone uses 12pt.
  This is internal content spacing, not a second header or titlebar margin.
- Body sections have 16pt between them. A 10pt uppercase section label sits 8pt
  above its aligned card, fields, or rows. Do not add a second gap inside the
  card to compensate.
- When the applet has a separate settings page, a visible 24pt circular
  floating `gearshape` button sits 8pt from the bottom and right window edges.
  The circle is the one round control in the app; every other button keeps its
  fixed radius. Reserve
  52pt bottom scroll space so it never covers content. It toggles between home
  and settings and remains visible on both pages. On Settings it uses
  `gearshape.fill` with selection-light background and its accessibility label
  and help become `Back to <home page>` so the return action is unambiguous.
  Omit it, and the reserved space, when the applet has no settings destination;
  Awake is the reference.
- Settings replaces all home tabs and navigation, begins directly below the
  titlebar, starts with a 13pt medium `Settings` page label on the body gutter,
  and uses full labeled rows. The compact titlebar keeps the tool name; it never
  changes to Settings. Returning restores the home state.

### Subordinate Surfaces

Modal sheets and detail sheets are not top-level scenes and therefore are not a
fourth family. They have no traffic lights, sidebar, independent restoration, or
window navigation. Their flat 40pt header owns the 13pt title, starts at the
normal 20pt gutter, places optional actions at the trailing 20pt inset, and uses
the compact header geometry without the traffic-light offset. Choose 420pt width
for a narrow one-column task, 560pt for a standard form, or 700pt for a
detail-heavy form. The sheet is content-sized up to 70% of the parent screen
height, then its body scrolls vertically under the fixed header. It never
scrolls horizontally. Content that cannot fit the 700pt profile belongs in a
workspace or a modeless family window. Escape dismisses it. State badges stay
in rows or cards, never in the header.

A modeless detail that needs independent movement, resizing, restoration, or
persistent navigation is not subordinate: define it as a compact applet or full
workspace `Window` scene and follow that complete family contract.

The tray popover is also subordinate: 340pt wide and no more than 70% of screen
height. When its product brief supplies multiple local summaries, use one
`Tray Tab` row with 8pt outer insets; otherwise omit tabs. It may also use an
optional status row, one scrolling product-brief content region, and a footer
for product-brief actions. Those regions appear only when their content exists;
the design contract does not invent transfer rows, status copy, or footer
commands. Measurement guides and capture overlays are transient task surfaces
and must not borrow launcher, workspace, or applet navigation chrome.

## Components

Reuse these instead of restyling per view (Views/Components/ + local patterns):

- **Icon button** — 24×24, SF Symbol ~12pt medium, 6pt radius, hover 0.06,
  `.buttonStyle(.plain)` + `.contentShape(Rectangle())`; preserve focus unless
  the compact-titlebar rule explicitly suppresses it.
- **Sidebar search** - at least 32pt high with 12pt outer inset, 8pt inner
  padding, 6pt radius, 12pt search icon, and 13pt text. Use the family-defined
  placeholder.
- **Sidebar row** - 28pt high at standard text size, 16pt icon, 8pt internal
  horizontal inset and gap, 8pt radius, 13pt text, and hover 0.06. Selection
  uses the native emphasized selected-content background while the window is
  key and the native unemphasized selection while inactive. Icon and label use
  the same matching native selected-content foreground; never tint only one.
- **Sidebar primary action** - at least 28pt high, 12pt horizontal inset, 8pt
  radius, accent fill, contrast-aware 13pt medium label, and one 13pt semantic
  icon.
- **Compact titlebar control** — 24pt high, 6pt radius, hover 0.06, and no
  default focus effect. Buttons and menus share this label treatment; only the
  primary action receives accent fill, and actual keyboard focus uses the 1pt
  inset replacement ring from the compact-family rule.
- **Tab pill** - text 12pt medium, 10/5 padding, 6pt radius, and selected
  background 0.06 with ordinary primary text. There is no selected underline,
  accent text, or enclosing segmented-control tray. An unselected hover uses
  the same 0.06 surface. The strip starts on the shared gutter and selection
  never moves its tabs.
- **Tray Tab** - at least 28pt high, 12pt medium text, 10pt horizontal inset,
  8pt radius, and 4pt between tabs. Hover is primary 0.06; selection is accent
  with contrast-aware text. The selected tab also exposes `isSelected` to
  accessibility. It is a tray-popover component, never an applet body tab.
- **Section card** - 10pt radius, 0.05 bg, 14pt padding, preceded by an
  UPPERCASE 10pt secondary header on the same gutter.
- **Card** (grid/tool) - 12pt radius, 0.03 bg, hover 0.06. Launcher tool cards
  also use their documented hover stroke and shadow.
- **Operational card** - 12pt radius, 0.03 bg, hover 0.06, 14pt padding, and
  10pt vertical spacing. Put identity/state first, progress second, and metrics
  plus discrete actions last.
- **Progress bar** — 6pt-high capsule, track `primary.opacity(0.08)`, tint by
  state (accent/green/orange/red).
- **Scroll indicator:** overlay, autohiding, mini control size. Apply
  `.thinScrollIndicators()` to every `ScrollView`, `Form`, `TextEditor`, `List`,
  and `Table`. Configure every native `NSScrollView` with
  `configureThinScrollIndicators()`. Never hide an indicator or reserve a thick
  scrollbar track.
- **State badge** - 11pt medium text + 10pt icon, 8/4 padding, tint at 0.12 bg,
  and a capsule shape. Lives on cards or rows only, never in sheet headers.
- **Empty state** — `EmptyStateView(icon:message:)`, centered.

## App and Tool Icons

Icons follow the bold, friendly-flat language of current independent macOS
utilities. Each tool gets one oversized metaphor and enough personality to
remain recognizable without a label. The family has three approved treatments:
the tool's **Chosen Color** identity plus the neutral **Midnight** and
**Porcelain** appearance families.

### Appearance Strategy

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

#### Neutral Palette

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

#### Tool Appearance Matrix

| Tool | Light appearance | Dark appearance | Decision |
|---|---|---|---|
| Cloud Sync | Midnight | Chosen Color | Preserve the blue cloud echo in dark mode |
| AI History | Midnight | Chosen Color | Preserve the terracotta message echo in dark mode |
| Logs | Midnight | Porcelain | Use the neutral contrast inversion without an exception |
| Ruler | Chosen Color | Chosen Color | Orange identity is fixed in both appearances |
| Awake | Chosen Color | Chosen Color | Yellow eye identity is fixed in both appearances |
| Color Picker | Chosen Color | Chosen Color | Colored samples are semantic and fixed |
| Text Extractor | Chosen Color | Chosen Color | Yellow OCR lens identity is fixed |
| Input Devices | Chosen Color | Chosen Color | Blue detailed-mouse identity is fixed |
| System Care | Chosen Color | Chosen Color | S11-08 centered disk-and-eraser identity is fixed |
| System Monitor | Chosen Color | Chosen Color | Midnight-blue display-and-metrics identity is fixed |
| NetToys | Midnight | Porcelain | Use the neutral contrast inversion without an exception |

The base `icon.svg` entry is the light-appearance asset. Add `icon-dark.svg`
with a `luminosity: dark` appearance only when the matrix calls for a different
dark asset. Tools that use Chosen Color in both modes keep one universal SVG.

Every new plugin adds its approved light and dark treatment to this matrix
before icon work begins. If its product brief has no approved Chosen Color
identity, use Midnight in light appearance and Porcelain in dark appearance.
An absent matrix row is a blocking metadata defect, never permission to guess a
palette or reuse another tool's semantic hue.

### Construction

- Work in a `512 × 512` SVG view box.
- Use a full-canvas rounded square with `rx="112"` as the ground.
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
  legacy exception: Cloud Sync, AI History, and Logs retain their listed
  `#FFFFFF` foregrounds. Neutral Midnight/Porcelain assets always use their own
  closed glyph tokens rather than either white.
- No decorative outline, gloss, blur, rim light, or soft drop shadow. A gradient
  is allowed only when color itself is the metaphor or part of an approved
  legacy Chosen Color asset.

The base application icon is the deliberate exception to the tool/plugin SVG
construction rules above. `powertoys/AppIcon.icon` uses Icon Composer's
`1024 × 1024` layered source canvas and solid document fill; its SVG layers
must not bake in the rounded-square ground or any lighting effect. It preserves
the accepted `docs/appicon.svg` bolt geometry, including the `52px` right/down
echo offset at that scale (`26px` on a 512 canvas), rather than adopting the
tool-icon `18 × 22` echo. Icon Composer supplies the system enclosure, lighting,
and prior-generation fallback.

### Solid Echo Construction

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
children. This prevents darker seams where parts overlap. AI History is the
reference: the rounded message body and bottom pointer share one terracotta
shadow group, so the pointer never looks like a second shadow.

At 32px the echo should read as a narrow lower-right depth cue, not a duplicate
icon. If it becomes a second symbol, the foreground is too small or the offset
has been changed.

### Chosen Color Palette

| Tool | Ground | Foreground | Semantic accent |
|---|---|---|---|
| Cloud Sync | `#1C1D22` | `#FFFFFF` at `.92` | `#5B8DEF` cloud echo at `.30` |
| AI History | `#1C1D22` | `#FFFFFF` at `.92` | `#D97757` message echo at `.30` |
| Logs | `#475569` to `#0F172A` | `#FFFFFF` | Terminal prompt |
| Ruler | `#F04E23` | `#23272E` | Cream graduation cutouts |
| Awake | `#F5B71E` | `#23272E`, `#F7F5F0` | Cream eye catchlight |
| Color Picker | `#23272E` | `#F7F5F0` | Coral-violet-blue sample |
| Text Extractor | `#2155B0` | `#FAF6EA` at `.88` | Powder-blue lens and muted sand waves |
| Input Devices | `#1C1D22` | `#F4F4F5` | OX16 Midnight Tether mouse and solid gray echo |
| System Care | `#17181B` | `#F3F3F1` | S11-08 gray disk and centered eraser |
| System Monitor | `#002B26` | `#E0FFF8` | OSM13 teal tidal waveform bands |

New Chosen Color tools should receive their own semantic hue unless a documented
product decision deliberately links them to an existing color. Neutral
appearance variants always use the closed Midnight or Porcelain palette instead
of inventing tool-specific grays.

### Asset Catalog Structure

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
  image entry. Do not duplicate an identical dark file.
- Launcher cards and the Dock use the same named asset. Do not create a separate
  Dock-only color treatment.

### Generation Workflow

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

## Interaction, Accessibility & Quality Gates

- **Never** use `onTapGesture` on containers holding selectable text — use
  `Button`; logs and content text must stay selectable.
- **Never** put hover opacities other than 0.06 (0.1 for filled), pressed
  opacities other than 0.1 (0.18 for filled), selection other than accent 0.1,
  native sidebar selection, solid accent tray-tab selection, or the explicit
  Tab Pill primary 0.06, or radii outside {4, 6, 8, 10, 12}.
- **Never** use capsule buttons, UI gradients, or baked icon effects. Capsules
  remain valid only for progress tracks and documented state or count badges.
- **Never** add a second alignment gutter inside one container.
- **Never** use `.formStyle(.grouped)` where its opaque insets break the shared
  edge. Prefer explicit section cards and labeled rows.
- **Do** animate layout-changing state (0.15–0.18s easeInOut) so cards never
  snap-resize; **don't** animate anything else.
- **Do** give every interactive element `.contentShape(Rectangle())` and a
  `.help()` tooltip when the icon isn't self-evident.
- A tab strip aligns by the leading pill boundary, not its inset text. That
  boundary and the first field, card, or row below share one edge; selection
  never shifts tab positions.
- Controls sharing a row share the same visible height and text baseline.
  At standard text size, adjacent search fields and selects inside compact body
  content are exactly 28pt high; accessibility sizing grows both to the same
  height. The family-defined sidebar search starts at its 32pt minimum.
- Preserve visible keyboard focus for launcher, workspace, body, sheet, and
  floating controls. Compact titlebar controls are the only default-focus-effect
  exception and use their defined keyboard-only replacement ring.
- Interaction states use one recipe everywhere: rest uses the component base;
  hover adds 0.06 primary to an unfilled control or 0.1 to a filled control;
  press adds 0.1 primary to an unfilled control or 0.18 to a filled control;
  disabled applies 0.38 opacity and ignores hover/press; selected uses the
  assigned 0.1 accent layer, native sidebar selection, or solid accent tray-tab
  role, except for Tab Pill's explicit primary 0.06 surface; focus uses the
  native system ring except for the compact replacement ring.
- A dense control may be visibly 24pt, but its complete rectangular hit region
  must not be smaller. Never make an icon itself the only clickable pixels.
- Every icon-only control has an accessibility label and help text. Traversal
  follows visual reading order, and Escape closes dismissible subordinate
  surfaces.
- Never communicate status with color alone. Pair tint with text, shape, or an
  icon, and keep labels useful when increased contrast is enabled.
- When Reduce Transparency is enabled, replace vibrancy with an opaque semantic
  system background while preserving pane separation. Do not introduce custom
  hex fallbacks.
- When Reduce Motion is enabled, disable layout animations and numeric-text
  transitions. State changes remain immediate and must not substitute a pulse,
  fade, or other ornamental motion.
- Point sizes and dimensions in this document are standard-appearance metrics.
  Use the role's `@ScaledMetric` value for non-chrome text and its vertical
  padding; horizontal gutters and icon geometry remain fixed. Sidebar rows,
  search, cards, operational rows, fields, and body controls use their listed
  heights as minimums and grow vertically. Launcher grid rows grow together;
  workspace content scrolls; compact applet height grows up to 600pt and then
  its body scrolls. Never shrink text to preserve a metric. Native traffic-light
  geometry and the 40pt compact titlebar stay fixed; one-line chrome labels
  truncate with full accessibility labels and help text.
- Long labels truncate only after the action region is protected. Localized
  controls never overlap, wrap inside a titlebar, or push traffic lights.

Treat every rule above as a defect when it regresses. Before accepting a new or
changed window, verify light and dark appearance; default, hover, pressed,
selected, disabled, focus, empty, error, and settings states; narrow and default
workspace sizes; keyboard traversal; reduced transparency; and a long-content
case with visible thin scroll indicators. Repeat the layout-changing states with
Reduce Motion and accessibility text sizing enabled.

For visual review, place the window beside its normative screenshot at the same
scale. Check material continuity first, then native control morphology, shell
geometry, alignment, density, radii, selection, and artwork. A dimensionally
correct mockup still fails if it reads as a generic web dashboard.
