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

## Routing

| Task or symptom | Required topic |
|---|---|
| Applet UI, titlebars, settings placement, gutters, tabs | [UI chrome](ui-chrome.md) |
| Text Extractor UI or behavior | [Text Extractor](text-extractor.md) |
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
