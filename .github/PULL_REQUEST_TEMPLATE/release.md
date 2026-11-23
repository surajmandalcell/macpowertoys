Release vX.Y.Z of MacPowerToys. Branch `release/vX.Y.Z`.
Major: breaking change or new paid tier. Minor: features. Patch: fixes only.

## In this PR

- [ ] `VERSION` is X.Y.Z (build number X*10000 + Y*100 + Z, passed by the Makefile)
- [ ] `CHANGELOG.md`: the Unreleased notes moved under `[X.Y.Z] - <date>`
- [ ] Helper `CFBundleVersion` in `NetToysHelper/Info.plist` raised if the helper code changed

## After the merge

- [ ] Tag the merge commit `vX.Y.Z` and push the tag
- [ ] `make release`: build, sign (Developer ID), notarize, and staple the app and DMG
- [ ] GitHub release `vX.Y.Z` with the DMG, its `.sha256`, and `release.json`
- [ ] Homebrew cask `macpowertoys`: version and sha256 in `samhqapp/homebrew-tap`, `brew audit --cask --online`
- [ ] Download link and version on macpowertoys.samhq.app
- [ ] Installed copy updated: `make install ALLOW_INSTALL=1` (no active Cloud Sync transfer)
