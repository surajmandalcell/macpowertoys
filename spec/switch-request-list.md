# Switch applet request list

Switch remains a separately installable macOS app. MacPowerToys embeds the
versioned `AIManagerCore` Swift package from the Switch repository and provides
its own lightweight SwiftUI applet. Installing Switch.app is optional. Both apps
use the same account store and Core's cross-process operation lock, so changes made in
either app appear in the other after refresh. A Switch Core update reaches
MacPowerToys when its package version is updated and MacPowerToys is rebuilt.

| Status | Requirement | Acceptance |
|---|---|---|
| Hosted launcher route verified | Add Switch to the built-in launcher with window routing, Dock identity, and saved window size. | Open from the launcher and a direct tool link; enable and disable it like other tools. |
| Build verified; live check pending | Use Switch Core without requiring Switch.app or importing its GUI/TUI modules. | A clean MacPowerToys build resolves the pinned Core package and launches with Switch.app absent. |
| Code complete; live check pending | Manage supported accounts in the applet. | Discover/import, sign in, switch defaults, verify, view all available rate-limit buckets, credits, and account activity, and remove accounts through Core with errors and recovery states visible. |
| Hosted verified; live check pending | Preserve standalone Switch's remaining account actions in MacPowerToys. | Open the selected provider, copy its saved auth path, reorder accounts, and inspect source, import, last-use, and workspace details. The combined MacPowerToys menu offers quick account switching and usage on demand. |
| Hosted verified; live check pending | Keep MacPowerToys lightweight: account management, sign-in, import, default switching, verification, usage, and account recovery. Conversation browsing and cleanup stay in standalone Switch. | No conversation or cleanup route, scan, or destructive action in the MacPowerToys applet. Recovery and linked-settings repair remain reachable. |
| Hosted layout and navigation verified; installed account flow pending | Follow the standalone Switch window's flow: narrow functional rail, page title and refresh strip, persistent account list, and adjacent Identity, Usage, activity, and account-detail panels. Keep the original icon. Include Accounts, Backup, and relevant Settings; omit Chat History and Cleanup as agreed. | Compare the port with `switch/docs/screenshots/accounts-dark.png` at 1120×740, then inspect light and dark, empty and populated, Backup, Settings, and minimum-width states. Every visible rail action must work. |
| Static checks complete; live check pending | Preserve performance and credential safety. | No idle polling or conversation scans; synthetic paths for automated tests; no login Keychain access. |

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

The original Switch icon appears in the launcher and Dock asset. The earlier
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
and Usage state. The installed app and helper currently report `5ba62fc`,
which contains the original-layout revision but not the final tray-refresh
correction. An updated signed install remains pending. A
live account and recovery check in the installed app remains open; synthetic
verification did not touch the owner's saved accounts.
