# Build and share a MacPowerToys tool

MacPowerToys plugins are independent macOS apps listed in Marketplace. A tool
can be written in Swift, Rust, or any language that produces a macOS `.app`
bundle. System Monitor does not load tool code or metric plugins.

1. Build a working app bundle with a unique bundle identifier. Include the
   architectures you intend to list. A Rust app can use a Rust macOS GUI
   framework; the host only needs its finished `.app` bundle.
2. Sign and notarize the complete app with your Developer ID. Put exactly one
   `.app` at the root of a ZIP archive and publish the ZIP over HTTPS, such as
   a GitHub Release asset.
3. Calculate the archive SHA-256 and create a catalog from
   [the valid example](../spec/marketplace/valid-catalog.json). Replace its
   example values with your tool's ID, name, description, icon URL, version,
   build, minimum versions, archive URL, SHA-256, bundle ID, signing Team ID,
   and architectures. The [schema](../marketplace.schema.json) defines every
   field and the supported categories. Increase `build` for each update.
4. Publish the catalog JSON at a raw GitHub HTTPS URL. In MacPowerToys, open
   Settings > Marketplace, paste that URL into Add Source, then install the
   tool. Share the catalog URL with other users so they can add the same source.

Marketplace checks the archive hash, app bundle ID, signing Team ID, and
notarization before installation. Keep credentials and private data inside
your tool. The optional `settingsSync.keys` list is only for preferences that
are safe to sync through the host's allowlist.
