# Verification Troubleshooting

## Test Actions Must Leave The Owner's Desktop Alone

- **Symptom:** During Xcode test execution on the shared Mac, the owner saw a
  removable-volume access prompt for `MacPowerToys.app` and a Gatekeeper
  "damaged" dialog for `powertoysUITests-Runner.app`.
- **Cause:** The generated Xcode scheme included an unsigned UI runner. A full
  `xcodebuild test` attempted to launch it. Xcode also launched Debug
  `MacPowerToys.app` as a unit-test host; macOS logged that app coming forward
  and requesting removable-volume access. The source checkout is on a
  removable volume.
- **Invariant:** The shared `powertoys` scheme has no test action. Executable
  tests use `powertoys-desktop-tests` only in an isolated macOS account or VM.
  `make test` requires `TEST_SESSION=isolated`, signs its products, and disables
  parallel test launches. Use build-only checks on the owner's desktop. Do not
  answer privacy or Gatekeeper decisions for the owner.
- **Check:** The app scheme has zero testables; the isolated scheme has two.
  `make test` without the isolated-session flag exits before Xcode starts.
  `build-for-testing` compiles both bundles without launching an app or runner.

## Isolated macOS Unit Tests

- **Symptom:** Executable XCTest verification on the owner's Mac can focus the
  app or trigger a privacy or Gatekeeper dialog.
- **Cause:** Unit tests launch a host app even when the test code itself has no
  UI action.
- **Invariant:** `.github/workflows/macos-tests.yml` runs the unit suite in a
  hosted Xcode 27 Mac on code pushes or manual dispatch. It uses ad hoc signing,
  the `TEST_SESSION=isolated` gate, installs rclone for Cloud Sync integration
  tests, and saves PNG XCTest attachments as `tray-renders` for offscreen review.
  The unit command skips UI tests; a separate hosted step runs Switch
  navigation in test mode and Portman menu-bar navigation after a normal app
  launch. It exports screenshots for both. Local owner-session checks remain
  compile-only.
  `.github/workflows/switch-ui.yml` can be dispatched manually for a focused
  Switch check when frequent pushes supersede the longer shared workflow.
- **Check:** Match the successful workflow run to the tested commit and inspect
  its XCTest result and tray renders. Run `36097325950` at `fbe1721` passed 842
  tests, with five skips and zero failures, and saved 13 PNG attachments. Its
  offscreen tray images show the centered Cloud Sync empty state and the Home
  fan row in both appearances. They do not prove native menu-bar placement or
  live fan hardware. A passing build alone does not count as an executed test.

## Local Entitlements In Package Builds

- **Symptom:** `make build` stops while packaging the AIManager Swift package.
- **Cause:** A relative command-line `CODE_SIGN_ENTITLEMENTS` path resolves from
  the package checkout, where `powertoys/Local.entitlements` does not exist.
- **Invariant:** Pass the absolute local entitlement path to Xcode for both
  development-signed and ad-hoc builds.
- **Check:** A compile-only Release build succeeds and its resulting app passes
  `codesign --verify --deep --strict` without launching an executable.

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
  then exercise every changed state in the running final binary only when
  desktop interaction is permitted or an isolated account or VM is available.
  Under a focus-preserving request, stop at the compile-only check and report
  the unverified interaction states. Rebuild after any edit following visual QA.
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
  signed runner once in an isolated account or VM, then use live accessibility
  and visual interaction there while reporting the harness limitation. Do not
  retry or use that fallback on the owner's active desktop when focus must stay
  undisturbed.
- **Check:** Inspect the result bundle message. Never report an early runner exit
  as a passing or failing product test.

## Unsigned UI Runner Gatekeeper Dialog

- **Symptom:** macOS reports `powertoysUITests-Runner.app` as damaged and leaves
  a Gatekeeper dialog after the test command stops.
- **Cause:** An app-style UI test runner built with `CODE_SIGNING_ALLOWED=NO` was
  launched. Unit-test execution also launches the MacPowerToys host app and can
  interrupt the owner's desktop.
- **Invariant:** Never launch an unsigned UI runner. Verify the runner with
  `codesign --verify --deep --strict` before launch. If a signed runner cannot
  connect, use live accessibility and visual smoke testing instead.
- **Check:** Confirm no `powertoysUITests-Runner` process exists, dismiss any
  remaining dialog normally only when desktop interaction is permitted, and do
  not claim the system helper was killed when only its dialog was closed. Under
  a focus-preserving request, leave the dialog untouched for the owner.

## Installation Gate

- **Symptom:** A verified source change is reported as done while the installed
  MacPowerToys process still runs an older build.
- **Cause:** The agent stopped after a build or test and skipped the installed
  app replacement and process restart.
- **Invariant:** Read the Cloud Sync transfer state before installation. Never
  replace or relaunch during an active transfer. When clear, commit the clean
  source, stop the running `/Applications` app, run `make install
  ALLOW_INSTALL=1` with task-unique DerivedData, and launch that exact installed
  path in the background. Complete this handoff after every local app code or
  UI change the owner asks to use; do not count a build as installation.
- **Check:** Confirm no active transfer, a fresh installed process ID and exact
  `/Applications` executable path, strict signing, and matching `HEAD`, built,
  installed, and embedded-helper source stamps. If a gate blocks installation,
  report the installed revision and the exact reason instead of claiming the
  latest UI is running.

## Missing Xcode During Final Build

- **Symptom:** The final Release build fails opening an IOKit SDK header even
  though a prior build in the same task succeeded.
- **Cause:** `/Applications/Xcode-beta.app` disappeared while the build was in
  progress. `xcode-select` then pointed to Command Line Tools, which does not
  provide `xcodebuild` for this project.
- **Invariant:** Do not install an older signed product with a stale source
  stamp. Keep the running app and preferences intact until a full Xcode app is
  available, or a hosted build at the clean current `HEAD` can be signed with
  the configured local team. `make install PREBUILT_APP=...` retains the same
  clean-source, source-stamp, helper, signature, and stopped-process gates.
- **Check:** Confirm a full Xcode app path and `xcodebuild -version`, or run
  `sh scripts/check-prebuilt-install.sh` and verify the hosted artifact's source
  stamp and local signature. Run the normal install gate without bringing the
  app forward.
- **Verified fallback:** Hosted run `36129347170` passed and archived commit
  `dc97280`. Local signing kept the app and login helper on team `GF57JXJF5A`;
  `codesign --verify --deep --strict` passed. With zero active transfers,
  `make install PREBUILT_APP=... ALLOW_INSTALL=1` replaced the old app. A new
  `/Applications` process started through `open -g`, and the saved remote host
  remained `oci1`.

## Development Signature Trust Rejection

- **Symptom:** `codesign --verify --deep --strict` passes, but a live
  Security.framework check reports `CSSMERR_TP_NOT_TRUSTED`.
- **Cause:** Structural signature validity and macOS trust evaluation are
  separate checks. The embedded Apple Development certificate may be valid
  while the local trust policy still rejects it.
- **Invariant:** Keep owner-session tests off the desktop and run interaction
  checks on the hosted Mac. Do not inspect or change the owner's Keychain trust.
- **Check:** Confirm the installed app runs from `/Applications`, inspect the
  embedded certificate dates without reading Keychain items, and report live
  interaction as unverified until macOS accepts the local signature.

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
