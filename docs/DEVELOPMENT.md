# Development

## Build

You need macOS 26.2 or later, Xcode 26.2 or later, and
[rclone](https://rclone.org/install/) for Cloud Sync.

```bash
brew install rclone
make build                 # signed with the Apple Development identity
make build ADHOC=1         # ad hoc signature on a Mac without that identity
make build-for-testing     # compiles the app and test bundles, launches nothing
```

You can also open `powertoys.xcodeproj` and run the `powertoys` scheme.
Executable tests launch the app as a test host. Run them with
`TEST_SESSION=isolated make test` while nothing you need is in front.
Release, signing, and installation steps are in [`.agents/rules/release.md`](../.agents/rules/release.md).

Personal-team signing works on the signing Mac. Public, warning-free
distribution needs Developer ID signing and Apple notarization.

## Packages

| Package | Repository | Used for |
| --- | --- | --- |
| OnePlusUI | [surajmandalcell/oneplus-ui](https://github.com/surajmandalcell/oneplus-ui) | Every window, page, card, control, and menu panel |
| NetToys | [surajmandalcell/nettoys](https://github.com/surajmandalcell/nettoys) | The NetToys tool, shared with the standalone app |
| Switch Core | [surajmandalcell/switch](https://github.com/surajmandalcell/switch) | Account switching and usage for the Switch tool |

Each package is pinned to an exact version tag in
`powertoys.xcodeproj/project.pbxproj`. To update one, tag a new version in its
repository, change the exact version here, resolve, review
`Package.resolved`, and run the tests.

## Switch integration

MacPowerToys uses `AIManagerCore` from the Switch repository. The two apps
have separate interfaces and share Core's data paths and its cross-process
operation lock. Conversation browsing and cleanup stay in standalone Switch.
The menu panel supports quick switching and on-demand usage refresh without
background polling.

Existing `~/Library/Application Support/AI Manager` data keeps its path for
compatibility. Updating Switch.app does not update Core inside MacPowerToys.
Tests use a disposable `AI_MANAGER_ROOT` and never read real auth files or the
Keychain.

## Tool lifetime

Each tool keeps its own window and saved state. Windows restore their display
and position before they appear. Heavy work runs only while a window or panel
needs it. Optional menu bar summaries and enabled background features keep
their own lifetimes.

## Cloud Sync and rclone

Provider credentials and remote configuration stay under rclone's control.
Every transfer is planned with a dry run before data moves. Completed progress
survives relaunches, **Recalculate** adds only newly found work, and each
transfer keeps its latest 100 local changes. Never replace a running
installation during a transfer.

## Raycast

Import the `raycast` directory into Raycast. The extension opens the launcher
and supported tools. `make install` rebuilds and reloads it.
