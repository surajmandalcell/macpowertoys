# Release and local installation

Never replace or relaunch the installed app while Cloud Sync has an active transfer.

After every verified code or UI change, build and replace
`/Applications/MacPowerToys.app` before handoff. This rule is standing approval
for local installation. If a Cloud Sync transfer is active, leave the installed
app untouched and report the blocked installation explicitly. Use computer
control for any required launch or inspection, and preserve the owner's current
focus.

Use `make install ALLOW_INSTALL=1` for local replacement. The build embeds its
source commit, and the installer must refuse the product if the worktree is
dirty or `HEAD` changed while it was building. Never copy an older DerivedData
product into Applications.

For a release checkpoint:

1. Run the unit and integration suite in isolated DerivedData.
2. Run UI smoke tests only when no installed transfer is active.
3. Validate the Raycast extension with `npm ci`, lint, and build.
4. Update the changelog and semantic version.
5. Commit the verified checkpoint.
6. Build Release with hardened runtime, then sign, notarize, staple, package, and checksum it with the Developer ID procedure below.
7. Install the verified build when no Cloud Sync transfer is active. Use
   computer control for a required launch only when it can preserve the owner's
   focus.

Pause and restart preserve completed files. The active file resumes only when its rclone backend supports it; otherwise that file restarts.

## Personal signed build checks

1. Confirm Cloud Sync has no active transfers.
2. Build and test locally; GitHub CI runs only on manual dispatch (owner
   decision 2026-10-01: CI minutes run out). Run unit tests on the owner's
   Mac with `tmp/redesign/tools/xtest.sh` only while no game or full-screen
   app is in front. It aborts the run if the front app changes. UI tests
   still need a separate macOS account. Never use a VM.
3. Run `make build`.
4. Verify the result with `codesign --verify --deep --strict`.
5. Quit the installed app, then run `make install ALLOW_INSTALL=1`.
6. Exercise startup, tray behavior, every built-in tool, and quit/relaunch.

Make embeds the source commit in the app and refuses installation if the
worktree is dirty or `HEAD` changes during the build. Do not copy a product
from older DerivedData.

The default build uses the Apple Development identity in the local login keychain for team `GF57JXJF5A`. `ADHOC=1` is the explicit fallback for Macs without that identity. Both modes use `powertoys/Local.entitlements` so Location access works while provisioning-only entitlements, including iCloud, stay omitted and builds do not require automatic profile creation.

An Apple Development signature is for local development. Distribution to other Macs without Gatekeeper warnings requires a paid Apple Developer membership, a Developer ID Application certificate, and Apple notarization.

## Developer ID release procedure

Apple requires a Developer ID Application signature and notarization for direct
macOS distribution. The Account Holder must first create or enable the
Developer ID certificate. Store notarization credentials once in Keychain:

```sh
xcrun notarytool store-credentials MacPowerToysNotary
```

Do not put the Apple ID password, app-specific password, issuer ID, or API key
in this repository. Confirm that Cloud Sync has no active transfer and that
`git status --porcelain` is empty. Then archive and export the app:

```sh
mkdir -p tmp/release
MPT_RELEASE_ROOT=$(mktemp -d "$PWD/tmp/release/macpowertoys.XXXXXX")
MPT_ARCHIVE="$MPT_RELEASE_ROOT/MacPowerToys.xcarchive"
MPT_EXPORT="$MPT_RELEASE_ROOT/export"
MPT_EXPORT_OPTIONS="$MPT_RELEASE_ROOT/ExportOptions.plist"
MPT_SOURCE_COMMIT=$(git rev-parse HEAD)

plutil -create xml1 "$MPT_EXPORT_OPTIONS"
plutil -insert method -string developer-id "$MPT_EXPORT_OPTIONS"
plutil -insert signingStyle -string automatic "$MPT_EXPORT_OPTIONS"
plutil -insert teamID -string GF57JXJF5A "$MPT_EXPORT_OPTIONS"

xcodebuild -project powertoys.xcodeproj -scheme powertoys \
  -configuration Release -archivePath "$MPT_ARCHIVE" \
  -allowProvisioningUpdates MPT_SOURCE_COMMIT="$MPT_SOURCE_COMMIT" archive

xcodebuild -exportArchive -archivePath "$MPT_ARCHIVE" \
  -exportPath "$MPT_EXPORT" -exportOptionsPlist "$MPT_EXPORT_OPTIONS" \
  -allowProvisioningUpdates
```

Confirm that the exported app contains the expected commit and Developer ID
signature. Then create and notarize the disk image:

```sh
MPT_APP="$MPT_EXPORT/MacPowerToys.app"
MPT_DMG="$MPT_RELEASE_ROOT/MacPowerToys.dmg"

test "$(plutil -extract MPTSourceCommit raw "$MPT_APP/Contents/Info.plist")" \
  = "$MPT_SOURCE_COMMIT"
codesign --verify --deep --strict --verbose=2 "$MPT_APP"
codesign -dv --verbose=4 "$MPT_APP" 2>&1 \
  | grep 'Authority=Developer ID Application'

hdiutil create -volname MacPowerToys -srcfolder "$MPT_APP" \
  -format UDZO -ov "$MPT_DMG"
xcrun notarytool submit "$MPT_DMG" \
  --keychain-profile MacPowerToysNotary --wait
xcrun stapler staple "$MPT_DMG"
xcrun stapler validate "$MPT_DMG"
spctl -a -vv -t open --context context:primary-signature "$MPT_DMG"
shasum -a 256 "$MPT_DMG"
```

Mount the final disk image on a clean account. Verify the embedded app with
`codesign --verify --deep --strict` and `spctl -a -vv -t execute` before
publishing the version tag or release asset.

References: [Apple Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
[Apple Gatekeeper signing and notarization](https://developer.apple.com/developer-id/).

Do not publish from a dirty worktree. Do not install over a running Cloud Sync transfer.

## Marketplace release checks

- Run `scripts/validate-marketplace-fixtures.py` locally after any change to `marketplace.schema.json` or `spec/marketplace/`.
- Before release, verify a marketplace install end to end with a quarantined, signed, and notarized test archive: checksum mismatch must abort, an unsigned or wrong-team app must be rejected, and update/uninstall must preserve or remove data as documented.
- Verify iCloud settings sync between two Macs signed into the same account: first-enable conflict prompt, propagation of the theme and source list, and that credentials, paths, and histories never appear in the key-value store.

## Public release gates

The repository is public. Version 1.8.0 was released on 2026-09-21 as an
owner-approved Apple Development testing build. Its release notes disclose
that it is not notarized. Those checks do not certify the current source.

Before each release:

- Confirm the tree is clean. Scan history for credentials and private UI data.
  Old `cc_history1.png`, `cc_history2.png`, and `logs.png` blobs expose private
  data. Removing current files does not remove those blobs. A clean repository
  or an owner-approved history rewrite is still required.
- Check repository links, topics, privacy and security links, social preview,
  private vulnerability reporting, secret scanning, push protection,
  Dependabot, and branch protection. Use the current tool registry for the
  README, marketplace schema, and route matrix. Exclude removed AI History.
- Run the complete suite in hosted CI or a clean supported account. Inspect
  every current tool's Dock icon in Light and Dark at 32px and full size.
  Check both `macpowertoys://` and legacy `powertoys://` routes.
- Verify an OAuth remote and a key-based or configuration-only remote with
  disposable round trips. Check hashes and remove test stores. Test Pause
  and Resume with backends that retain completed files and restart the active
  file. Do not claim byte-level rclone resume across stopped jobs.
- Run Raycast Store lint and all seven marketplace fixtures. Verify a real
  quarantined, signed, notarized marketplace install and two-Mac iCloud sync.
- For a warning-free binary, use a paid Apple Developer membership, Developer
  ID Application certificate, compatible provisioning, hardened runtime,
  notarization, stapling, and a SHA-256 checksum. Check the archive on a clean
  account before publishing. Development-signed test releases need explicit
  owner approval and visible Gatekeeper and notarization limitations.

Prior evidence: the 2026-08-31 Gitleaks 8.30.1 history scan had zero findings.
The 1.8.1 source gate passed 808 tests with five skips and zero failures,
strict app/helper signatures, Raycast checks, and all marketplace fixtures.
This evidence applies only to those revisions. Current redesign checks remain
in the request lists and `spec/troubleshoot/verification.md`.
