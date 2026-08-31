# MacPowerToys goals

Reviewed against current source on 2026-08-31.

This file is the goals index. Each request list contains the detailed status,
evidence, and remaining work.

## Current work

- Verify native titlebar dragging for Ruler Settings and Ruler Defaults.
- Verify the shared modal Close control in both SSH Anchor sheets.
- Verify the compact Tailscale device chooser with short and scrolling lists,
  including correct row and scrolling geometry.
- Verify hover and pressed feedback for every updated selectable row, card, and
  tab family.
- In one physical menu-bar matrix, verify live None, Combined, and Separate
  modes; compact navigation; saved selection and item positions; Awake sizing
  and selected states; focus and keyboard use; compact and dark appearance;
  contrast; tab-group, body, and footer rhythm; native clicks; and Cloud Sync
  Pause and Resume.
- Verify adaptive multi-column layouts, compact inline metadata, and readable
  narrow-width fallbacks.
- Verify that physical Command-Shift-3 opens Color Picker and suppresses the
  macOS screenshot action.
- Verify visible Raycast icon rendering and the NetToys cold launch. NetToys
  prefill routing and saved-frame restoration are already complete.
- Verify SSH Anchor at minimum width and across real address changes, retained
  key-only access for `win1`, Tailscale fallback and recovery, and host-key
  safety. `win1` is enrolled, healthy, key-verified, and Tailscale-enabled;
  current key-only access is confirmed.
- Verify that a signed NetToys subnet scan streams rows and enrichment fields
  at its minimum window size. The default-size signed scan is complete.
- Verify Input Devices with real mouse and trackpad hardware, sustained wheel
  input, and session lock and unlock.
- Verify System Monitor dragged-position preservation after relaunch and its
  per-item display settings at minimum width. All seven metrics, zero selection,
  enablement, ordering, persistence, and cadence are already test-proven.
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
