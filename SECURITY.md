# Security Policy

## Supported versions

Security fixes are applied to the latest release and the current `main` branch.

## Reporting a vulnerability

Please use GitHub's private **Report a vulnerability** form in the repository Security tab. Do not open a public issue for an unpatched vulnerability or include credentials, OAuth tokens, private file paths, or personal conversation data in a report.

Include the affected version, macOS version, impact, reproduction steps, and a minimal proof of concept when possible. You should receive an acknowledgement within seven days.

## Security boundaries

- The rclone remote-control server binds to loopback and uses a random per-launch credential.
- rclone configuration files contain provider credentials and must be protected like login secrets.
- Text Extractor requires Screen Recording permission because it captures a user-selected screen region.
- Claude History reads local Claude Code data chosen by the application's documented discovery rules.

Never attach a real rclone config, Claude history file, transfer log, or screenshot containing private data to a public issue.
