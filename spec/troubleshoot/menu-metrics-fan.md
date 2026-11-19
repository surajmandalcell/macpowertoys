# Menu Metrics And Fan Troubleshooting

The Task Manager tool was removed on 2026-11-16. What stays: the metric
sampler (`SystemMonitorService`), the top-processes service
(`MenuPanelTopProcesses`), and the Fan row on main panel Home. Code names
still use `SystemMonitor`. `DESIGN.md` owns every size, color, and type value.

## Sampling Lifecycle

- **Symptom:** Sampling continues after the panel closes, or readings stay
  pending after the panel opens.
- **Invariant:** One sampler and exactly one utility-queue timer at the
  shortest interval any owner asks for. While the status item exists,
  `main-panel-background` samples every 5 s (`MenuPanelMetricSampling.setBackground`
  from `MainMenuBarController.configure`), so charts open with history.
  Home owns `main-tray-home` at 1 s from `onePlusIsVisible`. Every cadence
  change restarts the timer with its first deadline now. Battery and GPU are
  skipped on Macs without them. Increment a generation before stop; a late
  sample must not change state.
- **Invariant:** Hidden Home reads no snapshot, so background samples never
  wake a view or format text.
- **Invariant:** CPU and network need a prior counter sample. Compute rates
  over monotonic elapsed time, so a 5 s gap never shows 5x rates. Keep
  baselines across cadence changes; reset them only when sampling starts
  from idle and on wake. Keep rates until a fresh valid pair exists. Keep at
  most 120 timestamped samples per metric; charts show the last 60 by index.
- **Invariant:** Home text is formatted off main into `MainPanelReadings`,
  which publishes only when a value changes. Battery and GPU presence is
  probed once per launch (`MainPanelHardware.current`), so the bento never
  changes shape after the first frame.
- **Symptom:** The first click after the panel was closed for a while was
  slow and glitched: 116 ms instead of 15-37 ms, the five process rows empty
  for 3 frames, then filled; within the old 60 s window, minutes-old values
  showed first and then jumped.
- **Cause:** `MainMenuBarController` released its hosting tree and
  `MenuPanelTopProcesses` its rows 60 s after close, so the next open rebuilt
  the whole tree and the process list. Home kept readings in view `@State`
  and formatted the newest sample only after the deferred visibility change,
  so the first frames showed old or empty tiles.
- **Invariant:** The main panel keeps its host while the status item exists
  (about 3 MB). `MainPanelReadingsModel` holds Home readings outside the
  tree; every opener calls `prepareForOpening()` before the first frame, which
  formats the newest background sample on main.
- **Check:** Close the panel for 150 s, open it from the status item with
  AXPress, and record a screen video: the first frame has current values and
  five rows, and the ledger stays near the warm time.
- **Check:** `SystemMonitorTests`: Home metrics get samples, 25 start and
  stop cycles return to zero timers, and sampling stays on until every owner
  stops. `MainPanelTests`: Home samples at 1 s while visible and falls back
  to 5 s on close or tab change; the bento columns stay equal without
  Battery or GPU.

## Chart Scroll

- **Symptom:** The Home chart lines stopped, then jumped back, at each new
  sample.
- **Cause:** `OnePlusChartTickerView.tick` started a new 1 s slide from one
  step to 0 at every sample. A sample that came late left the line resting
  at 0; one that came early cut the slide and jumped the line a step right.
- **Invariant:** One constant-speed scroll (one step per `chartTick`). A
  sample starts the next slide from the current presentation offset plus
  one step, clamped to 1.5 steps, toward -0.5 steps, with a duration that
  keeps the same speed. A sample only adds a point. Reduce Motion removes
  the scroll, so the chart steps.
- **Check:** Watch a chart for 10 s at 1 s sampling: no pause and no
  backward jump. The first frame after open shows no jump.

## Top Processes

- **Symptom:** The process sample hangs, icons are generic, or rows sort
  wrong.
- **Invariant:** `MenuPanelTopProcesses.refresh` samples on the sampler
  actor and sorts off main. Unavailable readings sort last. Real bundle icons
  load off main and are cached by bundle path; command-line executables use
  the terminal glyph. The `ps` fallback uses the cancellable runner with a
  5 s deadline and a 2 MB cap; keep libproc rows if it fails. Rows stay
  while the panel is closed (icons stay only for running apps), so a reopen
  never starts with an empty list. Home refreshes five rows while visible:
  a CPU baseline, 500 ms later the first rows, then every 2 s
  (`MainPanelProcessCadence`).
- **Invariant:** Row selection is kept by PID and clears when the PID
  leaves the rows or the panel hides. Quit Process never signals without
  the confirmation; it checks the PID still has the sampled start time, so a
  reused PID is never hit. Apps use `terminate`/`forceTerminate`, others
  SIGTERM/SIGKILL. The panel closes before the alert, which runs without
  activating the app.
- **Symptom:** A process CPU such as "101.2 %" wrapped to two lines.
  **Cause:** process CPU sums all cores and can pass 100%, and the 40 pt
  column could not hold it. **Invariant:** from 100 on the value is whole
  percent with no grouping (`SystemMonitorProcessRows`), and the OnePlusUI
  1.3.20 CPU column grows instead of wrapping.
- **Check:** `SystemMonitorTests` process sorting, protected fallback, and
  top-processes tests. `MainPanelTests` cadence and release test, and
  `testQuitProcessMapsPermissionExitAndReusedPIDs` (signal 0 only).

## Units

- **Invariant:** Disk values use decimal `TrayPopoverLayout.diskBytes`
  everywhere; RAM stays binary.
- **Check:** `testDiskByteFormatterUsesDecimalUnits`.

## Max Rejected On Apple Silicon

- **Symptom:** Max showed "Fan 0 rejected the maximum speed." (helper 1, M4 Pro
  Mac16,7).
- **Cause:** The old helper wrote `Ftst = 1`, waited 0.5 s once, and wrote
  `F0Md = 1` once. On M-series the SMC refuses the mode write until the
  unlock takes effect, a few seconds later. Mole's helper retries the mode
  write against a deadline ("fan test mode unlock failed", "mode write
  failed", "target write failed" in its strings).
- **Keys on this Mac** (read without root): `FNum` ui8 2; `Ftst` ui8 0;
  `F<n>Md` ui8 0 (0 Auto, 1 manual); `F<n>Tg` flt; `F<n>Mn` flt 1350;
  `F<n>Mx` flt 5777; `F<n>Ac` flt. No lowercase `md`/`tg` keys. Temperatures
  are `Tp*` (CPU P), `Te*` (CPU E), `Tg*` (GPU), all flt.
- **Invariant:** The helper (version 2) is a thin writer:
  `writeFanKey(key, value)` takes only `Ftst` 0/1, `F<n>Md` 0/1 for n below
  `FNum`, and `F<n>Tg` inside `F<n>Mn...F<n>Mx` (`FanKeyPolicy`). Every preset
  rule lives in the app (`FanDriver`), so a rule change never needs a new
  helper or password. The app reads each key back after a write and treats
  a mismatch as an error.
- **Invariant:** Max and Cool write `Ftst = 1`, then retry `F<n>Md = 1` every
  0.25 s for up to 10 s, then write `F<n>Tg`. The log records tries and time.
  Max targets `F<n>Mx`. Cool reads the hottest Tp/Te/Tg sensor every 3 s:
  Mn at 55 °C or less, Mx at 75 °C or more, linear between (70 °C is 75%);
  a tick rises at most 800 RPM and falls at most 250 RPM. Auto writes every
  `F<n>Md = 0`, then `Ftst = 0`.
- **Check:** after the owner approves helper 2, run
  `open -g "macpowertoys://fan/max"`, then `/cool`, then `/auto`; read
  `F0Ac`/`F0Md`/`Ftst` and the Fan log lines. End on Auto.

## Fan Stays Forced After The App Dies

- **Symptom:** Cool or Max stayed forced after a crash, force quit, or SIGKILL.
- **Cause:** The helper did not track clients, and the in-process revert
  ignored its result.
- **Invariant:** The last connection whose write left the fans manual owns
  them (`FanManualLease`). The helper restores Auto when that connection ends,
  or when it sends no write for 15 s (watchdog every 5 s; the app rewrites
  every target each 3 s tick). A failed restore keeps the owner and the
  daemon, so the watchdog retries. The app restores Auto and shows the reason
  when macOS takes the fans back or the helper stops. A disabled Awake
  refuses external actions.
- **Check:** `FanControlTests` lease and policy tests. Then, with helper 2,
  set Max, send SIGKILL, and confirm Auto returns on real hardware.

## Fan

- **Symptom:** Quit blocks on Fan, Fan polls after its panel closes, or Fan
  loses Cool and Max without helper access.
- **Invariant:** Quit awaits `restoreAutomaticOnExit()` (async throws). It
  queues Auto after selected presets, blocks new selections, keeps ownership
  until success, and propagates failure so termination can cancel.
- **Invariant:** The signed daemon accepts only allowlisted fan keys from the
  signed app (see "Max Rejected On Apple Silicon"), and the app restores Auto
  on a failed write. The helper installs with SMJobBless (see
  `system-tools.md`, Helper install); never type the admin password on the
  owner's behalf. Raise the helper `CFBundleVersion` before using a new XPC
  method. The in-app SMC reader is read-only, runs
  only while a fan view owns the poller, and bounds indices and lengths.
  Fan commands drain output with a cap and hard-kill after a short grace.
- **Invariant:** Fan is the first row of the Home control card, above
  Awake. It shows the RPM and Auto, Cool, and Max. A read that finds no fans
  hides the row. Fan starts and stops its service from `onePlusIsVisible`;
  hiding dismisses setup. Only a click on a segment the helper can apply
  writes (`canSelect`); the whole control dims while none can apply. A
  warning glyph owns helper setup and Restore Auto. Fan text is prepared off
  main, equal results do not publish, and publications stay at least 250 ms
  apart.
- **Invariant:** No test reaches the real fan helper: every test service
  gets a fake `applyPreset`, and no test selects on the shared service.
- **Check:** `FanControlTests` covers ordering, awaited restore, failure, and
  retry. Run `testFanViewStopsPollingWhileItsLayoutStaysMounted` and
  `MainPanelTests.testNoTestSendsAFanWrite`. Test the helper install, Max, and
  Auto on an isolated Mac.
