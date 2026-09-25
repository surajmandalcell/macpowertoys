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
| Hosted layout checked; keyboard/live pending | Use an icon-only navigation rail. Put saved accounts in the Accounts pane, never in the rail. Give selection, status, actions, and usage a precise hierarchy that fits the minimum window. | Inspect light and dark renders at default and minimum sizes; check empty, selected, error, and keyboard states. |
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
The earlier installed app reports source commit `dc97280`; the latest Switch UI
commits have hosted verification but are not installed locally. The earlier
install gate recorded successful signature verification. A sandboxed repeat
returned `CSSMERR_TP_NOT_TRUSTED`, so it cannot establish a trust failure.
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
