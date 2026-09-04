# Dev Sync developer guide

Dev Sync lives inside Cloud Sync. The behavior contract is
`spec/cloud-sync-dev-sync-spec.md`. This guide explains how the code is laid
out and how to extend it without touching reconciliation rules.

## Layout

| Area | File | Owns |
|---|---|---|
| Models | `powertoys/Models/DevSyncModels.swift` | Every shared type: pairs, projects, signatures, baselines, plans, operations, conflicts, capabilities, defaults. |
| Contract | `powertoys/Services/DevSync/DevSyncEngine.swift` | The `DevSyncEngine` protocol the interface talks to, live status, setup types, and an in-memory preview engine. |
| State | `DevSyncStateStore.swift` | Atomic JSON documents under `Application Support/MacPowerToys/DevSync/`. |
| Safety | `DevSyncSafety.swift` | Retained versions, conflict copies, staging, partials, retention. |
| Roots | `DevSyncRoots.swift` | Root validation, volume identity, the volume capability probe, mount events. |
| Git | `DevSyncGit.swift` | Read-only Git calls, manifests, ignore checks, topology, identity, locks. |
| Discovery | `DevSyncDiscovery.swift` | Project roots, candidates, rename matching. |
| Policy | `DevSyncPolicy.swift` | The file policy engine and its precedence. Its `DevPathPolicy` conformance, which the scanner consumes, lives in `DevSyncResidency.swift`. |
| Events | `DevSyncEvents.swift` | FSEvents stream, dirty scheduler, self-event ledger. |
| Scanner | `DevSyncScanner.swift` | Snapshots, signatures, hashing, collisions, manifests, verification. |
| Planner | `DevSyncPlanner.swift` | Pure reconciliation and catalog planning. |
| Rsync | `DevSyncRsync.swift` | Binary location, capability probe, argument builder, transfer process. |
| Links | `DevSyncLinks.swift` | Managed symbolic links. |
| Residency | `DevSyncResidency.swift` | Move to External and Bring Internal transactions. |
| Runner | `DevSyncOperationRunner.swift` | The fifteen-step operation transaction and recovery. |
| Engine | `DevSyncPairEngine.swift`, `DevSyncService.swift` | Per-pair state machine and the app-wide service. |
| Interface | `powertoys/Views/Rclone/DevSync/` | Manager, page, setup sheet, rows, conflict cards, pair settings. |

Data flows in one direction: events mark projects dirty, the scanner produces
snapshots, the policy engine labels paths, the planner turns snapshots into an
immutable plan, the runner executes the plan through the safety store and
`rsync`, and the verifier commits the baseline. Nothing below the planner
decides direction or deletion.

## Add a file policy rule

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

## Add an rsync capability

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

## Add a scenario

Every row in the spec scenario catalog is an acceptance test named by its
number. Add the row to the spec first, then the test in the module that owns
the behavior. A scenario that crosses modules belongs in
`DevSyncPairEngineTests`.

## Debugging

- Logs use `source: "DevSync"`. Paths are redacted to their last two
  components; sensitive matches show as `<sensitive>`.
- The state store keeps the newest five backups per pair under
  `DevSync/<pair-id>/backups/`. A corrupt document is moved aside with a
  `.corrupt-<timestamp>.json` suffix and reported in the pair status.
- Every operation is a JSON document under `DevSync/<pair-id>/operations/`.
  A non-terminal document at launch triggers recovery before any new work.
- The external safety store is `<external-root>/.cloudsync-system/<pair-id>/`.
  Retained versions keep their original relative path below
  `history/<operation-id>/`.
