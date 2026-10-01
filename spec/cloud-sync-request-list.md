# Cloud Sync Request List

Reviewed against current source on 2026-10-01.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Verify | Audit all Cloud Sync features and apply the 2026-10-01 density and motion rules. | `70fbe4f8`, `14af8be6`, `899359a7`, `d2bfd0d6`, `0b749887`, and `19a2077d` fix authenticated drag-out, file-kind selection and file Move, stale Quick Look caches, average speed after resume, and Dev Sync preview/error handling. Cleanup has a native delete confirmation. The file-tree Ignore action keeps its width and is visible for keyboard navigation and VoiceOver. Shared controls and text roles replace local chrome; metadata is trailing; single project/safety rows, settings controls and breadcrumbs use less chrome; local content motion and pill badges are removed. Actual RC and snapshot checks pass on files created in `tmp/redesign/audit-cloudsync/`. Both gated builds pass, including focused test compilation. Eight `36c585b4` background captures are baseline evidence. Report: `tmp/redesign/logs/w1-audit-cloudsync.md`. | Run the hosted regressions. The orchestrator must install clean HEAD, verify source stamp/path, capture both appearances, and exercise every changed control. OAuth, provider keys, saved remotes, live Dev Sync, and physical A4-A7 checks remain open. |
| Build verified; signed review pending | Apply A4-A7, S5, and horizontal density to the combined Cloud Sync panel. | `f9622ca5` uses direct remote and transfer rows with full hover. Remote status and time, transfer size, count, speed, and ETA use the width first. Single-value tiles and empty-state cards are removed. Existing New Transfer, Retry engine, disclosure, Pause, Resume, Retry, colors, and progress paths remain. | Gated app and desktop-test compilation pass. Run hosted transfer checks and signed actions in active, paused, failed, expanded, empty, and daemon-error states. Report: `tmp/redesign/logs/w1-panel-main.md`. |
| Source complete; verification pending | Audit Logs and fix main-window Retention and System issues rows for production pass A8. | Both settings hosts now use single-line `OnePlusSettingRow` values backed by the service policy, with help behind glyph tooltips. Counts and ranges trail the source filter; loading and empty views have no card. The Logs audit also fixes detached read cancellation, startup merge, failed-save retention, pruning after writes, source filtering, export errors, and full detail text. Source-derived checks pass; focused XCTest regressions are added. | Orchestrator installation, fresh dark/light captures, and hosted tests. Source and feature evidence: `tmp/redesign/logs/w1-audit-logs.md`. |
| Verify | Use the OnePlus Cloud Sync window anatomy at 1240 x 840 with a 216pt sidebar. | The owned Cloud Sync views now use `OnePlusWindowRoot(.rclone)`, the title/search slot action, transfer and remote groups, bottom Settings navigation, and page routing for all required transfer, activity, Dev Sync, settings, sheet, and remote page IDs. | The redesign orchestrator must capture the installed app and compare every sidebar page with the reference. |
| Verify | Show each transfer as an operational card without changing engine ownership or transfer state rules. | `899359a7` uses source and destination lines, plain state and ETA text, a progress bar, trailing size, speed and file counts, adjacent pause, resume, retry, info, cancel and remove actions, expanded file rows, and existing context actions. The audit also fixes file Move, authenticated exports and resumed average speed without changing engine ownership. | Exercise active, paused, retrying, failed, completed, expanded, and empty states in the installed app. |
| Verify | Provide a searchable and sortable activity ledger plus an operational remote browser. | Activity uses the native OnePlus table with time, operation, source, destination, size, duration, result, selection, details, and copy actions. The remote browser keeps Quick Look, drag in, drag out, breadcrumbs, upload, refresh, settings, cleanup, row context actions, and New Folder. New Folder uses the authenticated `operations/mkdir` client, a native name prompt, safe single-component validation, and an inline error state. | Verify sorting, Space, both drag directions, upload, folder creation failure and success, and context menus in the installed app. |
| Verify | Restyle Dev Sync without changing its review, conflict, or safety behavior. | The pair, project, conflict, safety, settings, and setup views now use OnePlus page, card, row, and sheet structure while calling the existing manager actions and safety-store flow. | Verify setup, preview-before-change, conflicts, drift, missing projects, pause, resume, and safety-store actions in the installed app. |
| Verify | Use one Cloud Sync settings implementation in both entry points. | `RcloneSettingsView` is the single card implementation used by the Cloud Sync window and main Settings. `RcloneSettingsPage` only adds the standalone page header. `f1df5f9` removes expanding panels and local maximum-height frames from the equal-width, top-aligned Sync engine and Transfers cards. The enforced retry policy displays neutral On text. Ignore patterns, Retries, and rclone each take the full width. Debug and desktop build-for-testing pass. | Recapture both hosts at natural card heights; verify validation, steppers, toggles, operation selection, and persistence. Report: `tmp/redesign/logs/27r10-main.md`. |
| Verify | Fix the first redesign screenshot review without masking shared package defects. | Activity reserves readable Result and Duration columns. Logs gives Message the remaining width, uses tail truncation, and opens the full text in its selectable detail sheet. Cloud Sync settings uses equal short-card columns, full-width Ignore patterns, one control width per card, and in-card headers. Empty-state actions are neutral and empty content fills the free vertical area. | The orchestrator must recapture every Cloud Sync and Logs page in both appearances. Window height, scroll gutters, native table skin, control tint, row height, button height, status dots, and muted contrast remain shared OnePlusUI work. |
| Verify | Apply the owner's fixed-chrome and speed review to every Cloud Sync and Logs page. | Transfer headers, Activity search, remote actions and breadcrumbs, Dev Sync status and safety content, Logs filters, and log detail stay fixed while only their row regions scroll. Activity, remote entries, and Logs filtering, sorting, and row formatting now run in cancellable background projections. Live Logs and transfer samples no longer invalidate their whole window. Native selection dropdowns now use `OnePlusSelect`; action menus remain menus. | The orchestrator must measure page switches below 100 ms, scroll the large row states, and capture the signed build after shared header and popup work lands. |
| Verify | Remove profiler hot paths from Cloud Sync and Logs without changing transfer or log behavior. | `55b65f0` removes full-page identity resets. `f6c1fd2` caches file-tree, upload-status, display-string, and cleanup totals. `b7d6a74` prepares Dev Sync groups and conflicts outside render. `736e00f` uses lazy setup rows and removes per-row tooltip modifiers while keeping accessibility labels. Activity, remote browser, and Logs already sort, filter, and format only when their inputs change. | The orchestrator must profile the signed build and confirm page switches stay below 100 ms and large tables scroll smoothly. |
| Verify | Fix the second redesign screenshot review without masking shared package defects. | Cloud Sync restores paired short settings cards after the embedding regression, gives the full Transfers card one 180pt control width, uses compact readable Activity times, aligns sidebar accessories, and gives each transfer filter correct summary and empty-state copy. Logs uses source-specific level counts, dated row times, a collapsed same-day range, the 500-entry limit, neutral level text, and a ghost Clear action. | The orchestrator must recapture every page. OnePlusUI still owns table cell/header insets, filler separators, numeric header alignment, no-tabs header spacing, settings scroll gutters, and the text-editor border rendering. Log retention remains fixed in `LogManager`; a real selector needs service ownership. |
| Verify | Fix the third redesign screenshot review and embedded settings findings. | `d6c13ea` equalizes the short settings pair, keeps Retries full width, uses the shared seconds stepper in the 180pt column, shortens captions, and names the transfer-status switch. `cb95b2d` presents the fixed two-day Logs retention policy as a key-value row. All 20 supplied captures were reviewed. | Recapture both settings hosts and exercise retry editing. OnePlusUI owns the 17pt scroller reservation, missing non-scrolling page bottom gutter, table insets, filler rules, cell type roles, light table offset, and editor border. See `tmp/redesign/logs/16r6-cloudsync.md`. |
| Verify | Review the fourth signed capture set without adding local workarounds. | All 20 dark and light `8cf8c02` captures were reviewed. Settings right gutters, paired-card heights, readable captions, the seconds stepper, and fixed Logs retention copy are visibly correct. No additional owned defect was found. | The foundation owner must fix all eight shared findings: table cell/header insets and origins, dark traffic-light placement, non-scrolling page bottom clearance, filler rules, editor border, column text roles, and appearance-dependent table offsets. See `tmp/redesign/logs/17r7-cloudsync.md`. |
| Verify | Adopt the shared table APIs after the fifth signed capture review. | All 20 dark and light `db47173` captures were reviewed. `429ec7d` gives Logs one header/cell column model, shared 12pt insets, a fixed glyph lane, and room for Warning. `97eecf1` uses secondary mono Time and Destination with primary mono Source in Activity. The captures confirm T=16, C=27, bottom clearance, no filler rules, and the editor bezel. | Recapture the changed tables in both appearances and check Warning, long sources, selection, sorting, and full-text details. The foundation owner still owns the 1pt System Issues appearance offset. Signed focus, panel height, identity colors, and latency checks remain with the orchestrator. See `tmp/redesign/logs/23r8-cloudsync.md`. |
| Verify | Keep complete editable lines visible after the sixth signed capture review. | All 20 dark and light `3e33de2` captures were reviewed. Logs column alignment, Source/Message clearance, and Activity type roles are visibly fixed. The 120pt Ignore patterns viewport cut through the next line. `a345e8b` sets it to 128pt in the single settings implementation, with the shared 11pt vertical text inset and overlay scroller unchanged. | Recapture both settings hosts and check editing, undo, persistence, and scrolling. `astra-foundation` still owns the 1pt System Issues light header shift. The shared native table must use one integral 28pt header extent and the same first-row origin in both appearances. Signed focus, panel height, identity colors, and latency checks remain with the orchestrator. See `tmp/redesign/logs/25r9-cloudsync.md`. |
| Done | Keep the newest transfer and local-change snapshot when background saves overlap. | The audit found that debounced saves detached from the main actor could complete out of order, allowing an older atomic replacement to overwrite newer transfer or change history. Both stores now give each snapshot a revision and use one ordered atomic writer per store; a late older revision is ignored. The focused writer, transfer-engine, and local-change tests pass. | None for one running manager instance; final full-suite verification is tracked in the app-wide audit. |
| Verify | Keep the tray's empty transfer state inside the same full-width content column as other tabs. | `EmptyStateView` fills its offered width, but the physical screenshot still showed a narrow clipped column because the scroll content did not offer the full tray width. `TrayMeasuredScroll` now gives every tab the known 360pt width before measuring height. The previous layout test covered the empty view outside the scroll container. | Confirm the normal installed popover after the final clean-HEAD install. |
| Done | Choose no Cloud Sync menu item, the combined popover, or a separate icon. | The shared launcher selector stores None, Combined, or Separate. Cloud Sync preserves its combined default and any legacy separate choice. Focused tests cover each mode, the exact `MacPowerToys.rclone` autosave name, its Open Cloud Sync route, disabled state, combined-tab support, and no-op item refresh. | None. The shared five-tool physical placement, relaunch, and click matrix remains in the main request list. |
| Done | Stop the Cloud Sync daemon and polling loop when no owner needs them. | `97038e7` adds idempotent window ownership and one runtime-need policy. `217388d` makes a Start at Launch preference change reconcile that policy at once. Closing the last idle window or switching Start at Launch off stops an unowned daemon and 700 ms poll. Active transfers, continuous jobs, and visible windows keep them alive. `bba9474` also removes all three volume observers on shutdown and registers exactly one set after restart; its 25-cycle regression proves `0 → 3 → 0` without growth. In the exact installed `327ebb1` build, Start at Launch off with no window or active job produced zero daemon, poll, window, watcher, observer, and long-task owners in two snapshots 30 seconds apart. No rclone process existed, and app CPU advanced by 0.01 seconds. The original Start at Launch setting was restored after the check. | None. |
| Verify | Keep an intentionally open Cloud Sync engine light while no transfer is pending. | The poller sleeps 5 seconds with only paused or terminal jobs, or no jobs; queued, running, and retrying jobs retain the 700 ms cadence. Creating, resuming, retrying, or globally resuming a job promotes it immediately when the daemon is ready and wakes the poll loop. All five focused engine tests and the exact-commit 812-pass, five-skip suite pass, including an immediate-start assertion and completed copy. The signed installed `e1b9384` build matched two idle owner snapshots: one intentional daemon/poller, zero Cloud Sync windows and watchers. Over a warm minute the app used about 0.05% of one CPU and rclone about 0.02%. | Check a transfer start and progress in the signed installed app. |
| Done | Rename "Split uploaded" to "List uploaded" and show uploaded files as a tree in the right pane. | `bb42342`; `TransferFileTreeView` uses "List uploaded" and tree rows in the uploaded column. | None. |
| Done | Vertically center Recalculate with Transfer plan and move the subtitle into an info popover. | `ebc8692`; the row is center-aligned and owns an `info.circle` popover. | None. |
| Done | Keep detail tabs aligned when the selected pill adds its 10pt inset. | `6ad4568`; the pill boundary starts at the shared 20pt gutter. `DESIGN.md` forbids tab movement on selection. | None. |
| Done | Add provider-aware transfer context-menu actions that open the source or destination folder on the provider website. | `RcloneRemote.websiteName` and `websiteFolderURL` support Google Drive and Box. The official rclone Box documentation confirms that rclone folder IDs map to Box folder URLs. OneDrive and Dropbox need provider URLs or shared-link APIs that the read-only stat path does not return. | None for providers with a stable, read-only folder URL. |
| Done | Put ETA on the right in the transfer state badge. | `59da6f6`; running jobs render `ETA ...` inside the right-side state badge. | None. |
| Done | Pause and resume a transfer directly from the menu-bar Cloud Sync tab. | Every active transfer row shows a state-aware Pause or Resume control wired to the existing safe job-manager actions. `3e36ad8` also gives the native menu-bar item an explicit accessibility name. The complete test suite and signed Release build pass. A controlled 19.5 MB transfer ran at the verified 1 KiB/s limit after the local Copy feature was temporarily disabled. The main-window Pause control reached the safe Paused state. Cleanup removed the test record, restored unlimited bandwidth and all rclone features, left zero active transfers, and moved the disposable files to Trash. | None. The physical Pause and Resume check is owned by the consolidated menu-bar matrix in `spec/main-request-list.md`. |
| Done | Make the Cloud Sync tray tab a detailed, bounded transfer console. | `92896f5` uses the existing `RcloneJobManager` and its poller to render at most five active and three recent jobs under the cloud symbol. Queued, running, retrying, paused, failed, cancelled, and completed states keep Pause, Resume, Retry, and engine recovery nearby. Expanded jobs show up to four exact in-flight files plus aggregate and per-file progress, bytes, counts, speed, and ETA when available. Focused bounds/state tests and the complete `519095b` suite pass. The exact installed build reported zero Cloud Sync window, watcher, and long-task owners while its Start at Launch daemon and poller stayed at one, proving the closed tray creates no extra runtime owner. | None. |
| Done | Always push verified changes and update the installed MacPowerToys app safely. | Git policy requires checkpoint pushes. The troubleshooting current-build rule and `Makefile` reject dirty or stale installs. The final gate found zero active app transfers and zero active rclone jobs before it installed the signed clean `HEAD`. | Never install while a Cloud Sync transfer is active. |
| Done | Keep the connector button and dropdown the same width and show long labels without idle animation. | The popover uses the trigger width. Long labels truncate with a tooltip and accessibility value; hover and auth-state changes use the shared short motion policy, so an open idle picker never marquee-scrolls. | None. |
| Done | Default OAuth providers to browser login and show alternate methods as provider-specific tabs. | `2e01de5`; browser, service-account, environment, token, and custom OAuth modes are derived from rclone metadata. | None. |
| Done | Put connector search inside the dropdown and use compact native chrome. | The popover owns the shared native small `NSSearchField` in a 24pt slot and applies `.thinScrollIndicators()`. The shared native-field regression covers the control. | None. The installed all-search-surface layout matrix remains in the main request list. |

## Dev Sync behavior contract

Consolidated on 2026-09-30. Implementation status and measured evidence stay
in [the Dev Sync request list](dev-sync-request-list.md). DESIGN.md owns all
window, control, and sheet geometry. Scenario IDs below stay stable.

Dev Sync reconciles internal and removable-drive trees inside Cloud Sync.
FSEvents marks work dirty; the scheduler groups it; policy selects paths;
the planner decides direction and conflicts; rsync transfers the approved
manifest. rsync never decides direction or deletion. Existing rclone Copy,
Sync, and Move jobs keep their own store and process.

Version 1 does not sync two Macs, merge source, follow symbolic links, offload
individual files, provide a distributed filesystem, guarantee live database
consistency, or securely erase files. Keep a separate versioned backup.

### Modes and first run

- Dev One-Way copies internal changes outward. External changes or deletions
  are destination drift. Retain external-only paths that have no baseline.
- Dev Bidirectional copies the single changed side to the unchanged side.
  Different concurrent changes are conflicts. Never choose newest by time.
- In both modes, external-only projects and plain folders stay external and
  get managed internal links. Residency is separate from mode.
- A whole internal project deletion in One-Way keeps the external project
  and offers verified conversion to external residency. Bidirectional pauses
  for a project-level decision. Never propagate whole-project deletion.
- First run previews mirrors, links, copies in each direction, safety moves,
  conflicts, excluded sizes, included sensitive paths, metadata loss, and
  required free space. No mutation occurs before approval. A missing mirror
  is planned against an empty destination. Same-path differences without a
  baseline are conflicts, never newest-wins.

### Safety invariants

These rules are mandatory in every mode and phase.

1. The internal and external roots are never the same directory.
2. One root is never inside the other, including through a symbolic link.
3. Discovery and scans use `lstat` semantics and never traverse a symbolic
   link.
4. A managed internal link always points to a project below the selected
   external root.
5. `rsync` never receives a managed link as a source project directory.
6. The app never runs a shell command string built from a path. Every process
   receives an argument array.
7. Every manifest uses NUL separators. A path that contains a newline is
   deferred with a reason when the selected `rsync` cannot accept NUL input.
8. A scan error disables deletion for the affected scope.
9. An unavailable root disables deletion for the pair.
10. A dropped FSEvents condition causes a full rescan.
11. A nonzero transfer result never advances the baseline without path
    verification.
12. A source file that changes during transfer is requeued.
13. A destination path that changed after planning is never overwritten.
14. A same-path project identity mismatch blocks that project.
15. A path-type conflict blocks that path.
16. A case collision blocks the affected project.
17. A whole-project deletion never propagates automatically.
18. Every destructive action has a safety record before it runs.
19. An unresolved conflict is never removed by retention cleanup.
20. A user-created symbolic link is never changed unless the user adopts it.
21. Cloud Sync staging, history, conflict, and partial paths are hard-excluded.
22. Sockets, FIFOs, block devices, and character devices are never copied.
23. Normal Dev Sync never uses `--inplace` and never uses continuous full-tree
    checksums.
24. Raw modification time is never the only bidirectional conflict rule.
25. Volume identity comes from the volume UUID, never only from the volume
    name.
26. Two active pairs never own overlapping roots, and one project never
    belongs to two pairs.
27. Watchers stay active during Cloud Sync's own transfer. Only verified
    self-generated events are suppressed.
28. The state store lives in Application Support, outside both roots.
29. Existing standard transfers are never migrated to Dev Sync automatically.

### Discovery and identity

Everything below the root syncs except policy exclusions. There is no project
picker. Each outermost Git repository is a unit. The root unit, `Everything
else`, owns loose files, plain folders, `_`-prefixed archives, bare repos,
and package markers outside those repositories. Its scans carve out nested
units and managed links. A nested repository inside an outer repository
syncs with that outer unit, including its .git data.

Discovery uses lstat, stops below accepted outer units, skips dependency and
system trees, and reports completeness and unreadable paths. A shallowest
drive-only plain directory outside a repository becomes a linked unit only
when the root baseline does not identify it as a mirrored deletion. Keep
that unit while its registered link validates, including after remount.

Relative path is a proposed match. Verify project UUID, resource identity,
Git topology, credential-stripped remote hints, and object hints. Two clones
of one remote at different paths remain separate projects. Rename detection
uses same-volume resource identity, then strong content and topology hints;
uncertain matches need confirmation. Move the counterpart on its own volume.

Initialized submodules sync with their superproject. Linked worktrees need
their common repository inside the pair for a usable destination. Never
rewrite .git pointer files. External submodule metadata, worktree common
directories, and object alternates produce topology warnings. Raw backup
needs acknowledgement and must not be labeled self-contained or ready to use.
Check xcode-select before invoking Git. Missing Git uses non-Git policy with
a warning and never opens the Command Line Tools installer.

### File policy

Every classification returns whether the path is included, the reason,
whether it is sensitive, whether it is volatile, and whether it needs a stable
window. The UI can answer "Why was this path excluded?" for any path.

Precedence, highest first:

1. Unsupported object type deny.
2. Cloud Sync internal path deny.
3. Explicit user rule.
4. Sensitive and local-file override.
5. Required Git metadata rule.
6. Git tracked-file inclusion.
7. Git ignore result (off by default; the skip list is the only filter).
8. Skip list: caches, dependency checkouts, build outputs, and temporary
   folders.
9. Default inclusion.

Rules 1 and 2 are hard. An explicit user rule overrides the sensitive default.
Rule 6 sits above rule 8 on purpose: Git-tracked content inside a skip-list
folder such as a committed `vendor/` or `build/` still syncs, while untracked
files beside it are skipped. "Tracked" here means present in the Git index
(`git ls-files --cached`). The working-tree manifest also lists untracked
files that Git does not ignore; those count as tracked everywhere except
inside a skip-list folder, where only index entries win.

Object types are detected by `lstat`, never by name. Cloud Sync internal paths
are the configured `.cloudsync-system`, `.cloudsync-partial`,
`.cloudsync-staging`, `.cloudsync-history`, and `.cloudsync-conflicts`
directories.

#### Git parses Git ignore rules

The canonical working-tree manifest for a Git project is:

```text
git ls-files -z --cached --others --exclude-standard
```

Batched event checks use `git check-ignore --stdin -z -v`. Every read-only Git
call sets `GIT_OPTIONAL_LOCKS=0`. The active global ignore file is resolved
through Git configuration and compared by identity and modification time at
app start and at each full reconciliation. The same rule applies to an exclude
file outside the working tree because of a linked worktree.

This covers nested `.gitignore` files, `.git/info/exclude`, the global ignore
file, negated patterns, tracked files that match an ignore pattern, and names
with spaces, newlines, and Unicode. `rsync --filter=':- .gitignore'` is not the
Git policy; it is only a fallback for a non-Git directory.

A change to `.gitignore`, `.git/info/exclude`, the global ignore file, project
Cloud Sync rules, sensitive patterns, or the common exclusion set schedules a
full project policy rescan. When an included path becomes excluded, the
prior destination version goes to the safety store, the active mirror drops it
only after a valid plan, and a destination-only path that was never in the
baseline stays untouched.

#### Sensitive and local files

"Back up ignored sensitive and local files" is on by default. Default include
patterns:

```text
.env  .env.*  .envrc  .direnvrc  local.properties  gradle.properties
secrets.properties  key.properties  *.tfvars  *.tfvars.json  *.auto.tfvars
.npmrc  .pypirc  .netrc  auth.json  credentials*.json  service-account*.json
google-services.json  GoogleService-Info.plist  *.pem  *.key  *.pub  *.crt
*.cer  *.der  *.p12  *.pfx  *.jks  *.keystore  *.mobileprovision
```

The user edits this list. A sensitive override can include a Git-ignored file
but never an unsupported object type or Cloud Sync system data, and never
searches inside hard-excluded dependency trees without an explicit path. A
broad suffix pattern has a configurable size guard. File contents never appear
in logs or previews. The UI warns when the external volume is not encrypted,
and the same warning covers history and conflict copies. Dev Sync never claims
that an unencrypted removable drive is a safe place for private keys.

#### Git metadata

Include `.git` except transient locks and temporary pack files. This preserves
local branches, unpushed commits, stashes, the index, reflogs, merge and
rebase state, hooks, local configuration, and Git LFS objects unless disabled.
A remote is never assumed to be a backup for unpushed objects.

Before the Git administration batch is copied, check for `.git/index.lock`,
`.git/HEAD.lock`, `.git/config.lock`, `.git/packed-refs.lock`,
`.git/shallow.lock`, `.git/refs/**/*.lock`, and `.git/objects/pack/tmp_*`.
Defer the Git metadata batch while a lock exists, wait for the normal quiet
window after it disappears, exclude the lock itself, keep in-progress rebase
and merge directories, and never run `git clean`, `git checkout`, `git reset`,
`git gc`, or `git fsck` during synchronization.

#### Common exclusions

Hard defaults: `.DS_Store`, `._*`, `.Spotlight-V100/`, `.Trashes/`,
`.fseventsd/`, `.TemporaryItems/`, and `.icloud` placeholder files. Editor
temporary files (`*.swp`, `*~`), log files, game-engine caches, and machine
learning run folders sync; the owner asked for them.

There is no blanket `*.lock` rule. `package-lock.json`, `pnpm-lock.yaml`,
`yarn.lock`, `Cargo.lock`, `go.sum`, `Podfile.lock`, `Gemfile.lock`,
`composer.lock`, `Package.resolved`, `gradle.lockfile`, and
`.terraform.lock.hcl` stay eligible.

The skip list applies to untracked, not explicitly included paths at any
depth. It is the only filter in the default configuration and is meant to be
long: it names things that are temporary without doubt.

| Ecosystem | Skipped |
|---|---|
| JavaScript | `node_modules`, `.npm`, `.pnpm-store`, `.yarn/cache`, `.yarn/unplugged`, `.pnp.cjs`, `.parcel-cache`, `.turbo`, `.next`, `.nuxt`, `.output`, `.svelte-kit`, `.vite`, `.astro`, `.docusaurus`, `.angular`, `.cache`, `.eslintcache`, `.stylelintcache`, `.webpack`, `.serverless`, `.vercel`, `.netlify`, `.wrangler`, `.nyc_output`, `storybook-static`, `*.tsbuildinfo` |
| Expo and React Native | `.expo`, `.expo-shared`, `.eas` |
| Python | `__pycache__`, `*.pyc`, `*.pyo`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `.nox`, `.hypothesis`, `.venv`, `venv`, `.eggs`, `*.egg-info`, `htmlcov`, `.coverage`, `.pdm-build`, `.pytype`, `.ipynb_checkpoints` |
| JVM and Android | `.gradle`, `.kotlin`, `.cxx`, `.externalNativeBuild`, `captures`, `.bloop`, `.metals`, `.bsp` |
| Apple | `Pods`, `Carthage`, `DerivedData`, `.build`, `.swiftpm`, `xcuserdata`, `.symbolcache`, `*.xcarchive` |
| Flutter | `.dart_tool`, `.pub-cache`, `.fvm` |
| Other | `_build`, `dist-newstyle`, `.stack-work`, `elm-stuff`, `.cpcache`, `zig-cache`, `.zig-cache`, `zig-out`, `bazel-*`, `.terraform`, `CMakeFiles`, `cmake-build-*`, `.vs`, `vendor` |
| Tests | `test-results`, `playwright-report`, `.playwright`, `cypress/videos`, `cypress/screenshots` |
| Temporary | `tmp`, `temp`, `.tmp`, `.temp` |
| Build outputs | `build`, `out`, `target`, `coverage`, `bin`, `obj` |

Kept on purpose: `dist` (release installers live there), `.idea`, `.vscode`,
`.claude`, `.codex`, `.agents`, `.cursor`, `.github`, `env`, `envs`, `data`,
`output`, `cache`, `packages`, `deps`, `logs`, `*.log`, editor temporary
files, Unity and Unreal caches, and `wandb`, `mlruns`, `lightning_logs`.
Plain names that are common source folders never enter the list. The user
adds patterns through explicit rules; the built-in list is not editable.

An explicitly included non-Git project uses the common profile, supports a
project `.cloudsyncignore` file with ordered rules and clear negation, previews
every exclusion, and never treats all hidden files as disposable.

### Events and scheduling

FSEvents is a dirty hint. Keep one stream per real root with file events,
root-change watching, and durable cursors. Watch external link targets
directly. Persist dirty generations before acknowledging them. Never start
one rsync per event. Each UI subscriber has its own service update stream.

Full scans follow dropped, wrapped, or invalid events, root or bookmark
changes, remount, recovery, policy changes, prior incomplete scans, and
unknown project paths. Map events to the nearest unit; collapse excessive
path hints to one unit scan. Never requeue unplannable external-resident or
excluded units indefinitely. A waiting unit must not starve other units.

| Timing | Default |
|---|---|
| FSEvents latency | 2 seconds |
| Normal quiet period | 10 seconds |
| Minimum project sync interval | 20 seconds |
| Continuous-activity checkpoint | 5 minutes |
| Large or volatile file quiet | 60 seconds |
| Periodic full reconciliation | 6 hours |

Presets: Responsive, Balanced (default), Low drive activity, Manual only.

Sliding debounce moves the due date after each event and makes a bounded
checkpoint at the maximum interval. Transfer only stable eligible paths.
Events during an active job form the next generation. More than 1,000 events
in 10 seconds collapse to project-dirty; more than 10,000 pending paths
discard individual hints. Sync Now merges into the next generation.

Watchers stay active during transfer. Suppress only self-events whose
resulting signature matches the operation ledger. A different signature or
later user edit requeues the path. Keep verified drift visible while a
delayed event waits. Publish per-project drift counts and their pair sum.

Use one mutation slot per external volume, two metadata scans, and one deep
hash. Mutations never overlap paths. User operations precede conflict safety
copies, mount recovery, event batches, periodic checks, and retention.
Automatic work uses utility or background priority. Honor optional power
gates. Idle scheduling sleeps until due work and wakes on events or commands.

### Scans and reconciliation

Use lstat snapshots and stable byte-order NUL manifests. A quick signature
includes type, size, volume-tolerant mtime, supported mode bits, and symlink
text. Resource identity is a same-volume rename hint. Directory mtime is not
content evidence. Hash with streaming SHA-256 when content is ambiguous,
both sides changed, coarse time hides changes, rename matching needs it, or
deep verification is requested. Do not checksum every tree on every batch.

Check source type, size, mtime, and resource identity before and after copy.
Changed sources stay dirty and never commit as clean. Large or volatile
files need two equal probes across the stable window. Do not silently cap
file size. Warn above the configured threshold and offer exclusion, manual
sync, quiet-only sync, and a write budget. Database and VM-image patterns
warn about consistency. Never delete them by pattern or use inplace copying.

Build case and Unicode comparison keys from the less capable filesystem.
List collisions and block the unit; never let rsync choose a winner. An
incomplete scan permits safe additions but disables deletion in its scope.

Entry states per side: absent, unchanged from baseline, changed from baseline,
added after baseline, type-changed from baseline, unreadable, unstable.

#### Dev One-Way decision table

`I` is internal, `E` is external, `B` is baseline.

| Internal | External | Action |
|---|---|---|
| Same as B | Same as B | No action. |
| Changed | Same as B | Copy I to E. |
| Added | Absent | Copy I to E. |
| Deleted | Same as B | Quarantine E, delete E, create tombstone. |
| Changed | Changed differently | Conflict. |
| Deleted | Changed | Delete/modify conflict. |
| Same as B | Changed | Destination drift. Do not overwrite. |
| Same as B | Deleted | Destination drift. Restore only after user policy or resolution. |
| Absent, no B | Added on E | Retain E. Report external-only path. |
| Added on I | Added differently on E | Conflict. |
| Same content, different quick metadata | Same content | Normalize supported metadata or update baseline. |
| Any | Unreadable or unstable | Defer. No deletion. |

A user option may let internal overwrite destination drift after safety
retention. It is not the default.

#### Dev Bidirectional decision table

| Internal | External | Action |
|---|---|---|
| Same as B | Same as B | No action. |
| Changed | Same as B | Copy I to E. |
| Same as B | Changed | Copy E to I. |
| Added | Absent | Copy I to E. |
| Absent | Added | Copy E to I, unless it is a new external project root that will be linked. |
| Deleted | Same as B | Quarantine and delete E. Record tombstone. |
| Same as B | Deleted | Quarantine and delete I. Record tombstone. |
| Changed | Changed, same content hash | Update baseline. |
| Changed | Changed differently | Content conflict. |
| Deleted | Changed | Delete/modify conflict. |
| Changed | Deleted | Modify/delete conflict. |
| Type changed | Any non-identical state | Type conflict. |
| Added | Added, same content | Establish baseline. |
| Added | Added differently | Add/add conflict. |
| Unreadable or unstable | Any | Defer. No destructive action. |

#### Tombstones

A tombstone is valid only when the relevant root was online, the parent scan
was complete, the path existed in the baseline, the path was confirmed absent,
and the delete was verified. It remains until both sides observed the deletion
and the retention interval passed. A tombstone never converts an old
disconnected copy into a new addition.

#### Conflicts

Types: content/content, add/add, delete/modify, modify/delete, type change,
case collision, Unicode normalization collision, project identity, project
path, rename/rename, rename/modify, unsupported Git topology, destination
drift, metadata-only, managed-link collision.

On detection: preserve both versions in the safety store when possible, leave
the active path unchanged unless one side must be stabilized, block only the
affected path or project, show internal, external, and baseline metadata, and
offer Keep Internal, Keep External, Keep Both, Mark as Same after manual merge,
Exclude Path, and Defer. Update the baseline only after the selected result is
verified. Conflict copies live outside the project and appear in the UI.

#### Renames

FSEvents rename flags are hints. Pair old and new paths by scan evidence in
this order: same resource identifier on the same volume, same type, size, and
strong hash, same Git project identity for project moves, user confirmation. A
safe rename moves the counterpart on its own volume, keeps the old path in the
operation journal, verifies the new path, updates the baseline atomically, and
avoids delete-plus-copy.

### Operation transaction and recovery

Plans are immutable. Each mutation records source and destination signatures
or absence, volume and project identity, parent type, required capacity, and
policy version. Recheck them before acting. A failed precondition stops the
path and replans; no stale destructive action continues.

1. Resolve bookmarks and volume identity.
2. Validate pair and project preconditions.
3. Check free space and file-system capabilities.
4. Persist the operation plan.
5. Prepare safety copies or same-volume safety moves.
6. Start the `rsync` transfer for approved paths.
7. Keep monitoring events.
8. Read the `rsync` result.
9. Verify destination paths.
10. Verify source stability.
11. Apply approved explicit deletions or link actions.
12. Commit baselines atomically and persist verified tombstones.
13. Mark the operation committed.
14. Clear only the dirty generation covered by the plan.
15. Apply retention cleanup after success.

When the process stops at any point, the journal shows the last durable
state. The next launch inspects the journal and the file system, then
finishes, rolls back, or replans. An `rsync` exit never implies that no files
changed.

Crash recovery at launch, for each operation that is not terminal: validate
pair roots and volume identity, inspect staged safety data, inspect
destination and source state, decide whether the operation can be verified and
committed, otherwise rebuild a plan, and never delete recovery data until the
operation is resolved.

### rsync and verification

Probe the selected binary's identity, version, help, and a real temporary
transfer at setup and after binary changes. Selection order is explicit user
path, app-managed binary, known package-manager paths, then system rsync.
Never depend on the interactive shell PATH. Test files, empty directories,
links, executable bits, unusual names, NUL input, partials, backups, and each
requested metadata feature. Help text alone is insufficient.

Use Foundation.Process with argument arrays and concurrent bounded stdout
and stderr reads. Cancel gracefully. Reject manifest paths that are absolute,
empty, contain active .. components, escape roots, traverse links, or name
app system data. Use sorted relative NUL input with `--files-from=- -0` and
`--` before roots where supported.

Base options are `-l -t -O --executability --partial --partial-dir`,
`--backup --backup-dir`, and `--itemize-changes`. Gate permissions, xattrs,
hard links, creation times, and timestamp tolerance on tested binary and
volume capabilities. Record ACL support but never emit -A. Do not preserve
owner/group, devices, special files, or compress local copies by default.
Never use inplace, append, copy-links, copy-dirlinks, keep-dirlinks,
remove-source-files, ignore-errors, delete-excluded, trust-sender, old-args,
or broad rsync delete. The safety engine performs planned deletions.

Exit 0 still needs verification. Exit 20 keeps cancelled dirty work; 23
verifies copied paths without committing the batch; 24 rescans vanished
sources; 25 is a safety stop; other failures keep the journal. Itemized output
is progress only. The plan and post-copy scan are the mutation record.

Verify existence, type, size, tolerant time, link text, supported modes, and
selective hashes against a stable source. Verify Now hashes all included
paths on both sides and stays cancellable. Periodic metadata reconciliation
also runs after unclean startup, remount, event loss, and policy changes.

### Storage, retention, and mounts

Atomic JSON documents and journals live below
`Application Support/MacPowerToys/DevSync/`. Baselines live in
`baselines.sqlite3`; successful reads migrate legacy per-project JSON.
Keep five metadata backups. Corrupt documents move aside and report their
failure. Open operation journals recover before new work. State stores no
project contents, secrets, or credentials. Policy schema changes need a new
preview or reconciliation before mutation.

The external safety store is `<external-root>/.cloudsync-system/<pair-id>/`
with staging, history, conflicts, manifests, recovery, and partials. Internal
retention uses state-store safety/history on the destination volume. Preserve
and verify the old version before every overwrite or deletion. Destructive
bidirectional actions stop when required safety storage is unavailable.
Retain overwrites for 7 days, deletions and resolved conflicts for 30 days,
and unresolved conflicts until resolution. Never expire open-operation data.
Clean expired completed staging, overwrites, deletions, then resolved
conflicts. Respect capacity limits and the free-space reserve.

Identify volumes by UUID, not display name. Probe read/write, capacity,
encryption, case behavior, links, permissions, xattrs, creation time,
timestamp precision, persistent identifiers, and practical path behavior.
Full fidelity requires proven requested capabilities. Portable mode names
metadata loss; unsafe paths, collisions, missing space, and unreliable
mutations block work. Unknown required size fails preflight conservatively.

Use the same pair timestamp tolerance in planner, runner, verifier, and
baseline. Protocol below 30 needs at least one second for whole-second
openrsync writes. If important-usage capacity is zero, use plain available
capacity. Path containment compares lexical children of canonical roots;
do not standardize a missing child differently from its existing parent.
Walk existing parents separately to reject symlink traversal.

Remount validates identity and capabilities, repairs only registered valid
links to that volume, and reconciles before events resume. Planned unmount
stops scheduling, cancels rsync, closes handles, and persists dirty work
without blocking unmount indefinitely. Unexpected removal keeps journal,
staging, partials, and dirty state. Never infer deletion from an offline root.

### Managed links and residency actions

Create links only to real directories below the verified external root with
safe absent internal paths and parent directories. Keep unexpected files,
folders, and user links intact. A link needs a matching state record; an
xattr alone is insufficient. Adopt user links only by explicit action.
Keep absolute target text plus volume identity and relative project path.
Repair mount-path text only for that same volume and target.

Deleting a managed link never deletes its external project. Show Repair;
automatic recreation is off by default. Removing it from the namespace ends
management. Offline links stay in place, never become empty local folders,
and never appear as deleted internal projects. Exclude them from discovery,
internal recursion, manifests, deletion comparisons, and duplicate totals.
Do not promise universal third-party traversal; offer Open Real Location.

Move to External converts a mirrored or internal project to
external-resident:

1. Pause the project.
2. Verify source and target identity.
3. Build the complete included manifest.
4. Copy to an external staging project.
5. Verify staging.
6. Atomically install or merge the external project.
7. Move the internal project to safety retention.
8. Create the internal managed link.
9. Resolve the link and verify project access.
10. Commit residency state.
11. Remove retained internal data only after retention or explicit action.

A failure before link verification restores or keeps the internal project.

Bring Internal converts an external-resident project to mirrored:

1. Pause the project.
2. Verify that the internal path is the expected managed link.
3. Verify internal free space.
4. Copy the external project to internal staging.
5. Verify staging.
6. Remove the managed link.
7. Atomically move staging to the internal project path.
8. Keep or create the external mirror.
9. Commit residency state.

Neither action writes a real directory over an unexpected path.

### Security and privacy

Paths use URL APIs, resolve and compare standardized real roots, reject `..`
escapes and NUL in process data, pass arguments without a shell, use NUL
manifests, verify destination components, never follow untrusted links, run as
the current user, and never request root privileges.

Repository content is untrusted data. Dev Sync never executes repository
scripts, hooks, package managers, or build commands, never sources `.env` or
shell files, never uses repository-provided `rsync` options, and never loads
executable plug-ins from a project. Git inspection is read-only.

The app is not sandboxed, so bookmarks resolve without security scope. If the
app becomes sandboxed, both roots need user-selected read/write access,
security-scoped bookmarks with balanced start and stop calls, helper access
under the app architecture, and a re-prompt for a stale bookmark. A symbolic
link does not grant a sandboxed process access to its target.

With sensitive-file backup enabled, show the external encryption state and an
unencrypted-target warning, use restrictive permissions for manifests,
partials, and safety data, never log contents, keep complete sensitive path
lists out of analytics, make retention visible, and include old versions in
storage estimates.

Structured logs carry timestamp, pair ID, project ID, operation ID, phase,
side, event category, item count, byte count, duration, error category, and
`rsync` exit code. Default path logging uses project-relative paths with
sensitive redaction. Privacy mode hashes or omits paths. Debug mode logs full
paths only after explicit enablement. Logs never contain file contents, `.env`
values, private-key content, tokens, bookmark bytes, or credentials embedded
in remote URLs. Remote display strips credentials.

### Interface and error recovery

Setup has Roots, Compatibility, What syncs, Rules, Activity, and Preview
steps. What syncs has read-only groups, no include switches or candidate
picker. Rules show the skip list and sensitive backup, Git metadata, and
metadata fidelity. Git ignore is off by default. Pair pages keep controls
and status fixed while project and conflict rows scroll.

Show residency, pending/clean/offline/drift state, per-project drift count,
pair totals, last sync, next checkpoint, bytes, safety size, and warnings.
Resolve conflicts through retained copies. Notify for missing drives,
blocked sync, low space, unencrypted sensitive backup, broken links, failure,
and first initialization. Do not notify for normal batches.

| Condition | Response |
|---|---|
| External volume absent | Mark offline. Persist dirty state. No deletion. |
| Wrong volume with the same name | Block. Show identity mismatch. |
| Root bookmark stale | Attempt resolution. Re-prompt if required. |
| Root moved | Re-resolve by bookmark and identity. Full reconciliation. |
| Drive becomes read-only | Stop mutations. Keep plan and dirty state. |
| Disk full | Stop before or during transfer. Keep safety and partial data. |
| `rsync` exit 24 | Rescan vanished paths. Retry after debounce. |
| `rsync` exit 23 | Mark partial. Verify copied paths but do not commit the batch. |
| App killed | Recover from the operation journal. |
| Mac sleeps | Resume and validate roots and source stability. |
| Drive unplugged during transfer | Mark recovery required. Never infer deletion. |
| Git lock persists | Show waiting-for-Git status. Never copy transient locks. |
| Case collision | Block the project and list names. |
| Symlink target escapes the project | Preserve link text only if policy permits. Never follow it. |
| Target path is an unexpected symlink | Block the path. Never write through it. |
| Source changes after planning | Abort that path and replan. |
| Inaccessible source directory | Mark scan incomplete. Disable deletion in scope. |
| Unsupported metadata | Use declared portable mode or block. |
| Safety store full | Stop destructive actions. Allow non-destructive preview. |
| Managed link replaced by a real directory | Path collision. Never overwrite. |
| State store corruption | Stop automatic mutation. Recover from backup or rebuild through a read-only scan and preview. |
| Git not installed | Non-Git policy with a warning. No installer dialog. |

### Scenario catalog

Each row is a concrete situation, what Dev Sync does, and what the person
sees. Rows also define acceptance tests; the test name is the row number.

#### Projects and residency

| # | Situation | What Dev Sync does | What you see |
|---|---|---|---|
| 1 | `personal/app-a` is a real project on both sides with identical content. | Establishes a baseline. Copies nothing. | Row `app-a · Mirrored · Clean`. |
| 2 | `personal/big-data` exists only on the external drive. | Creates the internal link `~/dev/personal/big-data -> /Volumes/DevSSD/dev/personal/big-data`. Never copies it inward. Never scans through the link. | Row `big-data · External`. Open Real Location shows the drive path. |
| 3 | `work/app-c` exists only internally. | Previews, then creates the external mirror. | Row `app-c · Pending mirror`, then `Mirrored`. |
| 3a | `~/dev/cleanup.sh`, `docs/`, and `organization/_archive/` are not inside any repository. | The root unit copies them to the same drive paths and carves out every repository inside them as its own unit. | Row `Everything else · Mirrored · Clean` under no group header; repositories under `organization` appear under the `organization` header. |
| 3b | `organization/lambton/meallens-data` exists only on the drive and no repository owns it. | Discovery reports the shallowest drive-only directory, the catalog makes it a linked unit, and the engine creates `~/dev/organization/lambton/meallens-data -> <drive>/organization/lambton/meallens-data`. | Row `meallens-data · External · Clean`. |
| 3c | The same folder was mirrored before and then deleted on the Mac. | The root unit baseline knows it, so it is a deletion: the drive copy moves to the safety store. No link appears. | Row `Everything else` shows the retained deletion in its history. |
| 3d | `personal/app-a/tmp/` and `~/dev/tmp/` both exist. | Both skip: `tmp` is in the skip list at any depth. | Excluded paths show `Why: skip list`. |
| 3e | A repository commits `vendor/` or `build/`. | Tracked files inside sync; untracked files beside them skip. | The row's excluded size counts only the untracked junk. |
| 4 | A real internal folder already exists where a managed link should go. | Keeps the folder untouched. Creates a managed-link collision. Never replaces it. | Conflict `Path collision`. Choices: Adopt folder as mirror (same identity only), Exclude, or Move folder to Trash yourself and Repair. |
| 5 | Both sides have `personal/app-b`, but the Git remotes and history differ. | Blocks that project. Copies nothing. | Conflict `Project identity`. Choices: Keep Both (exclude), Keep Internal (external goes to history), Keep External (internal goes to history). |
| 6 | The user already made `~/dev/personal/big-data` a symlink to the external project. | Offers to adopt it. Never changes it automatically. | Row `big-data · Adopt link` action. |
| 7 | An internal mirrored project disappears in Dev One-Way while the internal root is healthy. | Keeps the external project. Converts to external-resident and creates the link only after verifying the external copy. | Row changes to `External`. Notice: `app-a is now external only`. |
| 8 | An internal mirrored project disappears in Dev Bidirectional. | Pauses the project. Never deletes the external copy. | Row `Paused · Missing internally`. Choices: Keep external only (link), Bring back from external, Delete external too (to history). |
| 9 | An external-resident project disappears from the drive while the drive is mounted. | Marks the project missing. Never creates an empty internal folder. | Row `Missing on DevSSD`. The internal link stays in place. |
| 10 | The user renames `app-a` to `app-a2` internally. | Matches the old and new projects by resource identifier, moves the external folder on its own volume, keeps the baseline. | Row `app-a2 · Mirrored · Renamed`. No full recopy. |
| 11 | The user moves `personal/tool` to `work/tool`. | Same as a rename. | Row path updates. |
| 12 | A monorepo has nested `apps/api` and `apps/web` with one `.git`. | One project. | One row. |
| 13 | A repo contains a vendored independent Git repo. | The outer repo is the unit. The inner repo syncs as part of it, including its `.git`, and is never a separate unit. | One row for the outer repo; no candidate list. |
| 14 | A project uses submodules. | The superproject is the unit. Initialized submodule files are enumerated with Git in each work tree. | One row with a `Submodules` note. |
| 15 | A project is a linked worktree whose main repo is outside the pair. | Copies raw files. Marks the topology unsupported. Never rewrites `.git`. | Row warning `Destination copy is not usable as a worktree`. |
| 16 | A bare repository sits under the root. | Never a unit; its files sync as content of the unit that contains it. | No row. |
| 17 | Two clones of the same remote sit at different paths. | Two projects. No merge. | Two rows. |
| 18 | A folder has `package.json` but no `.git`. | Never a unit; its files sync as content of the unit that contains it. | No row. |
| 19 | The internal root is the home directory. | Allows it, bounds discovery to project roots, and shows the count. | Warning `312 projects found. Consider a narrower root.` |
| 20 | The two roots are nested, identical, or the same directory through a symlink. | Rejects the pair in setup. | Inline error `Roots must not overlap`. Continue disabled. |
| 21 | A second pair uses a root inside an existing pair. | Rejects it. | Inline error `~/dev/work is already owned by pair DevSSD`. |

#### Files inside a mirrored project

| # | Situation | What Dev Sync does | What you see |
|---|---|---|---|
| 22 | The editor saves the same file 50 times in two seconds. | One batch after the 10 second quiet window. Copies the final stable file. | Row `Syncing`, then `Clean`. One transfer, not fifty. |
| 23 | A developer types for 40 minutes without a pause longer than 10 seconds. | A bounded checkpoint every 5 minutes copies stable files. | Row `Syncing` every 5 minutes. Unstable files wait. |
| 24 | `npm install` writes 100,000 files under `node_modules`. | The skip list excludes them. The event storm collapses to one project scan. Nothing is copied. | Row `Scanning`, then `Clean`. Excluded size grows. |
| 25 | `.env.local` is Git-ignored and sensitive backup is on. | Includes it. Never logs its contents. | Path reason `Sensitive override`. Warning when DevSSD is not encrypted. |
| 26 | `.git/index.lock` exists because a rebase is running. | Copies eligible working-tree files. Defers the `.git` batch. Never copies the lock. | Row `Waiting for Git`. |
| 27 | Both sides changed `README.md` differently. | Copies both versions to the conflict store. Blocks the path. Never picks newest. | Conflict `Content · README.md` with sizes, times, and a text diff. |
| 28 | Internal changed `README.md`; external is at baseline (Dev Bidirectional). | Copies internal to external. Advances the baseline after verification. | Row `Clean`. |
| 29 | External changed `config.json`; internal is at baseline (Dev One-Way). | Never overwrites it. Records destination drift. | Row `Drift · 1 file`. Choices: Overwrite (old version kept 7 days) or Adopt external copy. |
| 30 | External deleted a mirrored file (Dev One-Way). | Never deletes the internal file. Records drift. | Row `Drift · 1 missing on DevSSD`. Choice: Restore to external. |
| 31 | Internal deleted `old.swift`; external unchanged (Dev One-Way). | Moves the external file to history, deletes it, records a tombstone. | Row `Clean`. History shows `old.swift · 30 days`. |
| 32 | A file exists only externally inside a mirrored project and was never in the baseline (Dev One-Way). | Retains it. Never copies it back. Never deletes it. | Row note `1 external-only file`. |
| 33 | A file changed on both sides but ends with identical bytes. | Hashes both, updates the baseline, copies nothing. | Row `Clean`. |
| 34 | Git checkout touched a file's mtime but not its bytes. | Quick signature differs, hash matches, baseline updates. | No transfer. |
| 35 | `Foo.swift` and `foo.swift` both exist on a case-sensitive internal volume and the drive is case-insensitive. | Blocks the project. Copies neither. | Row `Blocked · Case collision` listing both paths. |
| 36 | Two names differ only by Unicode normalization. | Same as a case collision. | Row `Blocked · Name collision`. |
| 37 | A file name contains a newline. | Passes it through the NUL manifest because the system `rsync` accepts `-0`. Defers it with a reason on an `rsync` that cannot. | Path reason `Newline in name` only on an unsupported binary. |
| 38 | A file name contains spaces, emoji, a leading dash, or 250 characters. | Copies it exactly. No shell is involved. | Identical name on DevSSD. |
| 39 | A symlink inside the project points outside it. | Copies the link text. Never follows it. | Path note `Link target outside project`. Dangling on DevSSD. |
| 40 | A file is a socket or FIFO. | Excludes it by type. | Path reason `Unsupported object type`. |
| 41 | An empty directory exists. | Preserves it. | Present on DevSSD. |
| 42 | A script has the executable bit and the drive is APFS. | Preserves it with `--executability`. | Executable on DevSSD. |
| 43 | The same script and the drive is exFAT. | Copies the file. Lists the lost bit in portable mode. | Compatibility note `Executable bits are not preserved on DevSSD`. |
| 44 | A project holds a 3 GB SQLite database that changes every second. | Classifies it volatile. Waits for a 60 second stable window. Warns. | Row note `app.sqlite · Volatile · waiting`. Choice: Exclude. |
| 45 | A project holds a 20 GB VM disk image. | Warns and defaults to manual sync for that path. | Path note `Large disk image · Manual sync`. |
| 46 | A log file grows continuously. | Uses the checkpoint rule and copies only stable snapshots. | Row `Clean` between checkpoints. Choice: Exclude pattern. |
| 47 | The user edits a file while `rsync` is copying it. | Post-transfer signature differs. Never commits that path. Requeues it. | Row stays `Syncing`, then `Clean` after the next batch. |
| 48 | The user edits the external copy seconds after Cloud Sync wrote it. | The self-event ledger sees a different signature and treats it as an external change. | Drift in Dev One-Way, copy back in Dev Bidirectional. |
| 49 | With Git ignore explicitly enabled, `.gitignore` gains `build/` after `build/` was already mirrored. | Full policy rescan. Moves the external `build/` to history after a valid plan. | Row `Clean`. History shows `build/`. |
| 50 | `.DS_Store` appears. | Hard-excluded. | Nothing. |
| 51 | A `.cloudsync-system` folder was copied into a project from an old drive. | Hard-excluded and reported. | Path reason `Cloud Sync system path`. |
| 52 | An iCloud placeholder `.icloud` file sits in a project. | Excluded as dataless. | Path reason `Not downloaded`. |

#### Drives, volumes, and mounts

| # | Situation | What Dev Sync does | What you see |
|---|---|---|---|
| 53 | The drive is unplugged during a transfer. | `rsync` fails. The operation becomes recovery-required. No baseline commit. Internal absence is never inferred. On remount, validates partials before retry. | Pair `DevSSD offline`. After remount `Recovering`, then `Idle`. |
| 54 | A different drive with the display name `DevSSD` is plugged in. | Compares the volume UUID. Blocks. Writes nothing. | Pair `Wrong drive · expected DevSSD (UUID …)`. |
| 55 | The same drive mounts at `/Volumes/DevSSD-1` because a stale mount point exists. | Matches the UUID. Repairs the text of every valid managed link. | Links resolve again. Notice `3 links repaired`. |
| 56 | The drive is mounted read-only. | Stops mutations. Keeps the plan and dirty state. | Pair `Blocked · DevSSD is read-only`. |
| 57 | The drive has 2 GB free and the batch needs 5 GB plus reserve. | Refuses to start. Keeps dirty state. | Pair `Blocked · Not enough space on DevSSD`. |
| 58 | The drive fills during a transfer. | The operation fails. Partials and safety data stay. Retries after space returns. | Pair `Error · DevSSD is full`. |
| 59 | The drive is exFAT with 2 second timestamps and no symlinks. | Portable mode with a 2 second modify window and the same baseline tolerance. Lists lost metadata. | Compatibility card `Portable · symlinks skipped · 2 s timestamps`. |
| 60 | The drive is APFS and encrypted. | Full fidelity. | Compatibility card `Full fidelity · Encrypted`. |
| 61 | The drive is APFS and not encrypted, and sensitive backup is on. | Warns once at setup and on the pair page. | Warning `DevSSD is not encrypted. Secrets and history are stored in clear.` |
| 62 | The internal root lives on a second internal volume that is unmounted. | Marks the pair offline. Never infers deletion. | Pair `Internal root offline`. |
| 63 | The internal root lives on a network volume. | Warns that events are unreliable and relies on periodic reconciliation. | Setup warning `Network volumes sync on a schedule only`. |
| 64 | The Mac sleeps mid-transfer. | The transfer continues or fails after wake. Verification catches gaps. | Row `Syncing` or `Retrying`. |
| 65 | The safety store reaches its size cap. | Cleans expired versions in order. Never removes unresolved conflicts. Stops destructive actions when still full. | Pair note `Safety store 95% full`. |

#### Links

| # | Situation | What Dev Sync does | What you see |
|---|---|---|---|
| 66 | The user deletes a managed link. | Marks it missing. Never recreates it automatically. | Row `Link missing · Repair`. |
| 67 | The user replaces a managed link with a real folder. | Creates a path collision. Never overwrites. | Conflict `Path collision`. |
| 68 | The drive is offline. | Leaves the broken link in place. Never replaces it with a folder. | Row `External · Offline`. |
| 69 | A tool opens the project through the link and resolves the physical path. | Nothing changes. The UI never promises universal compatibility. | Open Real Location. |
| 70 | Move to External is run on `app-a`. | Pauses, stages externally, verifies, installs, moves the internal project to retention, creates the link, verifies access, commits. | Row `External`. Trash-like retention for 30 days. |
| 71 | Move to External fails at staging verification. | Keeps the internal project untouched. | Row `Mirrored · Move failed`. |
| 72 | Bring Internal is run on `big-data`. | Verifies the link, checks free space, stages internally, removes the link, moves staging into place, keeps the mirror. | Row `Mirrored`. |
| 73 | Bring Internal finds a real folder where the link should be. | Refuses. | Error `Unexpected folder at ~/dev/personal/big-data`. |

#### Engine, Git, and recovery

| # | Situation | What Dev Sync does | What you see |
|---|---|---|---|
| 74 | Xcode Command Line Tools are not installed. | Detects it before the first Git call. Uses the non-Git policy with a warning. Never triggers the installer dialog. | Setup warning `Git is not available. Ignore rules use the common profile.` |
| 75 | The system `rsync` has no ACL support. | Records the capability and never passes the flag. | Compatibility note `ACLs not preserved`. |
| 76 | Homebrew `rsync` 3.x is selected. | Re-probes. Emits `--crtimes` only when the self-test proves it and both volumes support creation times. Records ACL support but never emits `-A`. | Compatibility note updates. |
| 77 | `rsync` exits 23 (partial). | Verifies copied paths. Never commits the batch. Retries the rest. | Row `Retrying · 2 files`. |
| 78 | `rsync` exits 24 (a source vanished). | Rescans and retries after debounce. | Row `Scanning`. |
| 79 | The app is force-quit between `rsync` completion and baseline commit. | At launch, reads the journal, verifies the destination, commits or replans. | Pair `Recovering`, then `Idle`. |
| 80 | The app is force-quit during a safety move. | Finishes or rolls back the move from the journal before any other action. | Same. |
| 81 | The state store is corrupted. | Stops automatic mutation. Restores the latest backup or rebuilds through a read-only scan and preview. | Pair `Needs attention · state restored from backup`. |
| 82 | The app upgrades with a new policy schema version. | Runs a full reconciliation and shows a new preview before mutations. | Preview sheet. |
| 83 | FSEvents reports dropped events. | Discards path hints and rescans the affected root. | Row `Scanning`. |
| 84 | Two pairs target two different drives. | Each drive has its own single mutation slot. | Both pairs sync in parallel. |
| 85 | Low Power Mode is on and the option is enabled. | Pauses automatic work. | Pair `Paused · Low Power Mode`. |
| 86 | The user presses Sync Now while a batch is running. | Merges the request into the next generation. Never starts a second `rsync` on the same volume. | Row `Syncing · changes pending`. |
| 87 | The user presses Pause mid-transfer. | Cancels `rsync` gracefully, keeps partials, keeps dirty state. | Pair `Paused`. Resume continues from partials. |
| 88 | An existing Copy or Sync transfer targets the same drive. | Unaffected. Dev Sync uses its own store and process. | Both appear in their own destinations. |

### Verification matrix

Unit: path normalization, root nesting, link boundaries, policy precedence,
sensitive overrides, Git ignore integration, case collisions, timestamp
tolerance, quick signatures, hash decisions, both decision tables, tombstone
lifecycle, conflict classification, rename scoring, retention eligibility,
`rsync` capability parsing, exit-code classes, and operation transitions.

Properties: a planner action never escapes either root; a destructive action
always has a safety action first; an incomplete scan produces no deletion;
two different contents never produce an automatic overwrite in bidirectional
mode; an unavailable volume never produces deletion; a managed link is never
traversed; a failed precondition performs no later destructive action for that
path; rerunning a successful plan transfers nothing; a tombstone prevents
resurrection; colliding names never enter a manifest.

Integration matrix: APFS case-insensitive, APFS case-sensitive, exFAT, an
encrypted volume, a read-only volume, low free space, and a changed mount
path. Path matrix: spaces, tabs, newlines, emoji, combining Unicode, leading
dash, long component, deep path, hidden file, case-only pair, normal,
dangling, absolute, and relative symlinks, hard link, empty directory,
executable, and extended attribute. Git matrix: normal, empty, no remote, two
remotes, shallow, submodule, nested repository, linked worktree, bare, LFS,
alternates, index lock, in-progress merge and rebase, changed `.gitignore`,
global ignore file, ignored `.env`, ignored private key, and a large ignored
dependency tree. Failure matrix: failure after each of the fifteen operation
steps, cancellation, forced termination, sleep, unplug, disk full, permission
removal, source and destination changes during copy, dropped events, and an
unavailable state store. Scale: 100 projects, 100,000 files, 1,000,000 ignored
files, a 10 GB object store, 10,000 rapid events, 10,000 small changed files,
one 20 GB stable file, and one continuously changing large file, recording
scan duration, CPU, peak memory, reads, bytes written, `rsync` launches, store
size, and cancellation latency.

Performance targets on Apple silicon with an SSD: an event that needs no
transfer never launches `rsync`; a 10,000-event storm produces one
reconciliation; saves in one project never scan another; a linked external
project is never scanned twice; the UI stays responsive; baseline writes are
atomic; memory scales with the active project; deep verification is
cancellable; retention never competes with a user transfer; hashing streams.
No timing promise appears in the UI without measurement.

### Extend a policy or capability

1. Add a case to `DevFilePolicyReason` in `DevSyncModels.swift` with a short
   user-facing `displayName`. The interface shows it in "Why was this path
   excluded?".
2. Add the rule in `DevFilePolicyEngine.decide` at its precedence level. The
   nine levels are fixed: unsupported type, Cloud Sync path, explicit user
   rule, sensitive override, required Git metadata, Git tracked, Git ignored,
   common exclusion, default inclusion. A new rule slots into one of these
   levels; it never adds a level.
3. Add a decision test in `DevSyncPolicyTests` that proves the new rule and
   proves it loses to every higher level.
4. If the rule reads a new setting, add the field to
   `DevSyncConfiguration.Policy` with a default and a `decodeIfPresent` line
   so old pair documents still load.

The planner and runner never change. They consume `DevFilePolicyDecision`
values only.

#### Add an rsync capability

1. Add a flag to `DevRsyncCapabilities` in `DevSyncModels.swift`.
2. Detect it in `DevRsyncProbe.probe`: parse the long option from `--help`,
   then prove it in the self-test with a real temporary transfer. A flag that
   only appears in `--help` is not enough; openrsync and rsync 3.x assign
   different meanings to some options.
3. Map it to an argument in `DevRsyncCommand.arguments`, gated by the flag and
   by the matching `DevVolumeCapabilities` value when the feature depends on
   the file system.
4. Add a builder test that proves the option appears only when the flag is
   true, and a probe test against `/usr/bin/rsync`.

The planner never sees `rsync` options. Reconciliation decisions do not change
when a capability is added or removed; only metadata fidelity changes.

#### Add a scenario

Every row in the scenario catalog above is an acceptance test named by its
number. Add the row here first, then the test in the module that owns
the behavior. A scenario that crosses modules belongs in
`DevSyncPairEngineTests`.

### Primary references

1. rsync manual: <https://download.samba.org/pub/rsync/rsync.1>
2. gitignore: <https://git-scm.com/docs/gitignore>
3. git-check-ignore: <https://git-scm.com/docs/git-check-ignore>
4. git-ls-files: <https://git-scm.com/docs/git-ls-files>
5. File System Events: <https://developer.apple.com/documentation/coreservices/file_system_events>
6. FSEvent stream flags: <https://developer.apple.com/documentation/coreservices/1455376-fseventstreamcreateflags>
7. Disk Arbitration: <https://developer.apple.com/documentation/diskarbitration>
8. URL resource keys: <https://developer.apple.com/documentation/foundation/urlresourcekey>
9. NSWorkspace mount notifications: <https://developer.apple.com/documentation/appkit/nsworkspace/didmountnotification>
