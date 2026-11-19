# System Tools Troubleshooting

Input Devices and shared background resource rules. Menu metrics, top
processes, and Fan are in [Menu metrics and Fan](menu-metrics-fan.md).
`DESIGN.md` owns every size and color.

## Local Unit Tests Must Not Activate The App

- **Symptom:** The guarded local run aborts when a test starts.
- **Cause:** Tests called `NSApp.activate` or `makeKeyAndOrderFront`.
- **Invariant:** Preserve the owner's foreground app. Unit checks use
  offscreen native fixtures and presentation spies. The unit host prohibits
  activation and skips Main launch and reopen. Tests that need activation
  run only in an isolated account. Never remove the wrapper's foreground
  guard.
- **Check:** `tmp/redesign/tools/xtest.sh` runs to the end with the owner's
  app in front.

## Input Devices

### Profiles And Device Data

- **Symptom:** Mouse settings change trackpad scrolling, scrolling stays
  modified after disablement, or cards show false or clipped values.
- **Cause:** Scroll events expose no stable device ID; the tap outlived the
  tool; a fixed card anatomy treated absent HID data as content.
- **Invariant:** Keep independent mouse-like and trackpad-like profiles with
  a manual override. Stop the event tap when the tool is disabled. Show each
  device's type, transport, IDs, speeds, and available HID values; omit
  absent values and the built-in keyboard battery. Enumerate without an open
  HID stream and collapse composite services to their pointing interface.
  Use full-width key-value rows; long values keep their full text in the AX
  label and tooltip. Both profiles keep seven setting rows in one column.
- **Check:** `testDeviceCardsOmitUnavailableValues`,
  `testMouseAndTrackpadProfileCardsShareOneHeight`, and
  `testScrollSettingsStackInOneColumnAtTheWindowWidth`. Disable the tool and
  confirm events pass unchanged.

### Settings Ownership And Panel

- **Symptom:** The page gains a second inset, the Scroll device footer
  scrolls, the panel opens very tall, or Refresh blocks main.
- **Invariant:** `InputDevicesSettingsContent()` is the one card set. Hosts
  embed it directly; `OnePlusMenuPanel` owns the panel inset. The Scrolling
  page keeps `InputScrollDeviceBar` fixed below its row scroller. Devices,
  Mouse, Trackpad, and Scroll device persist separate disclosures; for unset
  keys open Devices and collapse the rest, never overwriting saved choices.
  Collapsed profile headers show direction and speed. Refresh is a separate
  button. Keep one "Use custom scrolling" switch with help. Enumerate HID on
  one coalesced utility task and reuse an active tap. Disablement cancels
  discovery and invalidates queued smoothing steps by session generation.
- **Check:** Both card stacks start on the page title edge; the footer stays
  fixed. Test fresh defaults and saved choices across panel recreation.
- **Open:** In an isolated session, revoke Accessibility during interception;
  control must stop with visible recovery, and retry only on explicit action.

### Scroll Speed Endpoint

- **Invariant:** Accept one floating-point step beyond each speed endpoint
  (a saved 3.0x reads `3.0000000000000004`). Reject nonfinite values and
  larger excursions. Never rewrite saved owner preferences to repair range.
- **Check:** `testReverseAtSavedSliderEndpointsFollowsBothGates`.

### Event Tap Recovery

- **Invariant:** When macOS disables the scroll tap after a timeout or input
  change, re-enable the existing tap before the callback returns.
- **Check:** Sustained wheel input, then lock and unlock; the profile stays
  active without toggling.

### Event Taps Off The Main Thread

- **Symptom:** Scrolling and key presses freeze in every app while
  MacPowerToys is busy.
- **Cause:** Both active CGEventTaps were served on the main run loop.
  Smoothing dropped each real notch and posted 5 synthetic events from the
  main queue.
- **Invariant:** Every CGEventTap runs on `EventTapThread`. Callbacks read only
  lock-protected copies of settings and chords. They touch the main actor only
  to run an action, log, or stop. A real wheel event is never dropped. A
  disabled tap is re-enabled before the callback returns, and only while
  Accessibility is trusted.
- **Check:** `rg "CFRunLoopGetMain|assumeIsolated"` in
  `Core/InputDevicesManager.swift` and `Core/GlobalShortcutManager.swift` finds
  nothing. The smoothing unit test passes. Smoothing frames come from a
  per-screen `CADisplayLink` on `EventTapThread`, never a fixed timer; the
  real notch is rewritten as the first continuous frame, never dropped. With a real wheel during a forced
  main-thread stall, scrolling and typing stay smooth.

### Input Devices Scroll Field Fidelity

- **Symptom:** Slow speeds do not move. Games see zero or 5x deltas. Smooth
  mice get the trackpad profile. Events from other tools are transformed twice.
  Rewritten events lose their pixel scroll.
- **Cause:** Fixed-point fields went through integer accessors. Line deltas had
  no carry. Device type came only from `isContinuous`. No source-pid check
  existed. The line delta was written after the point delta, and CoreGraphics
  then recomputed the point delta from the line count.
- **Invariant:** Write line deltas first, then point and fixed-point deltas as
  doubles. Carry whole lines per axis. Zero events pass. A continuous event
  needs a phase to count as a trackpad. An event posted by another pid passes
  untouched.
- **Check:** `InputDevicesTests`, plus a real wheel at 0.35x and in a game.

## Background Resources

### Ownership

- **Symptom:** Reopening or re-enabling a tool increases timers, watchers,
  taps, helpers, status items, or idle use.
- **Invariant:** Every repeating task and external handle has one owner, one
  need condition, and one stop path. A closed or disabled tool owns none
  unless the user enabled that background feature. One bounded idle hardware
  handle may stay cached if `deinit` releases it. Allowed background work:
  enabled menu-bar surfaces, Awake, Input Devices scroll control, the fan
  helper, Settings Sync observers, a visible Cloud Sync window, active or
  continuous Cloud Sync jobs, Cloud Sync start-at-login, global shortcuts,
  and visible Ruler work. Repeated starts never raise the owner count.
- **Check:** Use test-only owner counts. Run 25 cycles. After 30 seconds,
  every count returns to baseline and the last ten RSS samples are stable.

### Idle Loops

- **Invariant:** A Dev Sync pair sleeps until its next due generation and
  parks with none; file events, manual sync, configuration, and remount wake
  it. An empty or paused Cloud Sync engine checks health every 5 seconds;
  queued or running work polls every 700 ms. New, resumed, and retried
  transfers submit at once and wake the poller.
- **Check:** An idle pair and an idle engine do no periodic work. Edits,
  Sync Now, resume, and retry run once, without loss or duplicates.

### Subprocesses And Buffers

- **Invariant:** Drain pipes while the child runs, keep only the stated cap,
  stop oversized or timed-out commands, and clear readability handlers on
  launch failure and exit. Dev Sync keeps at most 64 MiB per Git pipe.
  `SSHProcessRunner` defaults to 4 MiB per pipe. Portman drains 64 KiB chunks
  with an 8 MiB total cap. Drain one autorelease pool per file or pipe chunk.
  Portman link results expire after two minutes, at most 64 kept.
- **Check:** `SystemMonitorTests.testSubprocessDefaultOutputIsBounded`,
  `MarketplaceInstallerTests.testStreamingSHA256ReleasesReadBuffers`, and
  `PortmanTests.testPortScanCommandOutputIsBounded`.

### Unbounded Subprocesses

- **Symptom:** Portman data goes stale or Cloud Sync stalls after a long run.
  A disk command hangs.
- **Cause:** `lsof`, `ps`, `diskutil`, and `hdiutil` ran with no deadline.
  rclone wrote stdout into a pipe nobody read.
- **Invariant:** Every background subprocess has a deadline, a size cap, and no
  unread pipe. A timeout is an error, never a success.
- **Check:** `PortmanTests` deadline test. `rg "standardOutput = Pipe()"` shows
  a reader beside each match.

### Mic Lock Stalls And Input Fights

- **Symptom:** Main-thread stalls and endless input switching while Mic Lock
  is on.
- **Cause:** Synchronous CoreAudio calls ran on main. Re-enforcement ran from
  its own listener with no limit.
- **Invariant:** Mic Lock does all HAL reads and writes off main. It never
  rewrites the same target within 2 seconds. The level meter runs only while
  its page is visible and sends at most 10 updates per second.
- **Check:** `MicLockResolverTests`. `rg "DispatchQueue.main"` in
  `MacTweaks/MicLockService.swift` finds nothing.

## Permissions And The Helper Daemon

`PermissionCenter` is the only reader of permission state. It reads without a
prompt (`AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`, the
`AVCaptureDevice` and notification status, the fan helper status), refreshes
on app activation and on the system Accessibility-list notification, and
posts `.permissionsChanged`. A row that shows a missing permission adds
`.permissionWatch(kind)`; only then, and only while it is visible, a 2 s poll
runs. Prompts come only from a user action.

- **Check Again:** it awaits `PermissionCenter.refresh()`, which awaits
  `FanHelperService.refresh()`, not only a fan data read.
- **Symptom:** The Command-Shift-3 shortcut stayed dead after a later
  Accessibility grant. **Cause:** one re-check ran 1 s after the prompt, and
  activation only stopped the tap. **Invariant:** `GlobalShortcutManager`
  follows `.permissionsChanged` both ways. **Check:** `rg AXIsProcessTrustedWithOptions`
  finds only `PermissionCenter`.
- **Symptom:** Input Devices Grant asked for Input Monitoring too, and the
  page stayed on "Grant" until Refresh. **Cause:** `CGRequestListenEventAccess`
  was called, although the scroll tap is a modifying tap that needs only
  Accessibility (no listen-only tap or HID open exists), and nothing re-read
  trust. **Check:** `rg "CGRequestListenEventAccess|IOHIDManagerOpen|NSInputMonitoring"`
  finds nothing; `InputDevicesManager` follows `.permissionsChanged`.
- **Symptom:** Notifications were never asked for, so the sleep warning and
  the quit error never showed. **Invariant:** `PermissionCenter.allowNotifications()`
  asks once, at the first notification, and never at launch.
- **Symptom:** Restart audio asked for the admin password on every click.
  **Invariant:** with the helper installed, the daemon's `restartAudio` (no
  arguments, runs `/usr/bin/killall coreaudiod`, 5 s deadline) does it; any
  helper error falls back to the osascript prompt.
- **Check:** `PermissionCenterTests` (no watcher, no timer; a missing row
  polls; a grant or hiding stops it). A real grant and a real helper audio
  restart need the owner's Mac.

### Helper install (SMJobBless)

The owner types the admin password once; nothing goes through System
Settings or Login Items (owner decision 2026-11-19, the way Mole does it).

- Names: label, Mach service, signing identifier, and file name are all
  `com.surajmandal.macpowertoys.helper`. The tool sits in the app at
  `Contents/Library/LaunchServices/` and macOS copies it to
  `/Library/PrivilegedHelperTools/`. Its Info.plist and `launchd.plist` are
  linked into the binary (`__TEXT,__info_plist`, `__TEXT,__launchd_plist`).
- Requirements: the app's `SMPrivilegedExecutables` equals
  `MacPowerToysHelperContract.helperRequirement`, and the helper's
  `SMAuthorizedClients` equals `mainAppRequirement` (team `GF57JXJF5A`).
  The daemon keeps `setConnectionCodeSigningRequirement`.
  `FanControlTests` checks the plists against the contract; `make install`
  refuses a product whose signatures do not satisfy both strings.
- Install: `FanHelperService.install()` (AuthorizationCopyRights for
  `kSMRightBlessPrivilegedHelper` with our prompt text and app icon, then
  `SMJobBless`). It runs on the first
  Cool or Max click, or on "Install Helper" in the fan popover. Auto with no
  manual mode never installs. Tests never install.
- Version: the helper's `CFBundleVersion` is an integer. `neighborSnapshot`
  returns it. A lower running version shows "outdated" and the next write
  blesses again. Raise `NetToysHelper/Info.plist` `CFBundleVersion` when
  helper code changes; a normal app update with the same version asks for
  nothing.
- Touch ID and the "Apple could not verify ... malware" line: the
  `blesshelper` right (class user, group admin, no password-only key) allows
  Touch ID, but SecurityAgent logs `AEWP notarized 0, biometry prohibited 1`
  and `TouchID is not enabled` for this Apple Development build. Both go away
  only with a Developer ID Application signature plus notarization.
- Unsigned builds (`ADHOC=1`): the app fails its own team requirement, so the
  status is `unsupported`, fans stay read only, and the row says why.
- Migration: every launch, `retireLegacyRegistrations()` unregisters the old
  SMAppService daemon (`com.surajmandal.macpowertoys.nettoys-neighbor`) and
  the old `nettoys-helper` login item, but only while they are registered.
  The old daemon plist stays in `Contents/Library/LaunchDaemons` so macOS can
  find the job to remove.
- Mac Tweaks' microphone Test reads and asks through
  `PermissionCenter.microphoneStatus` and `requestMicrophone()`.
