# Changelog

Notable changes are documented here. The project follows semantic versioning after its first stable release.

## [Unreleased]

### Added

- Added Dev Sync to Cloud Sync: Dev One-Way and Dev Bidirectional pairs
  between an internal dev folder and an external drive, with Git-aware
  filtering, sensitive-file backup, managed links for drive-only projects,
  debounced batches, safety retention, and conflict resolution.
- Added Input Devices with separate mouse and trackpad profiles for direction,
  horizontal scrolling, speed, wheel smoothing, and available hardware details.
- Added System Care with storage drill-down, reviewed cleanup to Trash, app
  removal, history, and guided Mole installation and maintenance.
- Added System Monitor with CPU, memory, GPU, disk, network, battery, thermal,
  and load data.
- Added independent System Monitor menu items with saved order, icons, styles,
  update intervals, and metric formats.
- Added NetToys with IP Scanner, SSH Anchor, Network History, and Wi-Fi
  Priority.
- IP Scanner accepts hosts, ranges, CIDR blocks, lists, random targets,
  hostnames, and files. It saves, annotates, filters, and exports results.
- SSH Anchor monitors the selected port, tracks local identity, updates changing
  addresses, and can use a guarded Tailscale fallback.
- Network History records SSID uptime and outages. Wi-Fi Priority manages
  saved-network failover without storing passwords.
- Added None, Combined, and Separate menu-bar placement for Cloud Sync, Awake,
  Color Picker, Text Extractor, and Input Devices.
- Added Raycast launchers for Input Devices, System Care, System Monitor, and
  NetToys.

### Changed

- Replaced the custom Ruler with the behavior and settings from pinned FreeRuler commit `d38ca4f673f16c51485940e63eeee68babfbfeed` under its MIT license.
- Made Ruler Settings and Defaults independent native windows. Added Border
  Opacity, set its default to 25%, and disabled new-ruler shadows.
- Expanded Text Extractor with recognition quality, language correction,
  preferred languages, barcode detection, and a configurable shortcut.
- Changed the default Text Extractor shortcut to Command-Shift-2 and the default
  Color Picker shortcut to Command-Shift-3.
- Renamed Claude History to AI History and separated app activity from recent
  macOS errors and faults in Logs.
- Changed Awake's inactive state to Off and replaced its quick modes with a
  compact segmented control.
- Moved Cloud Sync priority to queued files. Added supported provider folder
  links and menu-bar Pause and Resume controls.
- Standardized launcher and workspace layout, adaptive columns, quiet dividers,
  thin overlay scroll indicators, compact search, rounded tool icons, and clear
  hover and pressed feedback.
- Changed menu-bar left-click to open the popover immediately. Right-click now
  shows only Open MacPowerToys and Quit.

### Fixed

- Fixed Text Extractor region capture on multiple displays, blank selections,
  cancellation, permission recovery, clipboard content, and completion cues.
- Matched native titlebar chrome, traffic-light alignment, focus behavior, and
  compact body spacing across utility windows.
- Fixed window size, position, and display restoration. Added minimum sizes for
  the launcher and workspace windows.
- Changed Command-Q to close only the active sub-app. The launcher now requires
  a second Command-Q before it quits the process.
- Fixed Input Devices scroll control after macOS disables its event tap.
- Fixed NetToys result streaming, scan persistence, MAC address recovery,
  background approval recovery, and SSH host-key identity.
- Fixed SSH Anchor fallback so failed Tailscale probes cannot bypass the local
  recovery delay.
- Fixed Raycast cold launches that showed the main window first and kept local
  extension icons and commands in sync with the installed app.

### Performance

- Reduced Text Extractor recognition latency and avoided screenshot data on the
  clipboard.
- Changed System Monitor to one scheduler with safe update intervals for each
  metric. Detailed sampling runs only while its window is open.
- Stopped unused Cloud Sync daemons, polls, tasks, and volume observers when no
  active transfer, continuous job, launch setting, or window needs them.
- Avoided unchanged menu-item writes and redundant Ruler, Dock icon, and status
  updates.

### Security

- Limited System Care cleanup to approved roots, rejected symbolic links, and
  moved reviewed items to Trash.
- Made SSH Anchor update only the selected `HostName` token with atomic writes,
  private backups, concurrent-change checks, and post-write verification.
- Kept SSH enrollment passwords out of arguments, environment variables,
  configuration, and logs. Added key-only and host-key checks.
- Limited the NetToys MAC helper to trusted MacPowerToys processes and returned
  only requested addresses on the active interface.
- Updated vulnerable Raycast dependencies.

## [1.7.1] - 2026-07-15

### Changed

- Made compact applet titlebars borderless and consistently aligned, with one padded row, compact rounded controls, outline-free initial focus, and app names reclaiming the hidden zoom-button space.
- Reduced the Raycast extension to MacPowerToys and built-in app launchers; separate tool-action commands are no longer exposed.
- Embedded the source commit in local builds and made installation refuse stale DerivedData products.
- Finalized the Text Extractor identity with the Cobalt 051 scanning-text icon.
- Reworked the product README around native transparent window screenshots and a direct macOS download path.

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
