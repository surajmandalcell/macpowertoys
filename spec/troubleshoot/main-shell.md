# Main Shell Troubleshooting

## Launcher Actions On Short Displays

- **Symptom:** In a 1024pt hosted display, selecting Switch showed its detail
  body but the header enable switch and Open button were beyond the right edge.
- **Cause:** The launcher forced 1200pt content and a 1200pt minimum even when
  the visible screen was narrower.
- **Invariant:** Use 1200×720 when it fits. Clamp the fixed launcher to the
  visible display and reduce grid columns before card actions become cramped.
  Keep the detail header controls inside the window.
- **Check:** Hosted [run 36137254239](https://github.com/surajmandalcell/macpowertoys/actions/runs/36137254239)
  passed the Switch launcher route on a 1024pt display. Its capture shows both
  header controls in bounds, and the UI test clicked Open to show Switch.

## Launcher Card Description Height

- **Symptom:** Tool descriptions end in an ellipsis after two lines while most
  of the launcher window remains empty.
- **Cause:** Every card had a two-line text limit and a 110pt minimum height,
  even though the built-in descriptions need up to five lines at four columns.
- **Invariant:** Keep complete built-in descriptions at the standard text size
  in the four-column launcher, without a fixed two-line limit.
- **Check:** Hosted run `36124794622` saved dark and light 980×676 native
  captures with complete descriptions on all 13 cards. Inspect the signed app
  only when desktop interaction is allowed.

## Launcher Adaptive Grid Falls To Three Columns

- **Symptom:** The 1,200pt launcher shows three cards per row although its
  specification and width-only test expect four.
- **Cause:** Four 220pt adaptive cards, gaps, and padding need 976pt of the
  nominal 980pt pane. The scroll view can reserve about 16pt for its scroller.
  At the resulting 916pt grid width, an offscreen SwiftUI repro places four
  sample cards on two rows instead of one.
- **Invariant:** Use four flexible columns at the standard launcher width, so
  the cards share the available grid width even with the scroller reservation.
  Keep complete descriptions and the aligned enable/Open row.
- **Check:** `LauncherGridTests` places four cards in one row at 916pt. Hosted
  [run 36101318344](https://github.com/surajmandalcell/macpowertoys/actions/runs/36101318344)
  passed and saved a 980×676 native capture with four columns, complete
  descriptions, and aligned controls. Inspect the exact signed app only when
  desktop interaction is allowed.

## Two-Row Launcher Card Density

- **Symptom:** Four columns were correct, but 172pt cards left the last of 13
  built-in tools clipped at the bottom of the standard 980×676 launcher.
- **Cause:** The icon/name header and the enable/Open row took separate vertical
  space above each description.
- **Invariant:** Keep four flexible columns. Let the 48pt icon span the name
  and action rows, with the name above the native switch and Open button.
  Place each complete description below that header. Keep the card, switch,
  and Open actions separate.
- **Check:** Hosted [run 36124794622](https://github.com/surajmandalcell/macpowertoys/actions/runs/36124794622)
  passed and saved 980×676 dark and light native captures. All 13 cards are
  fully visible with complete descriptions and visible controls. Live action
  checks await a focus-safe signed app session.

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

## Menu-Bar Popover Anchoring

- **Symptom:** The combined popover appears left of the click instead of
  perfectly centered below the menu-bar icon.
- **Cause:** SwiftUI's window-style `MenuBarExtra` owns placement and clamps the
  window to available screen edges. Its public scene API exposes content,
  insertion, label, and style, but no anchor-point or frame-origin control.
- **Invariant:** Keep the combined item as a native window-style `MenuBarExtra`.
  Do not replace native left-click presentation or use private status-item or
  window-server positioning APIs to force mathematical centering.
- **Check:** Confirm the app contains no custom popover position or frame-origin
  path and the local SwiftUI SDK exposes no `MenuBarExtra` placement control.
  Click the item near the middle and each screen edge; require immediate native
  presentation and accept system edge avoidance.

## Menu-Bar Popover Rhythm

- **Symptom:** Status dots, labels, transfer progress, and actions shift between
  rows or sit too close to neighboring items.
- **Cause:** Each tray section used independent icon widths, row heights, and
  spacing values, so mixed content had no shared alignment columns.
- **Invariant:** Use one compact reorderable icon strip above one vertically
  scrollable body. Let the strip use its intrinsic width while it fits; cap it
  at the available width and scroll only after overflow. Home places Pick
  Color, Extract Text, and Ruler in one direct-action row, followed by one
  compact Awake row. Complex tray-capable built-ins own focused tabs in this
  default order: Cloud Sync, Input Devices, System Care, System Monitor, and
  NetToys. App-only tools such as Logs never appear. Keep separate Open
  MacPowerToys, Settings, and Quit controls and no divider below the strip. Pin
  the tab group to the leading edge and those three app controls to one fixed
  trailing group; do not distribute the six controls as one centered row. Use
  the same 12pt symbol inside every 24pt tab and outer chrome control. Cloud
  Sync uses two overlapping clouds instead of a single-cloud symbol.
- **Check:** Exercise short and overflowing tab sets, confirm Home then Cloud
  Sync appear first, reorder two complex tabs, relaunch, and confirm order and
  selection persist. Compare Home and Cloud Sync alignment in light, dark,
  Increased Contrast, and Reduced Transparency.

## Menu-Bar Empty-State Width

- **Symptom:** The Cloud Sync tray icon and “No transfers yet” text sit in a
  narrow column at the left edge, even though the popover is full width.
- **Cause:** The empty view could fill only the width proposed by the measured
  scroll content. The earlier layout check gave it a 360pt parent directly and
  missed the scroll container's intrinsic-width path.
- **Invariant:** Give every tray tab the popover's content width inside
  `TrayMeasuredScroll`, before measuring its height.
- **Check:** Open an empty Cloud Sync tray in the final signed build. The cloud
  and text center inside the 360pt body in light and dark appearances.

## Menu-Bar Tab Density

- **Symptom:** The combined popover becomes a second settings window or a long
  mixed dashboard that is hard to scan.
- **Cause:** Every tool either embedded a full settings page or contributed to
  one undifferentiated vertical list.
- **Invariant:** Tabs organize distinct tasks, not every settings page. Home
  keeps only compact single-purpose controls. Cloud Sync shows connection and
  transfer operation, not configuration. Input Devices may reuse its full
  mouse and trackpad controls because those controls are the tool's immediate
  purpose. Other complex tabs expose only their useful menu-bar surface. Omit
  explanatory body subtitles; visible status text remains where it conveys
  changing operational state. Cap the body at 70 percent of the screen.
- **Check:** The all-tools state stays within the height cap. Cloud Sync has no
  durable settings form. Input Devices exposes the same saved controls as its
  window. No tab contains an unexplained duplicate Open button.

## Menu-Bar Visual Language

- **Symptom:** Bright tool-colored buttons make the popover look unrelated to
  the rest of MacPowerToys and reduce label contrast.
- **Cause:** Tool identity colors were used as large action fills.
- **Invariant:** Match the supplied dark utility-panel reference with an opaque
  semantic window background, monochrome SF Symbols, primary and secondary
  text, hairline grouping only where it helps scanning, and low-opacity neutral
  hover, pressed, and selected layers. Do not leave the popover material or
  desktop visibly blurred through the body. Never use a tool's major color as a
  large tray fill. Preserve keyboard focus and at least 24pt pointer targets.
- **Check:** Render Home and one complex tab in light and dark appearance.
  Labels remain readable at rest and on hover, selection is obvious without a
  bright accent block, and the panel still reads as part of MacPowerToys.

## Fan And Awake Tray Alignment

- **Symptom:** Fan looks like a separate badge, or both Fan and Awake waste
  space on the right while Fan and RPM split into two lines.
- **Cause:** The compact Fan used a tinted card and stacked text; both rows
  added 8pt to the tray's 12pt gutter on both sides.
- **Invariant:** Compact Fan uses the plain Awake-row pattern and a native
  segmented control. Both rows use a 16pt leading inset and only 4pt of
  trailing clearance, the least that keeps the native rounded ends visible.
  Size each native picker to its rendered width. The fan icon uses Awake's
  neutral tint, and Fan, RPM, and utilization share one line. Leave 18pt below
  the Fan row.
- **Check:** Inspect Home and System Monitor in the production-width tray in
  light and dark, including both row edges, the bottom edge, live RPM, and
  disabled fan controls.

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
  exactly one dashboard section or action, Separate removes it and adds one
  native status item, and None removes both without changing tool enablement.

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

## Heavy Launcher Settings First Frame

- **Symptom:** Selecting NetToys or System Monitor leaves the launcher frozen
  before the detail page appears.
- **Cause:** NetToys decoded saved history and scan archives on the main actor,
  while both heavy destinations built their complete settings trees before
  SwiftUI could present an immediate frame.
- **Invariant:** Present a cancellable loading shell before building these two
  settings trees. Read and decode NetToys history on a utility task, coalesce
  overlapping refreshes, and apply only completed snapshots on the main actor.
  Do not preload on hover or retain destination views after selection changes.
- **Check:** Time Awake, System Monitor, and NetToys from sidebar activation to
  the first accessible detail frame in the exact signed app. Confirm the two
  heavy pages expose their loading identifiers, switching away cancels the
  structured view task, and repeated selection does not grow background owners.

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

- **Symptom:** Awake, Color Picker, Text Extractor, Ruler, Logs, or Cloud Sync
  appears materially larger than MacPowerToys when its applet
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
