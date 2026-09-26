# Mac Tweaks request list

## Inline controls and catalogue correction, 2026-09-26

- [ ] Show only working Mac Tweaks controls and saved-value recovery in the app. Keep the rest of the 130-entry research catalogue in the compatibility document, not as placeholder cards or sidebar categories.
- [ ] Use one consistent compact disclosure row for every visible setting. Open the working control inside its card, keep one card open at a time, and retain category and ranked search context.
- [ ] Stop microphone control polling and input-level monitoring when Mic Lock is collapsed. Verify category switching and search do not stall.
- [ ] Inspect collapsed, expanded, and search screenshots from the final build and correct any visible density or alignment defects.

## Navigation and visual correction, 2026-09-26

- [x] Replace the flat item sidebar with one level of grouped category navigation. Show the selected category's settings as scrollable cards in the content pane. Hosted UI run `36182911001` navigated Input, Finder, Power, detail, and ranked search.
- [x] Keep long setting names out of the narrow sidebar. Use distinct category symbols, clear category groups, and the PowerToys menu-bar panel's neutral surfaces and compact spacing. The hosted 900 × 620 captures show single-line sidebar rows and scrollable neutral cards.
- [x] Align the Mac Tweaks traffic lights and sidebar title on the shared 40pt workspace title strip. The hosted window capture shows the centered native controls and title.
- [ ] Capture the final installed window, inspect its alignment and density, and correct visible defects before handoff.

## Expanded catalogue request, 2026-09-25

- [x] Account for every record in the supplied 130-entry research catalogue with a per-feature implementation status and reason. Treat its availability marks as research evidence, not runtime certification. See `spec/mac-tweaks-compatibility.md`.
- [x] Group Mac Tweaks into searchable categories. Sidebar search ranks titles, hidden keywords, phrase patterns, synonyms, and reasonable misspellings instantly.
- [ ] Implement supported preference controls with exact-key backup, durable undo, managed-setting checks, and visible failure states. Batch activation where a target process must refresh.
- [x] Keep the 130-entry compatibility research in documentation. Superseded: research-only entries no longer belong in the app's card list.
- [x] Preserve Mic Lock as the first active enhancement. Mac Tweaks remains an on-demand window with no separate menu-bar item.
- [ ] Verify code paths, build, installed app freshness, and available OS behavior. Report which parts still need macOS 15.8 and 26.7 runtime checks.

## Current request

- [x] Add Mac Tweaks as an on-demand MacPowerToys window with a searchable list of tweaks. Do not add a Mac Tweaks menu-bar item or tab.
- [x] Add Mic Lock as the first tweak. Keep the selected macOS input on a saved primary microphone, then three ordered fallbacks, then a safe non-wireless input.
- [x] Let users turn Mic Lock on or off, select inputs by stable device UID, and see saved devices while disconnected.
- [x] React to input changes, device connection, and wake; debounce reconnect bursts. Keep enforcement active while the app runs, even when the window is closed.
- [x] Show the current input, live mute and input volume when the device supports them, and an input-level meter only while the window is open.
- [x] Provide Refresh Devices and Revive Audio recovery actions with clear results. Revive Audio requests administrator approval before restarting CoreAudio.
- [x] Offer MacPowerToys launch at login so an enabled Mic Lock can resume after sign-in.
- [ ] Verify device changes, permission states, and the current installed app. Local test-bundle compilation passed; hosted unit tests passed in run 36142313540. Mac Tweaks has no tray tab or separate menu-bar item.

Release and test bundles compile. The local desktop policy does not allow launching XCTest here.

Reference: [MicLock](https://github.com/WantbeFree/MicLock), whose public README describes the input order and recovery actions.
