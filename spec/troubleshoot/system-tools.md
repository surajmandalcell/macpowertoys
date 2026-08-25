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
  port on the active local IPv4 subnet and identifies the device by exact MAC,
  or by a unique hostname with learned MAC evidence when randomized MAC mode is
  enabled. It changes only the selected `HostName` token and preserves every
  other SSH config byte. Network History stores reachability transitions, not
  every probe. Enabling NetToys registers and uses its bundled login helper.
  Disabling NetToys stops monitoring and unregisters the helper.
- **Check:** Exercise all four destinations. Compare the SSH config before and
  after an address change and confirm that the one expected token is the only
  changed byte range. Confirm ambiguous recovery never writes. Enable NetToys,
  quit MacPowerToys, and confirm the helper continues. Disable NetToys and
  confirm the helper exits and is no longer registered.

## NetToys Scanner Persistence And MAC Addresses

- **Symptom:** Scanner results disappear after changing destinations, or the
  MAC column is empty or shows `02:00:00:00:00:00`.
- **Cause:** The scanner view owned its model, so SwiftUI discarded the live
  results with the destination. Completed scan archives were written but not
  restored. On current macOS, the routing socket scrubs neighboring hardware
  addresses for third-party processes; the SDK reserves unsanitized neighbor
  cache reads for an Apple-restricted privilege. Local Network permission
  allows device discovery but does not grant that privilege.
- **Invariant:** The NetToys window owns the scanner model. Preserve live
  results, selection, and sorting across destination changes. Restore the
  latest completed run after relaunch, and persist target, ports, filter,
  search, scanner preferences, columns, openers, favorites, and annotations.
  Request Local Network access on use and show its state and recovery action in
  Settings. Never present macOS's `02:00:00:00:00:00` privacy placeholder as a
  device MAC; label the platform restriction directly instead.
- **Check:** Recreate the scanner model and confirm the latest archive loads.
  Change destinations and return, then quit and relaunch, confirming the result
  remains. Deny Local Network access and confirm Settings offers recovery. In
  the signed app, rescan a reachable neighbor and confirm the privacy
  placeholder is rejected and the MAC cell says `macOS restricted`.

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
- **Check:** Reject a cleanup target outside the allowed roots. Preview each
  destructive Mole action before opening its command in Terminal. Start a scan
  from each page and confirm the status stays at the bottom of the pane.

## System Monitor

- **Symptom:** Monitoring continues after the window closes, ignores the menu
  interval, or leaves status items after disablement.
- **Cause:** Detailed and menu sampling used separate unbounded timers or shared
  one lifecycle without a menu update gate.
- **Invariant:** Use one sampler and one timer. Collect detailed data only while
  the System Monitor window is open. When enabled, collect only selected lightweight
  menu metrics at the saved 1, 2, 3, or 5 second rate. Keep at most 120 samples.
  Remove the timer and all status items when neither surface needs them.
- **Check:** Close the window with the menu disabled and confirm sampling stops.
  Enable the menu, confirm its saved cadence, then disable it and confirm all
  System Monitor status items disappear.
