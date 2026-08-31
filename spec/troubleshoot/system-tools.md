# System Tools Troubleshooting

## NetToys

- **Symptom:** NetToys uses generic network tests or SSH tunnels instead of the
  requested four-part product.
- **Cause:** An earlier draft was mistaken for the final scope.
- **Invariant:** Use IP Scanner, SSH Anchor, Network History, and Wi-Fi Priority
  as the destinations. IP Scanner independently implements useful Angry IP
  Scanner
  behavior without GPL source. SSH Anchor monitors the selected SSH port every
  2 to 3 seconds. When the current address stops answering, it scans only that
  port on the default connection's local IPv4 subnet and identifies the device
  by exact MAC, or by one unique first hostname label with learned MAC evidence.
  Automatic setup inspects the selected SSH entry, retains both signals when
  available, enables the anchor, and enables the helper in one action. It
  adds one managed host-key policy during enrollment. When setup starts from an
  IP Scanner result, the selected scan address overrides a stale `HostName` and
  both changes use one atomic SSH config edit. Later recovery changes only the
  selected `HostName` token and preserves every other SSH config byte.
  Network History stores reachability transitions, not every probe. Enabling
  NetToys registers and uses its bundled login helper. Disabling NetToys stops
  monitoring and unregisters the helper.
- **Check:** Exercise all four destinations. Compare the SSH config before and
  after an address change and confirm that the one expected token is the only
  changed byte range. Confirm automatic setup fills the detected evidence and
  starts the helper. Start from a scanner address that differs from the SSH
  entry, choose the entry, and confirm enrollment inspects and saves the scanner
  address instead of the stale address. Change between Wi-Fi or wired
  connections and confirm the default interface is scanned. Confirm ambiguous
  recovery never writes. Enable NetToys, quit MacPowerToys, and confirm the
  helper continues. Disable NetToys and confirm the helper exits and is no
  longer registered.

## SSH Anchor Host-Key Identity

- **Symptom:** SSH reports an unknown host or a changed remote identification
  after SSH Anchor changes an address, especially when local addresses are
  reused by several devices.
- **Cause:** OpenSSH looked up `known_hosts` by the changing `HostName` address,
  so trust followed the DHCP slot instead of the enrolled device.
- **Invariant:** Enrollment atomically prepends one managed policy for every
  literal alias in the selected `Host` stanza. Use a stable, anchor-specific
  `HostKeyAlias`, `StrictHostKeyChecking accept-new`, and `CheckHostIP no`.
  OpenSSH accepts and stores the first key without a confirmation prompt, reuses
  it across local and Tailscale address changes, and still rejects a real host
  key change. The login helper migrates existing enabled anchors before probing.
  Later recovery still changes only the selected `HostName` token.
- **Check:** Resolve the prepared alias with `ssh -G` and confirm its host-key
  alias stays fixed while `hostname` changes. Connect once, move the same server
  to another address, and confirm no confirmation or changed-identification
  warning appears. Present a different server key through the same anchor and
  confirm SSH refuses it.

## SSH Anchor Key Access

- **Symptom:** SSH Anchor follows a Windows device to its new address, but
  `ssh <alias>` asks for the account password again.
- **Cause:** Host-key identity and user authentication are separate. SSH Anchor
  prepared stable host trust but never installed the Mac public key on the
  enrolled device. A password-authenticated connection can appear passwordless
  only while OpenSSH reuses that live connection.
- **Invariant:** Automatic enrollment checks key-only login. If the device
  rejects the key, request the SSH password once in a secure app sheet, pass it
  to system OpenSSH through a private one-use FIFO, and never store or log it.
  Install the selected public key in the Windows user authorized-key file. For
  an administrator account, also use the ProgramData administrator file and
  restrict it to the Administrators and SYSTEM SIDs. Use `ssh-copy-id` for
  Unix OpenSSH. Recheck with `BatchMode=yes` before recording success. Keep the
  stable `HostKeyAlias`, so the verified key remains valid after every address
  change. If the password sheet is dismissed, leave a quiet inline retry action
  for that anchor; the key button also remains available. Never bypass a
  changed host-key warning.
- **Check:** Confirm key-only SSH fails before enrollment. Complete Automatic
  enrollment, enter the password once, and confirm the app marks Key Access as
  verified. Confirm the password is absent from process arguments, environment,
  logs, and disk. Change the device address, wait for SSH Anchor recovery, and
  confirm key-only SSH still succeeds. On Windows, verify the standard-user and
  administrator paths and ACLs with separate test accounts.
  Dismiss the password sheet and confirm the affected anchor shows the compact
  retry notice, then use Retry and confirm the sheet reopens.

## NetToys Scanner Persistence And MAC Addresses

- **Symptom:** Scanner results disappear after changing destinations, or the
  MAC column is empty or shows `02:00:00:00:00:00`.
- **Cause:** The scanner view owned its model, so SwiftUI discarded the live
  results with the destination. Completed scan archives were written but not
  restored. On current macOS, direct routing-socket replies can scrub neighbor
  hardware addresses even with Local Network permission. A child `arp`
  process and an in-process neighbor-cache snapshot inherit the signed app's
  privacy context. A system launch daemon is exempt from per-user Local
  Network Privacy, but macOS requires explicit Background Item approval.
- **Invariant:** The NetToys window owns the scanner model. Preserve live
  results, selection, and sorting across destination changes. Restore the
  latest completed run after relaunch, and persist target, ports, filter,
  search, scanner preferences, columns, sort field and direction, openers,
  favorites, and annotations.
  Request Local Network access on use and show its state and recovery action in
  Settings. Query the scoped routing socket and in-process `NET_RT_FLAGS`
  snapshot first. If values are still missing, register the on-demand neighbor
  daemon and show its Not Enabled, Needs Approval, Allowed, or Unavailable
  state beside IP Scanner and in NetToys Settings. The daemon accepts no input
  and returns only the raw snapshot over mutually code-signing-restricted XPC;
  the app filters to the active interface and requested addresses. Do not tie
  the snapshot to the app's exact source commit because an approved daemon can
  remain alive across an app update. Never accept incomplete, all-zero, or
  `02:00:00:00:00:00` values.
- **Check:** Recreate the scanner model and confirm the latest archive and
  selected sort field and direction load.
  Change destinations and return, then quit and relaunch, confirming the result
  remains. Deny Local Network access and confirm Settings offers recovery. In
  the signed app, enable MAC Access, approve the Background Item when macOS
  asks, and rescan a reachable neighbor. Compare it with `/usr/sbin/arp -an`
  and confirm the same canonical MAC appears. Confirm the embedded daemon
  plist, signatures, and XPC peer requirements match the final installed app.
  Replace the app while the approved daemon remains alive, rescan, and confirm
  its canonical MAC still appears. Confirm another interface and an
  unrequested address are ignored.

## NetToys Background Approval Recovery

- **Symptom:** NetToys cannot be enabled, MAC Address Access says Needs
  Approval, and Open Login Items is disabled.
- **Cause:** The shared launcher disabled the complete settings body whenever a
  tool was off. NetToys kept its macOS background-service recovery action in
  that body, so the action needed to restore approval was unreachable.
- **Invariant:** Keep NetToys Settings interactive while NetToys is off. When
  macOS requires approval, direct the user to turn on every MacPowerToys entry
  under Background App Activity because the login helper and neighbor daemon
  are separate approved services. Other disabled tools keep their settings
  bodies disabled.
- **Check:** Disable NetToys and confirm Open Login Items remains enabled. Turn
  on every MacPowerToys Background App Activity entry, return to the app, and
  confirm NetToys enables, the login helper publishes a fresh heartbeat, and
  MAC Address Access changes to Allowed.

## NetToys Live Scanner Results

- **Symptom:** The scan counter moves, but the result table stays unchanged
  until the full network scan finishes. A selected-host rescan can also remove
  every unselected row.
- **Cause:** The scanner returned only a final result array. Hostname, protocol,
  and neighbor enrichment all completed before the view model replaced its
  table state.
- **Invariant:** Publish each host after liveness and port probing, update that
  row after hostname and optional protocol fetchers complete, then update it
  again if MAC and vendor data arrive. Merge by IP address. A selected-host
  rescan preserves unrelated rows. A full scan clears the prior run only after
  target resolution succeeds. Ignore callbacks from a cancelled or superseded
  scan. Keep comments in the visible table and every full-detail export.
  NetBIOS information includes available workgroup, user, computer, and MAC
  fields instead of returning only the first name.
- **Check:** Scan a subnet with responsive and unresponsive hosts. Confirm rows
  appear during the scan, later fields fill without row duplication, and live
  shown and alive counts change. Rescan one selected host and confirm every
  other row stays. Cancel and immediately start another scan, then confirm the
  first scan cannot change the new table. Add a comment and confirm it appears
  in the table and CSV, text, XML, SQL, and saved-result exports.

## SSH Anchor Tailscale Fallback

- **Symptom:** An SSH Anchor stops working away from its local network, or
  repeatedly flips between a local and Tailscale address. Enabling Tailscale
  can also report that its device list is unreadable even while Tailscale is
  running.
- **Cause:** The helper knew only the current local address and had no stable
  remote identity or route hysteresis. Tailscale treats a child process without
  `TERM` as a GUI launch, so a macOS app process received GUI error text instead
  of JSON from `tailscale status --json`.
- **Invariant:** Tailscale fallback is opt-in per anchor. Match an exact first
  hostname label only during setup; if it is not unique, require the device
  chooser. Persist the selected Tailscale node ID and refresh its endpoint by
  that ID. Prefer the local endpoint, fall back after two local failures, and
  return only after three verified local successes and a 30-second minimum
  Tailscale dwell. Accept a cached local address only on the active subnet.
  Apply the same route decision to newly discovered local candidates. Never
  switch to a cached or discovered local endpoint unless the route monitor
  returns `useLocal`.
  Every route change uses the existing verified, atomic `HostName` update and
  rollback path. Keep the existing bounded local-scan backoff and a 30-second
  Tailscale retry gate. Initial peer matching must inspect the scanner-selected
  local endpoint, not a stale address from the original SSH entry. Run the
  Tailscale child with `TERM=dumb` so its documented JSON command stays in CLI
  mode when launched by the signed app.
- **Check:** Decode a legacy local-only anchor. Reject ambiguous labels and a
  cached private address from another subnet. Confirm the two-failure,
  three-success, and dwell thresholds. Change a peer IP while retaining its
  node ID and confirm endpoint refresh. In the signed app, inspect the per-row
  Tailscale checkbox and chooser. Confirm enabling it reads the device list and
  saves the selected node without an unreadable-list error, then exercise
  fallback and local recovery with a disposable SSH host.

## Wi-Fi Priority Failover

- **Symptom:** A failed Wi-Fi connection stays active even when another saved
  network or the Mac's Instant Hotspot fallback is available.
- **Cause:** Network History measured outages but had no ordered failover
  configuration or switching policy.
- **Invariant:** Wi-Fi Priority stores an ordered list of saved SSIDs without
  passwords. Automatic failover is off until at least two SSIDs are configured.
  The helper checks Internet access every 2 to 3 seconds while enabled. After a
  continuous failure reaches the selected 5 to 60 second threshold, 10 seconds
  by default, scan nearby SSIDs and join the next saved network in order. Wait
  30 seconds before another attempt. Keep Instant Hotspot as the final
  system-managed fallback and open Wi-Fi Settings for its Auto-Join setting.
  Do not claim that the app can invoke Instant Hotspot through a public API.
- **Check:** Confirm legacy configuration decodes with failover off. Confirm the
  timing test stays idle through 9 seconds, attempts at 10 seconds, rotates to
  the next nearby SSID, wraps the order, and applies the 30-second cooldown.
  In the signed installed app, confirm the page lists saved SSIDs, keeps the
  switch disabled with fewer than two rows, and shows Instant Hotspot last.

## Network History Identity

- **Symptom:** Wi-Fi changes are reported as changes between `en0` and private
  gateway addresses instead of changes between Wi-Fi network names.
- **Cause:** The recorder used `interface | gateway` as the primary identity and
  treated SSID as an optional label.
- **Invariant:** Use SSID as the Wi-Fi identity. A gateway change on the same
  SSID is not a network change. If SSID is temporarily unavailable, wait for a
  known SSID instead of inferring a change from its private gateway. Use
  only the SSID in visible labels when it is available. Use
  `interface | gateway` only as the wired or unavailable-SSID fallback. Migrate
  legacy events by their exact `interface + gateway` pair only when that pair
  maps to one unambiguous stored or current SSID; otherwise retain the fallback.
- **Check:** Change the gateway while SSID stays fixed and confirm no network
  event. Change SSID with the same gateway and confirm one SSID-only event.
  Confirm every visible label shows only that SSID. Confirm wired gateway
  changes still create network events and use the route fallback. Confirm a
  legacy route pair inherits one known SSID and the migration is idempotent.

## Network History Availability Timeline

- **Symptom:** The availability graph is a cluster of vertical marks near the
  latest events instead of a readable account of when Internet access was up
  or down.
- **Cause:** The graph began and ended at sparse transition timestamps, mixed a
  network disconnect into the Internet series without recording its recovery,
  and inherited the transition list's search filter.
- **Invariant:** Draw Internet reachability as a chronological step timeline
  from the selected range's start through now. Network changes and search text
  do not directly alter the series. Show time before the first known state as a
  distinct no-data level instead of calling it unavailable. A network event
  must retain simultaneous gateway and Internet changes so disconnect and
  recovery remain paired. Use a later network boundary plus the current
  Internet state only to repair legacy records that omitted the paired recovery.
- **Check:** Record reachable, disconnect, reconnect, and an SSID-only change.
  Confirm the graph spans the full range, shows unrecorded time as no data,
  changes level only at the Internet transitions, ends at the current state,
  and does not change when transition search text changes. Confirm reversing
  transition order fails the timeline regression test.

## Input Devices

- **Symptom:** Mouse settings also change trackpad scrolling, or scrolling stays
  modified after the tool is disabled.
- **Cause:** Public scroll events do not expose a stable physical device ID, or
  the event tap outlived the tool state.
- **Invariant:** Keep independent mouse-like and trackpad-like profiles. Classify
  precise events as trackpad-like and coarse events as mouse-like unless the
  user selects an override. Stop the event tap when the tool is disabled. Show
  each detected device's type, transport, IDs, tracking and scroll speeds, and
  available HID resolution, polling, button, firmware, location, report, and
  serial values.
  Enumerate without requiring an open HID event stream, and collapse composite
  keyboard/trackpad services to their pointing interface. Do not show the
  event-classification implementation note in the task body.
- **Check:** Apply different reverse settings to both profiles, send precise and
  coarse scroll events, then disable the tool and confirm events pass unchanged.

## Input Devices Event Tap Recovery

- **Symptom:** Scroll control stops changing events even though the window still
  reports that control is active.
- **Cause:** The disabled-tap callback queued a full tap rebuild on the main
  queue. A timeout can leave that same queue unable to run the recovery.
- **Invariant:** When macOS disables the scroll event tap after a timeout or
  session input change, re-enable the existing tap before the callback returns.
- **Check:** Use sustained wheel input, then lock and unlock the session. Confirm
  the selected profile continues without toggling Input control or reopening the
  window.

## System Care And Mole

- **Symptom:** A cleanup can delete outside its reviewed scope, or Mole needs an
  embedded password prompt.
- **Cause:** Cleanup paths were not guarded, or an interactive CLI operation was
  treated as structured app output.
- **Invariant:** Never follow cleanup symlinks. Move only reviewed, guarded paths
  to Trash. Use Mole JSON for read-only data. Run privileged or interactive Mole
  commands in a visible Terminal. Never bundle Mole or collect sudo input. Keep
  Scan as the primary visible action on Overview and Cleanup before results.
  Keep one work-status surface in the bottom content inset on every System Care
  page. Keep top-strip menus and buttons at the shared 24pt action height.
  Only directory rows are actionable in Storage. File rows are informational
  and do not use hover, pressed, or button treatment.
- **Check:** Reject a cleanup target outside the allowed roots. Preview each
  destructive Mole action before opening its command in Terminal. Start a scan
  from each page and confirm the status stays at the bottom of the pane.

## System Monitor

- **Symptom:** Monitoring continues after the window closes, ignores a menu
  item's interval, or leaves status items after disablement.
- **Cause:** Detailed and menu sampling had separate lifecycles, or menu-only
  work sampled every metric on each wake. Settings and rendered menu state were
  also applied without a change check.
- **Invariant:** Use one sampler and exactly one utility-queue timer while a
  visible System Monitor surface needs data. The open detailed window takes one
  full snapshot each second. In menu-only mode, the timer wakes for the earliest
  due metric and samples only enabled metrics that are due. Take the first sample
  immediately.
- **Invariant:** When System Monitor is disabled, or when its window is closed
  and its menu is off, keep zero System Monitor timers and zero System Monitor
  status items. Increment a generation before stop. An in-flight sample may
  finish, but it must not change the snapshot, history, or menu after stop.
  Teardown is part of every close and disable path. `deinit` is only a backstop.
- **Invariant:** Let the user enable, disable, and reorder CPU, memory, GPU,
  disk, network, battery, and thermal items independently. Permit no selected
  items. Preserve saved order exactly inside a grouped item. Use the saved order
  when separate items are created, but let macOS and the user control their
  final menu-bar positions. Give each separate item a stable autosave name.
- **Invariant:** Store each item's icon, Icon and Value, Icon Only, or Value Only
  style, interval, and custom format. Support memory percentage, used, or
  available; disk percentage, used, or free; network download, upload, or both
  in bits or bytes; battery percentage or charging state; and compact or full
  thermal state. Use a versioned schema and preserve old global-interval and
  metric-selection settings during migration.
- **Invariant:** Default CPU, memory, and network to 2 seconds, GPU to 5 seconds,
  and disk, battery, and thermal to 30 seconds. Offer 1, 2, 3, 5, 10, 30, and
  60 seconds only where the source supports the rate. In menu-only mode, do not
  poll disk more often than every 15 seconds. Do not poll battery or thermal
  more often than every 10 seconds. Mark a metric that is not available for the
  current session. Do not keep a timer alive only to retry it. Retry after a
  relevant system event, wake, or explicit refresh.
- **Invariant:** CPU and network need a prior counter sample. Show a waiting
  state for the first delta. Compute the next rate over the real elapsed time.
  Do not synthesize a spike after an interval or sleep change. Keep at most 120
  timestamped detailed snapshots. Menu-only updates do not add chart history.
- **Invariant:** Compare normalized settings before writing UserDefaults or
  restarting the timer. Compare the full rendered title, image, tooltip,
  accessibility label, and length before writing an AppKit status item. Change
  status-item ownership only when the enabled set, order, or grouped or
  individual mode changes.
- **Check:** Test the service with no surface, each surface alone, and both
  surfaces together. Use at least one enabled menu metric. Require timer counts
  of 0, 1, 1, and 1. Also require zero timers and status items when the menu is
  on but no metric is selected. Disable the tool during a sample and confirm the
  generation guard rejects the result. Advance a test clock across mixed
  per-item intervals and confirm only due metrics run. Run past 120 chart
  updates and confirm the cap. Apply the same settings and same rendered value
  twice and confirm the second pass makes no UserDefaults or AppKit write.

## Background Resource Ownership

- **Symptom:** Reopening a window or enabling a tool several times increases
  timers, watchers, event taps, helpers, status items, or idle resource use.
- **Cause:** Start paths were not idempotent, or a close and disable path did not
  release the owner that its start path created.
- **Invariant:** Every repeating task and external handle has one named owner,
  one need condition, and one matching stop path. A disabled or closed tool owns
  no repeating task, file watcher, event tap, child process, helper, status item,
  or active system handle unless the user independently enabled that background
  feature. One bounded idle hardware handle may stay cached when reuse costs less
  than repeated acquisition and `deinit` releases it. Event-driven app-lifetime
  observers and one-shot debounce work are not polling loops.
- **Invariant:** Allowed background work is limited to the enabled menu-bar
  surfaces, Awake activity, Input Devices scroll control, the NetToys login
  helper, Settings Sync observers, a visible Cloud Sync window, active or
  continuous Cloud Sync jobs, the saved Cloud Sync start-at-login mode, global
  shortcuts, visible Ruler work, and visible AI History file watching. Each
  owner must still stop when its own need condition ends. Repeated start calls
  must not increase its owner count.
- **Check:** Expose test-only owner counts instead of inferring them from process
  CPU or memory. Run at least 25 open and close or enable and disable cycles.
  After a 30-second settle, require every owner count to return to its baseline
  and CPU-time growth to return to the baseline range. Confirm that the final
  ten RSS samples form a stable band with no cycle-by-cycle growth. Do not
  require process-wide zero CPU or an exact RSS return because allocators and
  other enabled tools share the process.
