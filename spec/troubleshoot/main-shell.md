# Main Shell Troubleshooting

`DESIGN.md` owns every size, color, and type value. Entries here keep the
cause, the invariant, and the check.

## Background Opens Keep The Owner's Focus

The owner plays games. A background route (`open -g`, a diagnostic URL, a
capture) must never activate the app or take key focus.

- **Symptom:** Background Main, applet, page, and panel routes took focus:
  on cold scene creation, on reuse of a warm page, after lock and unlock on
  another Space, and while the app was inactive.
- **Cause:** SwiftUI scene matching and a mounted `onOpenURL` receiver opened
  windows outside the router's activation guard. The presenter called
  `openWindow` for cold windows and deminiaturized before checking intent.
  Background presentation used `orderFrontRegardless` on any Space and
  while inactive. A scene condition that held only the tool ID also matched
  panel diagnostic URLs.
- **Invariant (routing):** Every scene disables automatic external-event
  matching. AppDelegate is the only URL receiver and sends every URL through
  `DeepLinkHandler` and `ToolActionRouter` once, with background intent. No
  window registers an `onOpenURL` fallback. Page requests are stored before
  presentation. Explicit launcher, menu, default launch, and Dock reopen
  actions keep activation. For an AppKit sub-app such as Ruler, close the
  main window before synchronous window creation.
- **Invariant (creation):** Background opens create a native window with the
  same scene content, or remount a retained one. They never deminiaturize,
  make key, activate, or call `openWindow`. Cold SwiftUI scenes keep their own
  controller, host, and style; force root layout and fix hidden geometry
  before ordering. Fixed roots use their registered canvas. Applets use the
  mounted `WindowAccessor` body size, because hosting fitting sizes can hold
  a stale titlebar inset. Keep the top-left point and skip unchanged frames.
  Background Pick and Extract open applets without starting selectors. The
  sheet routes (Cloud Sync New transfer, Switch Add account, folder choice)
  and startup or launch-error alerts wait for window focus.
- **Invariant (ordering):** While the app is inactive, background routes use
  `orderBack` on the current Space. A window not on the active Space updates
  content and page state but is not ordered. This applies to all 13 scene
  roots, `BackgroundToolWindow`, Ruler, Ruler Settings, diagnostic panels,
  Portman, and the separate panels. Diagnostic panels skip the dependency's
  front-ordering show method; normal menu clicks keep it.
- **Invariant (closed scenes):** Observe real `willClose` notifications with
  weak window references. Never reuse a closed scene shell or replace its
  controller. Explicit reopens use SwiftUI; background reopens use the native
  factory, which mounts the common root and sizes it before back ordering. A
  new root attachment clears the close record. Remount only controllers that
  `BackgroundToolWindow` owns. Save the frame before close unmounts content.
- **Invariant (panels):** Panel presentation does not need an
  `OpenWindowAction`. The background fallback hosts the production panel at
  its measured natural height, with the requested tab chosen first. Pass the
  resize callback into Task Manager, whose inner modifier overrides an outer
  one.
- **Diagnostics:** `diagnostics/native-close/<id>` calls
  [performClose](https://developer.apple.com/documentation/appkit/nswindow/performclose(_:))
  on the visible or minimized scene window without activation, ordering, or
  sheet changes. The older close-window route keeps its close-all behavior.
  The activation log records event subtype, route and foreground app,
  activation policy, three seconds of ordering calls, and 14 stack frames on
  a size-limited background queue.
- **Check:** `python3 tmp/redesign/checks/no-activation/check.py` (with
  `--inactive-before` and `--off-space-before` to prove the old cases fail)
  must show zero front, key, activation, or scene calls for every background
  route, inactive or off-Space. `python3 tmp/redesign/perf/r11-tm-route-check.py`
  passes native and diagnostic cases. Guarded `BackgroundToolWindowTests`
  pass. Hidden fixtures do not prove signed behavior.
- **Open:** On the signed build, replay native close and reopen for all 13
  IDs, lock/unlock, full-screen, both URL schemes, Raycast, and captures, with
  the foreground app unchanged after every background request. The
  activation requester in the inactive case is still unproven.
- **Open:** The route `open/main/settings-about` brought the app to the front
  once during a capture run. The cause is not found. Suspects: the native
  Menu on the About page and the update checker.
- **Platform limits:** Apple does not document
  [orderFrontRegardless](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless())
  as an activation cause.
  [orderBack](https://developer.apple.com/documentation/appkit/nswindow/orderback(_:))
  preserves key and main state.
  [isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace)
  has a defined meaning for hidden windows.
  [openWindow](https://developer.apple.com/documentation/swiftui/openwindowaction)
  always orders front. See also
  [scene routing](https://developer.apple.com/documentation/swiftui/scene/handlesexternalevents(matching:)).

## Main Window

### Sidebar Last Row Hidden Behind Fixed Settings Group

- **Symptom:** The last tool row was half hidden behind Settings and Exit.
- **Cause:** `ToolSidebarView` drew Settings and Exit as a fixed group over
  the end of the scroll view, and the list had no end padding.
- **Invariant (v15):** Settings and Exit are the `bottom` group of
  `OnePlusLinearSidebar`, a sibling below the scroll view, never an overlay.
  The scroll view ends above them, so no tool row can sit behind them. Both
  rows stay visible while searching. Shortcuts and keyboard order are
  unchanged.
- **Check:** The offscreen render in `LauncherGridTests` shows every tool row
  above Settings. On the installed build, capture the main window at rest
  and scrolled to the end.

### Settings Structure

- **Invariant:** The fixed canvas comes from `OnePlusWindowCanvas.mainWindow`
  through `appTool("main")` until a OnePlusUI tag owns it. It sets
  `isApplet` only to center the traffic lights on C = 22, the center of the
  44 pt v15 toolbar. `MainWindowShell` draws no texture. The sidebar groups
  tools with `MainCatalog.groups`; Command-2 to Command-9 use
  `MainCatalog.shortcutTools`. `OnePlusLinearPaneToolbar` sits outside page
  content and owns Command-[ and Command-]; never add a second shortcut for
  them. The All, Enabled, and Favorites tabs (`MainCatalogTabs`) and the
  Settings tabs sit in its trailing slot. `MainPageHistory` records every
  page change except its own traversal. A `manual/<id>` route stores a
  one-shot request that scrolls the tool page to How to use.
- **Check:** `LauncherGridTests` renders All tools, Ruler, and Settings in
  both appearances; compare with `docs/design/v15/main-window-*.png` at the
  same scale. It also checks that the last tab ends on the 24 pt content
  inset and that selection does not move the tabs. `MainCatalogTests` covers
  groups, shortcut order, and history.

### Page IDs, Retention, And Updates

- **Invariant:** Store validated page and tab IDs. Removed or disabled saved
  tools fall back to All tools. Explicit Settings and manual requests
  override saved tabs; plain Settings restores its tab. `main/settings-general`
  always opens General. Search stays in memory. Saved pages never open tool
  windows. Retain only the visited Task Manager page with
  `OnePlusRetainedPage`; the retained host disables safe-area regions. Keep
  sidebar selection in local state and save on hide or disappearance.
- **Invariant:** About and menu actions share bundle metadata and one manual
  URLSession update checker. Compare versions off main, reject invalid
  metadata and foreign release URLs, and show checking, current, available,
  and retryable error states. Keep the app menu-bar switch separate from
  macOS Menu Bar permission. Closing windows leaves enabled services
  running; Quit stops them.
- **Check:** Run `tmp/redesign/perf/perf-pages/check-main-selection.py`: 20
  switches make zero preference writes. The resolver matrix covers valid
  tabs, fallback, overrides, and manual routes; a reversed version
  comparison fails.

### Manual Route Does Not Scroll

- **Symptom:** A manual route opened the tool page without scrolling to
  How to use.
- **Cause:** All tool pages shared one view identity, so a tool page kept the
  scroll offset of the previous tool.
- **Invariant:** Each tool page has its own identity. It starts at the top,
  and the manual route can scroll to How to use.
- **Check:** Run `MainCatalogTests`. Capture a tool page, then capture its
  manual route. The manual capture shows How to use.

### Tool Enablement

- **Symptom:** A disabled tool still opens, starts at launch, or stays in the
  tray. Embedded pages showed two enable switches.
- **Invariant:** `SettingsManager` owns the one disabled-ID set; missing IDs
  are enabled. Routing, shortcuts, launch restoration, background services,
  and tray tabs read it. Disabled tools stay selectable only so they can be
  re-enabled. Overview rows carry an unlabeled switch and a chevron; Open
  stays in the context menu and Command-O. A tool page puts the switch and
  `Open <Tool>` side by side in its header row. The shared header owns
  enablement on embedded pages. A switch change while the tool starts or
  stops is ignored (`MainToolEnablement`).
- **Check:** Disable every tool from All tools and from its page. Open,
  shortcuts, deep links, CLI, Awake, Cloud Sync, and the tray all follow.

### Launcher Settings Reuse

- **Invariant:** Tool pages embed the same settings view as the tool window.
  Ruler reopens its AppKit panels. Mac Tweaks reuses its guarded rows and
  uses `needsReset(selection, hasBackup:)`, so a value at the default keeps a
  saved original and its reset. Related actions sit directly on the page;
  cards group several rows. Metadata sits on the trailing side; help and
  provenance go behind an info glyph. Cards keep natural height with no final
  separator, height frame, or spacer.
- **Invariant:** `ToolActionRouter.open(toolID:page:)` stores the page
  request before opening the window; `onOpenToolPage` consumes it once. Other
  tools never consume the main request.
- **Check:** Change one setting from each tool page and confirm the tool
  window shows it. Open Settings from cold and existing launcher states.

### Main Modified Page Removed

- **Invariant:** The owner removed the main Modified page and its logic.
  Per-tool reset stays inside the tool, such as the Mac Tweaks Modified page.
  Do not reintroduce a cross-tool preference registry or revision counter.
- **Check:** `rg -n "SettingsRegistry|MainModifiedView|modifiedRevision"
  powertoys powertoysTests` returns nothing. `main/modified` resolves to no
  page.

### Heavy Launcher Settings First Frame

- **Invariant:** Show a cancellable loading shell before building a heavy
  settings tree. Do not preload on hover or retain destination views after selection
  changes.
- **Check:** Time sidebar activation to the first accessible frame in the
  signed app. Switching away cancels the view task; owners do not grow.

## Startup And Quit

### Startup Readiness And Saved Data Recovery

- **Symptom:** A requested tool waits for archives, or a failed ModelContainer
  open terminates the app.
- **Invariant:** Migrate preferences in App init before scene commands cache
  settings owners, with no file work. Publish route and status-item readiness
  before archive reads and store migration. Open storage off main and share
  concurrent opens. Only Cloud Sync needs the container. On failure show the
  real error with Retry and Reveal Data Folder. Keep files and inputs; never
  reset or switch to temporary storage after a normal-run failure.
- **Check:** Run `tmp/redesign/checks/app-lifecycle/store-check.py` and
  `profile-startup.py`. Run `AppLifecycleTests` on hosted CI.

### Bounded Quit Keeps Recovery Available

- **Invariant:** Use `terminateLater`. Await Fan Auto and the throwing Color
  Picker and Cloud Sync drains. Logs flush but never block quit. Deadlines:
  20 s Fan, 10 s Color Picker, 30 s Cloud Sync. A deadline cancels its task
  and the quit, then shows Retry and Keep Open (see "Quit Refused With A
  Hidden Alert" for when it may show). Retain unfinished work for Retry.
  Save paused transfer snapshots before engine teardown. Never force exit
  from a timeout. Late startup work never resumes jobs after shutdown.
- **Check:** `tmp/redesign/checks/app-lifecycle/shutdown-check.py` (and
  `--mutate`). On the signed app check Fan Auto, save failure, early quit,
  Retry and Keep Open, and continuous-job resume.

### Quit Refused With A Hidden Alert

- **Symptom:** Quit showed an alert the owner never saw. The app stayed half
  shut down and had to be killed.
- **Cause:** The RSync quit stage threw when an earlier RSync shutdown was still
  running. The alert opened as a hidden modal while the app was in the
  background.
- **Invariant:** Logs never block quit. Logout, restart, and shutdown always
  finish. The alert shows only for a user quit while the app is active and a
  user-data stage (fan restore, Color Picker save, RSync save) fails. A
  refused quit in the background posts a notification or shows the alert at the
  next activation. It never activates the app. Dev Sync stop is bounded at 10
  seconds.
- **Check:** `AppLifecycleTests` quit decision test. Then quit an idle app and
  confirm the rclone marker file is removed.

### Two Copies At Launch

- **Symptom:** Two copies started together and both quit. A second copy started
  work before it quit.
- **Cause:** The instance check counted later copies as owners and ran after
  startup work.
- **Invariant:** Only the earlier copy (launch date, then lower pid) survives. A
  losing copy starts no service.
- **Check:** Start two copies at once. One stays, and the other quits without
  starting any service.

### Command-Q Window Routing

- **Invariant:** Replace only the app termination command. In a known
  sub-app, close every visible window in that tool scope through
  `performClose`. On the launcher, an unknown window, or no window, require
  two Command-Q presses within two seconds and show `Press ⌘Q again to quit`.
  Status-item Quit, Dock Quit, logout, and Command-W keep native paths.
  Resolve an unidentified sheet through its parent chain and end it first.
  Ruler closes every ruler through `RulerManager`, plus Settings and
  Defaults, and stops the mouse timer.
- **Check:** Command-Q in each sub-app closes only that tool. On the
  launcher, one press keeps the app, a second within two seconds quits.

### Background Launch Takes Focus

- **Symptom:** `open -g` or a login-item start brought MacPowerToys to the
  front and opened Main after about 4 s.
- **Cause:** macOS marks background starts as default launches too, so the
  app opened Main with activation.
- **Invariant:** Main opens at launch only when the app is active, or when the
  launch activation arrives within 3 s. A background launch opens nothing and
  calls no activating API.
- **Check:** Run
  `AppDelegateTests.testBackgroundDefaultLaunchNeverActivatesOrOrdersMainFront`.
  After a background start, read the frontmost app at 2, 5, and 10 s. It must
  not be MacPowerToys.

### Early Plugin Requests And Launch Failures

- **Invariant:** Built-in routes are immediate. Plugin routes await the
  coalesced Marketplace restore, then check enablement and receipt. Publish
  the real launch error to router state; Main shows a native alert with
  Retry through `open(toolID:)`, Open Logs, and Cancel. Close main only on
  confirmed success. Retry repeats every guard.
- **Check:** `tmp/redesign/perf/w3-windows/check-routes.py`.

### Marketplace Update Stops A Tool Before Validation

- **Invariant:** Request termination only after every artifact check
  passes, just before activation. Keep the replacement rollback.
- **Check:** `testManagerTerminatesOnlyForValidatedActivation`.

## Window State

### Window State Saves

- **Symptom:** A UserDefaults write on every move. Bad saved frames after a
  game changed the display mode.
- **Cause:** One save per move and resize event, including system moves after a
  display change.
- **Invariant:** Save 0.5 seconds after movement stops and on close. Make no
  saves for 2 seconds after a screen-parameter change.
- **Check:** `WindowStateManagerTests`.

### Restoration

- **Invariant:** Every fixed workspace and content-sized applet restores
  position only: the saved top-left edge with the current size, once on
  native attachment, before display. Never queue a later pass. With a
  missing display, choose the surviving visible frame with greatest overlap,
  then clamp; with zero overlap use the window's current screen. Keep
  automatic scene restoration disabled. Never use private window-server APIs
  to force a Space; exact Space placement is unsupported.
- **Check:** `WindowAccessorTests`. Run
  `tmp/redesign/perf/w3-windows/check-restoration.py` (negative coordinates,
  overlap, zero overlap, small display). Signed unplug and replug remain.

### Dotted Preference Keys Do Not Notify KVO

- **Invariant:** Observe UserDefaults changes, then compare snapshots of the
  watched literal keys. Notify only on a real change. Remove the token on
  stop and deinit.
- **Check:** The watched-key regression covers same value, unrelated key,
  and stopped observer.

### Dock Icon Optical Sizing

- **Invariant:** Keep the base `AppIcon` on AppKit's reset path. Render
  applet assets once per asset and appearance in a centered 396/512 inset.
  Skip assignment when asset and appearance are unchanged.
- **Check:** Unit-test the inset, cache identity, and suppression. Compare
  Dock sizes in both appearances on the signed build.

References: [suppressed launch](https://developer.apple.com/documentation/swiftui/scenelaunchbehavior/suppressed),
[AppKit state restoration](https://developer.apple.com/documentation/appkit/restoring-your-app-s-state-with-appkit).

## Memory After Close

### Closed Windows Release Their Content

- **Symptom:** All windows were closed, yet the process kept hundreds of MB
  of view graphs and hosting controllers.
- **Cause:** SwiftUI scenes keep root state after close. Retained native
  windows keep their hosting controller.
- **Invariant:** Build each scene through the lazy `OnePlusWindowContent`
  closure; native close unmounts the tool subtree and keeps native size. Call
  `onePlusPrepareForOpening` before ordering a cached window.
  `BackgroundToolWindow` releases its controller on close and rebuilds before
  any front ordering. Minimize and occlusion keep content. Glyph rasters stay
  in the bounded `ToolGlyph` cache.
- **Check:** `OnePlusWindowContentTests` and `BackgroundToolWindowTests`.
- **Open:** Signed full route matrix, close all, wait 30 s; footprint under
  250 MB with fast reopen.

### Closed Menu Panels Keep Memory And Work

- **Symptom:** Closed menu panels kept their view trees and process lists for
  the whole session. Menu metrics sampled while the menu bar was hidden.
- **Cause:** Presenters and controllers held the outer hosting controller. The
  sampling timer had no visibility check.
- **Invariant:** On close, sampling stops at once. `MenuPanelRelease` frees
  the Portman and separate tool panel roots after 60 seconds, and a reopen
  cancels that. The combined panel keeps its host (see menu-metrics-fan.md,
  Sampling Lifecycle). Status
  items whose window is not visible are not sampled or redrawn. A panel shown
  while the app is inactive arms its dismissal monitors and closes on the next
  outside click or Space change.
- **Check:** A separate panel reopen within 60 seconds is warm. In a full-screen Space, the
  System Monitor timer owner count is 0.

### Retained Menu Tabs Stop Hidden Work

- **Invariant:** Deliver the hidden root through layout before detaching a
  retained tab host. Measure natural height from current content; never
  reuse an old height without a valid invalidation.
- **Check:** `testVisitedTabRetainsControlStateAndStopsHiddenWork`.

## Menu-Bar Panels

### Presentation And Radius

- **Invariant:** Every status item uses `OnePlusMenuPresenter` with one
  retained borderless nonactivating `NSPanel`, clear and nonopaque.
  `OnePlusMenuPanel` clips fill and its inset border to the panel radius;
  AppKit derives the shadow from that outline, so never draw another. Keep
  natural height, the originating display's ceiling, and the top edge while
  resizing. Supply the status button's screen ceiling before host creation.
  Reuse hosts on warm open. Left click toggles; native context menus stay in
  AppDelegate. Outside clicks and Escape dismiss. Child popups and sheets
  stay inside the panel.
- **Check:** `OnePlusMenuRadiusTests` and `OnePlusMenuSizingTests`.
- **Open:** Signed native shadows, all panel entry paths, both displays, and
  warm open within 100 ms.

### Layout And Tabs

- **Invariant:** The combined panel has no top bar. Its footer leads with
  the icon tabs (Home first; tool tabs reorder through Move Left and Move
  Right) and ends with the gear and Open App. Quit lives in the status
  item's right-click menu. Home is the bento, the Fan and Awake card, three
  top processes, then the Pick Color, Extract Text, and Ruler action bar.
  The body is the only scroller: `MainPanelBodyLayout` gives it its natural
  height up to the ceiling minus the shell chrome, and the hosts resize the
  panel from `onGeometryChange`. Complex tabs default to
  RSync UI and Input Devices. App-only tools such as Event
  Viewer never appear. Order and selection persist. Every tab gets the
  shared body width before measuring its natural height. Empty states are
  small cards; omit a separate empty transfer card when remote cards already
  say so. Tabs hold operational state, not settings forms; Input Devices may
  reuse its full controls. Identity colors mark key data only; chrome stays
  neutral; no large tool-colored fills. The menu-extra label is 14 pt.
- **Invariant:** Keep prepared transfer, network, cleanup, account, and
  process state at the panel root. Read files and format rows off main. Mount
  only the selected tab. No tab animation or new identity on switch.
  Sampling checks native panel visibility.
- **Check:** Exercise short and overflowing tab sets, reorder, relaunch.
  Review every tab in both appearances.

### Placement

- **Invariant:** Cloud Sync, Awake, Color Picker, Text Extractor, and Input
  Devices each expose None, Combined, and Separate. A tool uses at most one
  placement. Keep legacy separate choices, the Cloud Sync and Awake combined
  defaults, and stable autosave names.
- **Check:** All three modes for all five tools; None never changes
  enablement.

### Tab Content

- **Invariant:** Cloud Sync shows remotes with
  their latest transfer state and time on one row, matched by exact remote
  name, plus New Transfer. Switch loads usage only on request and shows one
  refresh icon and one unloaded-limit warning. Input Devices shows devices,
  batteries, and profile values before controls.
- **Check:** Run the remote-activity regression. Check unloaded usage.

### Fan And Awake Rows

- **Invariant:** Only main Home shows `FanControlView`, with its own
  visibility owner; other pages omit Fan.
  Fan uses the shared linear control row with the RPM as its status.
  When control is unavailable, a warning glyph opens the built-in helper
  approval flow; no package or Terminal command. The app never approves its
  own background item.
- **Check:** Inspect main Home at production width in both
  appearances, with live RPM and disabled controls.

## Tool Glyphs And Status Image Size

- **Invariant:** `ToolGlyph` owns 12 unique glyphs drawn from each tool's own
  icon. Asset glyphs such as `EventViewerGlyph` are marked
  `ToolGlyph.isAsset` and drawn through `assetImage` or `ToolGlyphImage`,
  never `Image(systemName:)`. Portman uses the original `PortmanStatusGlyph`,
  copied at 14 pt as a template, without normalization. `StatusItemIcon`
  caches other templates on a 14 pt canvas with an 11.2 pt ink span,
  rasterizing SF images once at 4x.
- **Check:** `ToolGlyphTests`, including exact Portman pixels at 1x, 2x, 4x.
  After install, capture only the menu bar with `screencapture -R`.
