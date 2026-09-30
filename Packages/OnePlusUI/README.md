# OnePlusUI v2

OnePlusUI is the native macOS component package for MacPowerToys. It implements
[DESIGN.md v14](../../DESIGN.md): fixed canvases, dynamic colors, two densities,
native controls, and static texture. It requires macOS 15 and Swift 6.2.

Views never restyle a component locally. Add a named variant to this package
when a surface needs different geometry or behavior. Keep approved tool icon
artwork unchanged. Existing `OnePlusTheme`, `OnePlusPanel`, `OnePlusSegments`,
`OnePlusControlButtonStyle`, and `onePlusControl` call sites remain supported.

## Window structure

```swift
import OnePlusUI

Window("Cloud Sync", id: "rclone") {
    OnePlusWindowRoot(canvas: .rclone) {
        OnePlusSidebar(title: "Cloud Sync") {
            OnePlusSidebarSearch(text: $query)
        } navigation: {
            OnePlusNavRow("Transfers", systemImage: "arrow.triangle.2.circlepath",
                          selected: page == "transfers") { page = "transfers" }
        } bottom: {
            OnePlusNavRow("Settings", systemImage: "gearshape") { page = "settings" }
        }
    } content: {
        OnePlusPage {
            OnePlusPageHeader(title: "Transfers")
        } content: {
            OnePlusCard { OnePlusCardHeader("Recent transfers") }
        }
    }
}
.defaultSize(OnePlusWindowCanvas.rclone.size)
.windowResizability(.contentSize)
.windowStyle(.hiddenTitleBar)
```

Set `NSApp.appearance` once for the app. Do not force a color scheme on a tool.
`OnePlusWindowRoot` supplies the window fill, one fixed texture layer, sidebar
line, density, and native chrome. Do not add another root texture.

For an existing root, use `.onePlusFixedCanvas(.logs)`. Applet canvases keep
their fixed width and use the 22 pt title centerline. Color Picker and Text
Extractor keep their content-driven height. All other canvases fix both axes.
Canvas sizes describe the visible window, including the hidden titlebar.
The shared modifier subtracts its measured inset once, including nested roots.
Chrome keeps all three native traffic lights visible and disables zoom and
full screen. It measures the zoom button for the title's 14 pt gap.

Read `@Environment(\.onePlusIsVisible)` before publishing live data to a view.
Fixed canvases supply it automatically. It becomes false when the host window
is occluded, minimized, ordered off screen, or closed, without polling. Apply
`.onePlusLiveUpdates()` to a custom native host that does not use a fixed
canvas. Samplers may keep collecting while their views stop observing.

Page titles start at `OnePlusMetrics.contentTop` (16 pt from the visible
window top). Sidebar content still starts at 54 pt. Header actions center on
the title's first line. `contentGap` is the separate 16 pt body gap; use it
for padding between page regions. Applet titlebars keep their 22 pt centerline.
Applets never use `contentTop`. Their first body element starts `contentGap`
below the 40 pt titlebar or tab strip. Use `OnePlusPage(layout: .applet)` to
get that gap and the 16 pt side gutters. Fixed toolbars and footers also use
`contentGap`, in both applets and workspaces.

## Table and list pages

Use `scrolls: false` when the content already owns scrolling. Header, tabs,
toolbar, and footer stay fixed. The content fills the remaining height.
Slots are optional; the page supplies the gutters and 16 pt content gap.
Fixed bodies end at the density gutter: 24 pt regular, 20 pt compact.
An empty conditional footer keeps that gutter and adds no footer gap.

```swift
OnePlusPage(scrolls: false) {
    OnePlusPageHeader(title: "Processes")
} toolbar: {
    OnePlusSearchField(prompt: "Find a process", text: $query)
} footer: {
    OnePlusStatus("\(rows.count) processes")
} content: {
    Table(rows) {
        TableColumn("Name", value: \.name)
        TableColumn("PID", value: \.pid)
    }
    .onePlusNativeTable()
}
```

Place an inspector beside the table inside `content`; only the table rows
scroll. For settings cards, keep the default `scrolls: true`. Embedded
settings supply only cards and inherit this page's single scroll container.
The page proposes its full overlay viewport width to content. A legacy
scrollbar preference does not reduce the card width or add a side gutter.

Menu panels also own their scrolling. Pass natural-height content to
`OnePlusMenuPanel`; do not wrap it in a screen-height scroll view. The shell
measures each active tab, shrinks for short content, and caps long content at
90 percent of the visible screen. Apply `.onePlusScrollIndicators()` to any
separate row scroll region; it keeps overlay style after native replacement.
Use the optional `toolbar` and `footer` builders for search, forms, and
summaries that must stay fixed. These slots sit outside the capped scroller.
Empty slots reserve no height. Closed panels stop live observation.

For SwiftUI `Table`, share `OnePlusGridColumn` values between
`.onePlusTableCell(column, position: .first)` and
`.onePlusNativeTable(columns: columns)`. Use `.last` for the final cell;
middle cells use the default position. The model sets alignment, insets,
`textRole`, and optional `textColor`. `headerLabelInset` reserves a glyph
lane before a label. Keep Time at `.mono`; path columns can use `.mono`
with `textColor: OnePlusColor.ink` for primary identity text.

## Component catalog

| API | Use |
| --- | --- |
| `OnePlusColor` | Use a dynamic token, such as `.panel`, `.ink`, `.line`, `.chartSeries`, or `.storageSeries`. |
| `OnePlusTheme` | Use the compatibility namespace; `card` maps to `panel`. |
| `OnePlusMetrics` | Read shared geometry, radii, spacing, and centerline math. |
| `OnePlusWindowCanvas` | Choose one of the 13 tool canvases or construct a fixed preview canvas. |
| `OnePlusDensity` / `.onePlusDensity(_:)` | Set `.regular` or `.compact` at the window or panel root. |
| `OnePlusTextRole` / `.onePlusText(_:)` | Apply one of the 15 type roles with density, color, tracking, and case. |
| `OnePlusMotion.animation(reduceMotion:duration:)` | Get an animation, or `nil` under Reduce Motion. |
| `OnePlusFixedWindowChrome` | Apply native fixed-window policy; its measured zoom callback is optional. |
| `OnePlusWindowRoot` | Compose `canvas`, `sidebar`, and `content` once per window. |
| `onePlusIsVisible` / `.onePlusLiveUpdates()` | Suspend view observation while its native window or panel is not visible. |
| `OnePlusWindowTexture` | Draw the fixed root ribbon; normally supplied by the root. |
| `OnePlusTextureAsset` | Access the four cached reference PNGs through `.image`. |
| `.onePlusGrain(opacity:)` | Add static corner grain before clipping to the final card shape. |
| `OnePlusDitherTexture` | Use the compatible standalone corner texture view. |
| `OnePlusSidebar` | Supply search, scrolling navigation, and bottom navigation slots. |
| `OnePlusSidebarTitle` | Position a title from the measured native traffic lights. |
| `OnePlusSidebarSearch` | Bind a native search field with the Command-K hint and shortcut. |
| `OnePlusNavRow` | Supply title, icon, selection, optional count, and action. |
| `OnePlusNavCaption` | Label a navigation section in its fixed slot. |
| `OnePlusNavBadge` | Display a text-only navigation count. |
| `OnePlusPageHeader` | Supply title, subtitle, `.system` or `.dotMatrix`, and actions. |
| `OnePlusToolPageHeader` | Place a 40 pt tool icon beside the title at the shared 16 pt content top. |
| `OnePlusCatalogMetrics` | Read fixed catalog card, list, icon, and action geometry. |
| `OnePlusTab` / `OnePlusTabStrip` | Bind selection to underline tabs with counts and trailing tools. |
| `OnePlusPage` | Keep header, tabs, toolbar, and footer fixed; use `scrolls: false` for a table that fills the remaining height. |
| `OnePlusCard` | Group natural-height content with a shared fill, line, and radius. |
| `OnePlusPanel` | Use the compatible card that fills available height. |
| `OnePlusCardHeader` | Add a 40 pt title row with an optional icon and accessory. |
| `OnePlusSettingRow` | Supply label, caption, help, reset, and a 160 or 180 pt control column. |
| `OnePlusSectionTitle` | Label a section with an optional trailing link action. |
| `OnePlusButtonStyle` | Choose a variant; omitted size follows density, while regular and small force 28 or 24 pt. |
| `OnePlusMenuButton` | Build an action menu with a ghost or neutral trigger. |
| `.onePlusNeutralControls()` | Give native menus and template images neutral tint. |
| `OnePlusInteractionStyle` | Add shared interaction feedback to caller-owned row geometry. |
| `OnePlusControlLabel` | Style a native Menu label with the same button geometry. |
| `OnePlusControlState` | Show deterministic rest, hover, pressed, and focus samples in the showcase. |
| `OnePlusSwitchStyle` | Style a native Toggle binding with the compact switch shell. |
| `OnePlusCheckboxStyle` | Keep native checkbox behavior and shared type. |
| `OnePlusRadio` | Bind a native radio-group Picker to typed choices. |
| `OnePlusSegmented` | Bind typed choices; pass `width: 160` or `180` to fill the control column. |
| `OnePlusSegments` | Use the compatible intrinsic-width segmented control. |
| `OnePlusSelect` / `OnePlusMenuLabel` | Bind choices in the shared neutral popup. |
| `OnePlusStepperField` | Edit a bounded integer with validation and a non-repeating native stepper. |
| `OnePlusTextField` | Edit a line with a label, optional error, and submit action. |
| `OnePlusSearchField` | Bind native search with Escape-to-clear and an optional focus trigger. |
| `OnePlusTextEditor` | Edit plain text in NSTextView with native undo, selection, and IME support. |
| `OnePlusMetricTile` | Show a metric, unit, caption, optional chart, and optional action. |
| `OnePlusSparkline` | Draw a cached line from samples and a range. |
| `OnePlusAreaChart` | Add a cached four-point ordered-dot fill and grid to a chart. |
| `OnePlusUsageBar` | Show one clamped usage fraction in a five-point track. |
| `OnePlusSegmentBar` | Show proportional categories from values and series colors. |
| `OnePlusStatus` | Pair neutral status text with a dot; request `.success` explicitly for green. |
| `OnePlusBadge` | Show a count, with an optional pending state. |
| `OnePlusKeyValueRow` | Align a label and selectable value. |
| `OnePlusTable` / `.onePlusTableHeader()` / `.onePlusTableRow(selected:)` | Share native Table and List row geometry. |
| `.onePlusTableCell(column, position:)` / `.onePlusNativeTable(columns:)` | Use one `OnePlusGridColumn` model for SwiftUI cell roles, insets, alignment, and headers. |
| `OnePlusGridColumn` / `OnePlusGridTable` | Show a small read-only table with fixed column widths. |
| `OnePlusNativeTable` / `.onePlusNativeTable()` | Share 9 pt uppercase native headers and 34 or 28 pt rows. |
| `OnePlusEmptyState` | Show an icon, title, explanation, and optional action. |
| `OnePlusDotTitle` | Draw a cached 5 × 7 title with one accessibility label. |
| `OnePlusToast` | Show a message and post an accessibility announcement; the caller owns its lifetime. |
| `OnePlusSheet` / `OnePlusSheetWidth` | Supply header, body, and footer inside native `.sheet`. |
| `OnePlusBanner` | Show an inline information, warning, or error row with an optional action. |
| `OnePlusMenuPanel` | Supply tabs, actions, optional fixed toolbar/footer, and a body capped to screen height. |
| `OnePlusMenuMetrics` | Read the 356 pt panel geometry and span-aware column widths. |
| `OnePlusMenuTab` / `OnePlusMenuTabStrip` | Bind 26 pt tabs; use `onMove` to store their order. |
| `OnePlusMenuTile` | Supply compact metric content in one, two, or three columns. |
| `OnePlusMenuControlRow` | Place Fan or Awake controls beside an icon, label, and status. |
| `OnePlusMenuSectionHeader` | Add a menu section line, title, and optional link. |
| `OnePlusMenuMetric` / `OnePlusMenuItemCard` | Show a host header, metric cells, detail, and trailing actions. |
| `OnePlusMenuOpenApp` | Supply the ghost Open App action. |
| `OnePlusAppletTitlebar` | Add a 40 pt bar with title and actions on the 22 pt centerline. |
| `OnePlusFloatingSettingsButton` | Place a 24 pt Settings or Back button at the applet's trailing edge. |
| `.onePlusFloatingSettingsInset()` | Reserve 52 pt below an applet body before an existing gear overlay. |
| `.onePlusFloatingSettings(isActive:help:action:)` | Reserve the same area and place the gear in one modifier. |
| `.onePlusScrollIndicators(axes:)` / `OnePlusOverlayScroller` | Keep full viewport width and thin overlay thumbs on the requested axes. |

Catalogs can use `OnePlusSegmented(iconChoices:selection:accessibilityLabel:)`
for labeled icon segments and `OnePlusButtonStyle.catalogOpen` for 26 pt Open
actions. `OnePlusNavRow(muted:)` dims a label while keeping navigation active.
`OnePlusSidebarSearch(alternateShortcut:)` adds a shortcut beside Command-K.
`OnePlusNavCaption(spacing: .sectionStart)` adds 16 pt before a later section.
`OnePlusTab(countDigits:)` reserves three digits by default for stable counts.
`OnePlusNavBadge(minimumDigits:)` supplies the same slot in other navigation.
`OnePlusButtonStyle(.borderedIcon)` paints the raised square for report actions.
`OnePlusActionMenu` keeps SwiftUI command builders and uses the shared popup.
Its legacy width argument remains valid; the trigger fits its label. Native
submenu commands appear under named section headers in the current popup.

## Add a variant

1. Read the corresponding `DESIGN.md` recipe and check the existing component.
2. Add a named variant in that component's file. Keep its current defaults.
3. Reuse tokens and native behavior. Keep hover, press, and focus geometry fixed.
4. Add the variant and its applicable states to the showcase.
5. Check dark and light appearances, keyboard behavior, and accessibility labels.
6. Add a small test when the variant introduces logic or geometry calculations.

Textures decode once. Chart patterns and title paths are cached. No component
uses an idle animation loop. A temporary task or observer must end when its
owner disappears. Native menus, sheets, text editing, and Full Keyboard Access
keep their platform behavior. Data loading, empty, and error states belong to
the containing card, not every leaf control.

## Build and review

```sh
swift build
swift test
swift run OnePlusUIShowcase
```

The showcase opens a 1240 × 840 window in the background. Its pages cover
tokens, type, controls, data, settings, Task Manager, menu panels, applets, and
feedback. Use the header appearance control to check dark and light. All
sample actions change local state. Quit through the sidebar or window close.
The app does not read MacPowerToys settings, accounts, or credentials.


## Compact and native forms

`OnePlusTabStrip(layout: .applet)` uses the 16 pt applet gutter.
The default workspace gutter stays unchanged.
`OnePlusMenuTab` accepts an optional accessibility identifier for native tests.

Set `environment(\.onePlusControlHeight, OnePlusMetrics.controlHeight)`
to use 28 pt fields, select menus, segmented controls, and regular buttons
inside a compact menu panel. Small buttons remain 24 pt.

Native XIB forms can use these classes with module `OnePlusUI`:

- `OnePlusNativeWindowView`: opaque window body with window tokens.
- `OnePlusNativeCardView`: panel fill, border, and 8 pt radius.
- `OnePlusNativeCaptionLabel`: section caption style.
- `OnePlusNativeSwitchButton`: NSButton state and target/action with a switch.
- `OnePlusNativeStepperField`: editable number and native stepper. The
  existing number formatter supplies its limits. Target/action stays intact.

Call `OnePlusNativeForm.style` after loading a reusable controls nib.
Native titles, localization, accessibility labels, and key loops stay in
the owning application. These variants add no timers or observers.
