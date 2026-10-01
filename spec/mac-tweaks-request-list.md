# Mac Tweaks request list

## Round 18 root texture correction, run 71, 2026-10-02

- [x] Remove the decorative window ribbon once in `OnePlusWindowRoot` for `.macTweaks`. Shared commit: `0516519`. Keep the flat fill and all other canvases unchanged.
- [x] Add one offscreen package regression across all 13 canvases in both appearances. It fails on the old Mac Tweaks root and passes with the exception. Both texture tests pass.
- [~] `swift test` executes 148 tests: 147 pass. The known unowned `OnePlusStatCell` compact-height check still measures 46pt against 44pt. The orchestrator owns that correction, publication, tagging, dependency adoption, installation, and signed captures of all ten pages plus search. Report: `tmp/redesign/logs/w13-fix18-oneplus.md`.

## Round 11 control and wallpaper corrections, 2026-10-01

- [x] T084: remove the extra disabled opacity from shared selects and segments. Keep one 0.38 treatment on the custom timing field. T085: use the mono role with control ink for timing values; keep caption units, the native stepper, and 28pt height. Commit: `e9f06d55`.
- [x] T086: delete only the shared wallpaper's grid strokes. Keep static artwork, uniform scaling, and window and Dock geometry. Commit: `bd8e54aa`.
- [x] Review all 20 Round 10 Mac Tweaks captures from signed `198055e4` in Light and Dark. No additional lane defect found. Offscreen segments match bare shared rendering in both appearances and enabled states. Restoring the removed opacity fails that check. Timing text uses the mono role at the same height.
- [~] Completed batch gates failed only on unowned app files. Existing queued gates remain running under the orchestrator's one-gate correction; no further build is queued. The complete preview file type-checks against the shared module. Integrated signed verification remains. ImageRenderer cannot prove native select or stepper rendering. The orchestrator must recapture Dock and the shared desktop previews, inspect disabled selects, segments, and timing controls, and finish the installed-app handoff. Report: `tmp/redesign/logs/w3-audit-tweaks.md`.

## Production audit, 2026-10-01

- [x] Preserve reset actions and Modified entries whenever an exact-value backup exists, even at an explicit or absent system default. Disable new edits on unsupported OS releases while keeping restore available.
- [x] Preflight managed preferences and external changes before any reset write. Reset tracked originals and untracked defaults in one operation. Do not create a reverse-reset backup for an untracked default reset. Protect unreadable backup records and their nested values. Core checkpoints: `c2000537`, `66adbe1c`.
- [x] Show loading and custom values truthfully. Surface microphone and meter errors. Use full-row Modified hover and one-line About values with tooltips. UI checkpoint: `6503e8b0`.
- [x] Enable Awake consistently from Power and search. Show actual assertion state and remaining time. Confirm affected-app restart, wait for termination, and reopen in the background with visible failures.
- [x] Apply the binding horizontal-density and motion correction: put single control rows directly on the page, remove preview-only cards, move About version to the trailing side, put help in tooltips, remove notice transitions and refresh rotation, and keep all nine previews static. Update the hosted hover test to require still frames. This supersedes earlier hover-film requirements.
- [~] Ten installed baseline pages were captured without clicks or foreground activation. A read-only probe read all 27 exact-domain keys for 25 controls. Before and after snapshots match; no test write or affected-app restart was performed.
- [~] Focused preference and UI tests type-check with the XCTest overlay. The read-only backup predicate check passes and fails when backup awareness is removed. Final shared build-for-testing passes for the Debug app and both test bundles after concurrent unowned errors. Five requests per gate mode completed. Log: `tmp/redesign/logs/audit-tweaks-tests-fifth.log`. Hosted test execution and final signed interaction checks remain with the orchestrator. Audit report: `tmp/redesign/logs/w1-audit-tweaks.md`.
- [x] Main launcher follow-up, `5a3e95b5`: use `needsReset(selection, hasBackup:)` in embedded Settings. A saved original keeps reset available at the default. Put Review changes directly on the page; remove its single-row Preferences card and inline help. Keep operation notices visible.
- [x] Main documentation follow-up, `b4fd441d`: add the README tool entry and short section. Extend How to use with all pages, search, reset, Modified, exact-value backups, OS edit gates, static previews, restart or Later, Mic Lock, and shared Awake controls. Both shared compile modes pass. Hosted tests and signed interaction checks remain. Report: `tmp/redesign/logs/w1-main.md`.

## Round 10 main-window corrections, 2026-09-30

- [x] Replace the launch-only embedded card with the existing Expanded Save panels, Alternate Save panels, and Page-scroll animation controls. Reuse `MacTweaksPreferenceRows` and its guarded store; preserve defaults, exact-value restore, OS write gates, and visible errors. Real values load on a utility task with an explicit loading state.
- [x] Pair Window and Safety in equal natural-height cards with a 16pt gap. Present enforced backup, managed-preference, and external-change safeguards as read-only values, not invented settings. Replace duplicate Open with Review changes to the existing Modified page. Commit: `a1fd972`.
- [~] Debug and desktop build-for-testing pass. Orchestrator signed dark/light recapture and apply, restore, error, advanced-route, focus-mode, and speed checks remain. Report: `tmp/redesign/logs/27r10-main.md`.

## Round 9 screenshot corrections, 2026-09-30

- [x] Expand the Finder preview crop and center it on the artwork at x300/y160. Keep uniform scaling and the full titlebar, sidebar, status row, and window boundary. The 240pt preview body has more than 20pt vertical clearance.
- [x] Review all 20 signed `3e33de2` captures in both appearances. Mixed select and segment tracks share their 180pt painted column. System has the shared section-start gap.
- [~] Recapture Finder at rest and during hover in the next signed build. Check the complete window and at least 20pt vertical clearance. Other live focus, permission, reset, tooltip, idle CPU, panel, and latency checks remain. See `tmp/redesign/logs/25r9-tweaks.md`.

## Round 8 screenshot corrections, 2026-09-30

- [x] Pass each card's control width through `MacTweaksSegmentedControl` to the shared `OnePlusSegmented(width:)`. Selects and segments use one painted column, 180pt for three-way cards and 160pt for ordinary cards.
- [x] Use `OnePlusNavCaption("System", spacing: .sectionStart)` after Apps. Keep Everyday's standard caption and the shared navigation row height.
- [x] Review all 20 signed `db47173` captures in both appearances. The title starts at T=16, chrome uses C=27, Modified columns and bottom clearance match, and dark preview labels remain readable in Light.
- [x] Signed `3e33de2` captures confirm both caller fixes. Dock controls paint from x900 to x1080; Screenshots controls paint from x470 to x650. System starts about 25pt below Apps. Live checks remain in the Round 9 row. Earlier report: `tmp/redesign/logs/23r8-tweaks.md`.

## Round 7 screenshot corrections, 2026-09-30

- [x] Give Modified headings and rows the same 16pt inset, 8pt gaps, 170pt value columns, and 28pt reset lane. Derive the extra header inset from the shared table cell inset.
- [x] Signed `db47173` captures confirm Modified column edges, dark chrome, and bottom clearance. The shared segmented-width, section-start caption, and selected-value tooltip APIs landed. Round 8 adopts the first two APIs; live tooltip access remains unverified. Earlier report: `tmp/redesign/logs/17r7-tweaks.md`.

## Round 6 screenshot corrections, 2026-09-30

- [x] Keep the Input Test or Live label visible beside a flexible shared meter in a 180pt control column.
- [x] Put rules inside 44pt setting rows. Choose one control width per card and stretch the lower Dock pair to one height. Shorten Alternate Save panels and widen microphone selects.
- [x] Replace the last appearance-dependent preview material with a fixed dark Dock fill. The embedded Preferences launch card was superseded by the real controls in Round 10 above.
- [x] Signed `db47173` captures confirm the Test label and meter, card row rules, equal lower Dock heights, and dark preview surfaces. Round 8 adopts the shared width and section-start APIs. Earlier report: `tmp/redesign/logs/16r6-tweaks.md`.

## Round 5 screenshot corrections, 2026-09-29

- [x] Derive Modified from live values versus declared defaults, including values changed outside Mac Tweaks. Keep exact-value restore for backed-up changes and return untracked changes to the system default.
- [x] Show Dock timing defaults as `Default (0.40)` and `Default (0.35)` with seconds, and show declared defaults in select controls.
- [x] Keep preview scenes and labels on fixed dark colors in Light and Dark. Remove the Power preview instruction chip and use sentence case for the live status.
- [x] Keep long Finder, Windows, and microphone controls readable. Use distinct Input section icons and keep the input meter visible beside Test.
- [~] Recapture all ten pages from the exact signed build. The 41pt scroll gutter and 28pt header gap remain shared OnePlusUI foundation fixes.

## Owner review 1 corrections, 2026-09-29

- [x] Keep the shared page header at the owner's current `T = 16` and every card on its 24pt leading edge. Mac Tweaks draws no local page header or second body inset.
- [x] Keep the Modified table header and Reset all action fixed. Only its lazy settings rows scroll.
- [x] Remove preference reads from SwiftUI body evaluation. Load current values on a utility task, cache modified rows, and enumerate microphone devices away from the main actor.
- [x] Use `OnePlusSelect` for every value selector. Keep action-only menus native until `OnePlusMenuButton` lands.
- [~] Measure the 100ms page-switch gate and inspect the fixed Modified header in the exact signed build.

## Settings embedding contract, 2026-09-29

- [x] Expose `MacTweaksSettingsContent()` as one 16pt card stack with no page, scroll view, outer padding, page header, spacer, or maximum-height frame.
- [~] Update the foundation-owned tool dispatcher to embed the content directly in the main window, then inspect the signed dark and light tool pages.

## Round 2 screenshot corrections, 2026-09-29

- [x] Remove corner grain from settings and preview cards. Use regular button sizing and the 180pt control column for cards that contain three-way controls.
- [x] Keep Input volume on one baseline. Give the remaining control width to the slider.
- [x] Render the simple Power preview without the deferred desktop drawing group. Use a neutral status dot.
- [~] Recapture every page in dark and light from the signed installed build. Shared window height, segmented labels, row pitch, status color, and muted contrast fixes remain with the foundation.

## OnePlusUI normalization, 2026-09-29

- [x] Normalize Mac Tweaks to the fixed 1120 x 826 OnePlusUI canvas. Use the 200pt sidebar, 54pt title row, page header, cards, 40pt card headers, 44pt setting rows, 160pt control column, and shared search and selection controls.
- [x] Keep every active tweak, exact-value restore, Modified page, per-row reset, and hover-only preview. Add page routes for Input, Dock, Finder, Windows, Screenshots, Apps, Power, Menu bar, Modified, and About.
- [x] Move Revive Audio into an owned service. Drain at most 16 KiB of standard error while it runs. Cancel it when the window closes. Stop it after 60 seconds.
- [~] Inspect every page in dark and light on the exact installed build. Verify search, reset, Mic Lock, preview hover, protected audio restart, and process cancellation.

## Exact reference geometry and film quality, 2026-09-27

- [x] Match the supplied reference at a static 1120 × 826 points. Fill the complete rounded native window so no transparent titlebar-height strip remains below the UI.
- [x] Put the native traffic lights and Mac Tweaks title on the same 64pt centerline and verify the result from an exact-build screenshot.
- [x] Make the full search surface focus the field, including its icon, key hint, and inner padding. Keep typing, clearing, Command-K, Escape, and typo-ranked results working.
- [x] Port the reference films to continuous hover-only motion with a shared 600 × 304 scene, uniform scaling, clipping, ordered dither, wireframe texture, soft depth, and no overlapping or staged jumps. Return to the same poster frame on leave and respect Reduce Motion.
- [x] Inspect Dock, Finder, Input, ranked search, empty search, and animated preview states from the exact hosted build, then install and verify the clean signed commit.

Hosted run `36329261546` exported the redesigned Dock, Finder, Input, ranked
search, segmented-control, and empty-search captures. The dither and reference
geometry render correctly, but the run exposed a 32pt outer-frame surplus and
a paused hover timeline that did not resume. The scene default now uses the
hidden-titlebar content size while the SwiftUI canvas remains 1120 × 826, and
hover creates an active timeline only while playback is needed. The first
corrected rerun, `36331644220`, showed that SwiftUI still restored an 858pt
outer frame and did not start playback from the synthesized hover. The native
window override in `36332115260` reproduced both failures: the fixed 826pt
SwiftUI root became 858pt after the hidden titlebar, and the hosted runner's
Reduce Motion state kept the hover preview at rest. Run `36332602611` verified
continuous hover playback, all navigation and search states, and the current
visual treatment. Its only Mac Tweaks failure was the flexible root shrinking
to the hosted display's 677pt visible height. Mac Tweaks now fixes the SwiftUI
root at the intended 1120 × 794 content size, which produces the 1120 × 826
outer frame without the old titlebar-height surplus. Preview motion still
follows Reduce Motion in production; only the UI test process forces playback
for deterministic verification. The app and UI test bundles compile; the final
hosted run, `36333394471`, passed the 1120 × 826 frame, continuous hover film,
navigation, icon-side search hit area, typo ranking, segmented controls, empty
state, and dark-appearance checks. All eight exported captures were reviewed.
The hosted 1024 × 768 desktop clips the lower and trailing portions of the
larger reference window, so its screenshots are evidence for the rendered
states while the accessibility frame assertion verifies the complete outer
geometry. Runs `36334450203` and `36334715320` then passed the same Mac Tweaks
UI gate after the shared window-policy and component-package changes. The
immutable committed snapshot at `1b044456db52a43b529e822da01528de550497d9`
built successfully and was installed without disturbing concurrent uncommitted
work. The app and embedded helper were then rebuilt from the documentation-only
successor so both source stamps matched repository HEAD; both use team
`GF57JXJF5A`. A fresh process runs the `/Applications/MacPowerToys.app`
executable with the Mac Tweaks route. Native Computer Use access to
MacPowerToys was denied, so the installed window could not be captured locally.
The development certificate still reports the documented
`CSSMERR_TP_NOT_TRUSTED` trust-chain warning during manual verification; no
Keychain trust was changed.

## Fixed reference redesign, 2026-09-27

- [x] Rebuild the Mac Tweaks window from `mac-tweaks-design.html` as the visual source of truth: a fixed dark shell, 200pt sidebar, aligned native traffic lights and title, compact panels, immediate controls, quiet textures, and the selected Faders icon.
- [x] Preserve every currently implemented Mac Tweaks feature while removing the old disclosure-card and staged Apply flow. Show only actionable controls, keep exact per-key rollback, and make reset available beside each changed setting plus a Modified review page.
- [x] Add short hover-driven previews that rest when idle, reset when the pointer leaves, and respect Reduce Motion. Keep motion local to controls and preview content so navigation remains immediate.
- [x] Finish production behavior for search, empty results, errors, protected actions, restart-later guidance, close/reopen, quit, reset-one, and reset-all. Changes persist immediately; closing or quitting the window must not discard them.
- [x] Verify fixed sizing, keyboard and accessibility labels, every category, search ranking, changed-state recovery, dark rendering, and source-stamped installation. Compare native screenshots against the supplied reference and correct visible layout differences before handoff.

The Release app and desktop test bundles compile after the redesign. The exact
Mac Tweaks source in hosted run `36295278541` passed fixed-frame, navigation,
Mic Lock refresh, ranked search, empty-state, segmented-control sizing, and dark
appearance checks. All seven captures were compared with the HTML reference.
The clean signed app and helper were installed from the current clean commit,
all four source stamps match, and the fresh process runs the exact
`/Applications` executable. Native
Computer Use approval was denied, so the installed window could not be captured
locally. The signed build also hits the documented local development-certificate
trust rejection (`CSSMERR_TP_NOT_TRUSTED`) when manually reverified after the
successful guarded install; no Keychain trust was changed.

## Pinned result and visual examples, 2026-09-26

- [x] Keep the first visible setting row at the top of the content pane while the remaining results scroll. Its expanded controls remain in the scrollable body.
- [x] Add short, replayable examples inside each working setting card. Explain the setting's effect with specific before and after states, match the neutral MacPowerToys style, and stop motion when the card closes. Respect Reduce Motion.
- [x] Align the empty-search action with its message and put expanded form controls on one trailing edge.
- [x] Inspect collapsed, expanded, search, scrolling, light, and dark states in the signed hosted build. Run `36260257730` passed both Mac Tweaks UI tests and confirmed the dark capture's background brightness.

Release app and test bundles compile. Hosted run `36260257730` passed the
collapsed, expanded, category, pinned-row, typo search, empty-search, and dark
appearance interactions. Its light and dark screenshots were reviewed at
900 × 620. Dark appearance uses the app's `appTheme` setting and a pixel check,
since the system-only launch argument had produced a light capture. The
`/Applications` app must be restamped from the final clean documentation commit.
Native Computer access to MacPowerToys was denied, so local app-scoped visual
interaction remains unavailable.

## Tool icon, 2026-09-26

- [x] Present three distinct Mac Tweaks icon options at launcher and small sizes.
- [x] The owner selected 01 Faders. Use that exact artwork for the launcher and the Mac Tweaks Dock icon.
- [~] Verify the selected icon in the signed installed app at launcher and Dock sizes.

The promoted SVG matches 01 Faders byte for byte, the Release asset catalog
contains `MacTweaksLogo`, and the hosted Mac Tweaks captures show the Faders
Dock icon at small size. Local installed-app inspection remains unavailable
because Computer Use approval was denied.

## Inline controls and catalogue correction, 2026-09-26

- [x] Show only working Mac Tweaks controls and saved-value recovery in the app. Keep the rest of the 130-entry research catalogue in the implementation matrix below, not as placeholder cards or sidebar categories.
- [x] Use one consistent compact disclosure row for every visible setting. Open the working control inside its card, keep one card open at a time, and retain category and ranked search context.
- [x] Stop microphone control polling and input-level monitoring when Mic Lock is collapsed. Hosted run `36211588257` expanded and collapsed Mic Lock, switched Finder cards, and opened a typo-matched search result.
- [x] Inspect collapsed, expanded, and search screenshots from the final build. Hosted run `36212055219` passed and the compact Mic Lock card now leaves room for the next row at 900 × 620.

The app and UI test bundle compiled locally. Hosted run `36210967511` stopped before UI launch on an unrelated System Monitor tray compile error. Runs `36211588257` and `36212055219` passed Mac Tweaks UI; the final collapsed, Mic Lock, Finder, Power, and search captures were reviewed. Installed-app verification remains open.

## Navigation and visual correction, 2026-09-26

- [x] Replace the flat item sidebar with one level of grouped category navigation. Show the selected category's settings as scrollable cards in the content pane. Hosted UI run `36182911001` navigated Input, Finder, Power, detail, and ranked search.
- [x] Keep long setting names out of the narrow sidebar. Use distinct category symbols, clear category groups, and the PowerToys menu-bar panel's neutral surfaces and compact spacing. The hosted 900 × 620 captures show single-line sidebar rows and scrollable neutral cards.
- [x] Align the Mac Tweaks traffic lights and sidebar title on the shared 40pt workspace title strip. The hosted window capture shows the centered native controls and title.
- [~] Capture the final installed window, inspect its alignment and density, and correct visible defects before handoff.

The exact-current hosted captures provide the final native-window comparison.
Local capture of the signed installed window remains unavailable because
Computer Use approval was denied.

## Expanded catalogue request, 2026-09-25

- [x] Account for every record in the supplied 130-entry research catalogue with a per-feature implementation status and reason. Treat its availability marks as research evidence, not runtime certification. See [the implementation matrix below](#implementation-matrix).
- [x] Group Mac Tweaks into searchable categories. Sidebar search ranks titles, hidden keywords, phrase patterns, synonyms, and reasonable misspellings instantly.
- [x] Implement supported preference controls with exact-key backup, write-ahead recovery, durable undo, managed-setting checks, conflict-safe rollback, and visible failure states. Batch activation where a target process must refresh.
- [x] Keep the 130-entry compatibility research in documentation. Superseded: research-only entries no longer belong in the app's card list.
- [x] Preserve Mic Lock as the first active enhancement. Mac Tweaks remains an on-demand window with no separate menu-bar item.
- [x] Verify code paths, build, installed app freshness, and available OS behavior. Report which parts still need macOS 15.8 and 26.7 runtime checks.

The final source compiles and its macOS 27 hosted UI checks pass. The app's
current deployment target is macOS 26.2, so macOS 15.8 cannot run this build.
Physical macOS 26.7 preference behavior and device-specific Mic Lock flows
still require hardware runtime checks; unsupported features stay out of the UI.

## Current request

- [x] Add Mac Tweaks as an on-demand MacPowerToys window with a searchable list of tweaks. Do not add a Mac Tweaks menu-bar item or tab.
- [x] Add Mic Lock as the first tweak. Keep the selected macOS input on a saved primary microphone, then three ordered fallbacks, then a safe non-wireless input.
- [x] Let users turn Mic Lock on or off, select inputs by stable device UID, and see saved devices while disconnected.
- [x] React to input changes, device connection, and wake; debounce reconnect bursts. Keep enforcement active while the app runs, even when the window is closed.
- [x] Show the current input, live mute and input volume when the device supports them, and an input-level meter only while the window is open.
- [x] Provide Refresh Devices and Revive Audio recovery actions with clear results. Revive Audio requests administrator approval before restarting CoreAudio.
- [x] Offer MacPowerToys launch at login so an enabled Mic Lock can resume after sign-in.
- [~] Verify device changes, permission states, and the current installed app. Local test-bundle compilation passed; hosted unit tests passed in run 36142313540. Mac Tweaks has no tray tab or separate menu-bar item.

The current app and helper are installed with matching source stamps, and the
app relaunched from `/Applications`. Physical device changes and fresh
permission states remain hardware checks. The local desktop policy does not
allow launching XCTest here.

Reference: [MicLock](https://github.com/WantbeFree/MicLock), whose public README describes the input order and recovery actions.


## Implementation matrix

Checked 2026-09-25. The target families are macOS 15.8, 26.7, and 27.0. The supplied 130 records remain in `TweakCatalog.swift` as a research backlog; only coded controls appear in Mac Tweaks. Mic Lock is an additional, already implemented item. This matrix separates **coded controls** from **observed behavior**. The current Mac compiled on 27.0, but none of the new preference effects has been certified by changing the owner's settings, and 15.8/26.7 have not been runtime tested. The app disables preference writes on unlisted minor releases. Do not interpret a successful preference read-back as proof of visible behavior.

Verdicts:

- **Control coded**: a scoped preference editor, exact original-value and absent-key backup, conflict check, rollback action, and activation guidance exist. New writes are gated to researched OS minors; restore stays available after an OS update. Behavioral certification is still required on each target OS.
- **Existing control reused**: Mac Tweaks exposes an already implemented MacPowerToys service and its persisted controls in the same window.
- **Apple setting in research**: the native control belongs to Apple. Generic shortcuts were removed from the Mac Tweaks window because they did not open the exact setting or edit it.
- **Issue**: the feature is feasible or plausible, but the key, scope, permission path, side effects, lifecycle, or version behavior is unresolved. It has no live toggle.
- **Cannot ship universally**: the stated old recipe is obsolete, broken, or unsafe as one control across all three OS families. Alternatives may exist and would need their own feature record.

The control engine writes only selected keys via exact CFPreferences domains, saves the original value and whether it was absent, and compares the current value before undo so an external change is not overwritten. Dock and Finder refreshes are explicit. Terminal is never closed by the app. A full product claim still requires visible effect, restart persistence, conflicting-setting, and undo checks on all three OS families. [Apple's preference-domain guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html), [exact-domain read API](https://developer.apple.com/documentation/corefoundation/cfpreferencescopyvalue%28_%3A_%3A_%3A_%3A%29), [write/delete API](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/PreferencePanes/Tasks/Preferences.html).

### Controls with a coded preference editor (25)

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

### Existing running control exposed in Mac Tweaks (1)

| ID | Implementation and remaining check |
| --- | --- |
| `helper.keep-awake` | Reuses `AwakeService` and `AwakeSettingsView`: timed, until-date, and indefinite power assertions persist in MacPowerToys. The app must keep running. Check actual sleep behavior on each target OS and supported hardware. |

### Apple settings retained in the research backlog (25)

These may become controls after version-specific implementation and UI checks. They are absent from the Mac Tweaks sidebar and search until then. [Apple System Settings guide](https://support.apple.com/guide/mac-help/change-system-settings-mh15217/mac), [Screenshot options](https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac), [window tiling](https://support.apple.com/guide/mac-help/tile-app-windows-mchlef287e5d/mac).

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
| `native.desktop-click` | Desktop & Dock; "Only in Stage Manager" is not complete disabling. |
| `native.stage-manager` | Desktop & Dock; strip and grouping. |
| `native.hot-corners` | Desktop & Dock; version-specific actions. |
| `native.text-assists` | Keyboard/Text Input; app support varies. |
| `native.keyboard-functions` | Keyboard and Accessibility; hardware varies. |
| `native.trackpad` | Trackpad and Accessibility; hardware varies. |
| `native.appearance` | Appearance and Accessibility; contrast and motion settings. |
| `native.units` | General/Language & Region and Control Center clock. |
| `native.app-options` | Safari, TextEdit, Activity Monitor, Messages; each app owns its UI. |

### Issues to resolve before offering a control (72)

#### Other hidden preferences (24)

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

#### Version-specific preferences (13)

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

#### Research candidates (14)

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

#### Administrator controls (2)

| ID | Blocking issue |
| --- | --- |
| `hardware.auto-start` | Apple documents NVRAM `BootPreference` for Apple silicon laptops on 15+; needs hardware gate, administrator flow, exact prior-state backup, and shutdown test. This controls startup, not closed-lid sleep. |
| `power.schedule` | `pmset` is documented on 15/26; a safe editor must preserve unrelated schedules and account for unsaved work, FileVault, and 27 verification. |

[Apple startup control](https://support.apple.com/en-us/120622), [Apple power scheduling](https://support.apple.com/guide/mac-help/schedule-your-mac-to-turn-on-or-off-mchl40376151/mac), [Apple archived HID note](https://developer.apple.com/library/archive/technotes/tn2450/_index.html), [nix-darwin PAM implementation](https://raw.githubusercontent.com/nix-darwin/nix-darwin/master/modules/security/pam.nix).

#### Running enhancements (19)

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
| `helper.airdrop-workflow` | Received-file identification and folder access without moving unrelated files. |
| `helper.mouse-scroll` | Device discrimination and Input Monitoring permission. |
| `helper.pointer-profiles` | Per-device acceleration and reconnect handling. |
| `helper.mouse-buttons` | Device/button mapping and conflict handling. |

### Cannot ship as one supported control (7)

| ID | Reason |
| --- | --- |
| `avoid.glass-off` | Old whole-system switch applied to Tahoe 26.0 only, with side effects. It is not a 26.7/27 solution. |
| `avoid.icloud-save` | The old global preference is no longer honored by current macOS. |
| `avoid.scroll-stacks` | The old Dock scroll recipe has no current stack-opening proof; scroll-to-Exposé is a different behavior. |
| `avoid.single-app` | The historical Dock mode has no current all-version behavior proof; a helper would be a new feature. |
| `avoid.help-top` | The old Help window recipe has no modern support proof. |
| `avoid.all-animation` | One global key cannot remove every native and custom app animation and has documented side effects. |
| `avoid.split-dark` | The split appearance recipe has documented dark-on-dark notification contrast problems. |

[TinkerTool limitations](https://www.bresink.com/osx/0TinkerTool/issues.html) and [release history](https://www.bresink.com/osx/0TinkerTool/history.html) provide the version and side-effect evidence. These are "cannot ship as stated," not proofs that no different implementation can ever exist.

### Certification gate

For each coded control, use a clean account on 15.8, 26.7, and 27.0; record original key presence/type/value; apply one setting; check the visible effect; restart the target app and sign in again where applicable; change the value from Apple's UI or another utility; verify conflict handling; then restore both originally present and absent keys. Check Dock layouts, Finder file operations, screenshot PDF plus thumbnails, Terminal with active shells, multiple displays and notches, managed preferences, VoiceOver, and permissions. Until those observations exist, this report records the controls as **coded, not runtime certified**.
