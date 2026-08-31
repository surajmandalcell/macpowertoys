# Public release checklist

Track these gates before the next public binary release. The repository is
already public at `surajmandalcell/macpowertoys`.

## Repository

- [x] Confirm `git status` contains only intentional files. The tree was clean
  after the 2026-08-31 combined suite.
- [x] Scan the full Git history for credentials. Gitleaks 8.30.1 found zero
  findings on 2026-08-31.
- [ ] Remove private UI data from public history. Old versions of
  `cc_history1.png`, `cc_history2.png`, and `logs.png` expose local
  conversations, identifiers, and a home path. Normal commits cannot remove
  these blobs. Create a clean repository or explicitly approve a history
  rewrite and force-push.
- [x] Use the current `macpowertoys` repository name in badges, clone URLs,
  schema IDs, security links, and release links. A repository search found no
  old public repository URL on 2026-08-31.
- [x] List all 11 built-in tools in the README and marketplace schema. On
  2026-08-31, both lists matched `ToolRegistry.builtInTools`.
- [x] Enable private vulnerability reporting, secret scanning, push
  protection, and Dependabot security updates. The GitHub API confirmed all
  four settings again on 2026-08-31.
- [x] Protect `main`. On 2026-08-31, the GitHub API confirmed that protection
  applies to administrators, force-push and deletion are disabled, and normal
  fast-forward pushes need no pull request, review, or status check.
- [x] Add repository topics, the project description, and README privacy and
  security links.
- [x] Verify the GitHub social preview. The live 1,200 by 600 repository card
  was readable and contained no private app data on 2026-08-31.

## Verification

- [x] Run local unit, rclone, and signed UI smoke checks. On 2026-08-31,
  543 of 543 tests passed, a controlled local rclone transfer passed, and the
  signed app completed 275 sub-app open and close cycles without an error.
- [x] Validate all seven marketplace fixtures. The executable pinned `uv`
  validator passed all seven fixtures on 2026-08-31.
- [ ] Run the complete suite on a clean supported Mac account.
- [ ] Verify every tool's Dock icon in light and dark appearance at 32 px and
  full Dock size. All 13 current light and dark source variants render as
  valid 32 by 32 images. The live Dock appearance still needs inspection.
- [x] Verify both `macpowertoys://` and legacy `powertoys://` links. In exact
  installed build `327ebb1`, both schemes opened the main window. One
  background matrix opened all 11 sub-app windows through each scheme; the
  WindowServer showed the expected AI History, Cloud Sync, Logs, Ruler,
  Awake, Color Picker, Text Extractor, Input Devices, System Care, System
  Monitor, and NetToys windows without bringing the app forward.
- [ ] Test at least one OAuth remote and one key-based or configuration-only
  rclone remote.
- [ ] Test pause and restart with a backend that supports partial continuation
  and one that restarts the active object.
- [x] Run the Raycast Store lint with the owner's valid username. The package
  uses `surajmandalcell`, and `npm --prefix raycast run lint:store` passed on
  2026-08-31.

## Distribution

- [ ] Enroll in the paid Apple Developer Program before preparing a public
  binary.
- [ ] Create a Developer ID Application certificate and an
  entitlement-compatible provisioning profile.
- [ ] Confirm the hardened runtime, Developer ID signature, notarization,
  stapling, and SHA-256 verification. Gatekeeper rejected the current Apple
  Development build as expected on 2026-08-31.
- [ ] Verify the archive on a clean account before publishing the tag.
- [ ] Publish explicit pre-release limitations and recovery instructions.

Never replace or relaunch an installed MacPowerToys build while Cloud Sync is actively transferring data.
