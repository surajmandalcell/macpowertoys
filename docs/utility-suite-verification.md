# Utility Suite Verification

This checklist is intentionally deferred until the active large-file upload is
finished. Do not install or relaunch PowerToys before completing that transfer.

## Static checks

- Build the `powertoys` Debug and Release configurations.
- Run `powertoysTests`, including `UtilityToolsTests`.
- In `raycast`, run `npm install`, `npm run lint`, and `npm run build`.
- Confirm App Intent metadata extraction succeeds without shortcut warnings.

## Ruler

- Create horizontal, vertical, and joined rulers from the window, menu, URL, App
  Shortcut, and Raycast.
- Move and resize on 1x and 2x screens. Confirm a horizontal ruler remains 54 points
  tall and a vertical ruler remains 54 points wide.
- Exercise every zero corner, unit, opacity, color, shadow, float, aspect preset,
  arm toggle, group, reset, show/hide, crosshair, pinned/dragged guide, and copy format.
- Calibrate two displays independently and confirm reconnecting either restores its
  value.
- Disconnect a display while rulers are visible, relaunch, and confirm every frame is
  clamped to an available visible frame.
- Measure regions on displays arranged left, right, above, below, and rotated.

## Awake

- Verify Passive, Indefinite, Timed, and Until modes with and without Keep Display On.
- Inspect `pmset -g assertions` for the PowerToys reason and confirm every disable,
  expiration, and quit path releases it.
- Change the wall clock during Timed mode and confirm the interval does not change.
- Change timezone during Until mode and confirm the absolute deadline remains correct.
- Sleep and wake during both expiring modes and validate remaining time.
- Attach to a short-lived PID and confirm Awake disables when it exits.
- Exercise menu-bar presets, global shortcut, URL actions, App Shortcut, and Raycast.

## Color Picker

- Pick on each display and verify immediate clipboard output in all nine formats.
- Compare HEX, alpha, RGB, HSL, SwiftUI, and NSColor values against known colors.
- Verify duplicate samples move to the top without losing their pin.
- Verify copy, pin, delete, search, clear-unpinned, relaunch persistence, Copy Last,
  global shortcut, App Shortcut, and Raycast commands.
- Focus a history row and verify Return copies the default while number keys 1–9 copy
  the corresponding format. Change and disable the global shortcut from the toolbar.

## Text Extractor

- Test first-run explanation, permission grant, denial, and System Settings recovery.
- Select text on every display scale and arrangement, including Shift-drag reposition.
- Test accurate/fast modes, automatic detection, preferred languages, and language
  correction.
- Confirm cancellation, no-text, invalid language, and capture failure preserve the
  previous clipboard.
- Confirm captured images are not written to disk or sent over the network.
- Exercise global shortcut, App Shortcut, URL, and Raycast commands.

## Regression and release

- Confirm PowerToys does not auto-open tool windows on normal launch.
- Exercise Claude History, RSync, Logs, menu bar, window restoration, and app quit.
- Verify VoiceOver labels, keyboard navigation, light/dark mode, increased contrast,
  and reduced transparency.
- Install the signed Release build only after the upload completes, then repeat the
  cold-launch and single-instance command matrix.
