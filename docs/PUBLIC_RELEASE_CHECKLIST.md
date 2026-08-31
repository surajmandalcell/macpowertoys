# Public release checklist

Track these gates before the next public binary release. The repository is
already public at `surajmandalcell/macpowertoys`.

## Repository

- [ ] Confirm `git status` contains only intentional files.
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
  protection, and Dependabot security updates.
- [ ] Protect `main`. The GitHub API reported no branch protection on
  2026-08-31.
- [x] Add repository topics, the project description, and README privacy and
  security links.
- [ ] Verify the GitHub social preview.

## Verification

- Run macOS unit, rclone integration, and UI smoke tests locally.
- Run the complete suite on a clean supported Mac account.
- Verify every tool's Dock icon in light and dark appearance at 32 px and full Dock size.
- Verify both `macpowertoys://` and legacy `powertoys://` links.
- Test at least one OAuth remote and one key-based or configuration-only rclone remote.
- Test pause and restart with a backend that supports partial continuation and one that restarts the active object.
- [x] Run the Raycast Store lint with the owner's valid username. The package
  uses `surajmandalcell`, and `npm --prefix raycast run lint:store` passed on
  2026-08-31.

## Distribution

- Enroll in the paid Apple Developer Program before preparing a public binary.
- Create a Developer ID Application certificate and an entitlement-compatible provisioning profile.
- Confirm hardened runtime, Developer ID signature, notarization, stapling, and SHA-256 verification.
- Verify the archive on a clean account before publishing the tag.
- Publish explicit pre-release limitations and recovery instructions.

Never replace or relaunch an installed MacPowerToys build while Cloud Sync is actively transferring data.
