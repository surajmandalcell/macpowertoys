# Switch workspace request list

Switch remains a separately installable macOS app. MacPowerToys embeds the
versioned `AIManagerCore` Swift package from the Switch repository and provides
its own SwiftUI workspace. Installing Switch.app is optional. Both apps use the
same account store and Core's cross-process operation lock, so changes made in
either app appear in the other after refresh. A Switch Core update reaches
MacPowerToys when its package version is updated and MacPowerToys is rebuilt.

| Status | Requirement | Acceptance |
|---|---|---|
| Pending | Add Switch to the built-in launcher and give it a native full workspace, window routing, Dock identity, and saved window size. | Open from the launcher and a direct tool link; enable and disable it like other tools. |
| Pending | Use Switch Core without requiring Switch.app or importing its GUI/TUI modules. | A clean MacPowerToys build resolves the pinned Core package and launches with Switch.app absent. |
| Pending | Manage supported accounts in the workspace. | Discover/import, sign in, switch defaults, verify, view usage, and remove accounts through Core with errors and recovery states visible. |
| Pending | Provide Switch's conversation and maintenance features where Core supports them. | Browse/search history and review cleanup before any destructive action; recovery remains discoverable. |
| Pending | Match MacPowerToys workspace visual and accessibility rules. | Inspect normal signed UI at default and minimum sizes in light/dark appearances; check loading, empty, selected, error, and keyboard states. |
| Pending | Preserve performance and credential safety. | No idle polling; expensive work runs off the main actor and stops with the window; synthetic paths for automated tests; no login Keychain access. |
