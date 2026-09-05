# MacPowerToys goals

Reviewed against current source on 2026-09-05.

This file is the goals index. Each request list contains the detailed status,
evidence, and remaining work. The Dev Sync section below is the active goal
tree for the current build.

## Dev Sync

Contract: `spec/cloud-sync-dev-sync-spec.md`. Status and evidence:
`spec/dev-sync-request-list.md`. Every task ends with a checkpoint commit and
a push. A task is complete only when its check passes.

Legend: `[ ]` pending, `[~]` in progress, `[!]` blocked, `[x]` complete.
`Needs:` names the barrier that must be complete first.

```text
Dev Sync overall            [███████████████████░] 68/69
Checkup G7                  [██████████░░░░░░░░░░] 3/6
G1 Foundation               [████████████████████] 15/15
G2 Dev One-Way              [████████████████████] 14/14
G3 Dev Bidirectional        [████████████████████] 10/10
G4 Interface                [████████████████████] 11/11
G5 Hardening and release    [████████████████████] 13/13
G6 Everything mode          [█████████████████░░░] 5/6
```

### G1 Foundation: a complete read-only first-run plan with no mutation

- [x] 1.1 Shared models in `powertoys/Models/DevSyncModels.swift`: pair, root,
  project, residency, identity, states, signature, baseline, tombstone, link,
  conflict, dirty entry, cursor, action, preconditions, plan, operation,
  policy decision, configuration, `rsync` and volume capabilities.
  Check: the app target builds and a model round-trip test passes.
- [x] 1.2 State store: atomic JSON documents under
  `Application Support/MacPowerToys/DevSync/`, per-project baselines,
  operation journal, backups, and corruption fallback. Needs: 1.1.
  Check: store tests cover round trip, atomic replace, backup restore, and a
  corrupt document.
- [x] 1.3 Roots: bookmark resolution, canonical real paths, same, nested, and
  aliased root rejection, and pair overlap rejection. Needs: 1.1.
  Check: tests for scenarios 20 and 21.
- [x] 1.4 Volumes: UUID identity, mount and unmount observation, read-only and
  capacity reads, and the capability probe with a real temporary probe.
  Needs: 1.1. Check: probe test on the internal volume and a simulated
  capability record for exFAT.
- [x] 1.5 `rsync` capability probe: `--version`, `--help` option parsing,
  self-test, capability record, fingerprint invalidation. Needs: 1.1.
  Check: the probe passes against `/usr/bin/rsync` and the record shows
  `-0`, `--files-from`, `--backup-dir`, no ACL flag.
- [x] 1.6 `rsync` argument builder and exit-code classes. Needs: 1.5.
  Check: builder tests for full fidelity, portable, and unsupported binaries;
  exit classes for 0, 20, 23, 24, 25, other.
- [x] 1.7 Git availability check without the installer dialog, `ls-files`
  manifest, `check-ignore` batch, global ignore identity, lock detection,
  topology analysis for `.git` files, submodules, linked worktrees, bare
  repositories, and alternates. Needs: 1.1. Check: Git matrix fixtures in a
  temporary directory.
- [x] 1.8 Project discovery with `lstat` walk, outermost repository rule,
  unmanaged candidates, identity fingerprint, and rename candidates.
  Needs: 1.7. Check: scenarios 12 to 19.
- [x] 1.9 File policy engine with nine-level precedence, sensitive overrides,
  size guard, common exclusions, transient Git locks, Cloud Sync system paths,
  and a reason for every decision. Needs: 1.7. Check: precedence tests and
  scenarios 25, 40, 50, 51, 52.
- [x] 1.10 Snapshot scanner, quick signatures, streaming SHA-256, stability
  probes, and collision detection. Needs: 1.1. Check: path matrix and
  scenarios 33, 34, 35, 36.
- [x] 1.11 FSEvents monitor with event IDs, root watching, and dropped-event
  flags; dirty scheduler with sliding debounce, checkpoint, storm collapse,
  and persisted dirty work; self-event ledger. Needs: 1.2.
  Check: scheduler tests for scenarios 22, 23, 24, 83, 86.
- [x] 1.12 Reconciliation planner for Dev One-Way with preconditions and an
  immutable plan. Needs: 1.9, 1.10. Check: every row of the one-way decision
  table and the ten planner properties.
- [x] 1.13 First-run planner: project catalog merge, file merge, and preview
  summary. Needs: 1.8, 1.12. Check: first-run tables and scenarios 1 to 5.
- [x] 1.14 Managed link manager: create, validate, repair, adopt, remove,
  offline handling, and exclusion from scans. Needs: 1.4.
  Check: scenarios 2, 6, 55, 66, 67, 68.
- [x] 1.15 Read-only preview end to end on a temporary pair: discovery,
  policy, scan, plan, summary, zero mutations. Needs: 1.13, 1.14.
  Check: an integration test asserts no file changed.

### G2 Dev One-Way: every one-way scenario passes on a real pair

- [x] 2.1 Safety store on the external root and internal history: staging,
  history, conflicts, partial, restrictive permissions, retention limits.
  Needs: 1.2. Check: retention tests and scenario 65.
- [x] 2.2 `rsync` transfer engine: `Process` with argument arrays, NUL
  manifest on stdin, concurrent output capture, progress, cancellation.
  Needs: 1.6. Check: a real transfer of the path matrix through openrsync.
- [x] 2.3 Verifier: post-transfer signature check, source stability, atomic
  baseline commit. Needs: 2.2. Check: scenario 47.
- [x] 2.4 Operation runner with the fifteen-step transaction and journal.
  Needs: 2.1, 2.3. Check: failure injected after every step leaves a
  recoverable journal.
- [x] 2.5 Planned deletions through the safety engine with tombstones.
  Needs: 2.4. Check: scenario 31.
- [x] 2.6 Destination drift detection and the two drift actions.
  Needs: 2.4. Check: scenarios 29, 30, 32.
- [x] 2.7 Policy-change removal to history. Needs: 2.5. Check: scenario 49.
- [x] 2.8 Volatile and large file handling. Needs: 2.4.
  Check: scenarios 44, 45, 46.
- [x] 2.9 Pair engine actor: state machine, one mutation per volume, pause and
  resume, Sync Now merge. Needs: 2.4, 1.11. Check: scenarios 86, 87.
- [x] 2.10 Mount and unmount handling with recovery-required operations.
  Needs: 2.9. Check: scenarios 53, 54, 56, 57, 58.
- [x] 2.11 Crash recovery at launch. Needs: 2.9. Check: scenarios 79, 80, 81.
- [x] 2.12 Residency conversion when an internal project disappears.
  Needs: 2.9, 1.14. Check: scenario 7.
- [x] 2.13 Move to External and Bring Internal transactions. Needs: 2.12.
  Check: scenarios 70 to 73.
- [x] 2.14 Real pair soak: a disposable internal root and a disposable
  external volume image, all one-way scenarios, zero data loss. Needs: 2.13.
  Check: five signed live checks on a 4 GB APFS image; the fifth, on
  `e885f8c`, passed first run, edit, drift, eject, remount, and removal
  with every file intact on both sides.

### G3 Dev Bidirectional: no simultaneous change causes a silent overwrite

- [x] 3.1 Baseline comparator with tolerance and hash escalation. Needs: 2.3.
- [x] 3.2 Tombstone lifecycle. Needs: 2.5. Check: resurrection property.
- [x] 3.3 Two-side planner for every row of the bidirectional table.
  Needs: 3.1, 3.2.
- [x] 3.4 Conflict store with both versions preserved. Needs: 2.1, 3.3.
  Check: scenario 27.
- [x] 3.5 Six conflict resolutions with verified baseline updates. Needs: 3.4.
- [x] 3.6 Rename detection and same-volume counterpart moves. Needs: 3.3.
  Check: scenarios 10, 11.
- [x] 3.7 First-run bidirectional merge. Needs: 3.3, 1.13.
- [x] 3.8 Internal-side deletions to history with the external store online
  guard. Needs: 3.3.
- [x] 3.9 Interrupted two-way operation recovery. Needs: 2.11, 3.3.
- [x] 3.10 Project-level decision when a mirrored project disappears on one
  side. Needs: 3.3. Check: scenario 8.

### G4 Interface: reads as part of Cloud Sync, fast, native

- [x] 4.1 `DevSyncManager` published state and the `Dev Sync` sidebar row with
  a conflict and blocked count badge. Needs: 2.9.
- [x] 4.2 Empty state with `Set Up Dev Sync`. Needs: 4.1.
- [x] 4.3 Setup sheet steps Roots and Compatibility. Needs: 1.3, 1.4, 1.5.
- [x] 4.4 Setup sheet steps Projects and Rules. Needs: 1.13.
- [x] 4.5 Setup sheet steps Activity and Preview with a literal primary
  action. Needs: 1.15.
- [x] 4.6 Pair page strip with state subtitle, Sync Now, Pause or Resume,
  and the actions menu. Needs: 4.1.
- [x] 4.7 Status card. Needs: 4.6.
- [x] 4.8 Project rows as operational cards with residency and state badges,
  sizes, warnings, and every row action. Needs: 4.6.
- [x] 4.9 Conflict cards with metadata, optional diff, and six actions.
  Needs: 3.5.
- [x] 4.10 Notifications for the seven listed events only. Needs: 2.10.
- [x] 4.11 Pair settings replacement page and `DESIGN.md`, `Tool.swift`
  manual, and `CHANGELOG.md` updates. Needs: 4.8.

### G5 Hardening and release

- [x] 5.1 Path matrix integration test through the real `rsync`.
- [x] 5.2 Git matrix fixtures.
- [x] 5.3 File-system matrix on APFS case-insensitive, APFS case-sensitive, and
  an exFAT disk image.
- [x] 5.4 Failure matrix after each transaction step.
- [x] 5.5 Scale check with 10,000 events and 100,000 files; record the
  measurements in the request list.
- [x] 5.6 Deep verification with cancellation.
- [x] 5.7 Power and quality-of-service policies.
- [x] 5.8 Log redaction audit: no contents, secrets, bookmarks, or credentials.
- [x] 5.9 Retention cleanup ordering.
- [x] 5.10 `docs/DEV_SYNC.md` extension guide.
- [x] 5.11 Complete unit suite green, Raycast build green, signed Release
  build, and local installation when no transfer is active. Check: 857
  tests pass at `438aef1`; the installed app embeds that commit.
- [x] 5.12 Live check in the installed build: setup, preview, first sync,
  drift, conflict, unplug, remount, link repair. Check: 12 of 12 steps
  passed on the signed `e885f8c` build; conflict resolution and link repair
  are covered by the engine, links, and interface suites.
- [x] 5.13 Make Git ignore the primary filter inside the running engine:
  feed the Git working-tree manifest into every policy construction (engine
  scan, service preview, deep verification) so project-specific ignore rules
  never reach the drive, and accept dangling symlinks after an openrsync
  partial exit. Check: a fixture with `secrets/` and `*.log` ignored copies
  neither, and a dangling link commits to the baseline.

### G6 Everything mode: sync all except junk

- [x] 6.1 Ask the owner about every ambiguous folder class with real names
  from the dev root. Check: answers recorded in the spec skip-list table.
- [x] 6.2 Expand the skip list across ecosystems, keep `dist`, editor temp,
  logs, game engines, and ML runs, drop Git ignore as a filter, and let
  Git-tracked content win. Check: `testEverythingModeSkipListIsTheOnlyFilter`.
- [x] 6.3 Root unit `Everything else` covering all non-repository content
  with nested units and links carved out. Check:
  `testRootUnitSyncsLooseContentAndLinksDriveOnlyFolders`.
- [x] 6.4 Drive-only folders outside repositories become linked units at
  the same internal path. Check: discovery, catalog, and engine tests.
- [x] 6.5 Setup sheet without include switches, `What syncs` step, Rules
  with Extra patterns, pair page grouped by top-level folder.
- [ ] 6.6 Full suite green, signed install, everything-mode live check on a
  fixture with loose files, `_docs`, nested repositories, `node_modules`,
  `tmp`, and a drive-only folder.

### G7 Checkup: wider launcher, clean sidebars, Input Devices, tray, audit

- [x] 7.1 Launcher 1200 x 720 with four cards per row; saved 780 frames
  cannot return. Check: `testLauncherContentPaneFitsFourToolCardsInOneRow`,
  commits `c2a4277`, `78e5fb6`, screenshot `docs/screenshots/macpowertoys-launcher.png`.
- [x] 7.2 No version string or status dot in any sidebar. Check: `7d41ab0`
  removes the Cloud Sync daemon line and dots and the System Monitor dot.
- [~] 7.3 Input Devices redesign: equal cards, mouse horizontal scrolling,
  shared settings view for tray and launcher. Needs: worker inputdevices.
- [x] 7.4 Tray popover: every tool's shared settings in the popover, no
  extra space under the tab row. Check: `e5edb24`, `db075f4`; three
  `TrayPopoverLayoutTests` measure the 8pt gap, the shared settings per
  tool, and the 70% cap; installed-build check pending in 7.6.
- [~] 7.5 Audit of every tool for performance and correctness, findings at
  `spec/troubleshoot/audit-2026-09-05.md`, grouped Forms on the gutter.
- [ ] 7.6 Full suite green on the merged tree, signed install, live check
  of launcher, Input Devices, tray, and Dev Sync everything-mode.

## Current work

- Dev Sync is complete through the goal tree above; only the visual check
  of an existing transfer row beside a running pair remains in its request
  list.
- Verify native titlebar dragging for Ruler Settings and Ruler Defaults.
- Verify the shared modal Close control in both SSH Anchor sheets.
- Verify the compact Tailscale device chooser with short and scrolling lists,
  including correct row and scrolling geometry.
- Verify hover and pressed feedback for every updated selectable row, card, and
  tab family.
- In one physical menu-bar matrix, verify live None, Combined, and Separate
  modes; compact navigation; saved selection and item positions; Awake sizing
  and selected states; focus and keyboard use; compact and dark appearance;
  contrast; tab-group, body, and footer rhythm; native clicks; and Cloud Sync
  Pause and Resume.
- Verify adaptive multi-column layouts, compact inline metadata, and readable
  narrow-width fallbacks.
- Verify that physical Command-Shift-3 opens Color Picker and suppresses the
  macOS screenshot action.
- Verify visible Raycast icon rendering and the NetToys cold launch. NetToys
  prefill routing and saved-frame restoration are already complete.
- Verify SSH Anchor at minimum width and across real address changes, retained
  key-only access for `win1`, Tailscale fallback and recovery, and host-key
  safety. `win1` is enrolled, healthy, key-verified, and Tailscale-enabled;
  current key-only access is confirmed.
- Verify that a signed NetToys subnet scan streams rows and enrichment fields
  at its minimum window size. The default-size signed scan is complete.
- Verify Input Devices with real mouse and trackpad hardware, sustained wheel
  input, and session lock and unlock.
- Verify System Monitor dragged-position preservation after relaunch and its
  per-item display settings at minimum width. All seven metrics, zero selection,
  enablement, ordering, persistence, and cadence are already test-proven.
- Complete the public release checklist only after every product and live
  verification item above passes.

## Request lists

- [Main app and Cloud Sync](spec/main-request-list.md)
- [Cloud Sync details](spec/cloud-sync-request-list.md)
- [Dev Sync](spec/dev-sync-request-list.md)
- [Awake](spec/awake-request-list.md)
- [Color Picker](spec/color-picker-request-list.md)
- [Text Extractor](spec/text-extractor-request-list.md)
- [Ruler](spec/ruler-request-list.md)
- [Input Devices, System Care, System Monitor, and NetToys](spec/system-tools-request-list.md)

## Status rules

- Use `Done` only when source evidence or a live check proves the result.
- Use `Verify` when the source is complete but the installed app needs a check.
- Use `Open` when implementation work remains.
- Use `Platform limit` when a public macOS API cannot provide the result.
- Use `Accepted` when the user accepts the current behavior or defers the work.

Update this index when a request list adds or closes current work.
