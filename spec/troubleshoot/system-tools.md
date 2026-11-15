# System Tools Troubleshooting

NetToys, Input Devices, System Cleaner with Mole, and shared background
resource rules. Task Manager, Fan, and Remote Stats are in
[Task Manager](task-manager.md). `DESIGN.md` owns every size and color.

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

## NetToys

### Product Scope And Helper

- **Symptom:** NetToys uses generic network tests, or the helper outlives a
  disabled tool.
- **Invariant:** The destinations are IP Scanner, SSH Anchor, Network
  History, and Wi-Fi Priority. IP Scanner implements Angry IP Scanner
  behavior independently, without GPL source. Network History stores
  reachability transitions, not every probe. Enabling NetToys registers its
  bundled login helper; disabling it stops monitoring and unregisters the
  helper.
- **Check:** Exercise all four destinations. Enable NetToys, quit
  MacPowerToys, and confirm the helper continues. Disable NetToys and
  confirm the helper exits and is unregistered.

### NetToys Helper And Pages

- **Symptom:** Wi-Fi Priority left a working network after a few failed HTTPS
  checks and kept rotating. The helper and pages polled files and processes
  every 2 to 3 seconds. The helper exited when it had no work.
- **Cause:** One HTTPS probe was the only failure test. Rotation had no limit.
  Blocking subprocesses ran on the Swift cooperative pool. Polling had no
  visibility gate.
- **Invariant:** Failover needs Internet access AND the gateway to fail for at
  least 30 seconds, and tries each saved network once. Subprocesses run on
  dispatch threads with a kill deadline. At most 16 pings run at once. The
  status file is written only on change or every 20 seconds. Pages poll only
  while visible. The helper idles instead of exiting. Launch reconcile runs off
  the main thread and is skipped when NetToys is off.
- **Check:** `NetToysCoreTests` failover and ping tests. On the signed build,
  take the gateway down for 30 seconds, run a /24 scan, and check the helper
  under launchd.

### Helper Status And Background Approval

- **Symptom:** Settings and Scanner stall before display, or NetToys cannot
  be enabled because Open Login Items is disabled.
- **Cause:** Labels read `SMAppService.status` during body and layout. The
  launcher disabled the whole settings body while the tool was off, which
  hid the recovery action.
- **Invariant:** Keep one observed status snapshot. Coalesce refreshes and
  read status on a utility task; show Checking until the first result.
  Rendering never queries ServiceManagement. Keep NetToys Settings
  interactive while NetToys is off. When approval is needed, tell the user
  to turn on every MacPowerToys entry under Background App Activity, because
  the login helper and neighbor daemon are separate services. Other disabled
  tools keep their settings disabled.
- **Check:** The manager fixture verifies one read for overlapping refreshes
  and none for repeated getters. Disable NetToys and confirm Open Login Items
  stays enabled. Approve every entry and confirm NetToys enables and MAC
  Address Access shows Allowed.

### Feature Gates And Tray

- **Symptom:** SSH Anchor or Wi-Fi Priority keeps probing after its switch is
  off, the tray starts its own poller, or tray sections lose their state.
- **Invariant:** Persist one global SSH Anchor gate in `NetToysConfiguration`;
  off keeps per-anchor choices but returns idle statuses without probes.
  Wi-Fi Priority reuses its enable flag. The tray reads saved configuration
  and helper status once when shown and owns no timer. SSH Anchor, Wi-Fi
  Priority, and Network History each persist their own disclosure, show at
  most five items, and route to the matching page. Each disclosure button has
  one full-width hit shape. Refreshes never collapse an expanded section.
- **Check:** Disable each feature from its page and the tray and confirm no
  matching helper request. Expand each section, save each configuration
  type, reopen the tray, and confirm all three states remain.

### History Loading And Location

- **Symptom:** Opening NetToys or its tray stalls while history loads, a
  heavy tool switch freezes the launcher, or Location is requested on open.
- **Cause:** `NetToysHistoryViewModel` decoded archives in initializers and
  every three seconds on main. SwiftUI kept heavy-settings readiness across
  tool changes. Location was requested on appearance while
  `notDetermined`.
- **Invariant:** Model initialization does no file I/O. Load one Sendable
  snapshot on a utility task, reject canceled results, and coalesce
  refreshes. The view-owned task stops when its destination disappears. Show
  "No scans in this period" for a nonempty archive and "No saved scans" only
  for an empty one. Key the settings subtree by tool ID. Request Location
  only from the visible user action; denied or restricted access opens
  System Settings.
- **Check:** Run `testHistoryDistinguishesEmptyPeriodFromEmptyArchive`.
  Alternate NetToys and Task Manager in the signed app; each click responds,
  the last selection wins, and no Location dialog appears before the click.

### Scanner Results, Targets, And Imports

- **Symptom:** Rows appear only at scan end, a rescan removes other rows,
  results vanish on page change, a scan uses an old subnet, or imports stall.
- **Cause:** The scanner returned one final array, the view owned its model,
  the automatic target refreshed asynchronously, restored rows lost their
  run's target, and imports had no size limit on main.
- **Invariant:** The window owns the scanner model. Publish each host after
  liveness and port probes, then update it as hostname, protocol, MAC, and
  vendor data arrive. Merge by IP. A selected-host rescan keeps other rows. A
  full scan clears the prior run only after target resolution succeeds.
  Ignore callbacks from canceled scans. Comments appear in the table and
  every full export. NetBIOS returns all available fields.
- **Invariant:** Restore the latest completed run after relaunch with its
  own target, and persist target, ports, filter, search, preferences,
  columns, sort, openers, favorites, and annotations. An automatic target
  resolves the active network again when Scan starts. A retained run with a
  different target shows "Results are from <target>. Scan to refresh." in
  the results status bar. The toolbar row holds only fixed controls; Scan
  and Stop share one width.
- **Invariant:** Strip comments before parsing. Limit target lists to 2 MiB,
  saved scans to 32 MiB, and entries to the resolver limit. Parse off main.
  Keep Scan and imports disabled during an import. Report precise errors.
- **Check:** Scan a subnet; rows appear live without duplicates. Rescan one
  host; other rows stay. Cancel and restart; the first scan cannot change the
  table. Change pages and relaunch; results stay. Import a mixed list and
  reject an oversized file and invalid UTF-8. Read an archive's real target
  before treating a restored result as a scan failure.

### Reverse DNS

- **Invariant:** Query a PTR record with a 1.5-second deadline, accept only
  bounded valid names, and publish protocol fields meanwhile. For an address
  in the active subnet, fall back to a bounded UDP PTR query to the gateway,
  then multicast DNS, because public resolvers cannot answer private PTR.
- **Check:** A live /24 scan names every host the router names
  (`dig -x <ip> @<gateway>`).

### MAC Addresses And The Neighbor Daemon

- **Symptom:** The MAC column is empty, shows `02:00:00:00:00:00`, this Mac's
  row lacks its MAC, silent phones show as down, or the first scan after
  launch finds no open ports.
- **Cause:** macOS scrubs neighbor data for ordinary processes; on macOS 27
  the `NET_RT_FLAGS` sysctl returns an empty table except to root. An old
  root daemon failed its code-signing requirement (4102) after reinstalls.
  This Mac's ARP entry routes through lo0. Right after launch, LAN
  connections fail while Local Network access is still enabling.
- **Invariant:** Request Local Network access on use and show state and
  recovery in Settings. Try the scoped routing socket and in-process
  snapshot first. Then use the on-demand neighbor daemon and show its Not
  Enabled, Needs Approval, Allowed, or Unavailable state. The daemon takes no
  input and returns only the raw snapshot over code-signing-restricted XPC;
  the app filters to the active interface and requested addresses. Do not
  tie it to the app's source commit. Both daemons exit 30 seconds after
  their last connection. `NetToysNeighborServiceManager` probes once per
  launch and restarts the daemon on 4102. Filter entries by `sdl_index` and
  reject incomplete, zero, and `02:00:00:00:00:00` values. A local address
  with a neighbor MAC counts as alive. Before a scan, probe the gateway and
  wait at most three seconds while it fails within 20 ms.
- **Check:** A probe signed as `com.surajmandal.macpowertoys` gets bytes, not
  4102. After a reinstall the daemon PID changes. Compare a scan with
  `/usr/sbin/arp -an`. Relaunch and scan at once; ports and this Mac's real
  MAC appear.

### SSH Anchor

- **Symptom:** SSH Anchor loses a device, SSH warns about an unknown or
  changed host after an address change, asks for a password again, or flips
  between local and Tailscale.
- **Cause:** `known_hosts` followed the changing address. Enrollment never
  installed the public key. No route hysteresis existed. Tailscale without
  `TERM` returned GUI text instead of JSON.
- **Invariant:** Probe the SSH port every 2 to 3 seconds. On failure, scan
  only that port on the default connection's subnet and identify the device
  by exact MAC, or one unique first hostname label with learned MAC
  evidence. Ambiguous recovery never writes. Automatic setup inspects the
  entry, keeps both signals, enables the anchor and the helper in one
  action. A scanner-selected address overrides a stale `HostName` in one
  atomic edit. Recovery changes only the selected `HostName` token.
- **Invariant:** Enrollment prepends one managed policy for every literal
  alias: a stable anchor `HostKeyAlias`, `StrictHostKeyChecking accept-new`,
  and `CheckHostIP no`. A real host key change is still refused. The helper
  migrates existing anchors before probing.
- **Invariant:** Enrollment checks key-only login. If the key is rejected,
  ask for the password once in a secure sheet, pass it to OpenSSH through a
  private one-use FIFO, and never store or log it. Install the key in the
  Windows user file, plus the ProgramData administrator file restricted to
  Administrators and SYSTEM for admin accounts; use `ssh-copy-id` on Unix.
  Recheck with `BatchMode=yes`. A dismissed sheet leaves a quiet retry.
- **Invariant:** Tailscale fallback is opt-in per anchor. Match a unique
  first label only at setup, else use the chooser. Persist the node ID and
  refresh by it. Fall back after two local failures; return after three
  verified local successes and a 30-second minimum dwell. Accept a cached
  local address only on the active subnet. Every route change uses the
  verified atomic `HostName` path with rollback. Run Tailscale with
  `TERM=dumb`. On each helper tick, keep state only for configured anchors.
- **Check:** Compare the SSH config before and after recovery; only the one
  token changes. `ssh -G <alias>` keeps the host-key alias while `hostname`
  changes. Key-only SSH works after enrollment and after an address change;
  the password is absent from arguments, environment, logs, and disk. Test
  Windows standard and admin accounts. Exercise fallback and recovery with a
  disposable SSH host.

### Wi-Fi Priority

- **Invariant:** Store an ordered list of saved SSIDs without passwords.
  Failover is off until two SSIDs exist and follows "NetToys Helper And
  Pages". Instant Hotspot stays the last system-managed fallback; open Wi-Fi
  Settings for Auto-Join. Never claim a public API can start Instant Hotspot.
- **Check:** Legacy configuration decodes with failover off. The switch stays
  disabled with fewer than two rows, and Instant Hotspot shows last.

### Network History

- **Invariant:** SSID is the Wi-Fi identity. A gateway change on the same
  SSID is not a network change. Wait for a known SSID instead of inferring a
  change. Labels show only the SSID. `interface | gateway` is the wired or
  missing-SSID fallback. Migrate a legacy pair only when it maps to one SSID.
- **Invariant:** The availability graph is a step timeline of Internet
  reachability from range start to now. Network changes and search do not
  alter it. Time before the first state shows as no data. A network event
  keeps simultaneous gateway and Internet changes.
- **Check:** Change the gateway on one SSID: no event. Change SSID: one
  event. Reversing transition order fails the timeline regression.

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
  nothing. The smoothing unit test passes. With a real wheel during a forced
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

## System Cleaner And Mole

### Cleanup Safety

- **Symptom:** Cleanup deletes outside its reviewed scope, accepts a changed
  target, reports a partial scan as complete, goes idle while work runs, or
  uninstalls the wrong same-named bundle.
- **Cause:** Unguarded or candidate-supplied paths, mutable completion IDs,
  unowned detached work, skipped read errors, and CLI calls without
  lifecycle or identity checks.
- **Invariant:** Never follow cleanup symlinks. Require one category's
  trusted root, an immediate child, and unchanged file and root identities at
  restore and Trash. Walk original path components with lstat; reject dot
  traversal. Foundation can rewrite `/private/var` to the `/var` link, so it
  cannot define the checked path. Freeze Trash IDs and keep real failures
  selected. Lock selection and new work until the worker exits. Trash and
  Homebrew install cannot be canceled. Report missing, denied, unsafe, and
  I/O failures separately, plus the 500-child bound per root; an access error
  alone does not prove TCC. Retry only affected roots.
- **Invariant:** Use Mole JSON only for read-only data. Run privileged or
  interactive Mole commands in a visible Terminal and never infer completion.
  Never bundle Mole or collect sudo input. Limit CLI output to 8 MiB and
  30 seconds; on cancel, timeout, or overflow send TERM, wait 250 ms, then
  KILL and reap. Installed help must list each preview flag. Before a
  name-based uninstall, require one exact path in fresh native and Mole
  inventories and recheck its identity.
- **Check:** Reject a target outside the allowed roots. Disposable fixtures
  cover identity replacement, links, partial Trash failure, competing starts,
  output cap, deadline, reap, and duplicate bundles. Run `SystemCareTests` on
  hosted CI.

### Pages And Rows

- **Invariant:** Storage, Cleanup, Applications, Mole, and History use
  `OnePlusPage(scrolls: false)`. Search, headers, inspectors, actions, and
  status stay fixed; only lazy rows scroll. Scan is the primary action on
  Overview and Cleanup before results. One work status sits in the bottom
  content inset. In Storage only directory rows are actionable.
- **Invariant:** Sum each app bundle's allocated size recursively without
  following links, on utility tasks, with cached real icons (80 x 80 pixels
  only; clear caches on window close). Show a dash while loading, never
  `Unknown` or `Zero KB`. A failed size shows a caption, a full reason in the
  inspector, and Retry Size on a window-owned task.
- **Invariant:** Help sits beside labels in 44 pt rows. Paired actions use
  intrinsic widths side by side. The pre-scan empty state centers across the
  full width. Activity rows keep separators except after the last row.
- **Invariant:** Parse Mole history into a one-line summary plus operation
  and target. Keep timestamp, status, and counts separate; omit absent
  values; never infer paths or success. Keep raw JSON in help. Reject
  malformed groups and keep prior history on a read failure.
- **Check:** Run `testMoleHistoryParsesNestedCountsTargetsAndOptionalMetadata`
  and `testSelectedTabUnderlineSurvivesInitialEntryAndTabChanges`. Run
  `tmp/redesign/syscare/check-r11-ui.py`. Start a scan from each page; status
  stays at the bottom.

## Background Resources

### Ownership

- **Symptom:** Reopening or re-enabling a tool increases timers, watchers,
  taps, helpers, status items, or idle use.
- **Invariant:** Every repeating task and external handle has one owner, one
  need condition, and one stop path. A closed or disabled tool owns none
  unless the user enabled that background feature. One bounded idle hardware
  handle may stay cached if `deinit` releases it. Allowed background work:
  enabled menu-bar surfaces, Awake, Input Devices scroll control, the NetToys
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
  `MarketplaceInstallerTests.testStreamingSHA256ReleasesReadBuffers`,
  `PortmanTests.testPortScanCommandOutputIsBounded`, and
  `SystemCareTests.testApplicationIconsKeepOnlyDisplaySizedPixels`.

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
