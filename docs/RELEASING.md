# Releasing MacPowerToys

1. Confirm unit, integration, UI smoke, and Raycast checks are green.
2. Update `CHANGELOG.md`, `MARKETING_VERSION`, and `CURRENT_PROJECT_VERSION`.
3. Archive a Release build with hardened runtime enabled.
4. Sign with a Developer ID Application certificate.
5. Submit the archive to Apple's notary service and staple the accepted ticket.
6. Package `MacPowerToys.app` in a versioned zip and generate a SHA-256 checksum.
7. Verify the packaged app on a clean supported macOS account.
8. Tag the exact commit and publish the zip, checksum, changelog excerpt, privacy link, and minimum macOS requirement.

The `Release` GitHub Actions workflow performs signing, notarization, stapling, packaging, checksum generation, and GitHub Release publication for `v*` tags. Configure these repository secrets before tagging:

- `MACOS_CERTIFICATE_P12`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`

Do not publish from a dirty worktree. Do not install over a running Cloud Sync transfer.

## iCloud entitlement

The app now carries the `com.apple.developer.ubiquity-kvstore-identifier` entitlement for iCloud settings sync. Developer ID signing therefore needs a Developer ID provisioning profile that includes iCloud key-value storage for `com.surajmandal.macpowertoys`. Unsigned CI builds (`CODE_SIGNING_ALLOWED=NO`) are unaffected.

For local signed builds, sign into Xcode > Settings > Accounts once, then run `make build SIGNED=1` — automatic signing generates the development profile with the iCloud capability. iCloud sync silently no-ops in unsigned builds.

## Marketplace release checks

- Run `scripts/validate-marketplace-fixtures.py` (CI does this) after any change to `marketplace.schema.json` or `spec/marketplace/`.
- Before release, verify a marketplace install end to end with a quarantined, signed, and notarized test archive: checksum mismatch must abort, an unsigned or wrong-team app must be rejected, and update/uninstall must preserve or remove data as documented.
- Verify iCloud settings sync between two Macs signed into the same account: first-enable conflict prompt, propagation of the theme and source list, and that credentials, paths, and histories never appear in the key-value store.
