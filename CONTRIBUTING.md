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
git clone https://github.com/surajmandalcell/macpowertoys.git
cd macpowertoys
make build-for-testing DERIVED_DATA=/tmp/macpowertoys-build-tests
```

## Local verification

Hosted macOS workflows run the unit, package, and UI checks. On the owner's
desktop, compile only. Run executable tests in hosted CI or a separate macOS
account or VM. Use these checks before you open a pull request:

```bash
make build-for-testing DERIVED_DATA=/tmp/macpowertoys-build-tests
TEST_SESSION=isolated make test DERIVED_DATA=/tmp/macpowertoys-tests
make build ADHOC=1 DERIVED_DATA=/tmp/macpowertoys-release
```

`make build-for-testing` compiles the app and all test targets without launching the app. `make test` runs the macOS unit and integration target. Do not run tests during an important Cloud Sync transfer.

For UI changes, open a signed current build and test each affected flow. Never launch an unsigned UI test runner.

Tests should assert observable behavior at a public or internal module seam. Prefer exhaustive state/enum tables and boundary cases over tests coupled to private methods. Every bug fix should include a test that fails before the fix.

For the Raycast extension:

```bash
cd raycast
npm ci
npm run lint
npm run build
```

`npm run lint` validates source and formatting without requiring a Raycast account. Store submission additionally requires the owner's Raycast username in `raycast/package.json` and a successful `npm run lint:store`, which also validates store metadata and icons.

## Releases

Follow [.agents/rules/release.md](.agents/rules/release.md) for local build
checks, Developer ID packaging, notarization, and public release gates.

## Pull requests

- Add or update tests for behavior changes.
- Do not include real user paths, credentials, logs, conversation content, or cloud data.
- Update `CHANGELOG.md` for user-visible changes.
- Keep user-facing names as `MacPowerToys` and `Cloud Sync`; internal compatibility identifiers may remain unchanged.
- Confirm that no running Cloud Sync transfer is interrupted during manual testing.

By contributing, you agree that your contribution is licensed under the MIT License.
