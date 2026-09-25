# Mac Tweaks implementation matrix

Checked 2026-09-25. The target families are macOS 15.8, 26.7, and 27.0. The supplied 130 records are all in `TweakCatalog.swift`; Mic Lock is an additional, already implemented item. This matrix separates **coded controls** from **observed behavior**. The current Mac compiled on 27.0, but none of the new preference effects has been certified by changing the owner's settings, and 15.8/26.7 have not been runtime tested. The app disables preference writes on unlisted minor releases. Do not interpret a successful preference read-back as proof of visible behavior.

Verdicts:

- **Control coded**: a scoped preference editor, exact original-value and absent-key backup, conflict check, rollback action, and activation guidance exist. New writes are gated to researched OS minors; restore stays available after an OS update. Behavioral certification is still required on each target OS.
- **Apple shortcut**: searchable documentation and, where there is one owning app, a button to open Finder, Screenshot, or System Settings exist. The native control already belongs to Apple; exact pane navigation is not yet implemented.
- **Issue**: the feature is feasible or plausible, but the key, scope, permission path, side effects, lifecycle, or version behavior is unresolved. It has no live toggle.
- **Cannot ship universally**: the stated old recipe is obsolete, broken, or unsafe as one control across all three OS families. Alternatives may exist and would need their own feature record.

The control engine writes only selected keys via exact CFPreferences domains, saves the original value and whether it was absent, and compares the current value before undo so an external change is not overwritten. Dock and Finder refreshes are explicit. Terminal is never closed by the app. A full product claim still requires visible effect, restart persistence, conflicting-setting, and undo checks on all three OS families. [Apple's preference-domain guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html), [exact-domain read API](https://developer.apple.com/documentation/corefoundation/cfpreferencescopyvalue%28_%3A_%3A_%3A_%3A%29), [write/delete API](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/PreferencePanes/Tasks/Preferences.html).

## Controls with a coded preference editor (25)

| ID | Scope and remaining check |
| --- | --- |
| `dock.reveal-delay` | 15/26/27; verify pointer delay and restart persistence. |
| `dock.animation-duration` | 15/26/27; separate from reveal delay. |
| `dock.hidden-app-dimming` | 15/26/27; verify a hidden app's icon. |
| `dock.lock-size` | 15/26/27; Apple documents `size-immutable`; verify user preference behavior. |
| `dock.lock-contents` | 15/26/27; Apple documents `contents-immutable`; verify rearrangement. |
| `dock.stack-selection` | 15/26/27; check a grid stack. |
| `dock.minimize-effect` | 15/26/27; verify hidden `suck` option and restore native choice. |
| `dock.slow-motion` | 15/26/27; check Shift gesture. |
| `dock.switcher-displays` | 15/26/27; needs multi-display test. |
| `finder.hidden-files` | 15/26/27; dotfiles are not every Finder metadata file. |
| `finder.quit` | 15/26/27; check Quit menu and desktop return. |
| `finder.path-title` | 15/26/27; check title on normal and special folders. |
| `finder.sounds` | 15/26/27; check operation sounds, not all system audio. |
| `finder.network-metadata` | 15/26/27; Apple's SMB scope, logout/login required. |
| `input.press-hold` | 15/26/27; global choice, per-app exceptions remain future work. |
| `dialogs.expanded-save` | 15/26/27; writes both Save panel keys, check app variance. |
| `windows.scroll-animation` | 15/26/27; only compatible native views. |
| `menubar.spacing` | 15/26/27; changes system status-item spacing, adds no Mac Tweaks menu-bar item. Check notch, hit targets, and VoiceOver. |
| `screenshots.format` | 15/26/27; new captures only. Tahoe PDF plus floating thumbnail is blocked by the editor. |
| `screenshots.shadow` | 15/26/27; window captures only. |
| `screenshots.date` | 15/26/27; new filename behavior. |
| `terminal.pointer-focus` | 15/26/27; Terminal windows only; manual restart. |
| `music.half-stars` | 15/26/27; check current Music library and rating views. |
| `finder.column-sizing` | 15.8 only in the target set. Hidden on 26.0; native Finder View Options from 26.1. |
| `apps.automatic-termination` | 15.8 only; native automatic termination, not a keep-app-alive guarantee. |

The current TinkerTool matrices document the visible feature families; nix-darwin documents most underlying key names and types. Apple documents the Dock lock keys in its [device-management source](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.dock.yaml) and the network metadata control in [SMB browsing guidance](https://support.apple.com/en-us/102064). These sources do not replace runtime checks. [TinkerTool 15](https://www.bresink.com/osx/0TinkerTool10/details.html), [TinkerTool 26/27](https://www.bresink.com/osx/0TinkerTool/details.html), [Dock keys](https://raw.githubusercontent.com/nix-darwin/nix-darwin/master/modules/system/defaults/dock.nix), [Finder keys](https://raw.githubusercontent.com/nix-darwin/nix-darwin/master/modules/system/defaults/finder.nix), [global keys](https://raw.githubusercontent.com/nix-darwin/nix-darwin/master/modules/system/defaults/NSGlobalDomain.nix), [capture keys](https://raw.githubusercontent.com/nix-darwin/nix-darwin/master/modules/system/defaults/screencapture.nix).

## Apple settings shown as searchable documentation (25)

These are implementable as convenience links or, after version-specific UI checks, as mirrored controls. The app opens Finder, Screenshot, or System Settings where one owner is clear, then tells the user where to find the selected choice. The grouped built-in-app entry provides instructions without a launch button. It does not claim direct pane navigation or silently write Apple's native controls. [Apple System Settings guide](https://support.apple.com/guide/mac-help/change-system-settings-mh15217/mac), [Screenshot options](https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac), [window tiling](https://support.apple.com/guide/mac-help/tile-app-windows-mchlef287e5d/mac).

| ID | Native owner / issue before direct editing |
| --- | --- |
| `native.dock-basic` | Desktop & Dock; size, position, magnification. |
| `native.dock-behavior` | Desktop & Dock; autohide, recents, indicators. |
| `native.dock-minimize` | Desktop & Dock; destination, Genie and Scale. |
| `native.finder-extensions` | Finder Settings; extension visibility and warning. |
| `native.finder-bars` | Finder View menu; path and status bars. |
| `native.finder-start` | Finder Settings; new-window folder and search scope. |
| `native.finder-sort` | Finder View Options and Settings; view/sort behavior. |
| `native.finder-desktop` | Finder Settings; desktop files and drives. |
| `native.finder-trash` | Finder Settings; 30-day removal is destructive over time. |
| `native.finder-sidebar` | Finder/System Settings; sidebar sizing and title icons. |
| `native.screenshot-location` | Screenshot Options; destination includes non-file targets. |
| `native.screenshot-thumbnail` | Screenshot Options; also interacts with PDF on some Tahoe builds. |
| `native.screenshot-memory` | Screenshot Options; remember selection. |
| `native.spaces-order` | Desktop & Dock / Mission Control. |
| `native.spaces-switch` | Desktop & Dock / Mission Control; logout may be needed. |
| `native.tiling` | Desktop & Dock / Windows; edge, Option, margins. |
| `native.desktop-click` | Desktop & Dock; “Only in Stage Manager” is not complete disabling. |
| `native.stage-manager` | Desktop & Dock; strip and grouping. |
| `native.hot-corners` | Desktop & Dock; version-specific actions. |
| `native.text-assists` | Keyboard/Text Input; app support varies. |
| `native.keyboard-functions` | Keyboard and Accessibility; hardware varies. |
| `native.trackpad` | Trackpad and Accessibility; hardware varies. |
| `native.appearance` | Appearance and Accessibility; contrast and motion settings. |
| `native.units` | General/Language & Region and Control Center clock. |
| `native.app-options` | Safari, TextEdit, Activity Monitor, Messages; each app owns its UI. |

## Issues to resolve before offering a control (73)

### Other hidden preferences (24)

| ID | Blocking issue |
| --- | --- |
| `dock.spacers` | Must merge only spacer tiles into the two live Dock arrays; Dock caching and concurrent edits can overwrite unrelated items. |
| `finder.open-animation` | Exact keys and a documented tab-detach artifact need targeted tests. |
| `finder.info-animation` | Exact key and scope not established. |
| `finder.wait-for-network` | Exact key unknown; visibly slower initial listing may be intended. |
| `finder.restrict-connect` | Exact key and restriction behavior unknown; not a security boundary. |
| `finder.restrict-eject` | Exact key and removable-device behavior unknown. |
| `finder.restrict-burn` | Exact key and optical-hardware relevance unknown. |
| `finder.restrict-go` | Exact key unknown; not a security boundary. |
| `dialogs.recent-limit` | Exact domain/key and supported numeric range need verification. |
| `dialogs.tooltip-delay` | Exact key/range and modern view behavior need verification. |
| `spaces.drag-delay` | Exact key/range and Mission Control behavior need verification. |
| `mail.custom-sound` | AIFF file lifecycle and protected Mail preference need a focused Full Disk Access flow. |
| `appearance.app-light` | Per-app domains differ; Mail/Safari protection and mixed UI need tests. |
| `appearance.font-defaults` | Category keys and app support vary; larger text may clip controls. |
| `appearance.font-smoothing` | Global versus current-host domain and app-specific effect need checks; old subpixel rendering cannot be promised. |
| `formats.numbers` | Locale-specific templates, preview, and exact preference mapping need tests. |
| `formats.currency` | Currency symbol and separator precedence need tests across locales. |
| `formats.date-time` | Template validation needs non-English and edge-date checks. |
| `diagnostics.handling` | Exact presentation key and crash-test isolation required. |
| `diagnostics.notification` | Exact key and notification behavior unknown; cannot claim telemetry off. |
| `diagnostics.exceptions` | Exact key and controlled exception test required. |
| `diagnostics.reporter-dock` | Exact key and crash reporter behavior need tests. |
| `safari.backspace` | Protected Safari preference and text-field safety need Safari-build checks. |
| `safari.zoom` | Protected Safari preference and site-specific override behavior need checks. |

### Version-specific preferences (13)

| ID | Blocking issue |
| --- | --- |
| `launchpad.grid` | Legacy Launchpad on 15 only; cannot reuse the mechanism for the 26/27 launcher. |
| `launchpad.fade-in` | Same 15-only mechanism; key and effect need validation. |
| `launchpad.fade-out` | Same 15-only mechanism; key and effect need validation. |
| `launchpad.page` | Same 15-only mechanism; key and effect need validation. |
| `appearance.corners` | Available from 26.4 and on 27; exact current key unknown. |
| `appearance.sidebars` | Available from 26.4 and on 27; exact current key unknown. |
| `appearance.menu-icons` | Tahoe documentation exists; 27 mechanism not established. |
| `windows.edge-grab` | Documented on 15/26; 27 behavior and key need checking. |
| `input.text-drag` | Documented on 15/26; 27 behavior and key need checking. |
| `input.layout-popup` | Documented on 26/27; old key recipe is not enough to choose a current domain. |
| `safari.bookmarks` | 26/27 and actual Safari build need verification plus protected preference access. |
| `timemachine.disk-prompt` | 15 evidence; no 26/27 support established. |
| `dock.recent-count` | 15 evidence; 26/27 key and effect unverified. |

Finder column sizing is in the coded-control table because the editor is gated to 15.8. TinkerTool records the native migration in [its notes](https://www.bresink.com/osx/0TinkerTool/issues.html) and the newer controls in [its version history](https://www.bresink.com/osx/0TinkerTool/history.html).

### Research candidates (14)

| ID | Blocking issue |
| --- | --- |
| `dock.running-only` | `static-only` exists, but current Dock behavior and Deeper's unreleased fix need testing. |
| `security.sudo-touchid` | Editing `/etc/pam.d/sudo_local` is an authentication policy change; needs administrator authorization, password fallback, and recovery. |
| `input.hid-remap` | `hidutil` mappings can disappear after service/device restart; must merge existing mappings and reapply safely. |
| `windows.drag-anywhere` | Key exists in maintained code; modifier behavior on 15/26/27 unknown. |
| `input.repeat-timing` | `InitialKeyRepeat`/`KeyRepeat` known; safe range and app behavior unknown. |
| `dialogs.expanded-print` | Keys known; three-version visible effect unverified. |
| `input.control-characters` | Key known; only compatible text views may honor it. |
| `windows.focus-ring` | Key known; focus visibility and accessibility effects need tests. |
| `finder.proxy-delay` | Old key coverage; current titlebar and accessibility setting interaction unknown. |
| `continuity.clipboard` | Another app offers a control; exact mechanism unknown. |
| `appearance.extra-accents` | Another app offers choices; exact supported values/hardware unknown. |
| `quicklook.mute` | Another app offers muted preview; exact mechanism unknown. |
| `textedit.blank-document` | Another app offers startup choice; exact mechanism unknown. |
| `menubar.input-devices` | Another app offers this Sound menu choice; exact mechanism unknown. |

### Administrator controls (2)

| ID | Blocking issue |
| --- | --- |
| `hardware.auto-start` | Apple documents NVRAM `BootPreference` for Apple silicon laptops on 15+; needs hardware gate, administrator flow, exact prior-state backup, and shutdown test. This controls startup, not closed-lid sleep. |
| `power.schedule` | `pmset` is documented on 15/26; a safe editor must preserve unrelated schedules and account for unsaved work, FileVault, and 27 verification. |

[Apple startup control](https://support.apple.com/en-us/120622), [Apple power scheduling](https://support.apple.com/guide/mac-help/schedule-your-mac-to-turn-on-or-off-mchl40376151/mac), [Apple archived HID note](https://developer.apple.com/library/archive/technotes/tn2450/_index.html), [nix-darwin PAM implementation](https://raw.githubusercontent.com/nix-darwin/nix-darwin/master/modules/security/pam.nix).

### Running enhancements (20)

These are technically plausible as dedicated helpers, extensions, or event monitors. They are not persistent `defaults` switches. Mic Lock is already the example of a narrow running feature in Mac Tweaks. Each new enhancement needs a lifecycle while the app window is closed, permission state, logout/restart behavior, conflict handling, and target-OS testing. [Supercharge feature inventory](https://sindresorhus.com/supercharge), [LinearMouse feature inventory](https://linearmouse.app/en/).

| ID | Main implementation issue |
| --- | --- |
| `helper.dock-click` | Intercept Dock activation without breaking normal clicks. |
| `helper.restore-minimized` | Accessibility window state and app activation across Spaces. |
| `helper.traffic-lights` | Window-button event interception across native and custom windows. |
| `helper.quit-guard` | Per-app keyboard interception, menu commands, and failure-safe exit. |
| `helper.finder-keys` | Finder-only shortcuts without swallowing text or other app input. |
| `helper.finder-context` | Finder extension/actions and file access permissions. |
| `helper.finder-tabs` | Finder tab state and version-dependent accessibility structure. |
| `helper.clipboard-files` | Explicit save action is feasible; destination and pasteboard type handling need design. |
| `helper.window-layout` | Accessibility permission, coordinate spaces, display changes. |
| `helper.mission-actions` | Mission Control previews are private/version-sensitive UI. |
| `helper.inactive-rules` | Timers, unsaved work, per-app exclusion, login lifecycle. |
| `helper.hyper-key` | Input monitoring and event tap resilience. |
| `helper.middle-click` | Gesture recognition and event injection without native conflicts. |
| `helper.media-keys` | Media key ownership across players and system versions. |
| `helper.clipboard-clear` | Clipboard ownership, sensitive content, lock event, timer lifecycle. |
| `helper.keep-awake` | Scoped power assertion lifecycle; works only while helper runs. |
| `helper.airdrop-workflow` | Received-file identification and folder access without moving unrelated files. |
| `helper.mouse-scroll` | Device discrimination and Input Monitoring permission. |
| `helper.pointer-profiles` | Per-device acceleration and reconnect handling. |
| `helper.mouse-buttons` | Device/button mapping and conflict handling. |

## Cannot ship as one supported control (7)

| ID | Reason |
| --- | --- |
| `avoid.glass-off` | Old whole-system switch applied to Tahoe 26.0 only, with side effects. It is not a 26.7/27 solution. |
| `avoid.icloud-save` | The old global preference is no longer honored by current macOS. |
| `avoid.scroll-stacks` | The old Dock scroll recipe has no current stack-opening proof; scroll-to-Exposé is a different behavior. |
| `avoid.single-app` | The historical Dock mode has no current all-version behavior proof; a helper would be a new feature. |
| `avoid.help-top` | The old Help window recipe has no modern support proof. |
| `avoid.all-animation` | One global key cannot remove every native and custom app animation and has documented side effects. |
| `avoid.split-dark` | The split appearance recipe has documented dark-on-dark notification contrast problems. |

[TinkerTool limitations](https://www.bresink.com/osx/0TinkerTool/issues.html) and [release history](https://www.bresink.com/osx/0TinkerTool/history.html) provide the version and side-effect evidence. These are “cannot ship as stated,” not proofs that no different implementation can ever exist.

## Certification gate

For each coded control, use a clean account on 15.8, 26.7, and 27.0; record original key presence/type/value; apply one setting; check the visible effect; restart the target app and sign in again where applicable; change the value from Apple's UI or another utility; verify conflict handling; then restore both originally present and absent keys. Check Dock layouts, Finder file operations, screenshot PDF plus thumbnails, Terminal with active shells, multiple displays and notches, managed preferences, VoiceOver, and permissions. Until those observations exist, the app and this report must say **coded, not runtime certified**.
