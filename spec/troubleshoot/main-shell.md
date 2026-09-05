# Main Shell Troubleshooting

## Compact Tool Enablement

- **Symptom:** Tool cards or detail pages spend one row on an `Enabled` label
  and another on an oversized custom Open button.
- **Cause:** Enablement and launch were styled as separate form sections instead
  of related actions for one tool.
- **Invariant:** Put the unlabeled native switch and native small Open button in
  one row. Keep an accessible enable label and keep disabled launch behavior.
- **Check:** Inspect every launcher card and tool detail. No visible `Enabled`
  label remains, both controls share one row, and Accessibility names the tool.

## Menu-Bar Click Routing

- **Symptom:** Custom double-click handling makes the menu-bar popover feel
  delayed or unreliable when the item already owns a native dropdown.
- **Cause:** Left-click arbitration competes with `MenuBarExtra` instead of
  letting the system own its standard interaction.
- **Invariant:** Leave all left clicks native and immediate. Intercept only
  right mouse-down to show Open MacPowerToys and Quit. Keep the tested
  `StatusItemClickCoordinator` dormant so a future non-dropdown status item can
  reuse it without changing the current menu item.
- **Check:** Unit-check that the status-item mask contains only right
  mouse-down. In the latest normal signed build, confirm that left-click opens
  the popover immediately and right-click shows only Open and Quit.

## Menu-Bar Popover Rhythm

- **Symptom:** Status dots, labels, transfer progress, and actions shift between
  rows or sit too close to neighboring items.
- **Cause:** Each tray section used independent icon widths, row heights, and
  spacing values, so mixed content had no shared alignment columns.
- **Invariant:** Use an 18pt leading icon column, at least 24pt for compact
  status/history rows, 8pt between peer controls, and align transfer progress
  with its text column. Keep Pause/Resume on the active transfer row. Every tab
  body uses the same 12pt horizontal gutter and 14pt bottom inset. Give the
  outlined tab group one 8pt outer inset above and below it. Its
  4pt inner inset must be equal on every edge, and non-scrolling tabs must use
  the complete available width. Use one accent selection, 4pt between tabs,
  and no divider below a group that already has its own surface. Show tab icons
  and names for one or two combined tools, then icons only above two. Persist
  the last selected available tool. Give the footer 8pt top and 10pt bottom
  insets.
- **Check:** Compare Cloud Sync idle, active, and paused states with Awake;
  leading labels and trailing actions must remain aligned without crowding.
  Measure every tab-group edge, both body bottoms, and both footer edges. Add a
  third combined tool, confirm labels disappear, then reopen the popover and
  confirm the last selected available tool returns.

## Menu-Bar Tab Body Gap

- **Symptom:** The popover leaves a wide empty band under the tab row before
  any content starts.
- **Cause:** The tab group carried its own bottom inset while each tab body
  added a second top inset, so two gaps stacked below one tab row. The group
  also kept a 20pt top inset, so 38pt of chrome surrounded a 36pt tab group.
- **Invariant:** The tab group owns the only gap on each side of the tab row:
  `TrayPopoverLayout.tabGroupOuterInset` (8pt), applied with one
  `.padding(.vertical,)`. `TrayPopoverLayout.bodyTopInset` is 0, so no tab body
  adds a second top gap under the tab row.
- **Check:** `TrayPopoverLayoutTests.testTrayBodyStartsOneOuterInsetBelowTheTabRow`
  renders the popover offscreen and measures its vertical ink bands. The first
  blank band must equal the outer inset, the tab-group band must equal
  `tabGroupInset * 2 + tabHeight`, and the next blank band must not exceed the
  outer inset plus 3 points of text ascent.

## Menu-Bar Tool Settings

- **Symptom:** A menu-bar tool exposes only a description and an Open button,
  so every setting needs the launcher or the tool window.
- **Cause:** The tray owned small per-tool views instead of the shared settings
  view.
- **Invariant:** Every combined tray tab shows one operational summary and then
  `ToolSettingsContent(toolID:)`, the same view the launcher detail and the tool
  window use. Each tab has one scrolling region, capped at 70 percent of the
  screen through `TrayPopoverLayout.maximumBodyHeight`. A settings view that
  cannot fit 340pt adapts through the `compactSettingsLayout` environment value;
  never copy its controls. A control in the tool's settings view must not repeat
  in the tray summary.
- **Check:** `TrayPopoverLayoutTests.testEveryTrayTabbedToolRendersItsSharedSettingsView`
  proves that no tray-tabbed tool falls back to the no-settings placeholder. In
  the installed build, change one setting in each tray tab and confirm the same
  value in that tool's window.

## Menu-Bar Tool Placement

- **Symptom:** A menu-capable tool is forced into the combined popover, can only
  add a separate icon, or has no launcher control for either placement.
- **Cause:** Combined membership and separate status items used independent
  Boolean rules instead of one per-tool placement preference.
- **Invariant:** Cloud Sync, Awake, Color Picker, Text Extractor, and Input
  Devices each expose one native segmented launcher control with None,
  Combined, and Separate. One tool occupies at most one placement. Preserve
  legacy separate choices, preserve the existing Cloud Sync and Awake combined
  defaults, and keep separate-item autosave names stable.
- **Check:** Exercise all three modes for all five tools. Confirm Combined adds
  exactly one tab, Separate removes that tab and adds one native status item,
  and None removes both without changing tool enablement.

## Menu-Bar Footer Contrast

- **Symptom:** Open MacPowerToys and Quit look disabled in the menu-bar footer.
- **Cause:** The footer used the native secondary text style at rest.
- **Invariant:** Footer actions use the 75% primary text token at rest and full
  primary text on hover.
- **Check:** Inspect both footer actions at rest and on hover in light and dark
  appearances. They remain readable and still gain contrast on hover.

## Shared Tool Enablement

- **Symptom:** A disabled tool still opens from a shortcut or deep link, starts
  at launch, or remains in the menu-bar tab strip.
- **Cause:** Availability was stored or checked independently by each surface.
- **Invariant:** `SettingsManager` owns the one disabled-ID set; missing IDs are
  enabled. Cards and detail pages write that state, while routing, shortcuts,
  launch restoration, background services, and tray tabs all read it. Disabled
  tools remain selectable in the launcher only so they can be re-enabled.
- **Check:** Disable every built-in tool once from All Tools and once from its
  detail page. Confirm Open, global shortcuts, deep links, CLI/start-at-launch,
  Awake assertions, Cloud Sync engine work, and tray presence all follow the
  same state; then re-enable from the detail page.

## Launcher Settings Reuse

- **Symptom:** Clicking a launcher tool shows help only, or its settings differ
  from the tool window and require duplicate maintenance.
- **Cause:** The launcher owned a separate detail implementation.
- **Invariant:** Detail pages open on Settings and embed the same settings view
  used by the tool window, with How to Use as the adjacent page. Ruler reopens
  its existing AppKit panels instead of cloning them in SwiftUI.
- **Check:** Change one setting from each launcher detail, reopen its tool
  window, and confirm the same value and control surface are present.

## External Sub-App Launch Ordering

- **Symptom:** A Raycast sub-app command shows the main window for one frame
  before it shows the requested sub-app.
- **Cause:** The main SwiftUI scene accepted an unmatched Ruler URL before the
  AppKit route ran. The Ruler route also built its windows before it closed an
  existing main window. Native SwiftUI scene links used a second manual route.
- **Invariant:** Make the main scene handle only the `main` event. Use only
  SwiftUI scene routing for native sub-app windows. For an AppKit sub-app,
  close the main window before synchronous window creation.
- **Check:** Start from a stopped process and sample WindowServer windows every
  5 ms while opening one native sub-app and Ruler. No positive-size main window
  may appear. Only the requested sub-app may draw.

## Command-Q Window Routing

- **Symptom:** Command-Q in one sub-app quits MacPowerToys and closes every
  other tool that shares the process.
- **Cause:** The standard application termination command went directly to
  `NSApplication.terminate` without checking the active window scope.
- **Invariant:** Replace only the app termination command. In a known sub-app,
  close every visible window in that tool scope through `performClose`. On the
  launcher, an unknown window, or no window, require two Command-Q presses
  within two seconds and show `Press ⌘Q again to quit` after the first press.
  Keep explicit status-item Quit, Dock Quit, logout termination, and Command-W
  on their native paths. Resolve an unidentified sheet through its parent chain,
  end the sheet, and then close the tool windows so modal state cannot block the
  close operation.
- **Ruler exception:** Close every managed ruler through `RulerManager` instead
  of calling `performClose` on its borderless windows. Also close Ruler Settings
  and Defaults, then stop the mouse timer.
- **Check:** In a normal signed build, press Command-Q in each sub-app and
  confirm only that tool closes. On the launcher, confirm one press keeps the
  app open, a second press within two seconds quits, and an expired press starts
  a new confirmation. Confirm Command-W behavior does not change.

## Window Space Restoration

- **Symptom:** A reopened utility returns to its saved frame and display but not
  necessarily to the macOS Space where it was last used.
- **Cause:** Public AppKit and SwiftUI restoration can preserve a window's
  system configuration by recreating windows that were open at quit. macOS does
  not expose a public API for assigning an independently reopened window to a
  Space.
- **Invariant:** Preserve frame and display through `WindowStateManager`. Keep
  automatic scene restoration disabled so tools never reopen merely because
  they were visible at quit. Never use private window-server APIs to force a
  Space.
- **Check:** Relaunch and reopen each window to verify its frame and display.
  Treat exact Space placement as unsupported unless Apple adds a public API or
  the product requirement changes to allow automatic reopening of prior scenes.

## Compact Applet Frame Restoration

- **Symptom:** A compact applet opens taller than its content, leaving dead
  space below the body and a floating settings button that sits well above the
  bottom-right corner.
- **Cause:** `WindowStateManager.restoreState` applied the complete saved
  frame, including a stale height, to windows whose height is content-driven.
  SwiftUI centers the fixed-size content in the taller window.
- **Invariant:** Fixed-size applet windows (`awake`, `color-picker`, and
  `text-extractor`) restore position only: keep the saved top-left
  edge and the window's current content-driven size. Never restore a saved
  width or height onto a content-sized applet.
- **Check:** Save an applet frame, change its expected content height, reopen,
  and confirm the body fills the window with the settings button 8pt from the
  bottom-right corner.

## Dock Icon Optical Sizing

- **Symptom:** Awake, Color Picker, Text Extractor, Ruler, Logs, Cloud Sync, or
  AI History appears materially larger than MacPowerToys when its applet
  window becomes key, or the Dock icon is regenerated during every focus event.
- **Cause:** Applet artwork filled the complete 512pt asset canvas while the
  base icon's visible body occupied about 396pt. Assigning each source image
  directly to `NSApp.applicationIconImage` therefore ignored optical sizing.
- **Invariant:** Keep the base `AppIcon` on AppKit's native reset path. Render
  applet assets once per asset and appearance in a centered 396/512 optical
  inset, observe the application's effective appearance, and skip
  application-icon assignment only when both the requested asset and appearance
  have not changed. The base icon remains an Icon Composer asset so macOS
  supplies its current material, depth, and appearance treatment.
- **Check:** Unit-test the 396/512 inset geometry, cache identity, window-to-icon
  mapping, and unchanged-asset suppression. In the installed signed build,
  compare the base and every applet in the Dock in light and dark appearances;
  their perceived body size should match without focus-time redraw churn.

References: Apple's
[SwiftUI suppressed launch behavior](https://developer.apple.com/documentation/swiftui/scenelaunchbehavior/suppressed)
and
[AppKit state-restoration sample](https://developer.apple.com/documentation/appkit/restoring-your-app-s-state-with-appkit).
