# Changelog

Notable changes are documented here. The project follows semantic versioning after its first stable release.

## Unreleased

### Added

- MacPowerToys product identity with copy-only migration from PowerToys data.
- Cloud Sync provider discovery for the connector catalog exposed by rclone.
- Authenticated loopback rclone control API with per-launch random credentials.
- Five-stage transfer priorities and persistent transfer-row expansion.
- Uploaded and not-uploaded split view with persistent ignore visibility controls.
- Public contribution, security, privacy, CI, and release documentation.

### Changed

- Renamed the RSync utility to Cloud Sync.
- Preserved both `macpowertoys://` and legacy `powertoys://` deep links.
- Made pause and recovery progress exclude uncommitted bytes from an active file.
- Prevented the new app identity from migrating or resuming work while legacy PowerToys is still running.

### Security

- Removed unauthenticated access to the local rclone remote-control server.
- Preserved existing rclone credentials when reconnect setup is cancelled or the app closes.
