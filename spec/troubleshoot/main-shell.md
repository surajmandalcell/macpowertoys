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

## Window Space Restoration

- **Symptom:** A reopened utility returns to its saved frame and display but not
  necessarily to the macOS Space where it was last used.
- **Cause:** Public AppKit and SwiftUI restoration can preserve a window's
  system configuration by recreating windows that were open at quit. macOS does
  not expose a public API for assigning an independently reopened window to a
  Space.
- **Invariant:** Preserve frame and display through `WindowStateManager`. Keep
  automatic scene restoration disabled so tools never reopen merely because
  they were visible at quit. Never use private window-server APIs to force a
  Space.
- **Check:** Relaunch and reopen each window to verify its frame and display.
  Treat exact Space placement as unsupported unless Apple adds a public API or
  the product requirement changes to allow automatic reopening of prior scenes.

## Compact Applet Frame Restoration

- **Symptom:** A compact applet opens taller than its content, leaving dead
  space below the body and a floating settings button that sits well above the
  bottom-right corner.
- **Cause:** `WindowStateManager.restoreState` applied the complete saved
  frame, including a stale height, to windows whose height is content-driven.
  SwiftUI centers the fixed-size content in the taller window.
- **Invariant:** Fixed-size applet windows (`awake`, `color-picker`,
  `text-extractor`, `ruler`) restore position only: keep the saved top-left
  edge and the window's current content-driven size. Never restore a saved
  width or height onto a content-sized applet.
- **Check:** Save an applet frame, change its expected content height, reopen,
  and confirm the body fills the window with the settings button 8pt from the
  bottom-right corner.

References: Apple's
[SwiftUI suppressed launch behavior](https://developer.apple.com/documentation/swiftui/scenelaunchbehavior/suppressed)
and
[AppKit state-restoration sample](https://developer.apple.com/documentation/appkit/restoring-your-app-s-state-with-appkit).
