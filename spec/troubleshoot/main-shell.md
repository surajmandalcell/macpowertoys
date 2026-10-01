# Main Shell Troubleshooting

## Startup Readiness And Saved Data Recovery, 2026-10-01

- **Symptom:** A requested built-in tool waits for archive restoration, or a
  failed ModelContainer open terminates the app.
- **Cause:** Startup awaited unrelated archives and created the store in the
  App initializer. Its catch called fatalError.
- **Invariant:** Migrate preferences in App init before SwiftUI scene commands
  can construct and cache settings owners. This migration does no file work.
  Publish route and status-item readiness before archive reads and store-file
  migration. Keep plugin-dependent work after Marketplace receipts. Open
  storage away from the main actor and share concurrent opens. Cloud Sync
  requires the container; built-in tools do not. Show the actual error with
  native Retry and Reveal Data Folder. Keep files and migration inputs.
  Retry reuses their paths. Never reset or select temporary storage after a
  normal-run failure.
- **Check:** The source-derived Swift 6 disposable-store check preserves all
  files on injected failure, then reads the saved record on Retry. The actual
  LogEntry/TransferRecord fixture keeps 10,000 rows and original inputs.
  Initial bundled migration takes 210-228ms/container opening 4.8-7.6ms. The
  final separated fixture takes 586ms for 1,000 preferences, 3.8ms for files,
  and 16.4ms for container opening under shared build load. App init copies
  preferences without creating the data folder. These values exclude full
  app startup and cold OS caches. Run
  `tmp/redesign/checks/app-lifecycle/store-check.py` and `profile-startup.py`.
  Hosted AppLifecycleTests and signed readiness, native recovery, Finder reveal,
  and Cloud Sync first-frame checks remain with the orchestrator.

## Bounded Quit Keeps Recovery Available, 2026-10-01

- **Symptom:** Quit blocks during Fan Auto, waits without a deadline, or exits
  after a critical save failed.
- **Cause:** Fan reset ran in applicationWillTerminate. Other cleanup stages
  had no failure result or bounded wait.
- **Invariant:** Use terminateLater. Await the existing Fan Auto operation and
  throwing Color Picker and Cloud Sync drains. Check LogManager.persistenceError
  after its flush. Deadlines are 20s for Fan, 10s for Color Picker, 10s for logs,
  and 30s for Cloud Sync. A deadline cancels its cleanup task and quit, then
  shows Retry and Keep Open. Retain unfinished work so Retry waits for it.
  Save paused transfer snapshots before engine teardown. Stop UI owners after
  critical success. Never force exit from a timeout. Keep late startup work
  from publishing or resuming jobs after successful shutdown.
- **Check:** `tmp/redesign/checks/app-lifecycle/shutdown-check.py` runs the actual
  stage with a task that ignores cancellation. It proves a main-actor heartbeat,
  bounded failure, one in-flight operation, save error, and successful retry.
  `--mutate` rejects missing task cancellation. The orchestrator must run
  AppLifecycleTests on hosted CI and check Fan Auto, save failure, early quit,
  Retry/Keep Open, and continuous-job resume on the clean signed installed app.

## Tool Glyphs And Status Image Size, 2026-10-01

- **Symptom:** Sidebar and panel glyphs differ from approved tool icons. Native
  status items look larger than Portman, and one Memory item hides the Task
  Manager identity.
- **Cause:** Tool symbols were copied across enums. Native SF images kept
  intrinsic bounds, and equal point sizes did not give equal painted sizes.
- **Invariant:** `ToolGlyph` owns the 14 unique tool symbols and Ruler angle.
  `StatusItemIcon` caches template images on a 14pt canvas with a centered
  11.2pt maximum ink span, measured from the old Portman socket. Rasterize
  once at 4x to keep SF hinting from changing geometry at display scale.
  Use the Task Manager glyph when exactly one metric is enabled; retain saved
  per-metric choices for multiple metrics and preserve Value Only behavior.
- **Check:** Run `ToolGlyphTests` on hosted CI. Compare the 16pt/32pt contact
  sheet in both appearances. After signed installation, capture only the
  menu bar with `screencapture -R` and inspect all separate/grouped styles.

## Diagnostic Panel URLs Consumed By Native Scenes, 2026-09-30

- **Symptom:** In signed `db471735`, background main and Task Manager panel
  URLs add no window after three seconds. Portman adds a 382 x 319pt window.
  The app log records Portman but neither failed panel request.
- **Cause:** SwiftUI scene matching uses the complete URL. The tool name in
  a diagnostic URL can select a native scene. Its URL callback rejected
  manually routed URLs, so the request never reached the diagnostic opener.
- **Invariant:** Forward valid diagnostics from every native scene callback.
  Panel presentation does not require an OpenWindowAction. The background
  fallback hosts the production panel views at their measured natural height.
  Pass its resize callback into Task Manager, whose inner height modifier
  overrides an outer callback. Keep requested selection before measurement.
- **Check:** Compile `nativeSceneDiagnosticsReachMeasuredBackgroundPanels`.
  Execute it on hosted CI. In the signed updated build, open both Home URLs
  with `open -g`. Require a panel within three seconds, unchanged foreground
  application, the requested tab, and content-sized height. Switch to short
  and tall pages and compare with native status-item panels. The installed
  process was preserved; updated-build checks remain with the orchestrator.

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

- **Symptom:** Catalog summaries end in an ellipsis or compete with the title.
- **Cause:** Cards used the full tool-page description or a text modifier that
  overrode the caller's secondary foreground color.
- **Invariant:** The 2026-10-01 owner rule requires two-line catalog summaries
  in secondary ink. Keep full descriptions on tool pages and in help. Use the
  color parameter of `onePlusText` when a role needs a different ink.
  Catalog-specific fonts live in OnePlusCatalogMetrics. Its 11pt summary
  uses 2pt native line spacing for a measured 16pt baseline pitch. Category
  text is 9.5pt; identity gaps are 9pt. Keep 40pt grid/header icons and
  29pt list icons. Reserve only the 24pt favorite target, without another
  spacer. A 133.94pt name fits the resulting 138pt identity width.
- **Check:** Inspect all 14 summaries at four columns in both appearances.
  Each summary fits two lines; tool pages retain their full descriptions.

## Launcher Page IDs And Manual Updates, 2026-10-01

- **Symptom:** Settings always reopened General, or About had no manual
  update check and omitted the service lifetime and menu-bar recovery help.
- **Cause:** Main tabs were transient and host help had no update result.
- **Invariant:** Store validated page and tab raw IDs. Main uses a non-optional
  stored page and an optional selection binding. Removed or disabled saved
  tools fall back to All tools. Each tool detail tab has its own key. Explicit
  Settings and manual requests override saved tabs. Search stays in memory;
  saved pages never open tool windows. Ordinary Settings restores its tab.
  Keep the app menu-bar switch distinct from macOS Menu Bar permission and
  available space. Closing windows leaves enabled services running; Quit
  stops them. Link existing manuals. About and menu actions share bundle
  metadata and one manual URLSession checker. Compare numeric versions off
  main, reject invalid metadata and foreign release URLs, show checking,
  current, available, and retryable errors, and link release notes/download.
- **Check:** The existing resolver matrix passes in a plain Swift harness,
  including valid tabs, invalid fallback, explicit overrides, and tool/manual
  routes. Numeric release and URL cases pass; a reversed comparison fails.
  OnePlusCatalogTests measures the native 16pt pitch. The shared tests gate
  compiles the app and desktop test bundles. Hosted execution and signed
  light/dark, relaunch, update success/failure/retry, shortcut registration,
  launch alert, and live timing checks stay open. The main handoff lists the
  exact remaining task flows in `tmp/redesign/logs/w3-main.md`.

## Launcher Adaptive Grid Falls To Three Columns

- **Symptom:** The 1,200pt launcher shows three cards per row although its
  specification and width-only test expect four.
- **Cause:** Four 220pt adaptive cards, gaps, and padding need 976pt of the
  nominal 980pt pane. The scroll view can reserve about 16pt for its scroller.
  At the resulting 916pt grid width, an offscreen SwiftUI repro places four
  sample cards on two rows instead of one.
- **Invariant:** Use four flexible columns at the standard launcher width, so
  the cards share the available grid width even with the scroller reservation.
  Keep two-line summaries and the aligned enable/Open row.
- **Check:** `LauncherGridTests` places four cards in one row at 916pt. Hosted
  [run 36101318344](https://github.com/surajmandalcell/macpowertoys/actions/runs/36101318344)
  passed and saved a 980×676 native capture with four columns, complete
  descriptions, and aligned controls. Inspect the exact signed app only when
  desktop interaction is allowed.

## Two-Row Launcher Card Density

- **Symptom:** Tall cards clipped the last tool row. The later 151pt cards
  still left an empty band between each description and its controls in
  the signed `198055e4` capture.
- **Cause:** A fixed card height and an expanding spacer separated the
  description from the enable/Open row.
- **Invariant:** The 2026-10-01 owner correction requires four flexible
  columns and content-sized cards with equal heights in each grid row.
  Keep a 40pt icon beside the name and quiet category caption. Reserve two
  summary lines and put the enable/Open row 12pt below them. Cards have no
  grain. Keep the card, favorite, switch, and Open actions separate.
- **Check:** Hosted [run 36124794622](https://github.com/surajmandalcell/macpowertoys/actions/runs/36124794622)
  passed and saved 980×676 dark and light native captures. All 13 cards are
  fully visible with complete descriptions and visible controls. Live action
  checks await a focus-safe signed app session. `8dda22b4` replaces the
  fixed height with content sizing. `LauncherGridTests` measures real cards
  and checks equal heights below the old 151pt height, plus a four-card row.
  Both compile gates pass; hosted execution and signed recapture remain.

## Compact Tool Enablement

- **Symptom:** Tool cards or detail pages spend one row on an `Enabled` label
  and another on an oversized custom Open button.
- **Cause:** Enablement and launch were styled as separate form sections instead
  of related actions for one tool.
- **Invariant:** Catalog cards and list rows pair an unlabeled switch with a
  ghost Open text button without an arrow. Tool pages keep the switch in the
  header and put "Open <Tool>" in the fixed bottom action bar on the 24pt
  gutter with a 1pt lineSoft divider. Keep accessible names and disabled
  launch behavior. Ruler keeps both native settings actions in its body.
- **Check:** Inspect grid, list, and all 14 tool pages. No enable caption or
  catalog Open arrow remains. Scroll and switch tabs; the page action stays
  fixed. Disable a tool and require every launch route to stop. Run the hosted
  footer regression and inspect the accent action in both appearances.

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
  default order: Cloud Sync, Input Devices, System Care, NetToys, and Switch.
  Task Manager owns a separate menu-bar popup. App-only tools such as Logs never
  appear. Keep separate Open
  MacPowerToys, Settings, and Quit controls and no divider below the strip. Pin
  the tab group to the leading edge and those three app controls to one fixed
  trailing group; do not distribute the six controls as one centered row. Use
  the same 12pt symbol inside every 24pt tab and outer chrome control. Cloud
  Sync uses `ToolGlyph.cloudSync`, the same single cloud as its sidebar
  and separate status item. Tool identity symbols keep their shape and weight
  on selection; color changes at once.
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
- **Invariant:** Let `OnePlusMenuPanel` give every tab its shared 338pt body
  width before measuring its natural height. The outer shell is 356pt wide.
  Empty states are small cards inside useful tab content. Do not give them a
  large centered region.
- **Check:** Open Cloud Sync with and without remotes or transfers. Require
  the remote section and New Transfer action in both appearances. The empty
  transfer card must use only its content height. When configured remote cards
  already report no transfers, omit the separate empty transfer card.

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
  changing operational state. Use natural content height. The complete panel
  can use at most 90 percent of the visible screen height.
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
  large tray fill. Keep identity colors on key data: blue transfer progress
  and network values, cleanup storage segments, and account usage bars.
  Keep chrome neutral. Follow the shared focus policy in `DESIGN.md` and
  preserve at least 24pt pointer targets.
- **Check:** Render Home and one complex tab in light and dark appearance.
  Labels remain readable at rest and on hover, selection is obvious without a
  bright accent block, and the panel still reads as part of MacPowerToys.

## Menu-Bar Tab Preparation

- **Symptom:** A tab starts with another tab's height or pauses before its
  controls appear.
- **Cause:** Identity resets, animated replacements, synchronous file reads,
  repeated row formatting, and competing preferred-height estimates add work
  during a tab change.
- **Invariant:** Keep prepared transfer, network, cleanup, account, and process
  state at the panel root. Read NetToys files and format cleanup rows off the
  main thread. Mount only the selected tab's live view. Do not animate a tab
  replacement or assign it a new identity. The shared shell reports the actual
  height. Task Manager sampling and its process loop also check native panel
  visibility, since the layout tree can remain mounted while closed.
- **Check:** Compile the cleanup row-and-total regression and all nine Task
  Manager page renders in both appearances. After foundation round 10 lands,
  check short-to-tall-to-short switches, focus, and latency on the signed build.

## Main menu tab snapshots, 2026-09-30

- **Symptom:** System Care and Cloud Sync show large empty blocks. Input
  Devices shows a long settings form without device data. NetToys omits the
  active IP and gateway latency.
- **Cause:** Empty-state views replaced each tab's operational summary.
  Input Devices embedded a padded settings wrapper. NetToys used only the
  helper's saved reachability state.
- **Invariant:** System Care shows startup-volume Used, Purgeable, and Free
  segments from one capacity snapshot. Purgeable space is separate from free
  space. Keep unavailable capacity as a dash. Use one primary Scan action.
  Preserve saved cleanup selection and confirmed Move to Trash.
  Cloud Sync shows configured remotes, each remote's latest transfer state
  and time, New Transfer, and the existing active and recent transfer controls.
  Match both source and destination endpoints by the exact remote name.
  NetToys reads the current route and IP once when its tab opens or Refresh
  is used. Read SSID without asking for permission. Probe the gateway once
  with the existing cancellable runner, a two-second deadline, and an 8KiB
  output cap. Cancel refresh work when the native panel hides. Never reuse
  another route's Internet state or add a poller.
  Switch loads usage only on request. Input Devices shows detected devices,
  reported batteries, and current profile values before its controls. Expand
  the existing cards-only settings content without another page gutter.
- **Check:** Run the startup-disk and remote-activity regressions on hosted
  CI. Review every tab in both appearances from the signed build. Check
  missing capacity, denied SSID access, gateway timeout, unknown battery,
  unloaded usage, compact empty states, controls, and tab-switch latency.

## Compact Panel Review, 2026-09-30

- **Symptom:** NetToys repeats en0 and has no Location recovery link. Cloud
  Sync repeats its empty transfer state. Remote host action text is centered.
- **Cause:** NetToys used the interface as its network title and its adjacent
  tile. Empty jobs always added a second card. Remote buttons used plain titles.
- **Invariant:** Use `NetworkIdentity.displayName` for the current network.
  When its fallback includes the interface, the adjacent tile shows connection
  type instead. Preserve blue identity ink. Missing Wi-Fi names offer a small
  Location access link to NetToys Settings, which owns permission status and
  request or recovery decisions. Missing SSID alone does not prove denial.
  Route all panel page links through the durable tool-page router before opening.
  Configured remotes retain their empty subtitle without another transfer card.
  Offline host actions use leading 8.5pt text, a trailing 9pt glyph, and the
  shared paint-only row style. Keep the 84pt action lane and native actions.
- **Check:** Review disconnected, Wi-Fi with and without SSID, wired, and helper
  permission states. Open Location access from a cold and an existing window.
  Check empty and active Cloud Sync, both remote cells, keyboard focus modes,
  natural height, and tab latency in the signed app.

Production correction, 2026-10-01: use direct rows for single controls and
empty states. Put metadata on the trailing side and helper status behind an
info glyph with help. Apply row hover to the full content surface; an opaque
card inside a button label hides the button's hover background. Switch has
one header refresh icon for accounts and visible usage, one orange unloaded
limit warning with help, and no per-account refresh hints. Keep progress and
identity colors. Hover, press, tab, and content changes are instant. Check
unloaded and loaded limits, account switching, nested row controls, and both
appearances in the signed build. Report: `tmp/redesign/logs/w1-panel-main.md`.

## Switch panel account errors, 2026-10-01

- **Symptom:** Signed `198055e4` shows a coral account error sentence below
  the first Codex quota bar in the r10 main Switch capture.
- **Cause:** `accountContent` appends `Text(error)` below the usage bars.
- **Invariant:** Keep account identity on one line. Provider names stay in
  help and accessibility text. Account errors use one small trailing orange
  exclamation glyph with the complete error as help and accessibility text.
  Keep the shared header missing-limit warning, usage bars, token totals,
  default marker, and full-row switching action.
- **Check:** In the updated signed build, compare failed and successful
  accounts in both appearances. An error adds no text row or height. Hover
  the glyph and require the full message. Check long names, retained quotas,
  both usage windows, default actions, and VoiceOver. Fix: `47e98b79`.

## Combined Menu Icon And Tab Outline

- **Symptom:** The MacPowerToys status glyph looks slightly too large, and an
  outline appears around the popover's tab bar after opening or hovering it.
- **Cause:** The menu extra displays its 16pt asset at intrinsic size, while
  the tab strip adds a rounded container stroke and background.
- **Invariant:** Size the native menu-extra label at 14pt. Keep the tab strip
  free of an outer container, with quiet fill on hover, press, selection, and
  keyboard focus.
  Do not remove keyboard activation or accessibility names.
- **Check:** Compare the signed installed status item and open popover in light
  and dark. Hover and Tab through tabs and the trailing actions; no rectangular
  outline appears, while state and focus remain clear.

## Monitor Summary On Short Displays

- **Symptom:** The Monitor Home grid loses its last card row below the visible
  menu-bar panel, despite a large blank area in a fixed-size offscreen capture.
- **Cause:** Eight 88pt summary cards plus the new secondary tab row exceeded
  the tray body's 70-percent screen-height cap on a short display.
- **Invariant:** The shared 356pt Task Manager panel sizes each destination
  naturally. Its 90-percent screen limit is a ceiling. Fan appears on Home
  and Sensors. Only overflowing content scrolls on smaller screens.
- **Check:** Measure the natural Home height against the short-screen cap and
  inspect light and dark production-width renders. The first hosted render at
  `294c5a2` exposed the cutoff; hosted run `36152200305` passed the
  short-screen height regression after the summary cards were compacted. The
  hosted tray UI check also taps a secondary tab and summary card, then reopens
  the menu to verify the saved selection without using the owner's desktop.
  Run `36159003700` passed both tray UI cases and captured live CPU details.

## Fan And Awake Tray Alignment

- **Symptom:** Fan looks like a separate badge or Fan and RPM split into two
  lines at tray width.
- **Cause:** The compact Fan used a tinted card and stacked text; both rows
  added 8pt to the tray's 12pt gutter on both sides. Fan's read-only sentence
  also made its row taller. The native Awake picker draws its visible edge
  about 12pt inside its frame, so giving it another 12pt outer trailing inset
  leaves its buttons visibly short of the Home action edge.
- **Invariant:** The 2026-10-01 owner correction restores compact Fan below
  Awake on main Home when Task Manager is enabled. Main Home and Task Manager
  Home and Sensors reuse `FanControlView` with distinct visibility owners.
  Other Task Manager pages omit Fan. It uses the shared
  menu control row and compact 24pt three-option control.
  Fan, RPM, and utilization share one line; its icon stays
  neutral. Auto, Cool, and Max remain visible while unavailable options are
  disabled. When control is unavailable, a bare amber warning glyph opens the
  built-in-helper approval flow. There is no separate package or Terminal
  command. If manual control is unavailable but automatic recovery works,
  Restore Auto remains available in that popup. Independent availability in
  the segmented control needs a foundation API. The popup keeps its action
  clearance.
- **Check:** Inspect global Home, Monitor Home, and Sensors at production popup
  width in light and dark. Main Home, Task Manager Home, and Sensors show Fan. Check live
  RPM, disabled controls, and the bounded approval explanation
  without clipping. The app never approves
  its own macOS background item.

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

## Cold Launcher Settings Requests, 2026-10-01

- **Symptom:** The main-panel Settings button can open the launcher without
  showing Settings when its view has not mounted.
- **Cause:** A deferred notification can arrive before the view subscribes.
- **Invariant:** Use `ToolActionRouter.open(toolID:page:)`. It stores the
  matching tool-page request before opening or reusing the window.
  `onOpenToolPage` consumes it once on appearance or notification. Other
  tools must not consume the main request. System Care keeps General;
  Ruler Settings and Defaults keep their distinct AppKit controllers.
- **Check:** Compile the existing pending-request and native-route tests.
  Run them on CI. In the signed app, open Settings from cold and existing
  launcher states with other tools visible. Only the target context changes.
  Fix: `f1a191dc`. Report: `tmp/redesign/logs/w3-panel-main.md`.

## Launcher Settings Reuse

- **Symptom:** Clicking a launcher tool shows help only, or its settings differ
  from the tool window and require duplicate maintenance. A launch-only card
  repeats Open, or a short card grows an empty row-sized tail.
- **Cause:** The launcher owned a separate detail implementation. An expanding
  panel, local maximum-height frame, or trailing spacer stretched short cards.
- **Invariant:** Detail pages open on Settings and embed the same settings view
  used by the tool window, with How to Use as the adjacent page. Ruler reopens
  its existing AppKit panels instead of cloning them in SwiftUI. Mac Tweaks
  reuses its guarded preference rows and utility-task snapshots, not invented
  Window or Safety preferences. Enforced policies use neutral read-only text.
  Embedded Mac Tweaks uses `needsReset(selection, hasBackup:)`; a value at
  the system default must not hide a saved original or its reset action.
  Under the 2026-10-01 density rule, related action rows sit directly on the
  page. Cards group multiple rows of content. Main General groups Appearance
  with Windows and Launch with iCloud. Ruler has one direct native action
  row. Modified uses section titles with values and Reset on the same row.
  Marketplace puts its source-entry controls on the page and times, versions,
  counts, and status on the trailing side. Put help and provenance behind an
  info glyph or tooltip. Grouped cards use natural height, top alignment, and
  no final separator, height frame, or spacer that creates a false empty row.
- **Check:** Change one setting from each launcher detail, reopen its tool
  window, and confirm the same value and control surface are present. Review
  loading, error, restore, and advanced-review routes. In both appearances,
  require short cards to end at their final row, not their neighbor's height.

## Marketplace Update Stops A Tool Before Validation

- **Symptom:** A rejected update stops the running tool although its installed
  bundle is unchanged.
- **Cause:** The manager requested termination before download and artifact
  validation.
- **Invariant:** Keep every artifact guard in the installer. Request
  termination only after all checks pass, just before activation. Preserve
  the existing replacement rollback.
- **Check:** Run `testManagerTerminatesOnlyForValidatedActivation` on CI. Reject
  download, checksum, and signing-team failures without termination or bundle
  replacement. A valid update requests termination before replacement.

## Unrelated Defaults Writes Block Other Windows

- **Symptom:** Task Manager and applet pages pause while the launcher is open.
- **Cause:** Every defaults write increased the launcher's Modified revision.
  Its sidebar then read `SMAppService.mainApp.status` on the main thread.
  In signed `198055e4`, the wait profile contains 1,353 samples in this path,
  waiting for the service's synchronous XPC reply. Page and window-state
  writes can trigger the query even though no app preference changed.
- **Invariant:** Watch only registered preference keys with the existing
  `ToolSettingsPreferenceObserver`. Update the keys when Marketplace changes.
  Read Login Items status on a utility task, then publish Modified on the
  main actor. Cancel an obsolete result when the revision changes.
- **Check:** The actual observer fixture ignores page, window-state, and tray
  writes and accepts a real preference change. It and the cache mutation
  check are in `tmp/redesign/perf/w1-windows/check-costs.py`. After a signed
  install, replay Task Manager and applet pages with the launcher open, then
  verify Modified after a real preference or Login Items change.

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

## Missing Display Leaves The Titlebar Outside The Screen

- **Symptom:** A restored window has visible body content but an unreachable
  titlebar after its saved display is removed.
- **Cause:** The fallback accepted any 200 by 100 point overlap. It did not
  clamp the frame to a surviving screen. Zero overlap skipped restoration.
- **Invariant:** Select the surviving visible frame with greatest overlap,
  then use the existing clamp. With zero overlap, use the current window's
  screen. Keep the current fixed canvas unless it cannot physically fit.
  Restore before display. Add screen-change owners only for a reproduced
  stranded custom surface.
- **Check:** The actual restore path fails the old offscreen-titlebar case
  and passes negative coordinates, greatest overlap, zero overlap and a small
  display. Run `tmp/redesign/perf/w3-windows/check-restoration.py`. Signed
  unplug/replug, resolution and menu-bar-display checks remain.

## Early Plugin Requests And Launch Failures

- **Symptom:** A CLI plugin is unknown during startup, or an Open failure
  reaches only the log and leaves no visible recovery action.
- **Cause:** Receipt lookup ran before Marketplace restoration. The launch
  catch logged the error without publishing it to the launcher.
- **Invariant:** Keep built-in routes immediate. Plugin routes await the
  coalesced Marketplace restore, then check current enablement and receipt
  presence. Publish the actual launch error and tool ID to the existing
  router state. Keep main open on failure; close only on confirmed success
  and the close-main preference. Retry must repeat the execution guards.
- **Check:** `tmp/redesign/perf/w3-windows/check-routes.py` runs the actual
  router with non-GUI doubles. It covers early receipt readiness, disable
  during restore, a removed receipt, published failure and successful retry.
  Main provides a native alert with full tool/error details, Retry through
  open(toolID:), enabled Open Logs and Cancel. Its `a4e5f2fa` coalesces
  restoration and checks concurrent receipt publication. Signed recovery
  remains.

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
- **Invariant:** Every registered fixed workspace and content-sized applet
  restores position only. Keep the saved top-left edge and the current size.
  Restore once on native attachment, before display. Do not queue a later
  restoration pass or apply an old saved width and height.
- **Check:** The 2026-10-01 source check fails on the old policy for Cloud Sync,
  Logs, Input Devices, System Care, Diskman, NetToys, and Switch. The new policy
  passes all 14 saved identifiers and keeps the top-left edge and current size.
  `WindowAccessorTests` checks immediate attachment and the canvas registry.
  Signed reopen and late-frame checks remain with the orchestrator. Commands
  and timing limits are in `tmp/redesign/perf/w1-windows.md`.

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


## Dotted Preference Keys Do Not Notify KVO, 2026-09-30

- **Symptom:** A tool settings page did not observe a changed dotted key.
- **Cause:** UserDefaults KVO treats the key as a key path.
- **Invariant:** Observe UserDefaults changes, then compare snapshots of the
  watched literal keys. Notify only when a watched value changes. Remove the
  notification token on stop and deinitialization.
- **Check:** Hosted run `36705631910` passes the unchanged watched-key,
  same-value, unrelated-key, and stopped-observer regression.

## Retained Menu Tabs Keep Hidden Tasks Alive, 2026-10-01

- **Symptom:** Cached inactive tabs leave both tab tasks live. A height cache
  also leaves the panel at 600pt after content shrinks to 253pt or 133pt.
- **Cause:** A detached NSHostingView does not apply its replacement hidden
  environment until layout. Observed child changes can bypass a host-height
  cache's invalidation.
- **Invariant:** Deliver the hidden root through layout before detaching a
  retained tab host. Cache the visited host, then measure natural height from
  current content. Do not reuse an old height without a valid invalidation.
- **Check:** `testVisitedTabRetainsControlStateAndStopsHiddenWork` keeps the
  control value across visits, stops inactive and closed tasks, and resumes
  only the active tab. The fixed-region shrink and destination-height checks
  pass. Signed `198055e4` still fails the speed gates; rerun on the retention
  fixes before claiming the 100ms target. Evidence: `tmp/redesign/perf/w1-panels.md`.


## Menu Panels Use The Originating Display Ceiling, 2026-10-01

- **Symptom:** Long content on a secondary display uses the primary display's
  panel height. An explicit larger ceiling also shrinks to the primary limit.
- **Cause:** The shared shell clamps supplied height against NSScreen.main.
  Native presenters supply their ceiling only after the first host measurement.
- **Invariant:** Supply the status button's screen ceiling before host creation
  and measurement. Honor it directly. For Main MenuBarExtra, the existing
  height bridge reads the attached host window's screen on the main actor.
  Keep only a weak window reference. Natural height must still shrink.
- **Check:** The old source fails the explicit ceiling regression. The new
  source passes all initial height callbacks and the attached secondary-screen
  fallback without ordering or activating a window. Fixed regions still shrink
  to 253pt and 133pt. Commits: `b7e222d7`, `8801bfd9`, `0fa0407d`.
  Physical first-frame checks on both stacked displays remain with the
  orchestrator. Report: `tmp/redesign/logs/w3-perf-panels.md`.
