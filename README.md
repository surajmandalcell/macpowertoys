# MacPowerToys

<p align="center">
  <img src="docs/appicon.svg" width="128" height="128" alt="MacPowerToys icon">
</p>

MacPowerToys is an open-source collection of focused, native macOS utilities. Each tool has its own window and Dock icon, and the utility commands are individually searchable through Raycast and Apple Shortcuts.

[![macOS CI](https://github.com/surajmandalcell/powertoys/actions/workflows/ci.yml/badge.svg)](https://github.com/surajmandalcell/powertoys/actions/workflows/ci.yml)

> [!IMPORTANT]
> MacPowerToys is currently pre-release software. Build it from source and keep a backup of important data.

## Tools

| Tool | What it does |
|---|---|
| Ruler | Floating horizontal, vertical, and joined rulers, calibrated units, guides, region measurement, and developer copy formats. |
| Awake | Keeps the Mac or display awake indefinitely, for a duration, until a time, or while a process runs. |
| Color Picker | Samples screen colors, copies common developer formats, and keeps searchable, pinnable local history. |
| Text Extractor | Captures a selected screen region and recognizes text locally with Apple Vision. |
| Cloud Sync | Runs local and cloud copy, move, and sync jobs through rclone, with persistent progress, retries, priorities, ignore rules, and remote browsing. |
| Claude History | Browses, searches, and exports local Claude Code JSONL conversation history. |
| Logs | Searches and filters MacPowerToys diagnostic logs. |

## Requirements

- macOS 26.2 or newer
- Xcode 26.2 or newer for source builds
- [rclone](https://rclone.org/install/) for Cloud Sync
- Raycast only if you want the optional Raycast commands

Install rclone with Homebrew:

```bash
brew install rclone
```

## Build from source

```bash
git clone https://github.com/surajmandalcell/powertoys.git
cd powertoys
xcodebuild -project powertoys.xcodeproj \
  -scheme powertoys \
  -configuration Debug \
  build
```

You can also open `powertoys.xcodeproj` in Xcode and run the `powertoys` scheme. The built product is `MacPowerToys.app`.

Do not replace a running installation while Cloud Sync is transferring data. Pause or finish transfers first, then install the new build.

## Raycast

The `raycast` directory contains separate Root Search commands for Ruler, Awake, Color Picker, and Text Extractor actions.

```bash
cd raycast
npm ci
npm run build
```

Import the `raycast` directory through Raycast's **Import Extension** command. Commands use the `macpowertoys://` URL scheme. The legacy `powertoys://` scheme remains supported.

## Privacy and security

- Text extraction uses Apple's on-device Vision framework. Selected screenshots are not uploaded by MacPowerToys.
- Color history, logs, settings, transfer state, and Claude History indexes stay in the user's local Application Support directory.
- Cloud Sync credentials are managed by rclone in its local config. MacPowerToys protects its loopback rclone control API with a fresh random credential for every launch.
- Cloud providers and rclone itself may communicate with their own services during transfers and OAuth.

See [Privacy](PRIVACY.md) and [Security Policy](SECURITY.md) for details.

## Cloud Sync behavior

Cloud Sync preserves completed-file progress across pause, quit, and relaunch. Byte-level continuation of the currently active cloud object depends on the rclone backend; some providers must restart that one file. Priority changes reorder queued transfers without interrupting an active file.

The Add Connector sheet reads rclone's provider catalog at runtime, so it supports the connector types included by the installed rclone version instead of maintaining a hard-coded provider list.

## Architecture

```text
powertoys/
├── Core/                  App lifecycle, routing, persistence, shortcuts
├── Models/                Tool and transfer domain models
├── Services/              Native services and rclone integration
├── Views/                 SwiftUI windows grouped by tool
└── Assets.xcassets/       Appearance-aware app and tool icons
powertoysTests/             Unit and local integration tests
powertoysUITests/           UI smoke tests
raycast/                    Companion Raycast extension
```

Tools implement the internal `Tool` protocol and register with `ToolRegistry`. This is an internal module boundary, not an external plug-in API.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. By participating, you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

MacPowerToys is available under the [MIT License](LICENSE).
