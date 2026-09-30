# Switch applet request list

Switch remains a separately installable macOS app. MacPowerToys embeds the
versioned `AIManagerCore` Swift package from the Switch repository and provides
its own lightweight SwiftUI applet. Installing Switch.app is optional. Both apps
use the same account store and Core's cross-process operation lock, so changes made in
either app appear in the other after refresh. A Switch Core update reaches
MacPowerToys when its package version is updated and MacPowerToys is rebuilt.

| Status | Requirement | Acceptance |
|---|---|---|
| Pending, failed, and loaded states captured; hosted checks pending | Keep Daily activity stable before preparation completes and during refresh. | `f2f5436` reserves the 82pt grid with 16pt inner padding, shows pending totals as dashes, and replaces grid and totals together. All eight signed `3e33de2` Switch captures were reviewed. Loaded activity shows seven neutral grid rows in both appearances; pending and unavailable states were captured in round 5. The activity card retains its 220pt bounds and Usage its 264pt bounds. Debug and the desktop-test scheme build-for-testing pass. Hosted bounds tests, refresh retention, account and period changes, and the active Usage scroller remain unverified. `eb01001e` changes the About copy in `Models/Tool.swift` to "Choose Use as default" and "Backup shows interrupted operations". See `tmp/redesign/logs/25r9-nettoys.md`. |
| Build verified; signed review pending | Keep Switch Usage compact with the same bounds for loading, error, and loaded data. | `64d09cb` replaces the 392pt minimum body with a fixed 224pt body, giving a 264pt card. Usage facts stay fixed and all quota buckets remain available in the card's row scroller. Debug and desktop build-for-testing pass. Signed loading, error, single-bucket, and multiple-bucket checks remain. The main/catalog owner must change the manual point in `Models/Tool.swift` from "Make Default" to "Use as default". |
| Usage geometry superseded; other fixes retained | Keep the Switch usage card height stable and correct the round 2 page actions and copy. | The 392pt body in `b0fa4497` is replaced by the compact geometry above. `70c9b132` removes the default-state check glyph and Settings refresh action, standardizes Backup headers, and uses `Version` in About. A clean current-commit copy passes Debug and desktop build-for-testing. Inspect every state in the signed build. |
| Code complete; visual timing check pending | Keep Switch page changes within 100 ms and keep activity scrolling smooth. | Account-manager setup now runs after presentation on a detached task. The 365-day activity grid builds dates, labels, intensity levels, and totals off the main actor, then renders light cells without per-cell tooltips. Usage still loads only when an account opens or the user refreshes it. Measure page switches and inspect the populated activity grid in the signed build. |
| Build verified; integration pending | Expose one shared settings card body for the Switch window and launcher. | `b19734c` adds `SwitchSettingsContent(paths: ManagerPaths = .environment())` with App behavior, Menu bar defaults, and Data locations. The window uses it inside its existing `OnePlusPage`. It adds no page, outer gutter, scroll view, spacer, height expansion, or density override. Debug and desktop test compilation passed. Foundation must dispatch to `SwitchSettingsContent()` and delete `SwitchLauncherSettingsView`. Signed review remains. |
| Code complete; visual checks pending | Apply round 2 screenshot corrections to Switch. Remove the duplicate Appearance setting and use SF Mono for paths. Keep the allowed 44pt account rows. | `8c08a7c` updates Settings, import, and recovery through the shared path-row variant `dd25ae3`. Account subtitles use the caption role with shared icon and text alignment. Debug and desktop test compilation passed. New signed captures remain. Shared window, tint, focus, density, and contrast fixes belong to the foundation. |
| Code complete; Debug build passed; visual checks pending | Rebuild Switch with DESIGN.md v14 at 1240 by 840 points, a 200-point account sidebar, shared cards, and the original Switch and provider artwork. This replaces the earlier standalone rail layout requirement. | `6fb4d0a` covers accounts, `account/<id>`, Add, Backup, Settings, and About. Keeps Core account actions, on-demand usage, seven usage facts, quotas, credits, neutral activity, import conflicts, and recovery. Uses shared appearance; Core stays pinned at v3.3.0. Foundation now accepts nested account routes and imports OnePlusUI in the scrollbar tests. Lead-agent dark/light captures and installed interaction checks remain. |
| Hosted launcher route verified | Add Switch to the built-in launcher with window routing, Dock identity, and saved window size. | Open from the launcher and a direct tool link; enable and disable it like other tools. |
| Build verified; live check pending | Use Switch Core without requiring Switch.app or importing its GUI/TUI modules. | A clean MacPowerToys build resolves the pinned Core package and launches with Switch.app absent. |
| Code complete; live check pending | Manage supported accounts in the applet. | Discover/import, sign in, switch defaults, verify, view all available rate-limit buckets, credits, and account activity, and remove accounts through Core with errors and recovery states visible. |
| Hosted verified; live check pending | Preserve standalone Switch's remaining account actions in MacPowerToys. | Open the selected provider, copy its saved auth path, reorder accounts, and inspect source, import, last-use, and workspace details. The combined MacPowerToys menu offers quick account switching and usage on demand. |
| Hosted verified; live check pending | Keep MacPowerToys lightweight: account management, sign-in, import, default switching, verification, usage, and account recovery. Conversation browsing and cleanup stay in standalone Switch. | No conversation or cleanup route, scan, or destructive action in the MacPowerToys applet. Recovery and linked-settings repair remain reachable. |
| Hosted layout and navigation verified; installed account flow pending | Follow the standalone Switch window's flow: narrow functional rail, page title and refresh strip, persistent account list, and adjacent Identity, Usage, activity, and account-detail panels. Include Accounts, Backup, and relevant Settings; omit Chat History and Cleanup as agreed. | Compare the port with `switch/docs/screenshots/accounts-dark.png` at 1120×740, then inspect light and dark, empty and populated, Backup, Settings, and minimum-width states. Every visible rail action must work. |
| Assets built; installed visual check pending | Use the owner's selected 01-refined version of 05 emergency-stop for standalone Switch and the MacPowerToys launcher, window, and Dock identity. | Both apps use the same physical-switch artwork, readable at 32px, in light and dark appearances. The existing small menu-bar template keeps the original vector mark. |
| Static checks complete; live check pending | Preserve performance and credential safety. | No idle polling or conversation scans; synthetic paths for automated tests; no login Keychain access. |
| Hosted verified; installed interaction pending | Match the original Switch account controls and provider artwork. | Center the custom close control in the 48-point rail cell; remove the redundant rail plus; use the original Add Account provider flow, provider icons, double-check state, and “Use as default” copy. Compact About modals must not show an oversized self-Open action. |
| Hosted verified; installed interaction pending | Make Backup and usage layouts clear at the minimum window width. | Backup explains when recovery actions become available and provides a useful destination action; disabled controls remain legible. Activity period and duration values stay inside their panels without wrapping into extra rows. |
| Core, standalone, and hosted applet verified; installed interaction pending | Support Claude Code accounts through shared Switch Core. | Both standalone Switch and MacPowerToys list, sign in to, and switch managed Claude Code profiles through the same Core package without requiring the standalone app. |

The owner's active desktop is not an acceptable test environment for app-hosted
or UI test runners. Executable checks and synthetic renders run on hosted macOS;
local checks compile without launching the app. Account verification clears
cached usage when Core reports that sign-in is needed.

Before the lightweight redesign, synthetic Core checks covered account import,
default switching, removal, and recovery. Switch Core's chat and cleanup tests
remain in the standalone repository. The MacPowerToys test bundle now covers
account management and captures Accounts and Recovery in light and dark at
880pt and 1,024pt, plus the compact Switch menu. Hosted run 36129347170
passed the full macOS suite, built an installable archive, and confirmed the
duplicate import suggestion is gone. Its updated quick-menu renders have a
proper background in both appearances. Account-changing actions remain verified
with synthetic Core tests; the owner's saved accounts were not touched.
An earlier installed app reported source commit `dc97280`. Its install gate
recorded successful signature verification. A sandboxed repeat returned
`CSSMERR_TP_NOT_TRUSTED`, so it could not establish a trust failure.
A targeted hosted UI test opens Switch through its supported CLI route and
traverses Accounts and Recovery. Run 36131532331 passed unit tests but Xcode
could not spawn its separate UI-test Debug app. A separate build output and
explicit entitlements fixed that launch error. The Switch-only hosted workflow
avoids cancellation by unrelated shared CI pushes. Run 36137254239 passed both
the CLI navigation and launcher-to-Switch route on a 1024pt display, and its
screenshots confirm the launcher header actions remain visible. Run 36138071917
passed again after removing the duplicate launcher action and captured the
three-column All Tools grid at 1024pt. The owner's desktop was not used for
testing.

The selected emergency-stop artwork now supplies the launcher and Dock asset.
The earlier
header-tab revision passed launcher and CLI routes in hosted run 36150764154,
Accounts/Recovery navigation, and opening About, with window captures.
Run 36150672552 captured empty and populated Accounts at 880pt and 1,024pt in
light and dark, plus Recovery and the quick menu. The focus-outline assertion
was corrected, and the full hosted macOS suite passed in run 36153836043.
That header-tab revision was superseded by the original-layout revision below.

The original-layout revision now has the standalone 48-point icon rail,
200-point account list, title strip, Identity and Usage panels, activity grid,
and Backup/Settings pages. Selected-account usage checks once in the background;
failures stay inside its panel instead of opening a global alert. Settings
include the original Codex and Grok data locations with Reveal controls and a
usage-percentage choice shared with the compact menu. Hosted run 36184390010
captured light and dark, empty and populated, Backup, Settings, and 880-point
renders. Its two Switch-related repository UI checks found a missing focus
modifier and thin scroller on the activity grid; both are fixed in the next
revision. That run also had an unrelated Portman failure. Hosted Switch UI run
36184481199 opened Switch from the launcher, then found the Add control under
a different accessibility element type; the test now queries the identifier
and opens the provider menu. The final focused navigation run 36188088138
passed Accounts, Backup, Settings, About, and the Add provider menu. Full hosted
run 36188072379 passed every job, including synthetic Core actions, and captured
populated Accounts and Settings at 1120pt and 880pt in both appearances plus
the compact menu. Visual review found that the synthetic Usage snapshot could
be visible while Identity reverted to “Saved, not checked”: the host reloaded
an already populated model. The window now loads only a fresh model, and its
render-state assertion runs before the tray's intentional refresh. Compile-only
validation and every job in hosted run 36191255746 passed. Its populated
Accounts renders at 1120pt and 880pt in both appearances show matching Identity
and Usage state. Full hosted run 36192321188 also passed every job on the later
shared code revision. The signed app and helper installed from clean `eef6657`
pass strict verification, report matching source stamps, and the app runs from
`/Applications/MacPowerToys.app` after a background launch. A live account and
recovery check in the installed window remains open because Computer Use access
to MacPowerToys was rejected by automatic approval review. Synthetic verification
did not touch the owner's saved accounts.

The provider images in the applet come from standalone Switch's
`packages/mac-gui/Resources/Icons`: `ProviderCodex.png`,
`ProviderClaudeCode.svg`, `ProviderGeminiCLI.svg`,
`ProviderAntigravityCLI.png`, and `ProviderGlyphs/grok.png`. Their provenance
remains documented in that repository's `PROVIDER-ICON-PROVENANCE.txt`.

Switch Core v3.3.0 includes isolated Claude Code profiles. Its 185 Core tests
pass with synthetic homes, and the standalone UI builds and CLI acceptance passes.
MacPowerToys resolves the renamed `switch.git` package at v3.3.0. Hosted run
36211479231 exposed five missing custom-control focus modifiers in Switch; run
36211622600 exposed a brittle static-text query in the Add Account UI test.
Both are corrected in source. Offscreen renders from the first run also showed
the close symbol shifted out of its 48pt cell; the rail width correction is
visible in the subsequent hosted captures.

Hosted run 36213704605 passed all macOS jobs, including unit tests, and its
populated light and dark captures at 1120pt and 880pt show aligned Identity,
Usage, rate-limit bars, and the activity period control. Focused run
36213722329 passed launcher and CLI-route navigation through Accounts,
Backup, Settings, and About. The original Codex, Grok, Claude Code, Gemini,
and Antigravity provider artwork was compared byte for byte with standalone
Switch; focused run 36214350586 captured it in the Add Account picker. The
first compact About capture compressed one sentence, so its sheet gained the
needed height. Focused run 36215187515 passed, and its capture shows the full
sentence without an Open button. Standalone Switch 3.3.0 is installed with a
verified signature and responsive bundled CLI. Managed Claude profiles were
exercised only with synthetic homes; no saved account or login Keychain was read.
