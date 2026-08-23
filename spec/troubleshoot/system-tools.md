# System Tools Troubleshooting

## Input Devices

- **Symptom:** Mouse settings also change trackpad scrolling, or scrolling stays
  modified after the tool is disabled.
- **Cause:** Public scroll events do not expose a stable physical device ID, or
  the event tap outlived the tool state.
- **Invariant:** Keep independent mouse-like and trackpad-like profiles. Classify
  precise events as trackpad-like and coarse events as mouse-like unless the
  user selects an override. Stop the event tap when the tool is disabled.
- **Check:** Apply different reverse settings to both profiles, send precise and
  coarse scroll events, then disable the tool and confirm events pass unchanged.

## System Care And Mole

- **Symptom:** A cleanup can delete outside its reviewed scope, or Mole needs an
  embedded password prompt.
- **Cause:** Cleanup paths were not guarded, or an interactive CLI operation was
  treated as structured app output.
- **Invariant:** Never follow cleanup symlinks. Move only reviewed, guarded paths
  to Trash. Use Mole JSON for read-only data. Run privileged or interactive Mole
  commands in a visible Terminal. Never bundle Mole or collect sudo input.
- **Check:** Reject a cleanup target outside the allowed roots. Preview each
  destructive Mole action before opening its command in Terminal.

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
