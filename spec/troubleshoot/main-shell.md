# Main Shell Troubleshooting

## Menu-Bar Click Arbitration

- **Symptom:** Double-clicking the menu-bar icon opens and closes the popover
  instead of opening the main window, or right-click exposes the full popover.
- **Cause:** The first click was performed immediately, before macOS could
  report the second click in the double-click interval.
- **Invariant:** Intercept left and right mouse-down events on the status-item
  button. Delay a left single-click by `NSEvent.doubleClickInterval`; a second
  click cancels it and opens the main window. Right-click bypasses that
  coordinator and shows only Open MacPowerToys and Quit, with icons.
- **Check:** Unit-check single, double, and right-click routing, then exercise
  all three in the latest normal signed build.

## Menu-Bar Popover Rhythm

- **Symptom:** Status dots, labels, transfer progress, and actions shift between
  rows or sit too close to neighboring items.
- **Cause:** Each tray section used independent icon widths, row heights, and
  spacing values, so mixed content had no shared alignment columns.
- **Invariant:** Use an 18pt leading icon column, at least 24pt for compact
  status/history rows, 8pt between peer controls, and align transfer progress
  with its text column. Keep Pause/Resume on the active transfer row. Awake
  uses the same 12pt horizontal and 10pt vertical content insets as Cloud Sync.
- **Check:** Compare Cloud Sync idle, active, and paused states with Awake;
  leading labels and trailing actions must remain aligned without crowding.

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
  Claude History appears materially larger than MacPowerToys when its applet
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
