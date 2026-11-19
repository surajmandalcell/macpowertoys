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
- **Check:** `SystemMonitorTests`: Home metrics get samples, 25 start and
  stop cycles return to zero timers, and sampling stays on until every owner
  stops. `MainPanelTests`: Home samples at 1 s while visible and falls back
  to 5 s on close or tab change; the bento columns stay equal without
  Battery or GPU.

## Top Processes

- **Symptom:** The process sample hangs, icons are generic, or rows sort
  wrong.
- **Invariant:** `MenuPanelTopProcesses.refresh` samples on the sampler
  actor and sorts off main. Unavailable readings sort last. Real bundle icons
  load off main and are cached by bundle path; command-line executables use
  the terminal glyph. The `ps` fallback uses the cancellable runner with a
  5 s deadline and a 2 MB cap; keep libproc rows if it fails. The panel
  release clears rows and icons. Home refreshes three rows while visible:
  a CPU baseline, 500 ms later the first rows, then every 2 s
  (`MainPanelProcessCadence`).
- **Invariant:** Row selection is kept by PID and clears when the PID
  leaves the rows or the panel hides. Quit Process never signals without
  the confirmation; it checks the PID still has the sampled start time, so a
  reused PID is never hit. Apps use `terminate`/`forceTerminate`, others
  SIGTERM/SIGKILL. The panel closes before the alert, which runs without
  activating the app.
- **Check:** `SystemMonitorTests` process sorting, protected fallback, and
  top-processes tests. `MainPanelTests` cadence and release test, and
  `testQuitProcessMapsPermissionExitAndReusedPIDs` (signal 0 only).

## Units

- **Invariant:** Disk values use decimal `TrayPopoverLayout.diskBytes`
  everywhere; RAM stays binary.
- **Check:** `testDiskByteFormatterUsesDecimalUnits`.

## Fan Stays Forced After The App Dies

- **Symptom:** Cool or Max stayed forced after a crash, force quit, or SIGKILL.
- **Cause:** The helper did not track clients, and the in-process revert
  ignored its result.
- **Invariant:** The helper writes Auto when the connection that set a manual
  mode ends (`FanManualLease`). The app holds that connection only while the
  mode is manual. A failed revert retries 3 times, then shows an error. The
  helper-commit poll backs off. A disabled Awake refuses external actions.
- **Check:** `FanControlTests` lease test. Then, with the new helper approved,
  set Max, send SIGKILL, and confirm Auto returns on real hardware.

## Fan

- **Symptom:** Quit blocks on Fan, Fan polls after its panel closes, or Fan
  loses Cool and Max without helper access.
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
  `MainPanelTests.testNoTestSendsAFanWrite`. Test helper approval, Max, and
  Auto on an isolated Mac.
