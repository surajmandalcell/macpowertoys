# Shared Worktree Troubleshooting

## Concurrent Commits Invalidating Work

- **Symptom:** A verified fix disappears, an opposite behavior returns, or the
  build no longer represents the source about to be committed.
- **Cause:** Another checkpoint changed overlapping files after verification.
- **Invariant:** Re-run `git status`, recent `git log`, and the owned diff after
  every long build or live UI check and immediately before staging. Reconcile
  the newest direct user instruction against current source, then verify the
  final source state.
- **Check:** Compare the commit at verification time with `HEAD` at staging time.
  If it changed, inspect overlapping files and rebuild the reconciled result.

## Shared Files and Staging

- **Symptom:** A commit absorbs unrelated changelog, layout, or agent edits.
- **Cause:** Whole files were staged even though owned and unrelated hunks shared
  those files.
- **Invariant:** Preserve unrelated working changes and stage only owned paths or
  exact hunks. Inspect the complete index before commit. Never reset, amend, or
  discard another contributor's work.
- **Check:** `git diff --cached --name-status`, `git diff --cached`, and
  `git diff --cached --check` show only the current checkpoint.

## Stale Installed Build

- **Symptom:** A thread verifies current source but another thread installs an
  older DerivedData product and later work continues against stale UI.
- **Cause:** The installed bundle had no verifiable source provenance.
- **Invariant:** Final installation requires a clean worktree. Make builds embed
  their source commit, and `make install` refuses replacement when the tree is
  dirty or the embedded commit differs from current `HEAD`.
- **Check:** Confirm `git status --porcelain` is empty. Read `MPTSourceCommit`
  from the Release app and confirm it equals `git rev-parse HEAD`.

## Shared DerivedData Collision

- **Symptom:** The installed bundle reports current `HEAD` but renders UI from
  older source.
- **Cause:** Concurrent builds reused and overwrote the same DerivedData product.
- **Invariant:** Final installation uses one task-unique `DERIVED_DATA` path for
  the complete `make install ALLOW_INSTALL=1` invocation.
- **Check:** Confirm the installed source commit, then inspect the changed UI in
  the relaunched installed app. Commit provenance alone is not a visual check.
