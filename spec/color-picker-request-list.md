# Color Picker Request List

Reviewed against the current app source on 2026-07-14. Update this list when a
direct user correction or verified result changes a status.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Open | Keep a settings cog at the top-right beside `Pick Color`, opening the full settings page inside the same window. | `8f0209c` restored it, but `63ffc2f` later replaced it with a bottom-right `FloatingSettingsButton`. | Restore the top-right cog without compacting the settings UI. |
| Verify | Remove lag while the native color sampler is active. | `5b3d174` rejects overlapping sampler sessions and reuses the row date formatter. Its unit check passes. | Measure the normal installed app during an active pick. |
| Verify | Prevent transient focus outlines when the window first opens. | Compact titlebar, tab, and icon controls suppress focus effects. | Check a fresh normal launch before interaction. |
| Done | Make the Color Picker window narrower. | `ColorPickerLayout.windowWidth` is a fixed 420pt. | None. |
| Done | Move the tool title and primary pick action into one compact top row. | `CompactTitlebar` contains the text-only title and `Pick Color`. | None. |
| Done | Keep titlebar buttons at their prior compact size and prevent them from merging. | Shared actions are separate 24pt controls; only `Pick Color` has accent fill. | None. |
| Done | Remove the titlebar bottom border, app icon, and Clear action. | The shared titlebar has no separator or app icon; destructive clearing lives in Settings. | None. |
| Done | Move shortcut controls into a proper settings page. | Settings contains the enable toggle, fixed modifiers, key picker, and explanatory text. | None. |
| Done | Show only Settings content while Settings is open, with no top body margin. | History and Projects tabs render only outside Settings; the settings body has no top padding. | None. |
| Done | Left-align `Enable Pick Color shortcut` and place `Clear All` below it. | Both controls use leading alignment; clearing has scope text and confirmation. | None. |
| Done | Add Projects creation, selection, project-owned picks, persistence, and export. | `ColorPickerService` owns projects and selected destination; `ColorPickerTests` covers ownership and persistence; each named project exports CSS. | None. |
| Done | Make Search and format Select the same height. | Both controls are exactly 28pt high. `DESIGN.md` records Google's 56dp parity principle and the app's compact 28pt rule. | None. |
| Done | Fix selected-tab and content left-edge alignment. | Tabs, controls, rows, cards, and settings use one 12pt outer gutter; selection does not change tab geometry. | None. |
| Done | Reduce left and right body padding. | `ColorPickerLayout.bodyHorizontalInset` is 12pt throughout the applet body. | None. |
| Done | Vertically align titlebar items, lower traffic lights, remove zoom, and prevent resizing. | Color Picker uses the shared 20pt centerline, 4pt traffic-light offset, hidden zoom, and fixed root size. | None. |
| Done | Prevent the unsigned UI-runner Gatekeeper dialog and stale visual checks. | The mandatory verification rules prohibit unsigned UI runners, UI-test-mode visual QA, stale provenance, and shared DerivedData. | None. |
| Superseded | Add numbered `.agents/troubleshooting1.md` files and make agents load them. | The newer repo rule requires one `spec/troubleshoot/troubleshoot.md` entry point. Both `AGENTS.md` and `CLAUDE.md` load it, this list, and `DESIGN.md`. | Keep focused troubleshooting topics under `spec/troubleshoot/`; do not recreate compatibility files. |
