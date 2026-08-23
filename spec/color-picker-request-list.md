# Color Picker Request List

Reviewed against the current app source on 2026-08-24. Update this list when a
direct user correction or verified result changes a status.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Keep project counts and color timestamps on their related row. | `4ad3da2` puts each project count beside its name and each timestamp beside its color value. It also reduces the project row to the shared compact height. The full unit suite passes. | Inspect long project names and color values at the fixed window width. Confirm that primary text truncates before the count or time clips. |
| Superseded | Keep a settings cog at the top-right beside `Pick Color`. | The newer cross-app chrome requirement reserves compact titlebars for app names and primary actions; Color Picker uses the shared bottom-right `FloatingSettingsButton` for its full settings page. | Keep settings out of the compact titlebar. |
| Verify | Remove lag while the native color sampler is active. | `5b3d174` rejects overlapping sampler sessions and reuses the row date formatter. Its unit check passes. | Measure the normal installed app during an active pick. |
| Done | Prevent transient or persistent titlebar focus outlines. | Shared titlebar controls suppress focus effects, and Color Picker routes initial focus to its invisible window accessor like every compact applet. Fresh-open and cross-window focus checks in the normal signed `98f35f6` build showed no outline. | None. |
| Done | Make the Color Picker window narrower. | `ColorPickerLayout.windowWidth` is a fixed 420pt. | None. |
| Done | Move the tool title and primary pick action into one compact top row. | `CompactTitlebar` contains the text-only title and `Pick Color`. | None. |
| Verify | Keep titlebar buttons compact, slightly rounded, and visually separate. | Shared actions are separate 24pt controls with the titlebar-only 6pt radius; only `Pick Color` has accent fill. | Compare the fresh-open, hover, disabled, and focused states in the normal build. |
| Done | Remove the titlebar bottom border, app icon, and Clear action. | The shared titlebar has no separator or app icon; destructive clearing lives in Settings. | None. |
| Done | Move shortcut controls into a proper settings page. | Settings contains the enable toggle, a click-to-record `ShortcutRecorderField` that captures any modifier-plus-key combination, and explanatory text. | None. |
| Done | Show the same Color Picker settings when selected in the main launcher. | The applet and launcher both render `ColorPickerSettingsView`; shortcut, recorder, and Clear All behavior have one implementation. | Verify the shared surface in the final installed build. |
| Verify | Use Command-Shift-3 as the default Pick Color shortcut and allow it to be recorded. | Color Picker defaults to the physical 3 key with Command and Shift. The shared recorder normalizes shifted number-row labels, and a session event tap can suppress macOS's reserved screenshot chord after Accessibility access is granted. | Grant the access request if shown, then invoke Command-Shift-3 from another app and confirm Color Picker opens without taking a screenshot. |
| Done | Show only Settings content while Settings is open, with no top body margin. | History and Projects tabs render only outside Settings; the settings body has no top padding. | None. |
| Done | Left-align `Enable Pick Color shortcut` and place `Clear All` below it. | Both controls use leading alignment; clearing has scope text and confirmation. | None. |
| Done | Add Projects creation, selection, project-owned picks, persistence, and export. | `ColorPickerService` owns projects and selected destination; `ColorPickerTests` covers ownership and persistence; each named project exports CSS. | None. |
| Done | Make Search and format Select the same height. | Both controls are exactly 28pt high. `DESIGN.md` records Google's 56dp parity principle and the app's compact 28pt rule. | None. |
| Done | Fix selected-tab and content left-edge alignment. | Tabs, controls, rows, cards, and settings use one 12pt outer gutter; selection does not change tab geometry. | None. |
| Done | Reduce left and right body padding. | `ColorPickerLayout.bodyHorizontalInset` is 12pt throughout the applet body. | None. |
| Done | Vertically align the complete titlebar row, lower traffic lights, remove zoom, and reclaim its title space. | Color Picker uses one 4pt row inset, a 22pt centerline, a 6pt traffic-light shift, a 60pt title start, hidden zoom, and a fixed root size. `WindowAccessor` now reapplies the shared alignment whenever the window becomes key; regression coverage forces the late native reset that previously left the lights 6pt high. | None. |
| Done | Prevent the unsigned UI-runner Gatekeeper dialog and stale visual checks. | The mandatory verification rules prohibit unsigned UI runners, UI-test-mode visual QA, stale provenance, and shared DerivedData. | None. |
| Superseded | Add numbered `.agents/troubleshooting1.md` files and make agents load them. | The newer repo rule requires one `spec/troubleshoot/troubleshoot.md` entry point. Both `AGENTS.md` and `CLAUDE.md` load it, this list, and `DESIGN.md`. | Keep focused troubleshooting topics under `spec/troubleshoot/`; do not recreate compatibility files. |
