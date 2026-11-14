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
