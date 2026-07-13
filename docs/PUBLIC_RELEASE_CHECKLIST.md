# Public release checklist

Complete this once before making the repository public.

## Repository

- Confirm `git status` contains only intentional files.
- Scan the full Git history for credentials, private paths, transfer names, conversation content, logs, and screenshots.
- The previously tracked files under `docs/screenshots/` contained local UI data. Their deletion from the current tree does not remove them from Git history. Create a clean public repository or explicitly approve a history rewrite before publication.
- Enable GitHub private vulnerability reporting, secret scanning, Dependabot alerts, and branch protection for `main`.
- Add repository topics, a social preview, the project description, and the privacy and security links.

## Verification

- Confirm macOS unit, rclone integration, and UI smoke jobs pass on GitHub Actions.
- Run the complete suite on a clean supported Mac account.
- Verify every tool's Dock icon in light and dark appearance at 32 px and full Dock size.
- Verify both `macpowertoys://` and legacy `powertoys://` links.
- Test at least one OAuth remote and one key-based or configuration-only rclone remote.
- Test pause and restart with a backend that supports partial continuation and one that restarts the active object.
- Run `npm run lint:store` after adding the owner's valid Raycast username.

## Distribution

- Configure the six GitHub Actions secrets documented in `RELEASING.md`.
- Confirm hardened runtime, Developer ID signature, notarization, stapling, and SHA-256 verification.
- Verify the archive on a clean account before publishing the tag.
- Publish explicit pre-release limitations and recovery instructions.

Never replace or relaunch an installed MacPowerToys build while Cloud Sync is actively transferring data.
