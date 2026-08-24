# Backlog Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create one accurate goals index, clean product text, and close independent backlog items without changing the active design task.

**Architecture:** Keep each detailed request list as its source of truth. Add a small root index that links to those lists and shows only current unresolved work. Use existing tests and command surfaces for verification.

**Tech Stack:** Markdown, Swift, SwiftUI, XCTest, Raycast CLI, Xcode.

## Global Constraints

- Do not change design option 03 or cross-app layout alignment.
- Do not rename AI History in this task.
- Treat `vorssaint-utils` as a read-only reference.
- Use ASD-STE100 for new and changed text.
- Preserve work from other tasks in the shared worktree.

---

### Task 1: Canonical goals index

**Files:**
- Create: `goals.md`
- Create: `spec/system-tools-request-list.md`
- Modify: `AGENTS.md`
- Modify: `spec/main-request-list.md`
- Modify: `spec/cloud-sync-request-list.md`

- [x] Add a root index that links to each detailed request list.
- [x] Add a request list for Input Devices, System Care, and System Monitor.
- [x] Correct statuses that describe a future condition as current unfinished work.
- [x] Record only verified source and test evidence.
- [x] Run the status-count audit and `git diff --check`.
- [x] Commit the documentation checkpoint.

### Task 2: ASD-STE100 product text

**Files:**
- Modify only product-copy files outside the excluded design task.

- [x] Scan user-facing Swift strings for contractions, em dashes, British spelling, and sentence-length limits.
- [x] Fix confirmed violations without changing product behavior.
- [x] Repeat the scan and run `git diff --check`.
- [x] Commit the copy checkpoint.

### Task 3: Raycast discovery

**Files:**
- Modify: `spec/ruler-request-list.md` only after successful verification.

- [x] Run the Raycast extension build.
- [x] Register the existing extension with Raycast.
- [x] Confirm that Raycast finds Ruler.
- [x] Update the request status only after the live check.
- [x] Commit the verification checkpoint.

### Task 4: Conditional Cloud Sync backlog

**Files:**
- Modify: `powertoys/Models/RcloneModels.swift`
- Modify: `powertoysTests/RcloneModelTests.swift`
- Modify: `spec/cloud-sync-request-list.md`
- Modify: `spec/main-request-list.md`

- [x] Verify which providers expose stable folder links through the current rclone API.
- [x] Close or retain the provider-link item from that evidence.
- [x] Mark two-way auditing as conditional because Cloud Sync has no two-way mode.
- [x] Run focused Cloud Sync tests when source changes are necessary.
- [x] Commit the backlog checkpoint.

### Task 5: Individual file priority

**Files:**
- Modify: `powertoys/Models/RcloneModels.swift`
- Modify: `powertoys/Services/RcloneJobManager.swift`
- Modify: `powertoys/Views/Rclone/RcloneJobRowView.swift`
- Modify: `powertoysTests/CloudSyncStateTests.swift`
- Modify: `powertoysTests/RcloneModelTests.swift`
- Modify: `spec/main-request-list.md`

- [x] Confirm the supported rclone ordering boundary.
- [x] Limit queue priority to exact file jobs.
- [x] Keep directory jobs at normal priority.
- [x] Add a compact native priority menu to file job rows.
- [x] Keep a running file in its current job when priority changes.
- [x] Run focused queue and model tests.
- [x] Commit the priority checkpoint.

### Task 6: Final build and installed verification

**Files:**
- Modify request-list status files only for checks that pass.

- [x] Confirm that Cloud Sync has no active transfer.
- [x] Run the affected tests, then the full unit target.
- [x] Build the clean committed source in a task-specific DerivedData folder.
- [x] Install the signed build only when its source commit equals `HEAD`.
- [x] Complete safe live checks that do not require private user data.
- [x] Update verified statuses and commit the final record.
