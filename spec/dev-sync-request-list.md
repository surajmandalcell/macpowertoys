# Dev Sync Request List

Reviewed against `spec/cloud-sync-dev-sync-spec.md` on 2026-09-05. Update a
status only after checking current source and, for visible behavior, the
latest normal signed build. Scenario numbers refer to the scenario catalog in
the spec.

| Status | Request | Evidence | Remaining work |
|---|---|---|---|
| Open | Add Dev One-Way and Dev Bidirectional as explicit Cloud Sync destinations. | None yet. | Sidebar row, page, and setup sheet. |
| Open | Keep existing Copy, Sync, and Move transfers unchanged. | None yet. | Separate state store; no migration; regression on the 543-test suite. |
| Open | Show a mandatory first-run preview before any mutation. | None yet. | Preview step with counts, bytes, conflicts, warnings, and a literal primary action. |
| Open | Use Git as the source of truth for ignore rules. | None yet. | `git ls-files -z` manifests and `git check-ignore --stdin -z` with `GIT_OPTIONAL_LOCKS=0`. |
| Open | Include ignored sensitive files by default. | None yet. | Sensitive override with size guard and unencrypted-drive warning (scenarios 25, 61). |
| Open | Copy Git administration data with active-lock safety. | None yet. | Lock detection and deferred `.git` batch (scenario 26). |
| Open | Debounce FSEvents and collapse event storms. | None yet. | Sliding debounce, checkpoint, and storm thresholds (scenarios 22, 23, 24, 83). |
| Open | Never start one `rsync` per path. | None yet. | Manifest batches; one mutation per external volume (scenario 86). |
| Open | Give external-only projects managed internal links. | None yet. | Link creation, validation, repair, adoption, and removal (scenarios 2, 6, 55, 66, 67, 68). |
| Open | Never follow managed links during scanning or transfer. | None yet. | `lstat` discovery and manifest rejection of link traversal. |
| Open | Survive mount-path changes through volume identity. | None yet. | UUID identity and link text repair (scenario 55). |
| Open | Block transfer on a wrong volume. | None yet. | Identity mismatch state (scenario 54). |
| Open | Use a stored baseline for bidirectional decisions. | None yet. | Per-project baseline documents and the bidirectional decision table. |
| Open | Turn simultaneous changes into conflicts. | None yet. | Conflict store, conflict cards, and six resolutions (scenario 27). |
| Open | Require a complete healthy scan before any deletion. | None yet. | Incomplete-scan and offline-root deletion guards (scenarios 53, 62). |
| Open | Never propagate whole-project deletion automatically. | None yet. | Residency conversion and project-level decision (scenarios 7, 8). |
| Open | Retain every destructive change. | None yet. | `--backup-dir` overwrites, same-volume delete moves, retention cleanup (scenarios 31, 49, 65). |
| Open | Never advance an unverified baseline after interruption. | None yet. | Operation journal and crash recovery (scenarios 53, 79, 80). |
| Open | Block affected projects on case and Unicode collisions. | None yet. | Collision detector (scenarios 35, 36). |
| Open | Let file-system capabilities control metadata flags. | None yet. | Volume probe, `rsync` probe, and fidelity levels (scenarios 42, 43, 59, 60, 75, 76). |
| Open | Never build a shell command string. | None yet. | `Process` with argument arrays; source audit for `/bin/sh`. |
| Open | Pass unusual names through NUL manifests. | None yet. | `--files-from=- -0` and the path matrix (scenarios 37, 38). |
| Open | Probe `rsync` capabilities instead of assuming them. | None yet. | Capability record and self-test. |
| Open | Pass the failure and acceptance matrices. | None yet. | Tests named by scenario number. |
| Open | Distinguish mirrored and external-resident projects in the UI. | None yet. | Residency badges and Open Real Location. |
| Open | Explain how to add a file policy or an `rsync` capability without changing reconciliation. | None yet. | `docs/DEV_SYNC.md`. |
