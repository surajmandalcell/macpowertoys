# Mac Tweaks request list

## Round 5 screenshot corrections, 2026-09-29

- [x] Derive Modified from live values versus declared defaults, including values changed outside Mac Tweaks. Keep exact-value restore for backed-up changes and return untracked changes to the system default.
- [x] Show Dock timing defaults as `Default (0.40)` and `Default (0.35)` with seconds, and show declared defaults in select controls.
- [x] Keep preview scenes and labels on fixed dark colors in Light and Dark. Remove the Power preview instruction chip and use sentence case for the live status.
- [x] Keep long Finder, Windows, and microphone controls readable. Use distinct Input section icons and keep the input meter visible beside Test.
- [~] Recapture all ten pages from the exact signed build. The 41pt scroll gutter and 28pt header gap remain shared OnePlusUI foundation fixes.

## Owner review 1 corrections, 2026-09-29

- [x] Keep the shared page header at `T = 58` and every card on its 24pt leading edge. Mac Tweaks draws no local page header or second body inset.
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

- [x] Show only working Mac Tweaks controls and saved-value recovery in the app. Keep the rest of the 130-entry research catalogue in the compatibility document, not as placeholder cards or sidebar categories.
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

- [x] Account for every record in the supplied 130-entry research catalogue with a per-feature implementation status and reason. Treat its availability marks as research evidence, not runtime certification. See `spec/mac-tweaks-compatibility.md`.
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
