# Verification Troubleshooting

## README Window Screenshots

- **Symptom:** Product screenshots sit on white rectangles, lose their window
  depth, or give every utility the same visual weight.
- **Cause:** Transparent padding inherited GitHub's light page background and
  the README presented the launcher and applets at similar sizes. Isolated
  window grabs composited over a later backdrop also froze translucent material
  against the wrong background.
- **Invariant:** Capture the exact current UI, never generated UI, in place from
  the live desktop composite on either the current wallpaper or a quiet dark
  backdrop. Never layer an isolated window grab over another background. Keep
  the native window shadow visible. Present the main launcher full width,
  Cloud Sync as the first large detail, and compact applets below at a smaller
  size.
- **Check:** Preview the README hierarchy and confirm there are no white outer
  backgrounds, translucent material reflects the visible backdrop, the main
  launcher is largest, Cloud Sync comes next, and every compact applet remains
  legible at its displayed size.

## UI Change Verification

- **Symptom:** Source compiles but the final spacing, focus state, or interaction
  is still wrong.
- **Cause:** Verification stopped at the build or inspected an older binary.
- **Invariant:** Run the smallest static check, build the final source state,
  then exercise every changed state in the running final binary. Rebuild after
  any reconciliation or edit made following visual QA.
- **Check:** Record the exact final build result and inspect default, hover,
  selected, disabled, settings, and dismissal states that the change touches.

## Test Mode Misrepresents the Product

- **Symptom:** A newly built app opens with missing tools or stale-looking
  state even though the source and bundle are current.
- **Cause:** The app was launched with `MACPOWERTOYS_UI_TEST=1`. Test mode skips
  normal initialization and uses isolated runtime state, so the window is not a
  valid visual preview of the user's app.
- **Invariant:** Never use UI test mode for visual verification. Open only a
  normally initialized, signed build whose embedded `MPTSourceCommit` matches
  current `HEAD`.
- **Check:** Inspect the process launch environment and app provenance before
  judging the UI. Quit an invalid preview normally, then relaunch the verified
  build without UI test mode.

## UI Test Harness Failure

- **Symptom:** The UI runner exits before establishing a connection and no test
  assertion executes.
- **Cause:** The Xcode automation harness failed to bootstrap; this is not a
  product assertion result.
- **Invariant:** Distinguish harness failure from app failure. Retry the smallest
  signed runner once, then use live accessibility and visual interaction as the
  fallback while reporting the harness limitation.
- **Check:** Inspect the result bundle message. Never report an early runner exit
  as a passing or failing product test.

## Unsigned UI Runner Gatekeeper Dialog

- **Symptom:** macOS reports `powertoysUITests-Runner.app` as damaged and leaves
  a Gatekeeper dialog after the test command stops.
- **Cause:** An app-style UI test runner built with `CODE_SIGNING_ALLOWED=NO` was
  launched. Unsigned unit-test bundles are safe; unsigned UI runner apps are not.
- **Invariant:** Never launch an unsigned UI runner. Verify the runner with
  `codesign --verify --deep --strict` before launch. If a signed runner cannot
  connect, use live accessibility and visual smoke testing instead.
- **Check:** Confirm no `powertoysUITests-Runner` process exists, dismiss any
  remaining dialog normally, and do not claim the system helper was killed when
  only its dialog was closed.

## Installation Gate

- **Symptom:** A verified build is not installed, or installation interrupts an
  active Cloud Sync transfer.
- **Cause:** The transfer gate or final install step was skipped.
- **Invariant:** Read the transfer state before UI smoke tests and installation.
  Never replace or relaunch the installed app during an active transfer. When
  clear, install and relaunch the final verified build before handoff.
- **Check:** Confirm no active transfer, install the final Release product, and
  confirm the installed process is running.

## Raycast Local Install Drift

- **Symptom:** The signed app is current, but Raycast keeps old tool icons or
  launcher metadata.
- **Cause:** The app installer replaced only the app bundle. Raycast retained a
  separately built development extension, and its PNG icons had drifted from
  the app's SVG assets.
- **Invariant:** Generate Raycast tool icons from the app asset catalog, build
  the extension, and reload an imported local extension during `make install`.
  If Raycast is closed, update its extension directory without launching it.
- **Check:** Run the icon sync check, compare the imported manifest and assets,
  and inspect representative launchers in the running Raycast build.

## Cloud Sync Pause Test Ends Before Interaction

- **Symptom:** A disposable local transfer finishes before the menu-bar Pause
  control can be used, even when the engine reports a low bandwidth limit.
- **Cause:** The rclone local backend can use its optional server-side Copy
  feature. That path can clone or copy the file without streaming bytes through
  the bandwidth limiter. A cross-volume destination does not disable the Copy
  feature.
- **Invariant:** Test Pause and Resume with a disposable source and destination
  pair that cannot use server-side Copy. Confirm the engine applied the intended
  bandwidth limit before the transfer starts.
- **Check:** Confirm the main window reports one active transfer before opening
  the menu-bar Cloud Sync tab. After the check, cancel or finish the transfer,
  remove only its record, restore the prior bandwidth and feature settings,
  confirm that no transfer or checker is active, and move all disposable data
  to Trash.

Reference: rclone documents both the optional
[`Copy` feature](https://rclone.org/overview/#optional-features) and the
[`--disable copy` control](https://rclone.org/docs/#disable-string).
