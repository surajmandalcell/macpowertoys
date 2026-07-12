---
version: 1
name: PowerToys
description: Design language for PowerToys and its child tools (RSync, Claude History, Logs)
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
  icon-ground: "#1C1D22"                        # Glass Layers icon plate
  icon-accent-rsync: "#FFB13D"
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

# PowerToys Design Language

## Overview

PowerToys is a dense, quiet, native-feeling macOS utility. It should read like a
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
second, in-between alignment point. When a control has internal padding (tab
pills), outdent the control so its *text* sits on the gutter.

- Sidebar titles: `.padding(.leading, 84)` to clear traffic lights, `.top, 8`.
- Search field container: `.top, 52` / `.horizontal, 12` / inner `.padding(8)`.
- Content areas align with the sidebar search bar top (`.top, 52`); top strips
  inside tool windows hug the window top (≤10pt internal padding, no stacked
  offsets).
- No top padding on content views.

## Elevation & Materials

Depth comes from **opacity layers and vibrancy, never shadows**. Sidebars are
`.sidebar`-material blur extending seamlessly to the window top with traffic
lights floating over them. Windows use `.windowStyle(.hiddenTitleBar)`; never
hand-configure NSWindow titlebar properties. No drop shadows on custom views —
the only shadows are the system's window shadows.

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
- **Tab pill** — text 12pt (medium when selected), 10/5 padding, 6pt radius,
  selected bg 0.06; strip outdented so text hits the gutter.
- **Section card** — 12pt radius, 0.05 bg, 14pt padding, preceded by an
  UPPERCASE 10pt secondary header on the same gutter.
- **Card** (grid/tool) — 12pt radius, 0.03 bg, hover 0.06.
- **Progress bar** — 6pt-high capsule, track `primary.opacity(0.08)`, tint by
  state (accent/green/orange/red).
- **State badge** — 11pt medium text + 10pt icon, tint at 0.12 bg. Lives on
  cards/rows only — never duplicated into sheet headers.
- **Empty state** — `EmptyStateView(icon:message:)`, centered.

## Iconography — "Glass Layers"

App and tool icons are flat, layered marks: a `#1C1D22` rounded-rect ground, a
tinted echo plate at 0.28–0.3 opacity offset down-right (+30/+40 in a 512 grid),
and a white 0.92–0.94 top plate. Bold geometric silhouettes (bolt, arrows,
bubble), 22pt stroke, round joins. **No gradients, no baked shadows, no gloss** —
Tahoe/Liquid Glass supplies material effects at render time; baking them in is a
bug. Menu bar icons are single-color template renders of the same mark.

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
  scrolling live transfer rows, footer (Open PowerToys / Quit).

## Do's and Don'ts

- **Never** use `onTapGesture` on containers holding selectable text — use
  `Button`; logs and content text must stay selectable.
- **Never** put hover opacities other than 0.06 (0.1 for filled), selection
  other than 0.1/0.2, or radii outside {4, 6, 8, 12}.
- **Never** use capsule buttons, gradients, or baked icon effects.
- **Never** create formatters/regex inside view bodies or loops — `static let`.
- **Never** use `Array(x.enumerated())` in `ForEach` — stable IDs only.
- **Never** block the main thread with file I/O — `Task.detached`, chunked reads.
- **Never** add a second alignment gutter inside one container.
- **Do** animate layout-changing state (0.15–0.18s easeInOut) so cards never
  snap-resize; **don't** animate anything else.
- **Do** keep view bodies under ~50 lines — extract subviews.
- **Do** give every interactive element `.contentShape(Rectangle())` and a
  `.help()` tooltip when the icon isn't self-evident.
