# Switch workspace request list

Switch remains a separately installable macOS app. MacPowerToys embeds the
versioned `AIManagerCore` Swift package from the Switch repository and provides
its own SwiftUI workspace. Installing Switch.app is optional. Both apps use the
same account store and Core's cross-process operation lock, so changes made in
either app appear in the other after refresh. A Switch Core update reaches
MacPowerToys when its package version is updated and MacPowerToys is rebuilt.

| Status | Requirement | Acceptance |
|---|---|---|
| Code complete; live check pending | Add Switch to the built-in launcher and give it a native full workspace, window routing, Dock identity, and saved window size. | Open from the launcher and a direct tool link; enable and disable it like other tools. |
| Build verified; live check pending | Use Switch Core without requiring Switch.app or importing its GUI/TUI modules. | A clean MacPowerToys build resolves the pinned Core package and launches with Switch.app absent. |
| Code complete; live check pending | Manage supported accounts in the workspace. | Discover/import, sign in, switch defaults, verify, view usage, and remove accounts through Core with errors and recovery states visible. |
| Code complete; live check pending | Provide Switch's conversation and maintenance features where Core supports them. | Browse/search conversations and messages, filter roles, copy shown messages, page through long transcripts, and review cleanup before any destructive action; recovery remains discoverable. |
| Pending isolated UI check | Match MacPowerToys workspace visual and accessibility rules. | Inspect normal signed UI at default and minimum sizes in light/dark appearances; check loading, empty, selected, error, and keyboard states. |
| Static checks complete; live check pending | Preserve performance and credential safety. | No idle polling; Core runs history scans with bounded workers; synthetic paths for automated tests; no login Keychain access. |

The owner's active desktop is not an acceptable test environment for app-hosted
or UI test runners. Live checks remain pending until an isolated macOS account
or VM is available. A history scan already in flight may finish after the
window closes; opening the workspace does not start background polling.

Verification on 2026-09-25: compile-only Debug and Release builds passed;
Raycast lint, build, and icon parity passed; the headless Switch Core suite
passed 184 tests with 2 optional private-copy fixture tests skipped. The
MacPowerToys window was not launched for this final verification pass.

The cleanup path was checked again with a synthetic conversation after wiring
Core's shared activity ledger: a headless run moved the reviewed file to
recoverable Trash and retained its 123-token activity record. The MacPowerToys
test bundle compiled without executing its app host or UI runner.

A second headless run entered Maintenance without first opening Conversations,
confirmed the conversation title, moved it to Trash, and restored it with the
title intact. Account verification now clears cached usage when Core reports
that sign-in is needed; the workspace hides usage in that state.

A separate headless run used the exact Core revision pinned by MacPowerToys
with synthetic credentials. It imported two accounts, changed the default,
and removed the active account with an explicit replacement. No browser,
real credential store, or app window was opened.

The message workspace now uses Core's complete-conversation search and paged
detail API. A synthetic 121-message transcript was checked headlessly: the
first 100 and remaining 21 loaded in order, a response beyond the first page
matched a two-term search, the prompt filter excluded it, and export contained
only the shown result. The app and test bundles compiled without a launch.
