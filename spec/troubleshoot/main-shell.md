# Main Shell Troubleshooting

## Menu-Bar Click Arbitration

- **Symptom:** Double-clicking the menu-bar icon opens and closes the popover
  instead of opening the main window, or right-click exposes the full popover.
- **Cause:** The first click was performed immediately, before macOS could
  report the second click in the double-click interval.
- **Invariant:** Intercept left and right mouse-down events on the status-item
  button. Delay a left single-click by `NSEvent.doubleClickInterval`; a second
  click cancels it and opens the main window. Right-click bypasses that
  coordinator and shows only Open MacPowerToys and Quit, with icons.
- **Check:** Unit-check single, double, and right-click routing, then exercise
  all three in the latest normal signed build.
