# Contributing

Thanks for helping improve MacPowerToys.

## Before starting

1. Search existing issues and pull requests.
2. Open an issue before a large feature or architecture change.
3. Keep changes focused and avoid unrelated formatting or generated files.

## Local setup

Requirements are macOS 26.2, Xcode 26.2, and rclone for Cloud Sync integration tests.

```bash
brew install rclone
git clone https://github.com/surajmandalcell/powertoys.git
cd powertoys
xcodebuild build-for-testing \
  -project powertoys.xcodeproj \
  -scheme powertoys \
  -derivedDataPath /tmp/macpowertoys-derived \
  CODE_SIGNING_ALLOWED=NO
```

For the Raycast extension:

```bash
cd raycast
npm ci
npm run lint
npm run build
```

`npm run lint` validates source and formatting without requiring a Raycast account. Store submission additionally requires the owner's Raycast username in `raycast/package.json` and a successful `npm run lint:store`, which also validates store metadata and icons.

## Pull requests

- Add or update tests for behavior changes.
- Do not include real user paths, credentials, logs, conversation content, or cloud data.
- Update `CHANGELOG.md` for user-visible changes.
- Keep user-facing names as `MacPowerToys` and `Cloud Sync`; internal compatibility identifiers may remain unchanged.
- Confirm that no running Cloud Sync transfer is interrupted during manual testing.

By contributing, you agree that your contribution is licensed under the MIT License.
