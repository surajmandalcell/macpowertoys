# Task Manager Troubleshooting

Task Manager was formerly System Monitor; code names still use
`SystemMonitor`. `DESIGN.md` owns every size, color, and type value. Entries
here keep the cause, the invariant, and the check.

## Window Shell And Fixed Geometry

- **Symptom:** The window restores as resizable, the title drifts from the
  traffic lights, or the sidebar paint ends early and the workspace paints
  over it near the bottom edge.
- **Cause:** Fixed sizing ran only after attachment, restored state included
  an old size, `contentLayoutRect` was mistaken for the SwiftUI content view,
  zoom was hidden, and the workspace background drew outside its layout
  bound. A first pixel regression compared two workspace pixels and passed
  falsely.
- **Invariant:** Declare the fixed canvas in the scene and root. Restore
  position only. Reapply the nonresizable policy to the actual content view
  after attachment and on every key change. Zoom stays visible and disabled.
  Clip each painted pane to its layout bound. The sidebar, its navigation
  groups, and its native backdrop share one width; the workspace never draws
  into that region.
- **Check:** Attempt resize and zoom after reopening. Compare the title and
  traffic-light centerlines. In an exact-build capture, sample sidebar pixels
  near the leading edge and just inside the divider at middle and lower rows;
  they must match. The first workspace pixel past the divider must differ.

## Pages, Fixed Regions, And Retention

- **Symptom:** Page changes pause, body cards start on a second inset, or
  search, headers, sidebars, and footers move with rows. Overview and Settings
  rebuild on return. A page switch also lays out hidden menu hosts.
- **Cause:** One outer page scroller; process and report rows sorted in
  `body`; profiles loaded during view creation; every sample invalidated the
  whole window. Each switch wrote an AppStorage value, which reached retained
  hosts.
- **Invariant:** Use the shared page header and one Task Manager gutter.
  Card pages scroll only the card stack. Processes keeps search and the table
  header fixed around lazy rows. Remote Stats keeps status fixed. System
  Report keeps search, actions, category title, and its own sidebar fixed.
  Load profiles and prepare large row sets on utility tasks. Keep page
  identity stable; do not animate page replacement. Scope sample observation
  below window and panel chrome. All value selectors use `OnePlusSelect`.
  Inherit the shared focus policy from the roots; never disable focus effects
  on single controls.
- **Invariant:** Use `OnePlusRetainedPage` only for Overview and Settings.
  Create each host on first visit. Keep selection outside content equality.
  Forward only the required environment keys. When hidden, keep the last
  content without calling its live builder, and deliver false visibility
  before detaching. Clear the hosted graph on dismantle.
- **Invariant:** Keep navigation in local state. Read the saved page for the
  first frame, accept external page requests, and save on hide or close.
  Panel persistence observes shell visibility in the tab strip.
- **Check:** Switch through all 13 routes within 100 ms. Scroll 1,000 process
  rows without dropped frames; fixed regions stay put. Run
  `python3 tmp/redesign/perf/perf-tm/check-window-selection.py`, then with
  `panel`: 20 switches make zero preference writes. `OnePlusRetainedPageTests`
  require zero rebuilds for unrelated selection and hidden samples. Close the
  window and panel; their sampling owners must stop.

## Menu Panel Retention And Height

- **Symptom:** Panel tab switches rebuild unchanged content. The panel clips,
  keeps a stale height, or Light appearance stays dark.
- **Cause:** A selection Binding is a dynamic property even inside an
  equality boundary. Views forced a dark scheme. The popover trusted an
  estimated height.
- **Invariant:** Retain the shared hosts and page states. Compare content by
  page, model identities, and remote profiles. Keep the selection binding in
  the tab strip; pass selection actions into content and Home tiles. Put
  visibility and sampling outside the equality boundary. Do not cache page
  height. Inherit app appearance on every surface. Measure the complete shell
  before presentation; the shared shell owns natural height and the 90%
  ceiling, and its final-height callback updates the panel without estimates
  or resize animation. Reset unsaved navigation before measurement.
- **Check:** Run `python3 tmp/redesign/perf/perf-tm/check-retention.py`: 20
  selection changes rebuild current content zero times. Run
  `testTaskManagerMenuMeasuresTabsAndAsyncProfiles` on hosted CI. Signed
  timing (tabs within 100 ms) and complete frames remain open.

## Sampling Lifecycle

- **Symptom:** Monitoring continues after close, ignores a menu item's
  interval, leaves status items after disablement, or the window shows
  pending readings when opened behind another app.
- **Cause:** Detailed and menu sampling had separate lifecycles; menu-only
  wakes sampled every metric; settings and status items were written without
  a change check.
- **Invariant:** One sampler and exactly one utility-queue timer while a
  visible surface needs data. The window samples only the visible page's
  metrics; Processes, Remote, and About do not own the detailed timer. The
  panel has its own owner. In menu-only mode the timer wakes for the earliest
  due enabled metric. The first deadline is now; the Sendable callback
  captures immutable settings. Reset the sampler on its utility queue.
- **Invariant:** A covered or off-Space window stops sampling and keeps its
  last snapshot. Closed and minimized windows stop. Disabled tool, or closed
  window with menu off, means zero timers and zero status items. Increment a
  generation before stop; a late sample must not change state. Teardown is
  part of every close and disable path.
- **Invariant:** CPU and network need a prior counter sample. Compute rates
  over monotonic elapsed time. Reset rate baselines on every wake and keep
  rates until a fresh valid pair exists. Keep at most 120 timestamped
  snapshots; menu-only updates add no chart history. Live UI updates at most
  4 times per second.
- **Invariant:** Compare normalized settings before writing UserDefaults or
  restarting the timer. Compare the full rendered title, image, tooltip,
  accessibility label, and length before writing a status item.
- **Check:** Timer counts are 0, 1, 1, 1 for no surface, each surface, and
  both. Zero timers and items when the menu is on with no metric. Disable
  during a sample; the generation guard rejects the result. Run the startup
  and pending-Battery cases in `SystemMonitorWindowAuditTests` and
  `OnePlusLiveUpdatesTests`. Cover the window with a full-screen app; CPU
  stays near 0%.

## Menu-Bar Metrics

- **Symptom:** Values shift neighboring items, readings look current after
  the sampler fails, attachment glyphs stay black in Dark, or a cadence or
  placement change resets values to `...` and moves other items.
- **Cause:** Content-width items with proportional digits, native title
  centering, untinted attachments, a snapshot time that replaced a retained
  metric's read time, and reconfiguration that cleared every cached value
  and status item.
- **Invariant:** CPU, memory, GPU, disk, network, battery, and thermal each
  choose Off, Combined, or Separate. Store icon, style, interval, and format
  per item in a versioned schema; migrate old settings. Each separate item
  has a stable autosave name. Removing the last metric turns the menu off;
  an enabled menu with an empty saved selection restores RAM.
- **Invariant:** Defaults: CPU, memory, network 10 s; GPU 5 s; disk,
  battery, thermal 30 s. Menu-only disk polls no faster than 15 s, battery
  and thermal no faster than 10 s. An unavailable metric keeps no retry
  timer; retry on wake, a system event, or refresh.
- **Invariant:** Reserve bounded widths and use monospaced digits. Fill the
  final title slot. Resolve attachment tint on each draw. Keep each metric's
  own timestamp. One deadline marks readings stale after three intervals
  (minimum three seconds); help and AX expose it. Keep the last value across
  interval and placement changes; reuse unaffected status items. Pending or
  absent readings are `...` or a dash. Use the Task Manager glyph when only
  one metric shows.
- **Check:** `SystemMonitorStatusTests` covers retention, recovery, width,
  tint, and item updates. Run the menu-value retention test across an
  interval change, an empty delta, and Combined to Separate. Repeat crowded
  menu-bar and stale-expiry checks on the signed build.

## Processes

- **Symptom:** PIDs hide behind a limit, headers do not sort or show
  direction, icons are generic, a selected process looks frozen, or the
  protected-process fallback hangs.
- **Cause:** A capped list and sort picker, a header that drew only its
  label, symbols chosen from status instead of identity, no sample time in
  details, and a `ps` read to EOF with no deadline.
- **Invariant:** Show every sampled PID in a lazy stack. Headers reverse
  sort on repeat click, draw the native sort indicator, and persist column
  and direction. Unavailable readings sort last. Search covers name, PID,
  and path. Real bundle icons are prepared off main and cached by bundle
  path; command-line executables use the terminal glyph; unknown or pending
  icons leave the slot blank. Clicks select; Return, double-click, or Inspect
  opens details. Protected rows have no Quit. Quit needs a verified
  start-time identity.
- **Invariant:** Details resolve from the newest PID-and-start-time sample
  and show its time. Explain virtual address space. Offer Copy Path, parent
  and child context, and a persisted hierarchy that keeps every PID. Query
  endpoints with a selected-PID-only `lsof` every 30 s; cancel on selection
  or page change. The `ps` fallback uses the cancellable runner with a 5 s
  deadline and a 2 MB cap; keep libproc rows if it fails.
- **Check:** Scroll past row 25, sort every header both ways, relaunch, and
  confirm the sort. Inspect a normal and a protected process. Confirm no
  port subprocess runs with no selection.

## Overview, Charts, And Units

- **Symptom:** Charts fall below the time axis, endpoint labels miss grid
  lines, disk ticks wrap, units differ from System Care, captions are empty,
  or Overview edges and guides misalign.
- **Cause:** A forced plot height in a smaller host, a spacer stack for
  scale labels, per-tick units, the RAM formatter used for disk, and
  unconditional hero captions.
- **Invariant:** The requested height controls the Canvas and scale column;
  clip the plot. Time labels and legends stay outside. All detail scales use
  the shared grid fractions and pixel rounding; reserve 6 pt above and below
  the plot for endpoint labels. Disk and network ticks are numeric MB/s with
  the unit shown once above the plot. Disk values use decimal
  `TrayPopoverLayout.diskBytes` everywhere (window, panel, remote, status
  items); RAM stays binary; System Report keeps `system_profiler` values.
  Omit empty hero captions. Use the chart grid token with whole-point rules.
  Overview shows CPU, GPU, memory, disk, network, thermal, battery, and load,
  with no repeated history-card section. Load shows the 1-minute value.
  Missing RAM stays absent. Prepare chart series and labels outside
  rendering. Save exports atomically on a utility task and show errors. CPU
  shows System history as the secondary series. Label network rates "All
  interfaces"; take connection identity from the NetToys default route and
  show an address only when its interface matches that route.
- **Open:** System Report Copy and Export need bordered compact icon
  controls. OnePlusUI must add an icon trigger to `OnePlusMenuButton`; then
  both exports route through it and `OnePlusPopupMenu`.
- **Check:** Run `testHistoryChartsStayInsideTheirRequestedPlotHeight`,
  `testDiskByteFormatterUsesDecimalUnits`, and `SystemMonitorWindowAuditTests`
  on hosted CI. Run `python3 tmp/redesign/checks/30r11-tm.py` and
  `tmp/redesign/logs/30r11-panels-check.py`. Raise the hosted CPU height cap
  from 410 pt to 422 pt for the endpoint reserve. Compare Overview, Battery,
  Disk, and CPU in both signed appearances.

## Chart Dither Requests A Huge Bitmap

- **Symptom:** The system log shows `CGBitmapContextInfoCreate: unable to
  allocate 4611686016279904256 bytes` on Task Manager pages.
- **Cause:** The dither pattern was filled under a zero-area chart clip, for
  example a series that stays at its lowest value.
- **Invariant:** Skip the dither when the area bounds are empty or not finite.
  OnePlusUI 1.0.5 has the same guard in `OnePlusPlot`.
- **Check:** Run `SystemMonitorTests.testHistoryChartSkipsDitherForZeroAreaSeries`.
  Open Disk, Battery, and Sensors, then count the log lines with this message.
  The count is 0.

## Compact Panel Pages

- **Symptom:** Compact metrics lose digits, Memory shrinks beside capacity,
  details repeat hero facts, cards use the wrong inset, or plots are too tall.
- **Cause:** Precise decimals in narrow columns, a caption that competed with
  its metric, detail rows that copied hero values, and old card defaults.
- **Invariant:** Compact values use at most one decimal and separate units;
  help keeps full byte counts. Memory capacity uses a separate line in its
  tile. CPU, GPU, and Memory keep equal metric size and the lower history
  band. Disk keeps Read/Write; Battery keeps cycles and power. Omit an empty
  details card. Card headings and rows use the shared 16 pt token in both
  densities; detail-chart labels keep 12 pt. Disk pairs share one baseline.
  Reorder help sits on its handle. Compact plots request 64 pt. Offline
  remote hosts keep CPU, RAM, and network dashes and no empty storage row.
  `OnePlusMenuItemCard` supplies glyphs and offline readings; never restyle it
  locally. Battery reserves its four detail rows with dashes until a completed
  unavailable sample.
- **Check:** Run `testTaskManagerMenuMeasuresTabsAndAsyncProfiles` on hosted
  CI. Review Home, CPU, Disk, Network, and Sensors in both signed appearances.

## Fan Stays Forced After The App Dies

- **Symptom:** Cool or Max stayed forced after a crash, force quit, or SIGKILL.
  A failed Cool revert still showed "Auto in 10 minutes".
- **Cause:** The helper did not track clients, and the in-process revert
  ignored its result.
- **Invariant:** The helper writes Auto when the connection that set a manual
  mode ends (`FanManualLease`). The app holds that connection only while the
  mode is manual. A failed revert retries 3 times, then shows an error. The
  helper-commit poll backs off. A disabled Kwake refuses external actions.
- **Check:** `FanControlTests` lease test. Then, with the new helper approved,
  set Max, send SIGKILL, and confirm Auto returns on real hardware.

## Fan

- **Symptom:** Quit blocks on Fan, Fan polls after its panel closes, or Fan
  loses Cool and Max without helper access.
- **Cause:** Restore waited with a synchronous queue and reported no failure;
  an appearance subscription stayed active in a hidden layout; the segmented
  control was replaced by one button.
- **Invariant:** Quit awaits `restoreAutomaticOnExit()` (async throws). It
  queues Auto after selected presets, blocks new selections, keeps ownership
  until success, and propagates failure so termination can cancel.
- **Invariant:** The signed daemon accepts only Auto, Cool, or Max from the
  signed app, validates SMC keys and the hardware maximum, and restores Auto
  on a failed write. macOS owns Background App Activity approval; never
  approve it on the owner's desktop. Check the running daemon's source stamp
  before using a new XPC method. The in-app SMC reader is read-only, runs
  only while a fan view owns the poller, and bounds indices and lengths.
  Fan commands drain output with a cap and hard-kill after a short grace.
- **Invariant:** Fan shows on main Home (below Awake, when Task Manager is
  enabled), Task Manager Home, and Sensors, each with its own visibility
  owner. Fan starts and stops its service from `onePlusIsVisible`; hiding
  dismisses setup. It always shows Auto, Cool, and Max via
  `isChoiceEnabled`. A warning glyph owns helper setup and Restore Auto.
  Fan text is prepared off main, equal results do not publish, and
  publications stay at least 250 ms apart.
- **Check:** `FanControlTests` covers ordering, awaited restore, failure, and
  retry. Run `testFanViewStopsPollingWhileItsLayoutStaysMounted`. Test helper
  approval, Max, and Auto on an isolated Mac.

## Remote Stats

- **Symptom:** Cards stay Offline while the window samples, a saved host
  disappears, every sample opens a new SSH connection, Return does nothing,
  Open SSH opens an idle shell, or error text grows a card.
- **Cause:** Reading state belonged to one page; a child copied an empty
  profile array; no control socket; no submit action; the SSH command went to
  the clipboard; an inline error row added height.
- **Invariant:** Name the page Remote Stats. Remote selects Linux, macOS, or
  Windows and samples only after Connect. Default refresh is 30 s; Manual,
  5, 10, 30, 60, 120, and 300 s are offered. Manual takes the baseline pair
  for rates, then stops. Return starts the same validated connection as
  Connect. Blank user or port preserves SSH config.
- **Invariant:** Disconnect and the last owner's close cancel work. Polling
  ownership follows "Remote Stats Polling" below.
- **Invariant:** All surfaces observe `SystemMonitorRemoteSessions` by stable
  profile ID. Seed window and page state from the shared profile snapshot.
  Failed or disconnected sessions clear readings and show the reason in
  header help and AX labels, so bounds stay fixed. Reject empty numeric
  fields, malformed loads, and impossible disk values. Show numeric zero RAM.
- **Invariant:** Reuse one private OpenSSH control socket per host session,
  at a short `/tmp/mpt-remote-UUID/ssh` path in a mode-0700 directory. Keep
  BatchMode and host validation. Cancel and await the in-flight sample before
  master exit. One session never closes another's master.
- **Invariant:** Open SSH sends a private executable command file to
  Terminal after the user presses it. The command keeps the alias, user, and
  port, and removes its temporary files before SSH starts. Host actions share
  one horizontal row.
- **Check:** `SystemMonitorRemoteTests` on CI. Run
  `python3 tmp/redesign/logs/remote-r11-check.py`. `ssh -G` resolves the
  control options. On a live host: Return connects, change refresh while
  connected, Manual stops after the baseline pair, the second sample reuses
  the master, and no socket or master remains after Disconnect.

## Remote Stats Polling

- **Symptom:** Remote Stats polled for the whole window lifetime.
- **Cause:** A window-close event owned the polling.
- **Invariant:** Each host card owns its polling from appear to disappear.
- **Check:** On the signed build, switch pages. A connected host must survive a
  Remote to Overview switch.

## Scope

- **Symptom:** Monitor mixes clocks, Bluetooth, or plugins with metrics.
- **Invariant:** Keep monitor metrics and MacPowerToys plugins separate. The
  sidebar starts Overview, Processes, CPU and has no World Clocks,
  Bluetooth, Plugins, or Menu Bar page.
- **Check:** Inspect the sidebar order. The Marketplace still installs tools.
