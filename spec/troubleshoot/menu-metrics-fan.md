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
- **Invariant:** The helper is a thin writer:
  `writeFanKey(key, value)` takes only `Ftst` 0/1, `F<n>Md` 0/1 for n below
  `FNum`, and `F<n>Tg` inside `F<n>Mn...F<n>Mx` (`FanKeyPolicy`). Every preset
  rule lives in the app (`FanDriver`), so a rule change never needs a new
  helper or password.
- **Invariant:** Max and Cool write `Ftst = 1`, then retry `F<n>Md = 1` every
  0.25 s for up to 10 s, then move `F<n>Tg` once a second from the current
  `F<n>Ac`. Max climbs at most 1500 RPM a second to `F<n>Mx`. Auto writes
  every `F<n>Md = 0`, then `Ftst = 0`, without reading first.

## Cool Maxed The Fans At Once

- **Symptom:** Cool jumped straight to 5777 RPM, then failed with
  "F0Tg reads 1350 after writing 5777" and left the fans manual.
- **Cause 1:** Cool followed the hottest raw `Tp`/`Te` sensor. This M4 Pro
  has 112 of them; single cores spike to 80-90 °C under light load while
  the mean sits near 45 °C, so a 75 °C full-speed point meant Max. `Tg*`
  keys here read 0-4, so they are not GPU temperatures.
- **Cause 2:** SMC reads lag a write: `Ftst` reads the old value for about
  0.7 s (50 ms polling), `Md` and `Tg` for under 0.1 s. An immediate
  read-back fails, and a read-gated Auto skips keys that were just set.
- **Invariant:** Cool smooths the hottest `Tp`/`Te` reading in 20-110 °C
  (EMA 0.2 per 1 s tick). It follows `FanCurve.load()`: the `fan.curvePreset`
  curve, else the user's `fan.coolCurve` (standard: Mn at 65 °C), as a
  monotone cubic through the locked full-speed end at 90 °C; a tick rises at
  most 300 RPM and falls at most 150 RPM. Only one pick is on: a preset pick
  clears `fan.keepCelsius`, Hold sets it, and a curve edit clears both. With
  `fan.keepCelsius` saved, the `FanHold` PI loop replaces the curve, holds
  its speed inside target ±2 °C, and 90 °C still forces Mx. Each tick
  reads back the previous tick's `Md` and `Tg`; two mismatches in a row end
  manual control. The helper sets its owner from the write itself
  (`Ftst = 0` clears it), never from a read.
- **Check:** `fanprobe`-style SMC reads every 0.5 s across a Cool click:
  RPM leaves the current speed in steps of 300 or less.
- **Invariant:** `macpowertoys://fan/...` links work only while the user
  default `MPTAllowFanLinks` is true, because any web page can open a URL.
  Off, the route logs one line and does nothing.
- **Check:** after the owner approves helper 3, run
  `defaults write com.surajmandal.macpowertoys MPTAllowFanLinks -bool true`,
  then `open -g "macpowertoys://fan/max"`, `/cool`, `/auto`; read
  `F0Ac`/`F0Md`/`Ftst` and the Fan log lines. End on Auto, then
  `defaults delete com.surajmandal.macpowertoys MPTAllowFanLinks`.

## Fan Stays Forced After The App Dies

- **Symptom:** Cool or Max stayed forced after a crash, force quit, or SIGKILL.
- **Cause:** The helper did not track clients, and the in-process revert
  ignored its result.
- **Invariant:** The last connection whose write left the fans manual owns
  them (`FanManualLease`). The helper restores Auto when that connection ends,
  or when it sends no write for 15 s (watchdog every 5 s; the app rewrites
  every target each 1 s tick). A failed restore keeps the owner and the
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
  Awake. It shows the RPM, the CPU thermometer (`CPUHeat`, the same sensor as
  Cool, read on the 5 s poll and reset when the row hides), and Auto, Cool
  (or Custom), and Max with `.snug` segments (label plus 8 pt a side). The
  Fan title has no fixed width, which keeps "2,840 RPM" whole; a 48 pt title
  cut it. The clicked pill shows at once and falls back after 3 s if the
  helper never reports the preset.
  `MPTDiagnosticCPUCelsius` replaces the reading for screenshot checks;
  delete it after. A read that finds no fans
  hides the row. Fan starts and stops its service from `onePlusIsVisible`;
  hiding dismisses setup. Only a click on a segment the helper can apply
  writes (`canSelect`); the whole control dims while none can apply. A
  warning glyph owns helper setup and Restore Auto. Fan text is prepared off
  main, equal results do not publish, and publications stay at least 250 ms
  apart.
- **Symptom:** After quit and relaunch the fans were back on Auto.
- **Cause:** The chosen mode lived only in memory; quit and the helper lease
  both restore Auto, and nothing applied the choice again.
- **Invariant:** Every click or link saves the mode in `fan.savedPreset`.
  Launch (`restoreServices`) and wake (when the fans read Auto) call
  `restoreSavedPreset()`, which shows the saved mode at once and writes it
  only when the helper answers ready. It never installs: a missing or old
  helper leaves Auto and adds the bell item "Fans stay on Auto". Quit still
  restores Auto and keeps the saved mode.
- **Check:** link Cool, quit, relaunch: `Ftst=1`, `F0Md=1` within 10 s. Link
  Auto, quit, relaunch: stays Auto.
- **Invariant:** No test reaches the real fan helper: every test service
  gets a fake `applyPreset`, and no test selects on the shared service.
- **Check:** `FanControlTests` covers ordering, awaited restore, failure, and
  retry. Run `testFanViewStopsPollingWhileItsLayoutStaysMounted` and
  `MainPanelTests.testNoTestSendsAFanWrite`. Test the helper install, Max, and
  Auto on an isolated Mac.
