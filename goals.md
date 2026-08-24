# PowerToys goals

Reviewed against current source on 2026-08-24.

This file is the goals index. Each request list contains the detailed status,
evidence, and remaining work.

## Current work

- Verify that every workspace sidebar meets its body without a visible seam in
  the latest normal signed build.
- Verify the full-width Awake tray controls in the latest normal signed build.
- Verify separate menu bar icons, saved visibility, position restoration, and
  actions for every eligible background tool.
- Verify focus appearance and keyboard activation in the menu-bar panels with
  a physical menu-bar click. All other built-in surfaces passed.
- Verify compact inline metadata and adaptive two-column pages in the latest
  normal installed build at default and minimum widths.
- Verify content-sized menu-bar tabs and selected Awake controls in the latest
  normal installed build.
- Verify the darker menu-bar popover, equal tab-group edges, shorter body gap,
  added body-bottom space, footer rhythm, and native single-click in the latest
  normal signed installed build.
- Verify the 18pt by 6pt launcher-detail tab inset in the latest normal
  installed build.
- Complete the live checks in the request lists.
- Complete the public release checklist only after product work is complete.

## Request lists

- [Main app and Cloud Sync](spec/main-request-list.md)
- [Cloud Sync details](spec/cloud-sync-request-list.md)
- [Awake](spec/awake-request-list.md)
- [Color Picker](spec/color-picker-request-list.md)
- [Text Extractor](spec/text-extractor-request-list.md)
- [Ruler](spec/ruler-request-list.md)
- [Input Devices, System Care, System Monitor, and NetToys](spec/system-tools-request-list.md)

## Status rules

- Use `Done` only when source evidence or a live check proves the result.
- Use `Verify` when the source is complete but the installed app needs a check.
- Use `Open` when implementation work remains.
- Use `Platform limit` when a public macOS API cannot provide the result.
- Use `Accepted` when the user accepts the current behavior or defers the work.

Update this index when a request list adds or closes current work.
