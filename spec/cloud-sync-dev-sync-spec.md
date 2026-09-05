# Cloud Sync Dev Sync Specification

Reviewed against current source, the system `rsync`, and the pinned design
contract on 2026-09-05. `spec/dev-sync-request-list.md` tracks status and
evidence. `goals.md` tracks the build order. This file holds the behavior
contract only.

"Must" marks a rule that makes the implementation incorrect when it is broken.
"Should" marks a rule that needs a documented reason to deviate. "May" marks an
option.

## Purpose

Dev Sync keeps a development tree on the internal disk and a second copy on a
removable drive. It is a project-aware reconciler, not a loop that runs `rsync`
after each file event.

The pipeline has five layers:

1. FSEvents reports that a path may have changed.
2. A debounce scheduler groups events into one dirty project.
3. A policy engine decides which project paths are eligible.
4. A reconciliation planner decides direction, deletion, rename, and conflict.
5. `rsync` transfers approved files. It never decides direction or deletion.

Dev Sync adds two modes to Cloud Sync:

- **Dev One-Way**: internal projects sync to external. External-only projects
  stay external and appear as links in the internal tree.
- **Dev Bidirectional**: changes sync in both directions. External-only
  projects stay external and appear as links in the internal tree.

Example tree:

```text
Internal                              External
~/dev/personal/app-a/                 /Volumes/DevSSD/dev/personal/app-a/
~/dev/personal/app-b/                 /Volumes/DevSSD/dev/personal/app-b/
~/dev/work/app-c/                     /Volumes/DevSSD/dev/work/app-c/
~/dev/personal/large-data-app -> ...  /Volumes/DevSSD/dev/personal/large-data-app/
```

`large-data-app` is external-resident. Cloud Sync creates the internal link,
never copies it inward, never treats the link as a real internal project, and
never follows the link during a scan.

Data preservation beats automatic convergence. Dev Sync never silently
overwrites a file that changed on both sides, never infers deletion from an
unavailable root or an incomplete scan, never deletes an external-only
project, never deletes a complete external project when the internal project
disappears, retains every destructive change, and shows a first-run plan
before it changes existing data.

Existing Copy, Sync, and Move transfers keep their current behavior. Dev Sync
is a separate destination with its own state store. No existing transfer is
migrated to Dev Sync without user action.

### Goals

Dev Sync must:

1. Keep eligible files from internal projects copied to the external root.
2. Support safe bidirectional changes for mirrored projects.
3. Keep external-only projects physically external and linked internally.
4. Reduce write amplification from compilers, package managers, editors, and
   agents.
5. Use Git ignore rules as the primary development filter.
6. Include selected ignored local files such as `.env` and key files.
7. Preserve Git repository state, including uncommitted work and local objects.
8. Survive drive removal, app termination, disk-full errors, and partial
   transfers.
9. Detect and stop on path, project identity, case, and content conflicts.
10. Work with spaces, Unicode, hidden files, and unusual file names.

Dev Sync should show project residency and sync health, excluded and
estimated sizes, bytes written to the external volume, manual Move to
External and Bring Internal actions, and recent overwritten or deleted
versions. It uses only standard macOS APIs, Git, and the system `rsync`.

### Non-goals

Version 1 does not synchronize two Macs at once, synchronize through a
server, replace Git remotes, provide a distributed file system, provide
block-level sync for active virtual-machine disks, make a live database
transaction-consistent, merge source code, offload single files from inside a
project, follow symbolic links, copy device nodes, sockets, or named pipes,
guarantee that every sandboxed third-party app can traverse managed links, or
provide secure erase.

## Terms

| Term | Meaning |
|---|---|
| Sync pair | One internal root and one external root, for example `~/dev` and `/Volumes/DevSSD/dev`. |
| Side | `internal` or `external`. |
| Project root | A directory chosen by discovery or by the user. The default marker is a `.git` directory or a valid `.git` file. |
| Relative project path | The project path below the root, for example `personal/tools/parser`. The same path identifies the project on both sides. |
| Mirrored project | A real directory on both sides. |
| External-resident project | A real external directory plus a managed internal link. |
| Internal-resident project | A real internal directory that has no external mirror yet. |
| Baseline | The last verified common state of a project. Bidirectional decisions compare both current sides with it. |
| Dirty project | A project that an event or periodic check says may have changed. Dirty does not mean a transfer is required. |
| Reconciliation | One scan and decision pass that produces an action plan. |
| Safety store | Retained versions, conflict copies, staging, and partial files. It is never part of the user project tree. |
| Tombstone | A record of a verified deletion. It stops an old copy from returning as a new file. |
| Destination drift | An external change to a mirrored project in Dev One-Way. |
| Managed link | A symbolic link that Cloud Sync created and tracks. A user link becomes managed only when the user adopts it. |

## Modes and residency

### Dev One-Way

Project level:

- Internal projects copy to the matching external path.
- External-only project roots are retained and linked into the internal tree.
- A complete internal project removal never deletes the external project. It
  normally converts the project to external-resident.

File level inside a mirrored project, for a path in the baseline:

- An internal add or change copies to external.
- An internal deletion deletes the external path only after safety retention.
- An external change is destination drift and is never overwritten by default.
- Internal and external changes to the same path are a conflict.
- An external deletion is destination drift. It never deletes the internal
  file.
- A new external-only path is retained and reported. It is never copied back
  and never deleted because it is absent internally.

A later advanced strict mirror option may remove destination-only paths after
a preview and safety retention. It is off by default and still protects
external-only project roots.

### Dev Bidirectional

Project level:

- A new internal project gets an external mirror.
- A new external project stays external and gets an internal managed link.
- A mirrored project accepts file changes from either side.
- A project can move between mirrored and external-resident by user action.
- A complete project deletion needs an explicit project-level decision.

File level: compare baseline, current internal, and current external. Copy the
one changed side to the unchanged side. When both sides changed differently,
create a conflict. Never pick the newest timestamp by default.

### Residency is separate from mode

```swift
enum DevProjectResidency: String, Codable {
    case mirrored
    case externalResident
    case internalOnlyPendingMirror
    case externalOnlyPendingLink
}
```

An external-resident project in Dev Bidirectional needs no reverse copy. Edits
made through the internal link already change the external project.

### Whole-project deletion

| Situation | Behavior |
|---|---|
| Mirrored project disappears internally in Dev One-Way | Keep the external copy. Offer conversion to external-resident. |
| External-resident project disappears externally | Mark offline or missing. Never create an empty internal replacement. |
| Mirrored project disappears on one side in Dev Bidirectional | Pause the project and ask for a project-level decision. |
| Project disappears because the volume unmounted | Mark the volume offline. Never infer deletion. |
| Project moved or renamed | Try safe rename detection before any copy or delete. |

## First run

The first run has no baseline and uses conservative rules.

Project catalog merge for each relative project path:

| Internal | External | First-run action |
|---|---|---|
| Real project | Missing | Preview and create the external mirror. |
| Missing | Real project | Preview and create the internal managed link. |
| Real project | Same project | Compare content and establish a baseline. |
| Real project | Different project identity | Project identity conflict. |
| Symlink to the selected external project | Real project | Offer to adopt the link as managed. |
| Non-project object | Project | Path-type conflict. |
| Project | Non-project object | Path-type conflict. |

File merge inside a project that exists on both sides:

| Internal | External | Action |
|---|---|---|
| Present and identical | Present and identical | Establish baseline. |
| Present | Missing | Copy in the permitted direction. |
| Missing | Present | Keep in Dev One-Way. Copy to internal in Dev Bidirectional. |
| Present and different | Present and different | Conflict. |
| File | Directory or link | Type conflict. |
| Case or normalization collision | Any | Block the project. |

No first-run action uses newest-wins without an explicit user option.

Before the first mutation the preview must show: projects to mirror,
external-only projects to link, paths to copy, paths to quarantine or delete,
conflicts, ignored size, sensitive ignored files that will be included,
file-system capability warnings, and estimated required free space. The user
approves the full plan or excludes specific projects.

The preview plans a pending mirror against an empty destination, because the
mirror directory does not exist yet. It counts one managed link for each
external-only project, lists every included sensitive path, and compares the
required bytes with the available capacity minus the free-space reserve. A
preview that changes nothing must mean that both sides already match.

## Safety invariants

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

## Architecture

```text
SwiftUI (Cloud Sync workspace, Dev Sync destination)
        |
DevSyncManager (@MainActor, @Observable)  UI state, pair lifecycle
        |
DevSyncPairEngine (actor, one per pair)   job serialization, state machine
   |        |         |          |            |
Roots   Discovery   Events    Scanner     Planner ---> Safety store
Volumes Git         Scheduler Hasher      Links        Rsync engine
Probe   Policy                Collisions               Verifier
                                                        State store
```

Responsibilities:

| Component | Owns |
|---|---|
| `DevSyncManager` | Pair list, published state for the UI, start and stop, notifications, and the handoff to each engine. |
| `DevSyncPairEngine` | The pair state machine, per-project job serialization, one mutation at a time per external volume, pause and resume, recovery, and commit after verification. |
| Roots and volumes | Bookmark resolution, canonical real paths, nested-root rejection, volume UUID identity, mount and unmount, read-only and capacity checks, and the capability probe. |
| Discovery and Git | Project roots without following links, project boundaries, unmanaged candidates, rename detection, `.git` files, submodules, linked worktrees, bare repositories, and alternates. |
| Events and scheduler | FSEvents streams with event IDs and flags, dirty project mapping, debounce with a maximum checkpoint, storm collapse, persisted dirty work, and the self-event ledger. |
| Policy | Hard denies, explicit rules, sensitive overrides, Git metadata rules, Git ignore results from Git, common exclusions, and a reason for every decision. |
| Scanner | `lstat` snapshots, quick signatures, selective hashes, case and Unicode collisions, unstable files, incomplete-scan flags, and sorted NUL manifests. |
| Planner | Baseline comparison, copy, move, delete, retain, link, and conflict actions with preconditions. It never mutates the file system. |
| Safety store | Overwritten and deleted versions, both sides of a conflict, staging, retention limits, and unresolved-conflict protection. |
| Rsync engine | Capability probe, self-test, argument building, manifest transfer, progress, cancellation, and exit-code classes. It never decides direction. |
| Links | Managed link creation, validation, repair after a mount path change, user-link adoption, and recorded removal. |
| Verifier | Post-transfer comparison with the planned source signature, source stability, and one atomic baseline commit. |
| State store | Pairs, projects, baselines, dirty work, cursors, operations, conflicts, links, tombstones, backups, and crash recovery. |

The service publishes pairs, status, projects, conflicts, links,
capabilities, and notifications through update streams. Every subscriber
receives its own stream, so the interface can subscribe each time its window
appears without silencing another subscriber.

### State machines

```swift
enum DevSyncPairState: String, Codable {
    case disabled, initializing, idle, debouncing, planning, transferring,
         verifying, paused, volumeOffline, blocked, error
}

enum DevProjectState: String, Codable {
    case clean, dirtyInternal, dirtyExternal, dirtyBoth, waitingForQuiet,
         syncing, conflict, destinationDrift, linkOffline, blockedByTopology,
         blockedByFileSystem, missing, error
}

enum DevOperationState: String, Codable {
    case planned, safetyPrepared, transferRunning, transferComplete,
         verifying, committed, cancelled, failed, recoveryRequired
}
```

Pair transitions: `disabled -> initializing -> idle`, `idle -> debouncing ->
planning`, `planning -> idle`, `planning -> transferring -> verifying -> idle`,
any active state to `paused`, `volumeOffline`, or `error`, `error ->
planning` after a successful preflight, and `volumeOffline -> initializing`
after the correct volume mounts.

An operation journal entry is written before the first mutation.

### State store

The store is a directory of JSON documents under
`Application Support/MacPowerToys/DevSync/`. Every write is atomic. One
document per project baseline keeps memory proportional to the active project.
The store lives outside both roots, never contains file contents or secrets,
and keeps versioned backups of its metadata.

```text
DevSync/
  pairs.json
  <pair-id>/
    projects.json
    links.json
    tombstones.json
    conflicts.json
    dirty.json
    cursors.json
    capabilities.json
    baselines/<project-id>.json
    operations/<operation-id>.json
    safety/history/<operation-id>/...     internal-side retained versions
    backups/<timestamp>/...
```

Documents carry the fields listed in the shared models: pairs with mode,
roots, configuration, state, and timestamps; projects with relative path,
residency, kind, identity, resource identifiers, state, explicit inclusion or
exclusion, last-seen times, and warnings; baseline entries with entry type,
size, modification time, tolerance, mode bits, symlink target, content hash,
and extended-attribute digest; dirty entries; tombstones; managed links;
operations with plan, timestamps, `rsync` identity, exit code, byte counts,
and error summary; conflicts with both signatures and safety paths; and
FSEvents cursors per side and volume.

A successful baseline update is one atomic document replace. Dirty work is
persisted before it is acknowledged. Operation documents remain until the
operation is resolved. A change to the policy schema version triggers a
re-preview or full reconciliation.

## Project discovery

A directory is a Git project candidate when it contains a `.git` directory or
a `.git` file with valid Git indirection syntax. Submodules and linked
worktrees commonly use a `.git` file.

The discovery walk starts at each real root, uses `lstat` semantics, never
follows a symbolic link, skips Cloud Sync system paths, skips known dependency
and cache directories during marker discovery, stops normal recursion below an
accepted outer project root, inspects Git topology below the root without
treating every submodule as a project, preserves category directories, reports
unreadable paths, and returns a complete or incomplete flag.

Everything under the internal root syncs. There is no project picker and no
include switch. The catalog has two kinds of unit:

- Every outermost Git repository at any depth is one unit. A monorepo with
  many `package.json` files is one unit unless the user splits it. A nested
  independent repository can be offered as a candidate. A submodule is never
  auto-added.
- The root unit, shown as `Everything else`, covers every file and folder
  that is not inside a repository unit and not a managed link: loose files
  at the root, category folders such as `docs` and `organization`, and every
  `_`-prefixed folder such as `_docs`, `_assets`, `_evidence`, and
  `_archive`. Its relative path is empty, and its scans carve out every
  nested unit and link as `Separate project` or `Managed link`.

Non-Git markers (`Package.swift`, `.xcodeproj`, `package.json`, and the rest
of the marker list) never create a unit. A marker folder is ordinary content
of the root unit. It becomes its own unit only when the user includes it as a
candidate.

Drive-only folders: during the external walk, the shallowest directory that
exists on the drive but not on the Mac, outside every repository unit, is a
linkable directory. The catalog turns it into a nonGit unit with residency
`externalOnlyPendingLink`, and the engine creates the managed link at the
same internal path, exactly like a drive-only repository. A folder that the
root unit's baseline already knows was mirrored is a deletion on the Mac,
not a linkable directory; it follows the normal mirror rule with retention.

### Project identity

Relative path is the expected match. It is not sufficient for safety. Identity
uses the project UUID, the volume and file resource identifier for same-volume
rename detection, Git topology type, credential-stripped remote URL hints,
cheap repository object hints, and user confirmation for uncertain matches. Two
clones of the same remote can be intentional; a matching remote never
auto-merges projects.

### Rename and move detection

For a missing known project and a new project on the same side: compare
resource identifiers, then prior identity hints, then Git topology. Present a
rename candidate when confidence is high. Never delete the old matching project
on the other side until the rename is confirmed. A confirmed same-volume rename
moves the counterpart on its own volume instead of a full rewrite.

### Git topology

Submodules: the superproject is the project unit. The submodule working tree
and its metadata under the superproject Git directory are included. The
working-tree manifest enumerates each initialized submodule with Git in its own
work tree. An uninitialized submodule stays a Git link entry. A submodule Git
directory outside the pair produces a topology warning. A user can detach a
submodule as its own project only after a warning.

Linked worktrees: a `.git` file that points to a worktree administration
directory marks a topology group. Find the Git common directory and check that
the main repository and all needed worktrees are inside the pair. Do not
rewrite `.git` pointer files in version 1. Warn when the destination topology
will not resolve, allow a raw backup only after acknowledgement, and never show
the destination as ready to use when pointer validation fails.

Bare repositories are explicit projects. Object alternates are detected; an
alternate outside the pair produces a warning, and the copied repository is
never described as self-contained.

Git binary: use the Xcode or Command Line Tools `git`. Check
`xcode-select -p` before the first Git call so macOS never shows the Command
Line Tools installer dialog. When Git is unavailable, treat every project with
the non-Git policy, show a warning, and never claim Git-accurate ignore
behavior.

## File policy

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

### Git parses Git ignore rules

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

### Sensitive and local files

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

### Git metadata

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

### Common exclusions

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

## Events and scheduling

FSEvents is a dirty hint, never the source of truth. The implementation
handles coalesced events, event loss, a path that no longer exists, rename
events without a reliable pair, and changes made during Cloud Sync's own
transfer.

Each real root has one stream created with file-level events, root-change
watching, and a persisted event ID. Managed links are not real roots; the
external target is watched directly.

A full affected scan is mandatory after `MustScanSubDirs`, user-dropped or
kernel-dropped events, wrapped or invalid history, a root change, a bookmark
re-resolution, an external remount, an app upgrade that changes policy
semantics, state recovery, an ignore-rule change, an incomplete prior scan, or
an event on an unknown project path.

On each event: resolve the side without following links, discard Cloud Sync
system paths, find the nearest known project boundary, mark that project
dirty, mark discovery dirty when no project matches, keep the earliest and
latest event times, and never start `rsync` immediately.

Defaults, configurable per pair:

| Timing | Default |
|---|---|
| FSEvents latency | 2 seconds |
| Normal quiet period | 10 seconds |
| Minimum project sync interval | 20 seconds |
| Continuous-activity checkpoint | 5 minutes |
| Large or volatile file quiet | 60 seconds |
| Periodic full reconciliation | 6 hours |

Presets: Responsive, Balanced (default), Low drive activity, Manual only.

Sliding debounce with a maximum checkpoint: the first event sets first and
last dirty times and schedules at last plus quiet period. Each event moves the
schedule. When continuous activity reaches the checkpoint interval, a bounded
checkpoint includes only stable eligible paths and leaves unstable paths dirty.
When a job is active, new events merge into the next dirty generation.

A due generation for a project that cannot be planned, such as an excluded or
external-resident project, completes and drops. Requeue is reserved for a
project that waits for Git, a quiet window, or temporarily unavailable roots.
A generation that requeues without progress must never block the projects
behind it.

Storm collapse, configurable and testable: more than 1,000 path events in 10
seconds collapse to project-dirty. More than 10,000 pending paths for one
project discard the path hints and perform one project scan. Dropped-event
flags discard path hints and perform a complete affected scan.

Self-generated events: watchers stay on during transfer. An operation ledger
records expected destination path, action, resulting signature, operation ID,
and time window. A destination event is consumed only when the resulting path
matches the expectation. A different signature, or a user edit after Cloud
Sync wrote the file, requeues the path. A broad "ignore destination events
while syncing" rule is not acceptable.

Concurrency defaults: one `rsync` mutation per external volume, two project
metadata scans, one deep hash. Two mutation jobs never target overlapping
paths. Priority order: user-requested operation, conflict safety copy, mount
recovery, normal event batch, periodic verification, retention cleanup.
Automatic work uses utility or background quality of service. Optional power
settings pause on Low Power Mode, run large transfers only on power, pause
below a battery threshold, and prevent idle sleep only while a mutation is
active. When the dirty queue grows, collapse path events to project scans and
show "Changes pending" instead of a false error.

## Scanning and signatures

The scanner uses `lstat`, never traverses links, uses relative paths below the
project root, collects errors by path, reports completeness, detects changes
during the scan, sorts manifests in stable byte order, and reads file contents
only when a hash is required.

```swift
struct DevFileSignature: Codable, Equatable {
    let kind: DevEntryKind
    let size: UInt64?
    let modificationTimeNanoseconds: Int64?
    let mode: UInt16?
    let symlinkTarget: String?
    let resourceIdentifier: Data?
    let contentHash: Data?
    let xattrDigest: Data?
}
```

The quick signature uses entry type, size, modification time with the
volume-specific tolerance, executable or mode bits when supported, symlink
target text, and the file resource identifier as a rename hint. A resource
identifier is never a cross-volume identity.

Hash content only when both sides changed by quick signature, size and time
are equal but a change is suspected, the file system has coarse timestamps, a
first-run same-path comparison is ambiguous, a transfer is deeply verified,
rename matching needs more confidence, or the user asks for full verification.
Use SHA-256 through CryptoKit in streaming chunks.

Stability: record type, size, modification time, and resource identifier
before transfer and read them again after. A changed source is not committed,
keeps the destination copy as an intermediate result, is requeued, and stops
the project from reporting clean. Large or volatile files need two equal probes
separated by the stable window.

Directory modification time is noisy. Preserve structure, never use directory
mtime as a content signal, and preserve directory permissions only when both
volumes support them and metadata fidelity is enabled.

Case and Unicode collisions: build a destination comparison key from the
less-capable side, detect `Readme.md` beside `README.md` and names that
normalize to the same destination name, block the affected project, list every
colliding path, never auto-rename, and never let `rsync` choose a winner.

Incomplete scan: when a directory needed for deletion analysis is unreadable,
mark the scan incomplete, allow safe additive copies when preconditions pass,
disable deletions for that scope, and show the inaccessible path.

## Reconciliation

Entry states per side: absent, unchanged from baseline, changed from baseline,
added after baseline, type-changed from baseline, unreadable, unstable.

### Dev One-Way decision table

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

### Dev Bidirectional decision table

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

### Tombstones

A tombstone is valid only when the relevant root was online, the parent scan
was complete, the path existed in the baseline, the path was confirmed absent,
and the delete was verified. It remains until both sides observed the deletion
and the retention interval passed. A tombstone never converts an old
disconnected copy into a new addition.

### Conflicts

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

### Renames

FSEvents rename flags are hints. Pair old and new paths by scan evidence in
this order: same resource identifier on the same volume, same type, size, and
strong hash, same Git project identity for project moves, user confirmation. A
safe rename moves the counterpart on its own volume, keeps the old path in the
operation journal, verifies the new path, updates the baseline atomically, and
avoids delete-plus-copy.

## Plans and operations

The planner produces an immutable plan before any mutation.

```swift
enum DevSyncActionKind: String, Codable {
    case createDirectory, copyPath, movePath, stageExistingVersion, deletePath,
         createManagedLink, repairManagedLink, removeManagedLink,
         establishBaseline, createConflict, noOp
}
```

Every mutating action carries preconditions: expected source signature,
expected destination signature or absence, expected volume identifier,
expected project identity, expected parent path type, required free space, and
policy version. Preconditions are validated again before each action runs. A
failed precondition stops that path, requeues it, and rebuilds the plan. Stale
destructive actions never continue.

Operation order:

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
12. Commit baselines and tombstones in one atomic document replace.
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

## rsync adapter

The system binary on the current macOS is openrsync (`/usr/bin/rsync`,
protocol 29, "rsync 2.6.9 compatible"). It accepts `--files-from`, `-0`
(`--from0`), `--itemize-changes`, `--partial`, `--partial-dir`, `--backup`,
`--backup-dir`, `--executability`, `--extended-attributes`, `--modify-window`,
`--max-delete`, `--` before paths, and the `-l`, `-t`, `-p`, `-O`, `-H`, and
`-X` short options. It has no ACL option and no `--crtimes`. A verified run
copied a file with a space in its parent directory, an empty directory, a
symlink as a symlink, and an executable bit with `--files-from` and
`--partial-dir`.

Capability-first: do not hard-code behavior from the version. At setup and
after a binary change, run `--version` and `--help`, parse supported long
options, run a temporary local self-test, store a capability record with the
executable identity, version output, and test result, and invalidate prior
command profiles when the fingerprint changes. The self-test covers regular
files, directories, empty directories, symbolic links, the executable bit,
spaces and Unicode, a newline in a name where the file system permits it,
modification time, extended attributes when requested, hard links when
requested, partial-directory behavior, backup-directory behavior, and
NUL-delimited `--files-from` input.

Binary selection order: user-selected path, application-managed binary when
distribution is handled, known package-manager paths, system binary. The app
shows the selected path, version, protocol, supported metadata features, and
unsupported Dev Sync features. It never depends on the interactive shell
`PATH`.

Process execution uses `Foundation.Process` with `executableURL` and an
`arguments` array, never `/bin/sh -c`, `--` before source and destination when
supported, concurrent capture of standard output and error without pipe
deadlock, graceful cancellation, URLs until the process boundary, and no
interpolation of user paths into filter text.

Manifest transfer: the policy engine produces the exact transfer set as a
sorted NUL-delimited relative-path manifest passed through `--files-from=-`
and `-0`. Absolute paths, empty paths, active `..` components, paths that
resolve outside the project root, app system paths, and paths that traverse a
managed link are rejected. Approved files and required parent directories are
listed explicitly.

Base profile, built from capabilities:

```text
-l -t -O --executability --partial --partial-dir=<safety partial dir>
--backup --backup-dir=<safety history dir> --itemize-changes
--files-from=- -0
```

Conditional options: `-p` when both volumes support Unix permissions and
metadata fidelity is enabled, `-X` when both volumes support extended
attributes and the self-test proves it, `-H` when hard links are enabled,
`--crtimes` when the self-test proves it and both volumes support creation
times, and `--modify-window=<detected tolerance>` only when required. ACL
support is recorded for diagnostics and never emitted as `-A`.

Rules: preserve symbolic links as links, never follow source links, preserve
the executable bit when the target supports it, never preserve owner, group,
devices, or special files by default, no compression for a local copy, no full
checksums per batch, no directory modification time as a conflict input,
partial data stays on the destination volume, and the partial directory is
protected from synchronization and deletion.

Never use by default: `--inplace`, `--append`, `--append-verify`,
`--copy-links`, `--copy-dirlinks`, `--keep-dirlinks`, `--remove-source-files`,
`--ignore-errors`, `--delete-excluded`, `--trust-sender`, `--old-args`, or any
broad `--delete`. Planned deletions run through the safety engine, not
`rsync`.

Repeatedly changing large files get a longer stable window, an estimated byte
count, a per-path exclude, and a size warning. They never switch to
`--inplace` automatically.

Exit codes:

| Exit code | Meaning |
|---|---|
| 0 | Transfer succeeded. Verification is still required. |
| 20 | Cancelled or terminated. Keep dirty state. |
| 23 | Partial transfer. Verify copied paths but do not commit the batch. |
| 24 | Source vanished. Rescan and retry. |
| 25 | Delete limit stopped an operation. Mark safety stop. |
| Other | Fail the operation and keep the journal. |

`--itemize-changes` output feeds progress and diagnostics only. File names can
contain control characters, so the plan and the post-transfer scan are the
authoritative mutation record. Logs escape control characters and redact
sensitive paths in privacy mode.

Partial files can contain secrets. The partial directory stays on the
destination volume with restrictive permissions, is hard-excluded, uses a
project-safe relative name, is cleaned only when no active operation
references it, and never lives in a world-writable temporary directory.

## Verification

After transfer, verify each planned path against the stable source signature:
existence, type, size, modification time within tolerance, symlink target,
executable or mode bits when supported, and a selective hash when required.

"Verify Now" runs deep verification: scan all included paths, hash both sides,
identify silent same-size and same-time differences, show metadata fidelity
differences, and warn that it reads significant data from both drives.

A periodic full metadata reconciliation also runs at startup when the prior
state was not clean, after the external volume mounts, after an event-loss
flag, after a policy change, after an app version changes the schema or policy
version, and on request.

## Safety store and retention

External-side retention lives below the selected external root so internal
storage stays available:

```text
<external-root>/.cloudsync-system/<pair-id>/
    staging/  history/  conflicts/  manifests/  recovery/  partial/
```

Internal-side retention lives in the state store `safety/history` directory
because `rsync --backup-dir` and same-volume moves require the same volume as
the destination. Overwritten internal versions are small and expire on the
normal schedule.

Before a destructive action: preserve the existing version, record its side,
original path, and operation ID, verify that the safety copy or move
completed, and only then permit the overwrite or deletion. Overwrites use
`--backup-dir` so `rsync` moves the old destination version into history
before it replaces the file. Deletions are same-volume moves into history.
Dev Bidirectional destructive actions never proceed when the external safety
store is unavailable unless the user explicitly disables safety for that
action.

| Retention | Default |
|---|---|
| Overwritten files | 7 days |
| Deleted files | 30 days |
| Resolved conflicts | 30 days |
| Unresolved conflicts | Until resolved |
| Maximum safety-store size | Configurable, capacity-based default |
| Minimum external free-space reserve | Configurable |

Cleanup order: expired completed staging, expired overwritten versions,
expired deleted versions, resolved conflict copies, never unresolved conflict
copies, never data needed by an incomplete operation. Cleanup never consumes
the last free space.

The UI states that synchronized corruption and deletion can propagate, that
ransomware or user error can affect both active copies, that a separate
versioned backup is still useful, and never claims secure erase.

## Volumes and file systems

Store the bookmark for each root, the volume UUID, the volume name for display
only, the file-system type, and root-relative project paths. When a different
drive uses the same display name, do not sync, show a volume identity
mismatch, and require user action.

At pair setup and each meaningful remount, probe read/write access, available
capacity, case sensitivity, case preservation, symbolic-link support,
hard-link support, Unix permission or executable-bit behavior, extended
attributes, creation-time support, timestamp precision, persistent file
identifiers, maximum practical path behavior, and encryption state. Use
Foundation volume resource keys plus a real temporary probe, because a
reported capability alone is not enough.

Compatibility levels:

- **Full fidelity**: read/write, compatible case behavior, symbolic links,
  executable bits, and the requested extended attributes.
- **Portable mode**: continues when metadata is unsupported and lists the
  expected loss such as executable bits, symlinks, ACLs, extended attributes,
  creation times, hard links, or timestamp precision. It never claims an exact
  development copy.
- **Blocked mode**: case collisions exist, source symlinks cannot be
  represented and the user did not accept a skip policy, the target is
  read-only, project paths cannot be represented, project identity is unsafe,
  required free space is unavailable, or the self-test found unreliable
  mutation behavior.

Timestamp tolerance: detect the target resolution, set `--modify-window` only
when required, and use the same tolerance in the baseline comparator so coarse
file systems do not cause repeated false changes. The bundled macOS
`openrsync` (protocol 29) writes whole-second modification times, so the pair
tolerance is at least one second whenever the transfer tool reports a
protocol below 30. The planner, verifier, runner, and baseline all read that
one pair tolerance; none of them keeps a private value.

Path containment: every "is this path below that root" check compares the
lexical path built from the canonical root, never a standardized copy of a
path that does not exist yet. Foundation strips `/private` from an existing
`/private/var` root but keeps it on a missing child, so a standardized
comparison rejects every new folder under such a root. A symlink walk over
the existing parents still guards against link traversal.

Available capacity: read the important-usage capacity first and fall back to
the plain available capacity when the important-usage value is zero. External
volumes and disk images report zero for important usage, and a zero value
must never read as a full disk.

Free-space preflight estimates new bytes, changed bytes, the largest temporary
file, staging for new projects, safety history bytes, and the configured
reserve. It never starts an operation that would cross the reserve and fails
conservatively when the size is unknown.

On mount: resolve the expected volume identity, wait until the root is
accessible, rerun critical capability checks, repair a stale link target only
for links that are still present, registered, and point to the expected
project on the verified volume, never recreate a link the user deleted unless
the pair setting permits it, and run a full reconciliation before event mode.
On imminent unmount: stop scheduling, cancel the active `rsync`, close file
handles, persist dirty state, and never block unmount indefinitely. On
unexpected removal: mark the volume offline, keep the journal, never infer
deletion, and validate partial and staging data after remount.

## Managed links

A managed link gives one internal namespace without duplicating an
external-resident project.

Creation preconditions: the external target is a real project directory below
the selected external root, the internal link path is absent, all required
internal parent category directories are safe, the internal path is not inside
another project root unless explicitly allowed, no case or Unicode collision
exists, the volume identity is correct, and the project belongs to no other
pair.

Dev Sync creates the link for each external-only project when it refreshes
the catalog: at pair start and after every discovery pass while the drive is
online. A linked plain folder is not a repository, so once its internal link
exists neither walk reports it again; the catalog keeps it external-resident
as long as its managed link validates as healthy, and never marks it missing
on that evidence alone. When a file, folder, or link already exists at the internal path, Dev
Sync keeps it untouched, marks the project `Link missing` with the reason,
and waits for the user to move the item aside or exclude the project.

Cloud Sync may create normal internal category directories such as
`~/dev/personal/data/`. It never creates a managed link inside an existing Git
project to expose a nested external project; that needs an explicit user
decision.

A POSIX link stores path text. Write the current absolute resolved external
target, store the volume identity and target-relative path in the state
store, validate the target after each mount, repair it when the same volume
mounts at a different path, and never repair it when the volume identity
differs.

A link is managed only when it has a matching state record. An optional
extended attribute is an extra marker, never the only one. For an existing
user link that resolves to the expected external project, offer "Adopt as
Managed Link" and never change it automatically.

Deleting a managed link never deletes the external project. The link is
marked missing with a Repair action. Auto-repair runs only when the pair
setting enables it. "Remove from Internal Namespace" is the explicit action
that stops link management.

Offline: leave the link in place, mark it offline, never replace it with an
empty directory, never let discovery treat the broken link as a deleted
internal project, and never create a local shadow directory. The broken link
prevents an accidental second project at the same name.

Managed link paths are excluded from internal discovery, internal snapshot
recursion, internal-to-external manifests, deletion comparison, and duplicate
path statistics. The external target is watched and scanned directly.

Some tools resolve the physical path, apply sandbox rules, or watch
differently through a link. The UI never promises universal compatibility. It
shows the real resolved path and offers "Open Real Location".

## Move to External and Bring Internal

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

## Large, active, and volatile files

There is no silent universal maximum file size. Warn above a configurable
size, show planned bytes, use a longer stable window, let the user exclude or
manually sync the path, and keep a per-project byte budget.

Database patterns (`*.sqlite`, `*.sqlite3`, `*.db`, `*-wal`, `*-shm`,
`*.mdb`, `*.realm`) and disk images (`*.vmdk`, `*.qcow2`, `*.vdi`,
`*.sparsebundle`, `*.sparseimage`) trigger warnings, never automatic
deletion. Repeated changes classify the file as volatile with a longer stable
window. Related database files stay in one batch where practical. The UI
states that consistency is not guaranteed and recommends a tool-specific
snapshot or shutdown before sync. No database-specific command runs without an
explicit adapter.

Continuously growing files use the maximum checkpoint rule and transfer only
when stable enough. The user can exclude by pattern, sync manually, choose
per-project "sync only when idle", or cap writes per hour.

## Security and privacy

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

## User interface

Dev Sync is a destination in the Cloud Sync full workspace. It follows the
240pt data sidebar, the 40pt page strip, the 12pt body inset, native small
controls in one centered 24pt row, section cards, and operational cards from
`DESIGN.md`. It never opens a separate window or a compact applet.

### Sidebar

A `Dev Sync` navigation row sits after `Activity` and before the Remotes
group. Its trailing count badge shows unresolved conflicts plus blocked
projects when either is nonzero.

### Mode copy

```text
Dev One-Way
Internal projects sync to external. External-only projects stay external
and appear as links internally.

Dev Bidirectional
Changes sync in both directions. External-only projects stay external and
appear as links internally.
```

Dev One-Way is never described as a destructive exact mirror.

### Setup sheet

A 560pt standard sheet with the shared flat 40pt header, a scrolling body,
and a footer with Back, Cancel, and Continue. Steps:

1. **Roots**: internal root, external root, resolved volume, available space,
   encryption state, file-system type. Nested, identical, or aliased roots
   block Continue with the reason inline.
2. **Compatibility**: read/write status, metadata fidelity, case behavior,
   symlink support, timestamp precision, selected `rsync` and capabilities,
   and blocking issues.
3. **What syncs**: one sentence states that everything under the root
   syncs except the skip list, then read-only groups for Internal only,
   External only, On both sides, Identity conflicts, and Unsupported
   topology. Each row shows relative path, detected type, estimated included
   and excluded size, residency result, and warnings. There is no include
   switch. The `Everything else` row stands for the root unit.
4. **Rules**: Skip caches, dependencies, build outputs, and tmp (on) with
   Extra patterns, Back up sensitive and local files (on) with Edit
   patterns, Include Git object store and LFS objects (on), Preserve
   extended attributes (Auto), Preserve hard links (off), Version retention
   (on). Git ignore rules are off and not shown; the skip list is the only
   filter.
5. **Activity**: Responsive, Balanced, Low drive activity, Manual only, plus
   advanced debounce values, large-file threshold, only on power, and a byte
   budget.
6. **Preview**: counts and bytes for copy internal to external, copy external
   to internal, managed links, retained external-only paths, safety moves,
   conflicts, blocked paths, and ignored sensitive files included. The primary
   action states the real operation, such as `Create 3 mirrors and 1 managed
   link`.

### Pair page

The page strip shows the pair name and a state subtitle such as `Idle · DevSSD
online · synced 2 min ago`. Actions: `Sync Now` as the primary action,
`Pause` or `Resume`, and a menu with Preview Pending, Verify Now, Open
External Root, Open Safety Store, Repair Links, and Pair Settings.

Body, top to bottom:

1. A status card with drive online or offline, current phase, last successful
   sync, next checkpoint, pending projects and bytes, bytes written today,
   conflict count, destination drift count, safety-store size, and `rsync`
   status. Status never relies on color alone.
2. Project rows as operational cards: name and relative path, residency badge
   (`Mirrored`, `External`, `Pending mirror`, `Pending link`), state badge,
   last successful sync, included and excluded size, and active warnings.
   Context and row actions: Sync Project, Preview, Move to External, Bring
   Internal, Exclude Project, Edit Rules, Repair Link, Resolve Conflict, Open
   Real Location. The state badge changes as soon as the engine learns
   something: a clean or drifted project shows `Changes pending` from the
   first accepted event until its batch starts, and an external-resident
   project shows `Offline` while the drive is offline and returns to `Clean`
   when the link validates after the remount. A drifted row shows its own
   drift-path count as soon as the engine finds the drift, and the status
   card's drift count is the sum over every project.
3. Conflicts, one card per conflict, with relative path, conflict type,
   internal size and time, external size and time, baseline time, an optional
   text diff for small text files, and safety-copy locations. Actions: Keep
   Internal, Keep External, Keep Both, Open Both, Mark Resolved after Manual
   Merge, Exclude. No action deletes a safety copy immediately.

Empty state before setup: `No Dev Sync pair yet` with a `Set Up Dev Sync`
primary action.

### Notifications

Notify for an external drive missing for a configured interval, sync blocked
by conflict, disk almost full, sensitive backup to an unencrypted drive, a
broken managed link, an operation failure, and the first successful
initialization. Never notify for normal file batches.

## Defaults

| Setting | Default |
|---|---|
| External-only projects (both modes) | Retain and link internally. |
| External-only files inside a mirrored project (Dev One-Way) | Retain and report. |
| Complete internal project deletion | Keep the external project. Offer conversion to external-resident. |
| Bidirectional conflict rule | Preserve both. No newest-wins. |
| First-run same-path differences | Conflict. |
| Follow Git ignore | On. |
| Copy ignored sensitive and local files | On. |
| Copy `.git` data | On. |
| Copy Git LFS local objects | On. |
| Skip common caches and dependencies | On. |
| Skip unignored build outputs | Off. |
| Normal debounce | 10 seconds. |
| Continuous activity checkpoint | 5 minutes. |
| Concurrent external mutations | One per external volume. |
| Full checksum on every run | Off. |
| `--inplace` | Prohibited. |
| Destructive safety retention | On. |
| External encryption warning | On. |
| Repair stale mount-path text in a valid managed link | On, same verified volume and target only. |
| Recreate a deleted managed link | Off. Visible Repair action. |
| Whole-project automatic delete | Off. |
| Large-file warning | 1 GB. |
| Event storm threshold | 1,000 events in 10 seconds. |
| Path collapse threshold | 10,000 pending paths. |
| Pause on Low Power Mode | Off. |
| Large transfers require power | Off. |

Configuration shape:

```json
{
  "policySchemaVersion": 1,
  "mode": "devOneWay",
  "discovery": { "requireGitByDefault": true, "showMarkerCandidates": true, "allowNestedIndependentRepositories": false },
  "policy": { "followGitIgnore": true, "includeIgnoredSensitiveFiles": true, "sensitivePatterns": ["..."], "skipCommonCaches": true, "skipUnignoredBuildOutputs": false, "includeGitMetadata": true, "includeGitLFSObjects": true },
  "timing": { "fseventsLatencySeconds": 2, "quietPeriodSeconds": 10, "minimumProjectIntervalSeconds": 20, "continuousCheckpointSeconds": 300, "largeFileQuietSeconds": 60, "fullReconcileSeconds": 21600 },
  "safety": { "retainOverwritesDays": 7, "retainDeletesDays": 30, "retainResolvedConflictsDays": 30, "protectDestinationDrift": true, "wholeProjectDeleteRequiresConfirmation": true },
  "performance": { "maxConcurrentTransfersPerVolume": 1, "largeFileWarningBytes": 1073741824, "eventStormThreshold": 1000, "pathCollapseThreshold": 10000 },
  "metadata": { "permissions": "auto", "xattrs": "auto", "hardLinks": "off" },
  "power": { "pauseOnLowPowerMode": false, "largeTransfersRequirePower": false }
}
```

## Error handling

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

## Scenario catalog

Each row is a concrete situation, what Dev Sync does, and what the person
sees. Rows also define acceptance tests; the test name is the row number.

### Projects and residency

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
| 13 | A repo contains a vendored independent Git repo. | The outer repo is the project. The inner repo is offered as an unmanaged candidate and never auto-added. | Candidate `vendor/lib · Nested repository · Add / Ignore`. |
| 14 | A project uses submodules. | The superproject is the unit. Initialized submodule files are enumerated with Git in each work tree. | One row with a `Submodules` note. |
| 15 | A project is a linked worktree whose main repo is outside the pair. | Copies raw files. Marks the topology unsupported. Never rewrites `.git`. | Row warning `Destination copy is not usable as a worktree`. |
| 16 | A bare repository sits under the root. | Never auto-added. | Candidate `Bare repository`. |
| 17 | Two clones of the same remote sit at different paths. | Two projects. No merge. | Two rows. |
| 18 | A folder has `package.json` but no `.git`. | Never auto-added. | Candidate `Node package · Add / Ignore`. |
| 19 | The internal root is the home directory. | Allows it, bounds discovery to project roots, and shows the count. | Warning `312 projects found. Consider a narrower root.` |
| 20 | The two roots are nested, identical, or the same directory through a symlink. | Rejects the pair in setup. | Inline error `Roots must not overlap`. Continue disabled. |
| 21 | A second pair uses a root inside an existing pair. | Rejects it. | Inline error `~/dev/work is already owned by pair DevSSD`. |

### Files inside a mirrored project

| # | Situation | What Dev Sync does | What you see |
|---|---|---|---|
| 22 | The editor saves the same file 50 times in two seconds. | One batch after the 10 second quiet window. Copies the final stable file. | Row `Syncing`, then `Clean`. One transfer, not fifty. |
| 23 | A developer types for 40 minutes without a pause longer than 10 seconds. | A bounded checkpoint every 5 minutes copies stable files. | Row `Syncing` every 5 minutes. Unstable files wait. |
| 24 | `npm install` writes 100,000 files under `node_modules`. | Git ignores them. The event storm collapses to one project scan. Nothing is copied. | Row `Scanning`, then `Clean`. Excluded size grows. |
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
| 49 | `.gitignore` gains `build/` after `build/` was already mirrored. | Full policy rescan. Moves the external `build/` to history after a valid plan. | Row `Clean`. History shows `build/`. |
| 50 | `.DS_Store` appears. | Hard-excluded. | Nothing. |
| 51 | A `.cloudsync-system` folder was copied into a project from an old drive. | Hard-excluded and reported. | Path reason `Cloud Sync system path`. |
| 52 | An iCloud placeholder `.icloud` file sits in a project. | Excluded as dataless. | Path reason `Not downloaded`. |

### Drives, volumes, and mounts

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

### Links

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

### Engine, Git, and recovery

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

## Tests

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

## Source layout

```text
powertoys/Models/DevSyncModels.swift
powertoys/Services/DevSync/DevSyncStateStore.swift
powertoys/Services/DevSync/DevSyncRoots.swift
powertoys/Services/DevSync/DevSyncDiscovery.swift
powertoys/Services/DevSync/DevSyncPolicy.swift
powertoys/Services/DevSync/DevSyncEvents.swift
powertoys/Services/DevSync/DevSyncScanner.swift
powertoys/Services/DevSync/DevSyncPlanner.swift
powertoys/Services/DevSync/DevSyncRsync.swift
powertoys/Services/DevSync/DevSyncSafety.swift
powertoys/Services/DevSync/DevSyncLinks.swift
powertoys/Services/DevSync/DevSyncPairEngine.swift
powertoys/Services/DevSync/DevSyncManager.swift
powertoys/Views/Rclone/DevSync/DevSyncPage.swift
powertoys/Views/Rclone/DevSync/DevSyncSetupSheet.swift
powertoys/Views/Rclone/DevSync/DevSyncProjectRow.swift
powertoys/Views/Rclone/DevSync/DevSyncConflictCard.swift
powertoysTests/DevSync*Tests.swift
docs/DEV_SYNC.md
```

Adding a file policy or an `rsync` capability never changes reconciliation
rules. Policies add a `DevFilePolicyReason` case and one rule in the policy
engine. Capabilities add a probe result and one option in the argument
builder. `docs/DEV_SYNC.md` explains both extension points.

## References

1. rsync manual: <https://download.samba.org/pub/rsync/rsync.1>
2. gitignore: <https://git-scm.com/docs/gitignore>
3. git-check-ignore: <https://git-scm.com/docs/git-check-ignore>
4. git-ls-files: <https://git-scm.com/docs/git-ls-files>
5. File System Events: <https://developer.apple.com/documentation/coreservices/file_system_events>
6. FSEvent stream flags: <https://developer.apple.com/documentation/coreservices/1455376-fseventstreamcreateflags>
7. Disk Arbitration: <https://developer.apple.com/documentation/diskarbitration>
8. URL resource keys: <https://developer.apple.com/documentation/foundation/urlresourcekey>
9. NSWorkspace mount notifications: <https://developer.apple.com/documentation/appkit/nsworkspace/didmountnotification>
