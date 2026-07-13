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

## Tests and coverage

`make build-for-testing` compiles the app and every test target without launching the app. Run `make test` when no important Cloud Sync transfer is active; macOS unit tests launch an isolated app test host.

Pull requests run unit tests, local rclone integration tests, and UI smoke tests in clean GitHub runners. CI reports line coverage for `Core`, `Models`, and `Services` and rejects changes below the current 25% floor. SwiftUI `body` generation is intentionally excluded from this business-logic metric; user flows are protected by the separate UI smoke job.

Tests should assert observable behavior at a public or internal module seam. Prefer exhaustive state/enum tables and boundary cases over tests coupled to private methods. Every bug fix should include a test that fails before the fix.

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
