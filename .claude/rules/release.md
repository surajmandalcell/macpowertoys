# Release and local installation

Never replace or relaunch the installed app while Cloud Sync has an active transfer.

After every verified code or UI change, build, replace, and relaunch
`/Applications/MacPowerToys.app` before handoff. This rule is standing approval
for local installation. If a Cloud Sync transfer is active, leave the installed
app untouched and report the blocked installation explicitly.

For a release checkpoint:

1. Run the unit and integration suite in isolated DerivedData.
2. Run UI smoke tests only when no installed transfer is active.
3. Validate the Raycast extension with `npm ci`, lint, and build.
4. Update the changelog and semantic version.
5. Commit the verified checkpoint.
6. Build Release with hardened runtime, then sign, notarize, staple, package, and checksum it according to `docs/RELEASING.md`.
7. Install and relaunch the verified build when no Cloud Sync transfer is active.

Pause and restart preserve completed files. The active file resumes only when its rclone backend supports it; otherwise that file restarts.
