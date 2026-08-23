# Troubleshooting Index

This is the highest-priority repo-local operational guidance after platform and
direct user instructions. Read this file before every task, before other repo
rules, and before inspecting or changing implementation files.

## Mandatory Startup

1. Read this index completely.
2. Read every topic routed for the task completely.
3. Inventory the current implementation with `rg` before choosing a fix.
4. Inspect `git status` and recent commits before editing.
5. Re-read routed topics when the user corrects the result or requirements
   change.

## Mandatory Current Build Rule

- Always build, open, test, install, and report the latest source state only.
- Commit the complete source state and confirm the worktree is clean before the
  final visual launch or installation.
- Before opening an app, confirm its embedded `MPTSourceCommit` equals current
  `HEAD`. A missing or different commit means the app must not be opened.
- Never use `MACPOWERTOYS_UI_TEST=1` for visual verification. Test mode skips
  normal initialization and does not represent the user's app or saved state.
- Use one task-unique DerivedData path and close its preview normally when the
  check ends. Never reuse or open another task's DerivedData product.

## Routing

| Task or symptom | Required topic |
|---|---|
| Tray icon, launcher shell, window persistence | [Main shell](main-shell.md) |
| Applet UI, titlebars, settings placement, gutters, tabs | [UI chrome](ui-chrome.md) |
| Ruler behavior, windows, settings, or FreeRuler parity | [Ruler](ruler.md) |
| Text Extractor UI or behavior | [Text Extractor](text-extractor.md) |
| Input Devices, System Care, Mole, or Power Stats | [System tools](system-tools.md) |
| Internal logs or macOS system diagnostics | [Logs](logs.md) |
| Concurrent edits, staging, overwritten work | [Shared worktree](shared-worktree.md) |
| Builds, UI checks, installation, handoff | [Verification](verification.md) |

Read every matching topic. A task may require more than one.

## Maintenance Contract

- This file is the only troubleshooting entry point. Keep every topic under
  `spec/troubleshoot/` and never create duplicate compatibility rules elsewhere.
- The newest direct user correction wins over older notes. Update or delete the
  conflicting note in the same checkpoint.
- After any repeated defect or user correction, record the verified symptom,
  cause, invariant, and check in the narrowest topic before handoff.
- Keep this file as an index only. Put details in focused topic files under this
  directory and add each new topic to the routing table.
- Do not record guesses, temporary experiments, or unverified explanations.
