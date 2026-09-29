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
| `OnePlusToolPageHeader` | Align a 40 pt tool icon, title, subtitle, and actions on the window centerline. |
| `OnePlusCatalogMetrics` | Read fixed catalog card, list, icon, and action geometry. |
| `OnePlusTab` / `OnePlusTabStrip` | Bind selection to underline tabs with counts and trailing tools. |
| `OnePlusPage` | Keep header and tabs fixed while content scrolls inside shared gutters. |
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
| `OnePlusSegmented` | Bind typed choices with native accessibility and arrow-key selection. |
| `OnePlusSegments` | Use the compatible intrinsic-width segmented control. |
| `OnePlusSelect` / `OnePlusMenuLabel` | Bind choices in a native Menu popup. |
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
| `OnePlusGridColumn` / `OnePlusGridTable` | Show a small read-only table with fixed column widths. |
| `OnePlusNativeTable` / `.onePlusNativeTable()` | Share 9 pt uppercase native headers and 34 or 28 pt rows. |
| `OnePlusEmptyState` | Show an icon, title, explanation, and optional action. |
| `OnePlusDotTitle` | Draw a cached 5 × 7 title with one accessibility label. |
| `OnePlusToast` | Show a message and post an accessibility announcement; the caller owns its lifetime. |
| `OnePlusSheet` / `OnePlusSheetWidth` | Supply header, body, and footer inside native `.sheet`. |
| `OnePlusBanner` | Show an inline information, warning, or error row with an optional action. |
| `OnePlusMenuPanel` | Supply tabs, actions, and a scrolling body capped to screen height. |
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
| `.onePlusScrollIndicators()` / `OnePlusOverlayScroller` | Keep native scrolling with thin overlay thumbs. |

Catalogs can use `OnePlusSegmented(iconChoices:selection:accessibilityLabel:)`
for labeled icon segments and `OnePlusButtonStyle.catalogOpen` for 26 pt Open
actions. `OnePlusNavRow(muted:)` dims a label while keeping navigation active.
`OnePlusSidebarSearch(alternateShortcut:)` adds a shortcut beside Command-K.

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
