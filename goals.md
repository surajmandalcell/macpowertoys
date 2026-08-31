# PowerToys goals

Reviewed against current source on 2026-08-31.

This file is the goals index. Each request list contains the detailed status,
evidence, and remaining work.

## Current work

- Verify native titlebar dragging for Ruler Settings and Ruler Defaults.
- Verify the shared modal Close control in both SSH Anchor sheets.
- Verify the compact Tailscale device chooser with short and scrolling lists,
  including peer-row hover and pressed feedback.
- Verify hover and pressed feedback for every updated selectable row, card, and
  tab family.
- Verify Command-Q in a live sheet and across the launcher timeout path, then
  verify Command-W. The latest signed build closes every sub-app scope without
  terminating MacPowerToys.
- Verify live None, Combined, and Separate menu-bar modes for every eligible
  tool, including compact combined navigation, saved selection, and separate-
  item position restoration. Deterministic placement, action, and item-
  identity checks pass.
- Verify Awake tray sizing, selected states, content-sized tabs, and failure
  presentation.
- Verify menu-bar focus, keyboard use, compact layout, darker appearance,
  contrast, tab-group edges, body and footer rhythm, native single-click, and
  Cloud Sync Pause and Resume.
- Verify compact top-aligned launcher introductions and the 18pt by 6pt detail
  tab inset.
- Verify large sidebar search fields and thin native content search fields,
  including the Cloud Sync connector picker.
- Verify adaptive multi-column layouts, compact inline metadata, and readable
  narrow-width fallbacks.
- Verify that physical Command-Shift-3 opens Color Picker and suppresses the
  macOS screenshot action.
- Verify visible Raycast icon rendering, NetToys cold-launch and prefill routing,
  and NetToys saved-frame restoration.
- Verify SSH Anchor at minimum width and across real address changes, key-only
  setup for `win1`, Tailscale fallback and recovery, host-key safety, helper
  repair, and preservation of unrelated SSH configuration.
- Verify that a signed NetToys subnet scan streams rows and enrichment fields
  at its minimum window size. The default-size signed scan is complete.
- Verify Input Devices with real mouse and trackpad hardware, sustained wheel
  input, and session lock and unlock.
- Verify all seven System Monitor menu metrics, zero selection, ordering,
  dragged-position preservation, and per-item display settings at minimum width
  and after relaunch.
- Complete the public release checklist only after every product and live
  verification item above passes.

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
