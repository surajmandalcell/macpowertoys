# Cloud Sync And Dev Sync Troubleshooting

## Dev Sync stops after a drive reconnect

- **Symptom:** Dev Sync stops seeing edits after the drive is ejected and
  reconnected.
- **Cause:** Unmount stopped the streams but did not clear them, so start
  thought they still existed.
- **Invariant:** Every stream stop goes through `stopEventStreams()`, which
  clears the streams and ends the event channel. Batches apply in order on one
  consumer. The cursor file is written at most once every 5 seconds and at
  every stop.
- **Check:** After a remount, the engine has new streams, and a file edit makes
  a dirty generation.

## FSEvents callback lifetime

- **Symptom:** A possible crash in a file-watch callback.
- **Cause:** An unretained context pointer and main-queue delivery.
- **Invariant:** Each stream retains its owner until stop, invalidate, release,
  in that order. Delivery runs on a private serial queue.
- **Check:** `DevSyncEventsTests` stream ownership test.

## Fixture transfers in the owner's store

- **Symptom:** RSync UI lists sample jobs (`~/Desktop/demo.mov`,
  `~/Pictures/2026`) three times with 0 bytes, and installs refuse.
- **Cause:** A render harness linked the app code and set
  `RcloneJobManager.shared.jobs`; `AppDataLocation` pointed it at the real
  `transfers.json`. Each harness run merged 5 more fixtures.
- **Invariant:** Any process whose bundle id is not the app's uses the
  isolated `MacPowerToys-Tests` folder. The install guard
  `scripts/live-transfers.sh` blocks only on a running job that moved bytes
  or a busy rclone daemon.
- **Check:** `zsh scripts/live-transfers.sh` on a store with a 0-byte running
  entry exits 0.
