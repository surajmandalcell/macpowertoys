# System Tools Request List

Reviewed against current source on 2026-08-24. Update this list when a direct
user correction or verified result changes a status.

## NetToys

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Open | Use three destinations: IP Scanner, SSH Anchor, and Network History. | The direct correction on 2026-08-24 supersedes the earlier Network, Tests, and SSH Tunnels draft. Git recovery checks found no prior implementation. | Build the three-destination workspace with shared MacPowerToys geometry and controls. |
| Open | Reimplement the useful Angry IP Scanner feature set without copying GPL source, text, or art. | Native macOS networking APIs can scan bounded IPv4 ranges and selected TCP ports. | Add range, subnet, and IP-list targets; bounded concurrent scanning; host state, response time, hostname, MAC, vendor, and open-port results; sorting, filtering, selection rescans, cancellation, and CSV or text export. |
| Open | Add SSH Anchor for local devices whose IP address changes. | The user has a maintained `~/.ssh/config` and needs automatic recovery for one selected host and port. | Monitor the configured TCP port every 2 to 3 seconds. On failure, scan the active local IPv4 subnet on only that port, identify the selected device, and update its address. |
| Open | Support stable and randomized MAC address identity. | The user accepts exact MAC matching in stable mode and a loose unique-hostname match with learned MAC evidence in randomized mode because collisions are not expected. | Never change the config when the selected identity is missing or ambiguous. Learn evidence only from successful matches. |
| Open | Preserve the SSH config byte for byte except for the selected `HostName` token. | Generic OpenSSH serializers can change whitespace, comments, line endings, and unrelated stanzas. | Locate the selected stanza, compare the expected old token, splice only that token, write atomically, keep a recoverable backup, and verify the saved bytes. |
| Open | Track gateway and internet availability by active network. | Transition records are sufficient for outage history and avoid continuous sample storage. | Store network, disconnect, recovery, gateway, and internet transitions with timestamps. Do not store every probe. |
| Open | Require a bundled login helper whenever NetToys is enabled. | No helper target exists. | Enabling must register and use the helper. Disabling must stop monitoring and unregister it. Reconcile helper status at each app start. Do not run persistent NetToys monitoring in the main app. |
| Open | Integrate NetToys with MacPowerToys. | The registry, scenes, deep links, Raycast commands, tests, and installed app contain no NetToys tool. Vorssaint also has no implementation. | Add the tool, neutral icon assets, restored resizable window, launcher entry, deep link, Raycast command, tests, and installed-build verification. |

## Input Devices

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Anchor the Input Devices launcher settings footer to the bottom. | The empty Input Devices settings detail inserts its flexible space above the shared description and menu-bar toggle instead of beneath them. The signed `a5ad439` build showed the description and toggle anchored to the bottom edge. | None. |
| Verify | Offer a separate Input Devices menu bar icon. | The launcher setting stores the choice, and `IndividualMenuBarController` opens Input Devices from a native item with a stable autosave name. | Enable the item in the latest normal installed build, move it, relaunch, and confirm that it keeps its position and opens Input Devices. |
| Done | Add a macOS tool for mouse and trackpad control. | `cfa8832` added Input Devices as an on-demand tool with a separate window, launcher route, and app icon. | None. |
| Done | Keep the Scroll device selector at the bottom of the window. | `65f1c0e` moved the selector from the scrolling body to a native bottom inset. The exact installed `4e181f8` build confirmed the bottom position. | None. |
| Done | Use the selected I21 direction and show a detailed mouse. | `InputDevicesLogoA` now uses the I21 mouse shell, button split, scroll wheel, DPI key, and side controls. | None. |
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
| Done | Keep System Care work status at the bottom and align More, Rescan, and related top actions. | `1666d71` anchors the animated status banner to the bottom. `6247587` preserves the native width and centered 24-point height of every workspace action. The normal signed builds confirmed the bottom banner with a large external-drive scan and confirmed complete Scan, Rescan, More, Refresh, and Mole update controls at the compact limit. | None. |
| Accepted | Do not add System Care menu-bar controls now. | The request described this as possible later work, not a current requirement. | Reopen this item only after a direct request. |
| Done | Check System Care and Mole with real data. | The normal signed `631facd` build scanned 100 real cleanup candidates and moved only a controlled cache marker to Trash; Finder restored the exact marker with Put Back. A 361 MB project scan drilled into `docs`, updated its path, count, size, and breadcrumb, then returned to the root. System Care detected Mole 1.52.0. Deep Cleanup and MacPowerToys removal previews each generated and completed the exact `mo … --dry-run` command in Terminal without running a destructive maintenance command. | None. |
| Done | Lock icon S11-08. | `SystemCareLogo` uses the selected centered disk and soft eraser geometry with the approved Noir colors. | None. |

## System Monitor

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Name the tool System Monitor everywhere and make its icon show monitoring. | The registry, window, route, source symbols, menu item, Raycast command, tests, specifications, and asset use System Monitor. Narrow read-time fallbacks preserve the old disabled state, menu settings, window frame, and deep links. The icon uses a display with live metric bars. | None. |
| Done | Add CPU, memory, disk, network, battery, thermal, and load data. | `cfa8832` added native samplers and detailed pages for these values. | None. |
| Done | Collect detailed data only while the System Monitor window is open. | The window starts detailed sampling on appear and stops it on disappear. | None. |
| Done | Add an optional lightweight menu-bar view. | System Monitor can show CPU, memory, and network values without detailed disk, battery, thermal, or load sampling. | None. |
| Done | Support grouped and individual menu-bar items. | `SystemMonitorMenuMode` provides both layouts. | None. |
| Done | Make the menu update rate configurable. | The saved menu rate supports 1, 2, 3, or 5 seconds. | None. |
| Done | Keep monitoring resource use bounded. | One timer owns both modes. History keeps at most 120 samples. The service removes the timer and menu items when neither surface needs them. | None. |
| Done | Check live values, menu layouts, timing, and shutdown behavior. | The normal signed `29fcbd0` build used the saved one-second rate. Four live samples changed in grouped mode, and individual mode created exactly three items. After the detail window closed, 16 menu-only samples stabilized near 85.3 MB with low CPU use. Disabling the menu removed every System Monitor status item. Eight samples with both surfaces closed showed 0.0 to 0.1 percent CPU, then 0.0 percent with flat CPU time. | None. |
| Done | Animate page and live-value changes without using motion when Reduce Motion is enabled. | The normal signed `d1cf9e2` build exercised Overview, Processor, Memory, Network and Disk, and Menu Bar pages with changing live values. The app-wide motion policy and Reduce Motion regression test pass. | None. |

## Shared window behavior

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Done | Use the correct shared width and padding family for every system-tool sidebar. | Input Devices stays in the 220pt compact family; System Care and System Monitor use the 240pt data family. All use the shared 44pt top edge and 12pt horizontal padding. Focused layout tests and the signed `a5ad439` build confirmed all three sidebar families. | None. |
| Done | Remember window position, display, and size for the three tools. | Each window uses a stable `WindowAccessor` identifier. `WindowStateManager` stores all three identifiers. | None. |
| Done | Keep short metadata inline and use two columns on sparse wide pages. | `f44fc7a` adapts Input Devices profiles. `29fcbd0` adapts every System Monitor metric and chart page. `8f4b6dd` adapts System Care Storage and Applications. The normal signed builds confirmed all three tools at their compact and normal widths. Wide pages use multiple columns. Compact pages stack without clipped values. `631facd` also keeps every shared About header readable at the compact limit. | None. |
| Done | Confirm restoration with multiple displays. | `cf5c975` prevents SwiftUI's initial frame from replacing saved state before restoration. All 400 unit tests pass. In the normal signed build, Input Devices and System Monitor restored at 1891 × 1065 on the built-in display, and System Care restored at 1078 × 699 on the same display after a full app quit and relaunch. The Window menu and the unchanged saved display identifier confirmed the display. The three windows then returned to their normal 980 × 700, 1080 × 720, and 1180 × 780 frames on the main display. | None. |
| Done | Use quiet structural dividers and compact aligned top actions in all three workspaces. | `81de8b1` reduces the shared visual divider to 0.22 opacity, or 0.44 with Increased Contrast. `6247587` preserves every action's native width on the centered 24-point row. The normal signed builds confirmed the divider and every System Care action at the compact limit. The shared Increased Contrast and Reduce Motion checks pass. | None. |
