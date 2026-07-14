# Changelog

Notable changes are documented here. The project follows semantic versioning after its first stable release.

## Unreleased

### Changed

- Made compact applet titlebars borderless and consistently aligned, with one padded row, compact rounded controls, outline-free initial focus, and app names reclaiming the hidden zoom-button space.
- Reduced the Raycast extension to MacPowerToys and built-in app launchers; separate tool-action commands are no longer exposed.
- Embedded the source commit in local builds and made installation refuse stale DerivedData products.

## [1.7.0] - 2026-07-14

### Added

- Marketplace for installing independently signed, notarized companion tools from user-added catalog sources, with a public catalog schema (`marketplace.schema.json`), checksum and Developer ID/notarization verification, atomic install with rollback, and two-tier source removal.
- Tabbed App Settings sheet with General, Marketplace, and About tabs.
- Optional iCloud settings sync for an explicit allowlist of preferences, marketplace source URLs, and opt-in host-managed tool settings, with a first-enable conflict prompt.
- MacPowerToys product identity with copy-only migration from PowerToys data.
- Cloud Sync provider discovery for the connector catalog exposed by rclone.
- Authenticated loopback rclone control API with per-launch random credentials.
- Persistent transfer-row expansion.
- Uploaded and not-uploaded split view with persistent ignore visibility controls.
- A latest-100 local change audit for every Cloud Sync transfer, with added, edited, moved, and removed file events.
- Optional continuous Cloud Sync runs that rescan after a configurable quiet interval.
- An explicit rclone dry-run Recalculate action for checking new remaining work without replacing completed progress.
- Paired horizontal and vertical rulers with sharp corners and right-click group or ungroup controls.
- Public contribution, security, privacy, CI, and release documentation.

### Changed

- Renamed the RSync utility to Cloud Sync.
- Preserved both `macpowertoys://` and legacy `powertoys://` deep links.
- Made pause and recovery progress exclude uncommitted bytes from an active file.
- Prevented the new app identity from migrating or resuming work while legacy PowerToys is still running.
- Matched Cloud Sync byte labels to macOS decimal storage units and kept recalculated plans monotonic: totals only grow when rclone finds new work.
- Removed the misleading transfer-level priority control because rclone does not expose safe reprioritization for an active file, and compacted transfer progress, ETA, direction, and comparison status.
- Unified utility-window insets, translucent titlebar/body material, compact sizing, card hover treatment, and thin overlay scroll indicators.
- Enforced one running MacPowerToys process and one window per utility while still allowing multiple ruler overlays.
- Moved Color Picker settings into a focused view and added a confirmed clear-all action that preserves projects.
- Moved Text Extractor recognition settings to an unobtrusive floating control while keeping extraction as the primary titlebar action.
- Credited rclone in Cloud Sync About and documentation.

### Fixed

- Prevented destination-folder contents and resumed bytes from inflating a transfer plan beyond the source data.
- Restored the Cloud Sync transfer Changes tab and aligned its tab strip with the detail content.
- Removed excess top spacing from Logs and clipped top content from compact utility windows.
- Aligned the launcher card grid with the sidebar search field.

### Security

- Removed unauthenticated access to the local rclone remote-control server.
- Preserved existing rclone credentials when reconnect setup is cancelled or the app closes.
