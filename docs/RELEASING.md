# Releasing MacPowerToys

MacPowerToys releases are currently built and verified locally. The repository does not use GitHub Actions for building, signing, or publishing.

## Personal signed build

1. Confirm Cloud Sync has no active transfers.
2. Run `make test` and the UI smoke tests locally.
3. Run `make build`.
4. Verify the result with `codesign --verify --deep --strict`.
5. Quit the installed app, then run `make install ALLOW_INSTALL=1`.
6. Exercise startup, tray behavior, every built-in tool, and quit/relaunch.

Make embeds the source commit in the app and refuses installation if the
worktree is dirty or `HEAD` changes during the build. Do not copy a product
from older DerivedData.

The default build uses the Apple Development identity in the local login keychain for team `GF57JXJF5A`. `ADHOC=1` is the explicit fallback for Macs without that identity. Both modes use `powertoys/Local.entitlements` so Location access works while provisioning-only entitlements, including iCloud, stay omitted and builds do not require automatic profile creation.

An Apple Development signature is for local development. Distribution to other Macs without Gatekeeper warnings requires a paid Apple Developer membership, a Developer ID Application certificate, and Apple notarization.

Do not publish from a dirty worktree. Do not install over a running Cloud Sync transfer.

## Marketplace release checks

- Run `scripts/validate-marketplace-fixtures.py` locally after any change to `marketplace.schema.json` or `spec/marketplace/`.
- Before release, verify a marketplace install end to end with a quarantined, signed, and notarized test archive: checksum mismatch must abort, an unsigned or wrong-team app must be rejected, and update/uninstall must preserve or remove data as documented.
- Verify iCloud settings sync between two Macs signed into the same account: first-enable conflict prompt, propagation of the theme and source list, and that credentials, paths, and histories never appear in the key-value store.
