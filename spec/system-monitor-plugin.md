# System Monitor plugin contract

System Monitor uses the existing Marketplace installer. A monitor plugin is a
signed, notarized macOS app with one extra file at
`Contents/Resources/monitor.json`. Users add the publisher's HTTPS Marketplace
catalog in App Settings, install the app, then open System Monitor > Plugins.
The Marketplace checks the archive hash, signing team, notarization, bundle ID,
and architecture before installation. A plugin can be written in Rust, Swift,
Go, C, or any language that produces a macOS executable.

`monitor.json` is UTF-8 JSON, at most 16 KiB:

```json
{
  "formatVersion": 1,
  "metrics": [
    { "id": "physical-memory", "title": "Physical memory" }
  ]
}
```

Metric IDs use lowercase letters, digits, and hyphens, start with a letter or
digit, and have at most 64 characters. Titles have 1 to 60 characters. One
plugin may declare up to 16 distinct metrics.

When the Plugins page is visible, MacPowerToys runs the app's
`CFBundleExecutable` with one argument, `--macpowertoys-monitor-sample`. The
process must finish within 5 seconds, write one JSON object on standard output,
and exit 0. The response is at most 16 KiB:

```json
{
  "formatVersion": 1,
  "values": {
    "physical-memory": {
      "value": "16 GB",
      "detail": "Installed RAM"
    }
  }
}
```

`value` has 1 to 80 characters; optional `detail` has at most 100. Both are
single-line display text. Unknown metric IDs and invalid responses show an
error. Missing metric IDs show "No reading" after the first sample.
MacPowerToys samples one plugin at a time. It pauses 30 seconds after each
complete pass by default; the user can choose 15 or 60 seconds. Leaving the
page cancels the active process and all further sampling. Plugins run with the
current user's permissions. Install only publishers you trust.

The [Rust example](../examples/system-monitor-rust/README.md) builds a working
plugin and describes how to package it for a Marketplace catalog.
