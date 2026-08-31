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

## Developer ID release

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
MPT_RELEASE_ROOT=$(mktemp -d /tmp/macpowertoys-release.XXXXXX)
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
