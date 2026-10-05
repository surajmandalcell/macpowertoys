# Partition Manager Troubleshooting

Partition Manager (tool ID `disk-explorer`) is a partition tool only. It has
no folder scan, treemap, rings, or file removal. The core is
`powertoys/Core/DiskManagement.swift`; the window is in
`powertoys/Views/DiskExplorer/`.

## One safety guard for every write

- **Symptom:** A write could reach the startup disk, the disk with the app,
  an internal disk, or the External1TB drive.
- **Cause:** Earlier code checked protection in several places with
  different rules.
- **Invariant:** `DiskSafety.blockReason` is the only guard. It refuses
  `disk6` and `disk7` (also as any target, such as `disk7s1`), any disk that
  mounts `/Volumes/External1TB`, the whole disks behind `/`, the running app,
  and External1TB, internal disks, macOS-owned images, and read-only disks.
  A removable card in a built-in SD reader is not an internal disk.
  `DiskManagement.run` calls it for every operation except Mount and Verify,
  after it reads the disk again and confirms that the layout is unchanged.
  If protected disks cannot be resolved, every disk is protected.
- **Check:** `DiskManagementTests.testGuardProtectsStartupInternalReservedAndExternal1TBDisks`.
  The image matrix also confirms that the live `disk0` and `disk6` are refused.

## Partition identifiers change after an operation

- **Symptom:** After a format or delete, the selected partition is gone or a
  different partition is selected.
- **Cause:** diskutil renumbers partitions. An ExFAT format of `disk16s2` can
  produce `disk16s3` at the same offset.
- **Invariant:** The model keeps the start offset of the selection and selects
  the partition or free space at that offset after the refresh. Inventory sorts
  partitions by offset, not by identifier.
- **Check:** `DiskManagementTests.testSelectionFollowsAPartitionWhoseIdentifierChanged`.

## diskutil limits that the actions must respect

- **Symptom:** An operation fails with a diskutil error that the inspector
  could have predicted.
- **Cause:** macOS refuses these requests:
  - `eraseVolume` on an APFS physical store. Format and Delete use
    `apfs deleteContainer` with the container reference.
  - `addPartition` and `resizeVolume` on an MBR map. Create Partition and
    Resize require GPT, except Create on an empty map, which uses
    `partitionDisk` with the current scheme.
  - `addPartition` when the map has no partition, and before the first one.
  - `verifyDisk` on a GPT disk without an EFI partition (error -69771). Small
    images have no EFI partition.
  - `repairDisk` can stop at an interactive prompt. Only volumes are repaired.
  - ExFAT and FAT32 cannot be resized.
- **Invariant:** `PartitionAction.unavailableReason` disables each case with
  its reason, and `PartitionOperation.arguments` throws for it.
- **Check:** `DiskManagementTests.testActionsExplainWhyTheyAreUnavailable` and
  `testOperationsBuildExactDiskutilArguments`.

## Resize limits

- **Symptom:** The resize slider cannot shrink a partition.
- **Cause:** `MinimumSizePreferred` from `resizeContainer limits` and
  `resizeVolume limits` often equals the current size.
- **Invariant:** Use `MinimumSizeNoGuard` as the lower bound. The upper bound
  is the partition size plus the free space directly after it.

## Inventory includes the right disks quickly

- **Symptom:** The startup disk was missing, or APFS volumes showed no mount
  point, or inventory took more than six seconds.
- **Cause:** `disk0` reports `VirtualOrPhysical` as `Unknown`. APFS volume
  mount points are only in the `APFSVolumes` entries of `diskutil list`, and
  the startup volume mounts its snapshot (`disk3s1s1`). Serial
  `diskutil info` calls are slow.
- **Invariant:** List a whole disk unless it is virtual and not a disk image,
  and never list synthesized APFS container disks. Read mount points from
  `APFSVolumes` and accept a snapshot child. Run the `diskutil info` calls
  concurrently. Hide images whose file is under `/System/` or `/Library/`.
- **Check:** `DiskManagementTests.testParsingListsWholeDisksWithPartitionsVolumesAndFreeSpace`.

## Operation matrix

- `tmp/redesign/tools/partition-image-test.sh <empty folder>` runs every
  operation path through `DiskManagement.run` on a disposable 2 GB image,
  then detaches and deletes it.
- `tmp/redesign/tools/partition-sdcard-test.sh <empty folder>` runs the same
  matrix only on exactly one removable 14-17 GB SD or USB disk. It erases the
  card and ends with one ExFAT volume named PMDONE.

## Blocked eject

- **Invariant:** On a failed eject, list the processes with open files.
  Close and Force Quit check the disk, the guard, and each process identity
  again before a signal. Never force-eject. PID labels are verbatim.
