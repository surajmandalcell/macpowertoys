# System Tools Troubleshooting

## NetToys

### Scanner Reverse DNS Deadline

- **Symptom:** One local listener scan streamed its HTTP server field, but the
  complete scan waited 35.1 seconds for an unresolved hostname on the hosted
  Mac.
- **Cause:** Blocking `getnameinfo` had no deadline and held the host task open.
- **Invariant:** Query the system DNS responder for a PTR record with a
  1.5-second deadline, accept only bounded valid name data, and publish
  protocol fields while the hostname query runs.
- **Check:** Hosted run `36096121530` passes the streaming and malformed PTR
  checks; the same one-host fixture completes in 1.57 seconds. Confirm real
  network hostnames in the final signed app.

- **Symptom:** The NetToys tray tab shows only switches, so current anchor,
  Wi-Fi priority, and network issue state requires opening the full app.
- **Cause:** The compact surface had no persistent progressive disclosure.
- **Invariant:** SSH Anchor, Wi-Fi Priority, and Network History each have an
  independent disclosure state stored in app preferences. Expanded sections
  show at most five items: most recently checked anchors, Wi-Fi networks in
  priority order, or newest outage events. Each section routes to its matching
  full NetToys page. Each disclosure button owns one full-width content shape
  with 6pt horizontal and vertical padding, so hover, press, and keyboard focus
  cover the complete target instead of only its icon and text. Configuration
  and helper-status refreshes must not collapse an expanded section. The tray
  reads existing files once and owns no poller.
- **Check:** Expand each section, save each configuration type, reopen the tray,
  and confirm all three states remain. Confirm every list is capped at five and
  its full-page route selects the matching destination.

## NetToys Scanner Imports

- **Symptom:** A target list with a full-line `#` comment treats the comment as
  a hostname, a large file can stall the scanner window, and oversized IPv4
  ranges report a generic invalid-target error.
- **Cause:** `split` omitted the empty prefix before `#`; file reads and JSON
  decoding ran without a byte limit on the main actor; the target parser
  discarded the IPv4 address-limit error while trying hostname parsing.
- **Invariant:** Strip comments before parsing. Bound target lists to 2 MiB,
  saved scan files to 32 MiB, and target entries to the resolver limit. Parse
  and decode selected files off the main actor. Keep Scan and other imports
  disabled until the current import finishes, and report a precise error.
- **Check:** Import a mixed IPv4, hostname, and commented target list; reject
  an oversized file and invalid UTF-8; require the address and hostname limits
  to report the same target-limit error. Confirm the scanner remains responsive
  during a selected-file import.

## NetToys History Loading

- **Symptom:** Opening NetToys, its launcher settings, or the tray tab stalls
  while saved network and scanner history loads, and the history page hitches
  again on its periodic refresh.
- **Cause:** `NetToysHistoryViewModel` read and decoded both JSON archives in
  property initializers and repeated the same synchronous work on the main
  actor every three seconds.
- **Invariant:** Model initialization performs no file I/O. Load one Sendable
  history snapshot on a utility task, reject canceled results, and coalesce
  overlapping refreshes. The view-owned task controls periodic work and is
  canceled when its destination disappears.
- **Check:** The focused source regression rejects eager history and archive
  initializers and requires the utility task. Open and close the settings,
  history, and tray surfaces repeatedly; require responsive input, current
  data after loading, and no accumulating refresh task or timer.

## NetToys Location Prompt And Heavy-Tool Switching

- **Symptom:** Returning to NetToys or System Monitor stalls the launcher, and
  merely opening NetToys can show the Location permission prompt again.
- **Cause:** SwiftUI retained the heavy-settings readiness state while the
  selected tool changed, so the next heavy tree built synchronously. NetToys
  also requested Location on appearance, refresh, and app activation whenever
  Core Location still reported `notDetermined`.
- **Invariant:** Key the settings subtree by tool ID so each heavy destination
  starts with its cancellable loading shell and the old subtree is released.
  Read the current Location status during refresh, but request authorization
  only from the visible user action. An existing authorization performs no
  request; denied or restricted access opens System Settings.
- **Check:** Alternate NetToys and System Monitor repeatedly in the exact signed
  app. Each click must respond immediately, the final selection must win, and
  no Location dialog may appear until Allow Location Access is clicked.

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

## NetToys Feature Gates

- **Symptom:** SSH Anchor or Wi-Fi Priority keeps probing after its page-level
  switch is off, or the tray starts a second status poller.
- **Cause:** The UI switch did not own a persisted helper configuration gate,
  or tray presentation created independent background work.
- **Invariant:** Persist one global SSH Anchor gate in
  `NetToysConfiguration`; turning it off keeps per-anchor choices but returns
  idle statuses without port or recovery probes. Wi-Fi Priority reuses its
  existing persisted enable flag. The tray reads the saved configuration and
  the helper's published status once when shown; it never owns a timer.
- **Check:** Disable each feature from its page and tray, confirm the saved
  configuration changes, and confirm the helper performs no corresponding
  request while unrelated NetToys features keep their own state.

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

## Input Devices Card Parity

- **Symptom:** A mouse card is taller than a trackpad card on the same page, and
  a setting such as mouse horizontal scrolling looks missing.
- **Cause:** Device cards gated each detail row behind `if let`, so a device that
  reports fewer HID properties drew fewer rows. Scroll profile cards packed their
  toggles into a two-column grid, so the extra mouse smooth-wheel toggle added a
  row and the narrow columns truncated `Reverse horizontal` and
  `Horizontal scrolling` until they read as one control.
- **Invariant:** Both card kinds keep one fixed anatomy. A device card always
  renders the same eleven detail rows and prints an em dash for a value macOS
  does not report. Both scroll profile cards render the same six labeled rows,
  including horizontal scrolling and smooth wheel steps for the mouse and the
  trackpad. Never gate a row on the presence of data or on the device kind, and
  never place two settings side by side in one card row.
- **Check:** `testMouseAndTrackpadDeviceCardsShareOneHeight` and
  `testMouseAndTrackpadProfileCardsShareOneHeight` host each card at 340pt and
  compare `fittingSize.height`. A fully reported mouse and an all-nil trackpad
  must measure the same height.

## Input Devices Metadata Clipping

- **Symptom:** Device card values appear as fragments such as `V...or` and
  `3...×` at the normal Input Devices window width.
- **Cause:** Each metadata item occupied half a card while its fixed-width label
  and value also sat side by side, leaving too little width for the value.
- **Invariant:** Keep two equal card columns and eleven metadata fields, but
  stack each field's label above its value. Keep the full value in its
  accessibility label and native tooltip when a long identifier is truncated.
- **Check:** Inspect both cards in the current signed app at 980pt. Values such
  as Vendor, Device ID, Firmware, and Scroll speed remain readable, and both
  cards stay equal in height.

## Input Devices Scroll Settings Ownership

- **Symptom:** The launcher detail page and the Scrolling page show different
  Input Devices controls.
- **Cause:** The launcher needs `InputDevicesSettingsView`, and a second copy of
  the controls was written for it instead of reusing the tool's own view.
- **Invariant:** `InputDevicesScrollSettings` is the one implementation of the
  Scroll Control card and both profile cards. The Scrolling page renders it
  inside its workspace page and `InputDevicesSettingsView` wraps the same view
  for the launcher. The Scroll device selector stays at the bottom of both hosts
  in the shared `InputScrollDeviceBar`, never inside the Scroll Control card.
- **Invariant:** Give the native Scroll device picker a fixed 160pt frame whose
  content is trailing-aligned. The bar and profile cards use the same 20pt
  gutter; do not center an intrinsic-width menu inside that frame.
- **Check:** Open the Scrolling page and the launcher Input Devices detail and
  confirm they show the same rows in the same order.

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
- **Invariant:** Before a scan, center the cleanup icon and message across the
  full body width. A leading stack must not collapse the empty state to its
  intrinsic width.
- **Check:** Reject a cleanup target outside the allowed roots. Preview each
  destructive Mole action before opening its command in Terminal. Start a scan
  from each page and confirm the status stays at the bottom of the pane.

## System Monitor

- **Symptom:** Selecting a 10-second menu cadence or changing Off, Combined,
  and Separate sends a measured value back to `...` and can move unrelated
  menu-bar items. The title-bar selector also moves within its action area.
- **Cause:** Each settings reconfiguration cleared all cached menu values,
  reset the delta sampler, and removed every status item. The title-bar action
  combined a redundant variable-width metric label with its picker.
- **Invariant:** Keep the last measured value across interval and placement
  changes, including the first empty CPU or network delta after rescheduling.
  Reuse unaffected native status items, but remove values for disabled metrics.
  Use one fixed-size segmented control on each metric title bar. New CPU,
  memory, and network menu settings default to 10 seconds; saved choices stay
  intact. Remote Stats keeps its conservative 30-second default and offers an
  explicit 5-second choice.
- **Check:** Run the menu-value retention test with a measured sample, a
  10-second interval change, an empty delta, and Combined-to-Separate.
  Require the value and unaffected item identity to remain. Compare the picker
  bounds for all four metrics and three choices, then inspect the hosted tray
  render and the signed app without taking desktop focus.

- **Symptom:** Overview, Remote Stats, and tray metric cards feel dull or use
  unrelated colors, while the Monitor sidebar wastes content width.
- **Cause:** Card fills were derived from live status tints and weak gradients;
  Monitor inherited the 240pt data-sidebar width despite short navigation.
- **Invariant:** Use one named Coolors-derived color family for card surfaces
  in all three Monitor views, keep live status color on the graph or icon, and
  preserve readable text in both appearances. Use the 220pt sidebar and give
  the returned space to content; other workspaces keep their widths.
- **Check:** Compare offscreen light and dark Overview, tray, and disconnected
  Remote Stats renders, then inspect the signed app without taking focus.

- **Symptom:** Graphs stop short of card edges, Load shows unlabeled averages,
  pending menu readings say Waiting, and the installed app still says Remote.
- **Cause:** Card padding also inset the graph; Overview joined the 1-, 5-, and
  15-minute loads without labels; pending labels were long; `/Applications`
  still ran an older source revision. The saved `oci1` host remained in defaults.
- **Invariant:** Let graph strokes and fills reach the card edge while retaining
  header padding. Show the 1-minute Load value as the main number, explain it
  as average CPU demand, and label longer averages only on the CPU detail page.
  Use `...` until a Monitor reading exists. Install the committed, signed app
  without clearing remote preferences or taking focus.
- **Check:** Compile the Monitor app and test bundles without launching them.
  Confirm zero active transfers, `oci1` still saved, and the installed source
  stamp and process match the new clean `HEAD` after background handoff.
- **Verified visual check:** Hosted run `36128135753` passed and its offscreen
  Overview and tray renders show the short pending labels, labeled Load card,
  and tray graph running to the card edges. The first-sample CPU label was then
  corrected to `...`; run `36129347170` passed the full suite and archived that
  source. These renders do not prove live hover or remote keyboard interaction.

- **Symptom:** Overview is a sparse four-card summary with no visual history,
  or body subtitles leave a large dead band below the titlebar.
- **Cause:** The detailed sampler exposed more data than the overview rendered,
  and workspace copy repeated context already expressed by the destination.
- **Invariant:** Overview renders CPU, GPU, memory, disk, network, thermal,
  battery, and load in the adaptive grid. Each card uses the bounded 120-sample
  history as a muted semantic-tint sparkline backdrop. Do not repeat CPU,
  memory, or network in another Overview history-card section. Dedicated detail
  pages may retain larger charts. Omit body subtitles from System Monitor
  destinations and keep the shared content top inset compact.
- **Check:** Render the overview at 1,180 by 780 points and the tray at its
  production width. Confirm all eight values fit, history lines remain quiet,
  and closing either surface releases only its own detailed-sampling owner.

- **Symptom:** Monitoring continues after the window closes, ignores a menu
  item's interval, or leaves status items after disablement.
- **Cause:** Detailed and menu sampling had separate lifecycles, or menu-only
  work sampled every metric on each wake. Settings and rendered menu state were
  also applied without a change check.
- **Invariant:** Use one sampler and exactly one utility-queue timer while a
  visible System Monitor surface needs metric data. The detailed window samples
  only the visible page's metrics each second; Processes, Remote, and About
  do not own the detailed timer. The tray retains its own detailed owner. In
  menu-only mode, the timer wakes for the earliest due metric and samples only
  enabled metrics that are due. Take the first sample immediately. Reset the
  sampler on its utility queue without waiting on the main thread.
- **Invariant:** When System Monitor is disabled, or when its window is closed
  and its menu is off, keep zero System Monitor timers and zero System Monitor
  status items. Increment a generation before stop. An in-flight sample may
  finish, but it must not change the snapshot, history, or menu after stop.
  Teardown is part of every close and disable path. `deinit` is only a backstop.
- **Invariant:** Let the user choose Off, Combined, or Separate independently
  for CPU, memory, GPU, disk, network, battery, and thermal. Put the CPU,
  memory, network, and disk controls in their page title bars. Permit no
  selected items and mixed placements. Preserve saved order inside the
  combined item. Give each separate item a stable autosave name and leave its
  saved macOS position intact when other metrics are enabled or disabled.
- **Invariant:** Store each item's icon, Icon and Value, Icon Only, or Value Only
  style, interval, and custom format. Support memory percentage, used, or
  available; disk percentage, used, or free; network download, upload, or both
  in bits or bytes; battery percentage or charging state; and compact or full
  thermal state. Use a versioned schema and preserve old global-interval and
  metric-selection settings during migration.
- **Invariant:** Default CPU, memory, and network to 10 seconds, GPU to 5 seconds,
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
  status-item ownership only when the enabled set, order, or placement changes.
- **Check:** Test the service with no surface, each surface alone, and both
  surfaces together. Use at least one enabled menu metric. Require timer counts
  of 0, 1, 1, and 1. Also require zero timers and status items when the menu is
  on but no metric is selected. Disable the tool during a sample and confirm the
  generation guard rejects the result. Advance a test clock across mixed
  per-item intervals and confirm only due metrics run. Run past 120 chart
  updates and confirm the cap. Apply the same settings and same rendered value
  twice and confirm the second pass makes no UserDefaults or AppKit write.

- **Symptom:** Processes hides most PIDs behind a Show 25 picker, cannot sort
  directly from headers, and offers almost no detail after selection.
- **Cause:** The view capped the sampled list and used a sort picker; the
  process model retained only the fields needed by its four columns.
- **Invariant:** Show every sampled PID in a lazy scrolling stack. Make Process,
  CPU, Memory, and PID headers reverse sort direction on repeat click and
  persist the column and direction. Keep unavailable CPU and memory readings
  after measured values in either direction. Search includes name, PID, and
  path. Show parent, user, CPU, resident and virtual memory, threads, start
  time, and executable path for a selection. If macOS denies detailed `libproc` data,
  use bounded public `ps` output where available; do not show fake zero usage
  or allow Quit without a verifiable start-time identity.
- **Check:** Scroll beyond row 25, sort every header in both directions,
  relaunch and confirm the sort, then inspect a normal and a protected process.
  Confirm Quit remains guarded against PID reuse.

- **Symptom:** A selected process looks frozen, shows hundreds of gigabytes of
  unexplained virtual memory, or offers a path that is awkward to copy.
- **Cause:** The detail panel had no visible sample time or copy action and
  labeled virtual address space as memory. It omitted parent/child context and
  selected-process network endpoints.
- **Invariant:** Resolve selected detail from the newest PID-and-start-time
  sample and show its update time. Explain that virtual address space includes
  mapped or reserved ranges and is not physical RAM. Provide Copy Path for a
  real executable, parent and child context, and a persisted hierarchy option
  that keeps every PID and sorts siblings by the chosen column. Query network
  endpoints with a bounded, selected-PID-only `lsof` call every 30 seconds;
  cancel it when selection or page changes.
- **Check:** Run the real two-sample CPU regression in an isolated Mac session.
  Select a changing process, watch two update times and values, copy its path,
  inspect the virtual-memory help, and compare grouped and flat lists. Confirm
  no port subprocess runs with no selection.

- **Symptom:** Return does nothing in the remote host field, changing refresh
  requires a disconnect, or Open Terminal opens an idle shell.
- **Cause:** The field had no submit action, Refresh was disabled while
  connected, and Terminal received only an app-open request while the SSH
  command went to the clipboard.
- **Invariant:** Name the destination Remote Stats. Return starts the same
  validated connection as Connect. Refresh offers Manual, 5, 10, 30, 60, 120, and
  300 seconds; changing it or pressing Refresh Now restarts the page-owned
  polling task without installing a remote daemon. The selected cadence is
  persisted. Disconnect and page exit cancel polling. Open Terminal passes an
  `ssh://` URL to Terminal only after the user presses it. Use large native
  connection actions with balanced padding.
- **Check:** Use an SSH alias, press Return, change refresh while connected,
  select Manual and confirm no second automatic sample, then disconnect.
  Open Terminal from the action and confirm it starts the selected SSH session.

- **Symptom:** A protected-process fallback can leave Processes loading when
  `/bin/ps` stalls or emits excessive output.
- **Cause:** The fallback read its pipe to EOF and waited for exit before
  checking the output size, with no deadline.
- **Invariant:** Run `ps` through the existing cancellable subprocess runner
  with a five-second deadline and a 2 MB output limit. Keep the libproc rows
  if the fallback fails.
- **Check:** Compile the monitor tests, exercise the runner's output and timeout
  cases in an isolated test session, and inspect a protected process there.

- **Symptom:** A stalled fan helper can leave the fan card loading or delay app
  quit indefinitely.
- **Cause:** Its command path read a pipe to EOF, retained all output, and only
  sent a soft termination after five seconds.
- **Invariant:** Drain output with a fixed memory cap. Send a hard kill if the
  command remains alive after a short termination grace period. Keep fan
  commands off the main actor except the bounded Auto restoration on quit.
- **Check:** Use a synthetic command to exceed the output cap in an isolated
  test session; compile on the owner's desktop without invoking the helper.

- **Symptom:** The fan card has no RPM on a Mac without smctl or Stats.
- **Cause:** Both read paths required binaries installed outside MacPowerToys.
- **Invariant:** Read SMC fan keys in the app only while a fan view owns the
  poller. Limit fan indices and data lengths. Keep this path read-only; route
  writes through the guarded privileged helper.
- **Check:** Compile both Mac architectures, run the SMC layout and decoding
  regression in hosted tests, and inspect a fan-equipped Mac without either
  external binary installed.

- **Symptom:** System Monitor mixes unrelated clocks, Bluetooth, and metric
  plugins with activity monitoring, and Remote is labeled Linux-only.
- **Cause:** A broad feature list was treated as monitor modules even though
  plugins belong to the MacPowerToys Marketplace.
- **Invariant:** Keep monitor metrics and MacPowerToys tool plugins separate.
  Remote selects Linux, macOS, or Windows and samples only after Connect, at
  30 seconds or slower by default, stopping on Disconnect or page exit.
- **Check:** Confirm the sidebar order starts Overview, Processes, CPU; it has
  no World Clocks, Bluetooth, Plugins, or Menu Bar page. Confirm the existing
  Marketplace still installs tools and Remote is idle until connected.

## Background Resource Ownership

- **Symptom:** An enabled Dev Sync pair wakes five times a second when no
  files changed and no reconciliation is pending.
- **Cause:** Its scheduler loop checked the dirty queue every 200 ms, even
  after the queue became empty.
- **Invariant:** Sleep until the next due generation. When none exists, park
  the loop and wake it on file events, manual sync, configuration changes, or
  remount. Cancel the sleep and loop when the pair stops. A file event only
  reschedules the deadline; it does not start reconciliation early.
- **Check:** Keep an enabled pair idle and confirm no periodic scheduler work.
  Then edit a file and require one debounced operation. Repeat after a remount,
  rapid edits, a manual Sync Now, and stop/start; no generation may be lost or
  duplicated.

- **Symptom:** Cloud Sync's launch setting leaves its daemon and poller awake
  every 700 ms even though no transfer can advance.
- **Cause:** The poll loop used its active-transfer interval for an empty or
  fully paused queue.
- **Invariant:** An empty or fully paused engine checks daemon health every 5
  seconds. Queued, running, and retrying work retains 700 ms progress polling.
  Creating, resuming, or retrying a transfer submits it immediately when the
  daemon is ready and wakes the poller, so idle sleep never delays progress.
- **Check:** With Start at Launch enabled and no active transfer, measure the
  signed app and rclone at idle. Start a local copy and require an immediate
  running state followed by normal progress and completion. Resume and retry
  must also wake the loop without duplicate submissions.

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
  shortcuts, and visible Ruler work. Each
  owner must still stop when its own need condition ends. Repeated start calls
  must not increase its owner count.
- **Check:** Expose test-only owner counts instead of inferring them from process
  CPU or memory. Run at least 25 open and close or enable and disable cycles.
  After a 30-second settle, require every owner count to return to its baseline
  and CPU-time growth to return to the baseline range. Confirm that the final
  ten RSS samples form a stable band with no cycle-by-cycle growth. Do not
  require process-wide zero CPU or an exact RSS return because allocators and
  other enabled tools share the process.
