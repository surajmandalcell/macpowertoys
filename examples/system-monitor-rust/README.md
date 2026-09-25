# Rust monitor example

From this directory, build and try the sample:

```sh
mkdir -p RustMonitor.app/Contents/MacOS RustMonitor.app/Contents/Resources
rustc --edition=2021 -O main.rs -o RustMonitor.app/Contents/MacOS/RustMonitor
cp Info.plist RustMonitor.app/Contents/Info.plist
cp monitor.json RustMonitor.app/Contents/Resources/monitor.json
RustMonitor.app/Contents/MacOS/RustMonitor --macpowertoys-monitor-sample
```

The output reports installed physical RAM. It uses only Rust's standard
library. For distribution, replace the example bundle ID with your own, sign
and notarize the app, zip the single `.app` bundle, and publish an HTTPS
Marketplace catalog entry whose artifact hash, bundle ID, team ID, and
architecture match the archive. The catalog format is in
[`marketplace.schema.json`](../../marketplace.schema.json); a complete example
is in [`valid-catalog.json`](../../spec/marketplace/valid-catalog.json).

See the [plugin contract](../../spec/system-monitor-plugin.md) for the JSON
format and sampling limits. Keep collection short and read only. MacPowerToys
launches the plugin only while its Plugins page is visible.
