# System Tools Request List

Reviewed against current source on 2026-08-24. Update this list when a direct
user correction or verified result changes a status.

## Input Devices

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Add a macOS tool for mouse and trackpad control. | `cfa8832` added Input Devices as an on-demand tool with a separate window, launcher route, and app icon. | None. |
| Done | Use icon option 03. | `3e504d3` made `InputDevicesLogoA` the only Input Devices icon. | None. |
| Done | Keep separate mouse and trackpad profiles. | `InputDevicesManager` stores separate profiles. The UI exposes both profiles in two columns. | None. |
| Done | Add reverse vertical, reverse horizontal, horizontal, speed, and smooth-wheel controls. | Each profile has the applicable controls. The event tap applies the selected profile to scroll events. | None. |
| Done | Distinguish mouse-like and trackpad-like scroll events. | The manager classifies precise events as trackpad-like and coarse events as mouse-like. It also provides a manual override. | None. |
| Done | Show useful hardware details for each connected mouse and trackpad. | `1157bcb` and `d5942c9` added device type, transport, maker, speed, resolution, polling rate, buttons, IDs, firmware, report size, and serial data when macOS provides them. | None. |
| Verify | Confirm real mouse and trackpad control after Accessibility permission is granted. | Unit seams cover profile selection and event transformation. Source inspection confirms that disabling the tool stops the event tap. | Test vertical, horizontal, reverse, speed, and smooth-wheel behavior with real hardware. |

## System Care and Mole

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Add a large System Care interface for Mole and native cleanup. | `a073a35` added Overview, Storage, Cleanup, Applications, Mole CLI, History, Settings, and About pages. | None. |
| Done | Add a storage view that supports visual drill-down. | The Storage page has an interactive ring, breadcrumbs, size totals, and folder drill-down. | None. |
| Done | Make Mole installation and updates easy. | System Care detects Mole and provides Homebrew install and update actions. | None. |
| Done | Keep privileged and interactive Mole work visible. | Preview and maintenance actions open Mole in Terminal. The app does not collect a password or bundle Mole. | None. |
| Done | Keep cleanup safe and recoverable. | Native cleanup rejects paths outside approved roots, does not follow symbolic links, and moves reviewed items to Trash. | None. |
| Done | Make Scan the primary Cleanup action. | `6fb2d41` made Scan prominent on Overview and Cleanup before results exist. | None. |
| Done | Keep System Care work status at the bottom and align More, Rescan, and related top actions. | `1666d71` expands the page before adding the bottom safe-area inset, moves the status in from the bottom, and gives More a native secondary button beside the primary Rescan action. The normal signed build scanned a large external drive and confirmed that the live banner touched the bottom inset with no unused area below it. More and Rescan shared the centered 24pt action row. | None. |
| Accepted | Do not add System Care menu-bar controls now. | The request described this as possible later work, not a current requirement. | Reopen this item only after a direct request. |
| Verify | Check System Care and Mole with real data. | Guard and model tests cover path safety and operation data. | Test scan, Trash recovery, storage drill-down, Mole installation, and Terminal previews. |

## Power Stats

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Add CPU, memory, disk, network, battery, thermal, and load data. | `cfa8832` added native samplers and detailed pages for these values. | None. |
| Done | Collect detailed data only while the Power Stats window is open. | The window starts detailed sampling on appear and stops it on disappear. | None. |
| Done | Add an optional lightweight menu-bar view. | Power Stats can show CPU, memory, and network values without detailed disk, battery, thermal, or load sampling. | None. |
| Done | Support grouped and individual menu-bar items. | `PowerMenuMode` provides both layouts. | None. |
| Done | Make the menu update rate configurable. | The saved menu rate supports 1, 2, 3, or 5 seconds. | None. |
| Done | Keep monitoring resource use bounded. | One timer owns both modes. History keeps at most 120 samples. The service removes the timer and menu items when neither surface needs them. | None. |
| Verify | Check live values, menu layouts, timing, and shutdown behavior. | Delta tests cover CPU and rate calculations. Lifecycle logic matches the on-demand contract. | Measure the saved rate, memory, CPU use, and status-item removal in the installed app. |
| Done | Animate page and live-value changes without using motion when Reduce Motion is enabled. | The normal signed `d1cf9e2` build exercised Overview, Processor, Memory, Network and Disk, and Menu Bar pages with changing live values. The app-wide motion policy and Reduce Motion regression test pass. | None. |

## Shared window behavior

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Remember window position, display, and size for the three tools. | Each window uses a stable `WindowAccessor` identifier. `WindowStateManager` stores all three identifiers. | None. |
| Verify | Keep short metadata inline and use two columns on sparse wide pages. | `a318b41` put System Care storage paths, breadcrumb totals, and cleanup metadata on one row and made Settings adaptive. `4ad3da2` compacted Input Devices metadata and made Power Stats Menu Bar cards adaptive. The full unit suite passes. | Inspect all three tools at default and minimum widths. Confirm two columns on wide sparse pages, one column on narrow pages, and no clipped values. |
| Verify | Confirm restoration with multiple displays. | Unit tests cover saved display frames and fixed-size position restoration. | Move and resize each window, relaunch, and check each display. |
| Done | Use quiet structural dividers and compact aligned top actions in all three workspaces. | `81de8b1` routes workspace actions through one centered 24pt row and reduces the shared visual divider to 0.22 opacity, or 0.44 with Increased Contrast. The normal signed `1666d71` build confirmed the System Care top actions and live divider. The shared Increased Contrast and Reduce Motion checks pass. | None. |
