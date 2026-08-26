# PowerToys goals

Reviewed against current source on 2026-08-26.

This file is the goals index. Each request list contains the detailed status,
evidence, and remaining work.

## Current work

- Verify that every workspace sidebar meets its body without a visible seam in
  the latest normal signed build.
- Verify the full-width Awake tray controls in the latest normal signed build.
- Verify None, Combined, and Separate menu-bar modes, compact icon-only
  navigation above two combined tools, saved tab selection, separate-item
  position restoration, and actions for every eligible background tool.
- Verify the compact top-aligned launcher introduction for Input Devices and
  the other menu-bar-capable tools.
- Verify large search fields stay in sidebars and every content search uses the
  thin native control across apps and sub-apps.
- Verify focus appearance and keyboard activation in the menu-bar panels with
  a physical menu-bar click. All other built-in surfaces passed.
- Verify compact inline metadata and adaptive two-column pages in the latest
  normal installed build at default and minimum widths.
- Verify automatic SSH Anchor setup at the minimum window width, then change
  connections and confirm the signed helper repairs the enrolled host's IP
  without a host-key prompt or changed-identification failure.
- Complete the one-time in-app key setup for `win1`, then verify key-only SSH
  before and after SSH Anchor changes its address.
- Verify one signed SSH Anchor falls back through its pinned Tailscale device
  and returns to the local endpoint without changing an unrelated SSH stanza.
- Verify content-sized menu-bar tabs and selected Awake controls in the latest
  normal installed build.
- Verify the darker menu-bar popover, equal tab-group edges, shorter body gap,
  added body-bottom space, footer rhythm, and native single-click in the latest
  normal signed installed build.
- Verify the 18pt by 6pt launcher-detail tab inset in the latest normal
  installed build.
- Verify representative updated tool icons and launchers in the refreshed
  local Raycast extension.
- Verify that Input Devices keeps scroll control active through sustained wheel
  input and a session lock and unlock.
- Verify that a signed NetToys subnet scan fills rows and later fetcher fields
  live at its 1,280 by 800 default and 1,100 by 700 minimum sizes.
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
