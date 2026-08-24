# System Tools Troubleshooting

## NetTools

- **Symptom:** NetTools omits SSH port forwarding or loses its three-tab
  structure.
- **Cause:** A generic network-tool list replaced the remembered product
  structure and treated the SSH feature as an optional port scan.
- **Invariant:** Use Network, Tests, and SSH Tunnels as the three main tabs.
  Tests includes an SSH port 22 preset. SSH Tunnels includes saved local,
  remote, and dynamic SOCKS5 forwards through `/usr/bin/ssh`. Use SSH agent and
  config authentication. Never store passwords, passphrases, or private keys.
  Bind local listeners to `127.0.0.1`, bound logs, support Stop, and end child
  processes when the app quits.
- **Check:** Open all three tabs. Run the SSH port 22 test. Start and stop one
  local, remote, and dynamic profile. Confirm that no secret enters app storage
  and no tunnel process remains after quit.

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

## Power Stats

- **Symptom:** Monitoring continues after the window closes, ignores the menu
  interval, or leaves status items after disablement.
- **Cause:** Detailed and menu sampling used separate unbounded timers or shared
  one lifecycle without a menu update gate.
- **Invariant:** Use one sampler and one timer. Collect detailed data only while
  the Power Stats window is open. When enabled, collect only selected lightweight
  menu metrics at the saved 1, 2, 3, or 5 second rate. Keep at most 120 samples.
  Remove the timer and all status items when neither surface needs them.
- **Check:** Close the window with the menu disabled and confirm sampling stops.
  Enable the menu, confirm its saved cadence, then disable it and confirm all
  Power Stats status items disappear.
