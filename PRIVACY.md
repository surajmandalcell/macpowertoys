# Privacy

MacPowerToys has no first-party analytics, advertising SDK, or telemetry service.

## Local data

MacPowerToys stores settings, utility history, logs, transfer state, and indexes under the user's macOS Application Support and Preferences locations. Text Extractor processes the selected screenshot with Apple Vision on the Mac. Color Picker stores sampled colors locally.

Claude History reads local Claude Code JSONL files and builds a local cache for browsing and search. Export occurs only when the user requests it.

## Network access

Cloud Sync uses rclone. rclone and the configured storage provider may make network requests for OAuth, directory listings, and file transfers. Provider credentials are stored in rclone's local configuration according to rclone's behavior.

The optional Raycast extension sends only local `macpowertoys://` commands to the app.

## Permissions

- Screen Recording: required for Text Extractor to capture the selected region.
- User-selected file access is used for local transfer sources and destinations.

MacPowerToys does not sell personal information.
