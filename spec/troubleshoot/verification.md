# Verification Troubleshooting

## UI Change Verification

- **Symptom:** Source compiles but the final spacing, focus state, or interaction
  is still wrong.
- **Cause:** Verification stopped at the build or inspected an older binary.
- **Invariant:** Run the smallest static check, build the final source state,
  then exercise every changed state in the running final binary. Rebuild after
  any reconciliation or edit made following visual QA.
- **Check:** Record the exact final build result and inspect default, hover,
  selected, disabled, settings, and dismissal states that the change touches.

## UI Test Harness Failure

- **Symptom:** The UI runner exits before establishing a connection and no test
  assertion executes.
- **Cause:** The Xcode automation harness failed to bootstrap; this is not a
  product assertion result.
- **Invariant:** Distinguish harness failure from app failure. Retry the smallest
  signed runner once, then use live accessibility and visual interaction as the
  fallback while reporting the harness limitation.
- **Check:** Inspect the result bundle message. Never report an early runner exit
  as a passing or failing product test.

## Installation Gate

- **Symptom:** A verified build is not installed, or installation interrupts an
  active Cloud Sync transfer.
- **Cause:** The transfer gate or final install step was skipped.
- **Invariant:** Read the transfer state before UI smoke tests and installation.
  Never replace or relaunch the installed app during an active transfer. When
  clear, install and relaunch the final verified build before handoff.
- **Check:** Confirm no active transfer, install the final Release product, and
  confirm the installed process is running.
