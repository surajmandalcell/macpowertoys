---
version: 5
name: MacPowerToys
description: Design language for MacPowerToys and its child tools
colors:
  hover: "Color.primary.opacity(0.06)"          # the ONLY hover background
  hover-strong: "Color.primary.opacity(0.1)"    # filled buttons only
  selection-light: "Color.accentColor.opacity(0.1)"
  selection-strong: "Color.accentColor.opacity(0.2)"
  card: "Color.primary.opacity(0.03)"           # grids, subtle depth
  card-detail: "Color.primary.opacity(0.05)"    # detail/log views, softer contrast
  content-background: "Color(nsColor: .windowBackgroundColor)"
  text-subdued: "Color.primary.opacity(0.75)"
  text-on-selection: "Color.white.opacity(0.7)"
  text-preview: "Color.secondary.opacity(0.6)"
  icon-ink: "#23272E"
  icon-paper: "#F7F5F0"
  icon-midnight-ground: "#1C1D22"
  icon-midnight-echo: "#5B5D66"
  icon-midnight-glyph: "#F4F4F5"
  icon-porcelain-ground: "#E7E7EA"
  icon-porcelain-echo: "#A6A8AF"
  icon-porcelain-glyph: "#25262B"
  icon-ruler: "#F04E23"
  icon-awake: "#F5B71E"
  icon-color-picker: "#23272E"
  icon-text-extractor: "#F5B71E"
typography:
  title: { size: 13, weight: medium }
  body: { size: 13, weight: regular }
  row: { size: 13, weight: regular }
  control: { size: 12, weight: regular }
  caption: { size: 11, weight: regular }
  section-header: { size: 10, weight: medium, transform: uppercase, color: secondary }
  code: { size: 12, design: monospaced }
  micro: { size: 10, weight: regular }
rounded:
  control: 4        # toggles, small buttons
  field: 6          # text fields, icon buttons, pills, chips
  row: 8            # list rows, message bubbles, tray tabs
  card: 12          # cards, panels, sheets' section cards
spacing:
  gutter: 20        # one shared left edge for titles, tabs, headers, cards
  color-picker-body-gutter: 12
  card-padding: 14  # inner padding of section cards
  sidebar-title-leading: 84   # clears traffic lights
  content-top: 52   # content aligns with sidebar search bar top
  header-top: 0     # window-top strips hug the top (10pt internal only)
components:
  icon-button: { size: 24, radius: 6, hover: colors.hover }
  tab-pill: { padding-x: 10, padding-y: 5, radius: 6, selected-bg: colors.hover }
  section-card: { radius: 12, bg: colors.card-detail, padding: spacing.card-padding }
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

## Colors

All interactive and surface colors are **opacity layers over `Color.primary` or
`Color.accentColor`** — never raw hex in UI code (hex lives only in icon assets).
This keeps light/dark mode free.

- Hover is always `primary.opacity(0.06)`. Not 0.05, not 0.08. Filled buttons may
  deepen to 0.1 on hover.
- Selection is `accentColor` at 0.1 (light) or 0.2 (strong). No other values.
- Cards: 0.03 for grids and subtle depth; 0.05 where softer contrast is wanted
  (detail sheets, logs).
- Content areas sit on `Color(nsColor: .windowBackgroundColor)`, sidebars on an
  `NSVisualEffectView` with `.sidebar` material (state `.active`, never
  `.followsWindowActiveState`).
- Status tints: green = healthy/complete, orange = retrying/attempts,
  red = failure, secondary = idle/cancelled.

## Typography

San Francisco only, via `.system(size:weight:)`. The scale is closed:

13 medium (titles) · 13 regular (body/rows) · 12 (controls, tab labels) ·
12 monospaced (paths, patterns, code) · 11 (captions, metrics) ·
10 medium UPPERCASE secondary (section headers) · 10 (micro/tertiary detail).

Numbers that update live get `.monospacedDigit()` and
`.contentTransition(.numericText())`.

## Layout & Spacing

**One left edge.** Within any container, titles, tab strips, section headers, and
card edges share a single leading gutter (20pt in sheets). Never introduce a
second, in-between alignment point. Align a tab strip's leading pill boundary
to that gutter; never outdent the strip merely to align the pill's inset text.

- Sidebar titles: `.padding(.leading, 84)` to clear traffic lights, `.top, 8`.
- Search field container: `.top, 52` / `.horizontal, 12` / inner `.padding(8)`.
- Content areas align with the sidebar search bar top (`.top, 52`); top strips
  inside tool windows hug the window top (≤10pt internal padding, no stacked
  offsets).
- No top padding on content views.

## Elevation & Materials

Depth comes from **opacity layers and vibrancy, never shadows**. Sidebars are
`.sidebar`-material blur extending seamlessly to the window top with traffic
lights floating over them. Windows with custom chrome use
`.windowStyle(.hiddenTitleBar)`. Compact tools also use hidden titlebars and
render `CompactTitlebar` inside the window. Never use `.unifiedCompact`, native
toolbar action grouping, or manually configured `NSWindow` titlebar properties.
No drop shadows on custom views; the only shadows are the system's window
shadows.

## Shapes

Closed radius scale — pick the smallest that fits the role:

- **4pt** small buttons, toggles
- **6pt** text fields, icon buttons, chips, tab pills
- **8pt** list rows, message bubbles, tray tabs
- **12pt** cards, panels, section cards

**Never capsules** for buttons or badges in tool UIs. Progress bars are the one
capsule-shaped element (they're tracks, not controls).

## Components

Reuse these instead of restyling per view (Views/Components/ + local patterns):

- **Icon button** — 24×24, SF Symbol ~12pt medium, 6pt radius, hover 0.06,
  `.buttonStyle(.plain)` + `.focusEffectDisabled()` + `.contentShape(Rectangle())`.
- **Tab pill** — text 12pt medium, 10/5 padding, 6pt radius,
  selected bg 0.06; the strip starts on the shared gutter and selection never
  changes its inset or tab positions.
- **Section card** — 12pt radius, 0.05 bg, 14pt padding, preceded by an
  UPPERCASE 10pt secondary header on the same gutter.
- **Card** (grid/tool) — 12pt radius, 0.03 bg, hover 0.06.
- **Progress bar** — 6pt-high capsule, track `primary.opacity(0.08)`, tint by
  state (accent/green/orange/red).
- **Scroll indicator:** overlay, autohiding, mini control size. Apply
  `.thinScrollIndicators()` whenever an indicator is visible; never reserve a
  thick scrollbar track.
- **State badge** — 11pt medium text + 10pt icon, tint at 0.12 bg. Lives on
  cards/rows only — never duplicated into sheet headers.
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

| Family | Ground | Echo | Primary glyph | Dark detail |
|---|---|---|---|---|
| Midnight | `#1C1D22` | `#5B5D66` | `#F4F4F5` | `#25262B` |
| Porcelain | `#E7E7EA` | `#A6A8AF` | `#25262B` | `#F4F4F5` |

Use these exact neutral shades. They are not aliases of the warmer Chosen Color
ink `#23272E` and paper `#F7F5F0`. Mixing the two neutral families within one
variant weakens the deliberate temperature and contrast difference.

#### Tool Appearance Matrix

| Tool | Light appearance | Dark appearance | Decision |
|---|---|---|---|
| Cloud Sync | Midnight | Chosen Color | Preserve the blue cloud echo in dark mode |
| Claude History | Midnight | Chosen Color | Preserve the terracotta message echo in dark mode |
| Logs | Midnight | Porcelain | Use the neutral contrast inversion without an exception |
| Ruler | Chosen Color | Chosen Color | Orange identity is fixed in both appearances |
| Awake | Chosen Color | Chosen Color | Yellow eye identity is fixed in both appearances |
| Color Picker | Chosen Color | Chosen Color | Colored samples are semantic and fixed |
| Text Extractor | Chosen Color | Chosen Color | Yellow OCR lens identity is fixed |

The base `icon.svg` entry is the light-appearance asset. Add `icon-dark.svg`
with a `luminosity: dark` appearance only when the matrix calls for a different
dark asset. Tools that use Chosen Color in both modes keep one universal SVG.

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
- Use warm off-white `#F7F5F0` and charcoal `#23272E`, never pure white or black.
- No decorative outline, gloss, blur, rim light, or soft drop shadow. A gradient
  is allowed only when color itself is the metaphor or part of an approved
  legacy Chosen Color asset.

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
children. This prevents darker seams where parts overlap. Claude History is the
reference: the rounded message body and bottom pointer share one terracotta
shadow group, so the pointer never looks like a second shadow.

At 32px the echo should read as a narrow lower-right depth cue, not a duplicate
icon. If it becomes a second symbol, the foreground is too small or the offset
has been changed.

### Chosen Color Palette

| Tool | Ground | Foreground | Semantic accent |
|---|---|---|---|
| Cloud Sync | `#1C1D22` | `#FFFFFF` at `.92` | `#5B8DEF` cloud echo at `.30` |
| Claude History | `#1C1D22` | `#FFFFFF` at `.92` | `#D97757` message echo at `.30` |
| Logs | `#475569` to `#0F172A` | `#FFFFFF` | Terminal prompt |
| Ruler | `#F04E23` | `#23272E` | Cream graduation cutouts |
| Awake | `#F5B71E` | `#23272E`, `#F7F5F0` | Cream eye catchlight |
| Color Picker | `#23272E` | `#F7F5F0` | Coral-violet-blue sample |
| Text Extractor | `#F5B71E` | `#23272E`, `#F7F5F0` | Three descending handwritten lines |

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
2. Sketch and approve the Chosen Color glyph at 512px using rounded filled
   shapes and broad round-capped bands. Make it larger than feels initially
   comfortable.
3. Look up the tool in the appearance matrix before generating neutral assets.
   Never assume every tool receives both neutral families.
4. For a Midnight or Porcelain result, preserve the exact semantic geometry and
   apply only the closed palette plus the `18 × 22` solid echo. Do not redesign
   the metaphor between appearances.
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

## Window Chrome & Structure

- Multi-window launcher: main window (780×700, fixed) is a launcher — tools open
  in their own `Window` scenes (single-instance, `tabbingMode = .disallowed`)
  and the launcher closes itself when a tool opens. Tools never auto-open at
  launch unless their start-at-launch setting is on.
- Sidebars are custom `HStack` layouts — never `NavigationSplitView` /
  `NavigationView` (unwanted chrome).
- Search: custom field per the token spec — never the native `.searchable`.
- Forms: prefer custom section cards over `.formStyle(.grouped)` — grouped
  forms carry opaque insets that break the one-left-edge rule.
- Tray popover: 340pt wide, ≤70% of screen height; chrome-style tool tabs on
  top, status row (dot/retry + status text left, primary window shortcut right),
  scrolling live transfer rows, footer (Open MacPowerToys / Quit).

## Do's and Don'ts

- **Never** use `onTapGesture` on containers holding selectable text — use
  `Button`; logs and content text must stay selectable.
- **Never** put hover opacities other than 0.06 (0.1 for filled), selection
  other than 0.1/0.2, or radii outside {4, 6, 8, 12}.
- **Never** use capsule buttons, UI gradients, or baked icon effects.
- **Never** create formatters/regex inside view bodies or loops — `static let`.
- **Never** use `Array(x.enumerated())` in `ForEach` — stable IDs only.
- **Never** block the main thread with file I/O — `Task.detached`, chunked reads.
- **Never** add a second alignment gutter inside one container.
- **Do** animate layout-changing state (0.15–0.18s easeInOut) so cards never
  snap-resize; **don't** animate anything else.
- **Do** keep view bodies under ~50 lines — extract subviews.
- **Do** give every interactive element `.contentShape(Rectangle())` and a
  `.help()` tooltip when the icon isn't self-evident.

## Product Nitpicks

These are binding polish rules. Treat them as defects when they regress.

- A tab strip aligns by the leading pill's boundary, not its inset label. That
  boundary and the first field, card, or row below it share one outer edge;
  selecting another tab never shifts the strip or its tabs.
- Color Picker uses a compact 12pt body gutter for tabs, fields, cards, and
  settings. Keep every body surface on that same edge.
- Controls sharing a row must share the same visible height and text baseline.
  Google Material 3 applies one 56dp input height to search and builds exposed
  dropdowns around text fields. MacPowerToys uses the same parity principle at
  its compact scale: adjacent search fields and selects are exactly 28pt high.
- A compact tool window uses one custom 40pt titlebar for the 13pt medium tool
  title and 24pt-high primary actions. The title clears the traffic lights by
  84pt. Center titles and actions in the top 32pt native control band so their
  midpoints match the traffic lights. The title is text only, with no tool icon.
  Never repeat this content in another header row. Color Picker omits the bottom
  separator; other tools keep their existing separator unless their design
  explicitly says otherwise.
- Titlebar actions remain visually discrete and flat. Never place them in a
  shared rounded container or native toolbar group. Only the primary action
  receives an accent fill, using the 4pt small-button radius. Color Picker uses
  the shared custom actions, which suppress default focus outlines so
  launch-time focus cannot add temporary chrome.
- Compact sheet and detail headers use the same flat 40pt structure without the
  traffic-light inset. Escape dismisses a dismissible sheet or detail view.
- A tool's settings open inside that tool window and replace its content. Use
  full, labeled setting rows; never make a compact menu the only settings UI.
  Homepage tabs and navigation do not remain above settings, and settings
  content begins directly below the titlebar with no top margin.
- Applet settings uses a small 24pt floating `gearshape` button at the
  bottom-left of the content, aligned to its body gutter. It remains visible
  on the settings page and toggles back to tool content. Never place settings
  in a compact titlebar.
- Destructive history maintenance belongs in Settings, not the titlebar. A
  clear-all action must describe its scope and confirm before deleting saved
  items.
- A named color project is a working destination, not just a filter. New picks
  go into the selected project and every project can export its saved colors.

Sources: [Material 3 SearchBar defaults](https://developer.android.com/reference/kotlin/androidx/compose/material3/SearchBarDefaults),
[Material 3 exposed dropdown menus](https://developer.android.com/reference/kotlin/androidx/compose/material3/ExposedDropdownMenuBox.composable).
