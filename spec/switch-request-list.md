# Switch applet request list

Switch remains a separately installable macOS app. MacPowerToys embeds the
versioned `AIManagerCore` Swift package from the Switch repository and provides
its own lightweight SwiftUI applet. Installing Switch.app is optional. Both apps
use the same account store and Core's cross-process operation lock, so changes made in
either app appear in the other after refresh. A Switch Core update reaches
MacPowerToys when its package version is updated and MacPowerToys is rebuilt.

| Status | Requirement | Acceptance |
|---|---|---|
| Code complete; live check pending | Add Switch to the built-in launcher with window routing, Dock identity, and saved window size. | Open from the launcher and a direct tool link; enable and disable it like other tools. |
| Build verified; live check pending | Use Switch Core without requiring Switch.app or importing its GUI/TUI modules. | A clean MacPowerToys build resolves the pinned Core package and launches with Switch.app absent. |
| Code complete; live check pending | Manage supported accounts in the applet. | Discover/import, sign in, switch defaults, verify, view all available rate-limit buckets, credits, and account activity, and remove accounts through Core with errors and recovery states visible. |
| Hosted tests pass; latest UI corrections pending | Preserve standalone Switch's remaining account actions in MacPowerToys. | Open the selected provider, copy its saved auth path, reorder accounts, and inspect source, import, last-use, and workspace details. The combined MacPowerToys menu offers quick account switching and usage on demand. |
| Redesign in progress | Keep MacPowerToys lightweight: account management, sign-in, import, default switching, verification, usage, and account recovery. Conversation browsing and cleanup stay in standalone Switch. | No conversation or cleanup route, scan, or destructive action in the MacPowerToys applet. Recovery and linked-settings repair remain reachable. |
| Redesign in progress | Use an icon-only navigation rail. Put saved accounts in the Accounts pane, never in the rail. Give selection, status, actions, and usage a precise hierarchy that fits the minimum window. | Inspect light and dark renders at default and minimum sizes; check empty, selected, error, and keyboard states. |
| Static checks complete; live check pending | Preserve performance and credential safety. | No idle polling or conversation scans; synthetic paths for automated tests; no login Keychain access. |

The owner's active desktop is not an acceptable test environment for app-hosted
or UI test runners. Executable checks and synthetic renders run on hosted macOS;
local checks compile without launching the app. Account verification clears
cached usage when Core reports that sign-in is needed.

Before the lightweight redesign, synthetic Core checks covered account import,
default switching, removal, and recovery. Switch Core's chat and cleanup tests
remain in the standalone repository. The MacPowerToys test bundle now covers
account management and captures Accounts and Recovery in light and dark at
880pt and 1,024pt, plus the compact Switch menu. Hosted run 36128135753
passed the full macOS suite. Its renders exposed a duplicate import suggestion
for a saved account and a transparent quick-menu capture. Both are corrected
in later code; those corrections still need a hosted rerun and visual review.
