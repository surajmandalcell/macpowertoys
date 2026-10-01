import SwiftUI

struct BlockedDiskEject: Identifiable {
    let disk: ManagedDisk
    let blockers: [DiskEjectBlocker]
    let reason: String
    var id: String { disk.id }
}

@Observable
@MainActor
final class DiskManagementModel {
    private(set) var disks: [ManagedDisk] = []
    private(set) var isBusy = false
    private(set) var message: String?
    private(set) var error: String?
    private(set) var progressText = "Reading physical disks..."
    var blockedEject: BlockedDiskEject?
    var selectedDiskID: String?
    var selectedPartitionID: String?
    var lockRevision = 0
    private var lockStates: [String: Bool] = [:]
    let isPreview: Bool

    init(disks: [ManagedDisk] = [], selectedPartitionID: String? = nil, isPreview: Bool = false) {
        self.disks = disks
        self.selectedDiskID = disks.first?.id
        self.selectedPartitionID = selectedPartitionID
        self.isPreview = isPreview
    }
    var selectedDisk: ManagedDisk? { disks.first { $0.id == selectedDiskID } }
    func select(_ disk: ManagedDisk) { selectedDiskID = disk.id; selectedPartitionID = nil }
    func isLocked(_ disk: ManagedDisk) -> Bool {
        _ = lockRevision
        return !isPreview && (lockStates[disk.identity] ?? true)
    }
    func setLocked(_ locked: Bool, for disk: ManagedDisk) {
        guard !isBusy, !isPreview,
              disks.contains(where: { $0.identity == disk.identity && (locked || $0.manageable) }) else { return }
        DiskWriteLock.setLocked(locked, for: disk)
        lockStates[disk.identity] = locked
        lockRevision += 1
    }
    func updateDisks(_ current: [ManagedDisk], lockStates: [String: Bool]? = nil) {
        disks = current
        if let lockStates { self.lockStates = lockStates }
        if let selected = current.first(where: { $0.id == selectedDiskID }) {
            if !selected.partitions.contains(where: { $0.id == selectedPartitionID }) { selectedPartitionID = nil }
        } else {
            selectedDiskID = current.first(where: \.manageable)?.id ?? current.first?.id
            selectedPartitionID = nil
        }
    }
    func fail(_ error: Error) { self.error = error.localizedDescription }
    func clearError() { error = nil }
    func refresh() async {
        guard !isBusy else { return }
        progressText = "Reading physical disks..."
        isBusy = true
        defer { isBusy = false }
        do {
            let (current, locks) = try await Task.detached(priority: .utility) { try Self.inventoryAndLocks() }.value
            guard !Task.isCancelled else { return }
            updateDisks(current, lockStates: locks); error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func run(_ request: DiskRequest) async {
        guard !isBusy, !isPreview else { return }
        progressText = "\(request.action.rawValue) on /dev/\(request.target)..."
        isBusy = true; error = nil; message = nil
        defer { isBusy = false }
        do {
            message = try await Task.detached(priority: .userInitiated) {
                try DiskManagement.run(request)
            }.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            self.error = error.localizedDescription
        }
        await refreshAfterOperation()
    }
    func eject(_ disk: ManagedDisk, closing blockers: [DiskEjectBlocker] = [], force: Bool = false) async {
        guard !isBusy, !isPreview else { return }
        let request = DiskRequest(disk: disk, partition: nil, action: .eject, name: "", format: "", scheme: "", size: "")
        progressText = "Ejecting /dev/\(disk.id)..."
        isBusy = true; error = nil; message = nil; blockedEject = nil
        defer { isBusy = false }
        do {
            message = try await Task.detached(priority: .userInitiated) {
                blockers.isEmpty ? try DiskManagement.run(request) :
                    try DiskManagement.quitBlockersAndEject(blockers, request: request, force: force)
            }.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            let reason = error.localizedDescription
            let active = await Task.detached(priority: .utility) { DiskManagement.ejectBlockers(on: disk) }.value
            if !active.isEmpty && disk.manageable && !isLocked(disk) { blockedEject = BlockedDiskEject(disk: disk, blockers: active, reason: reason) }
            else { self.error = reason }
        }
        await refreshAfterOperation()
    }

    private func refreshAfterOperation() async {
        progressText = "Refreshing devices..."
        do {
            let (current, locks) = try await Task.detached(priority: .utility) { try Self.inventoryAndLocks() }.value
            updateDisks(current, lockStates: locks)
        } catch {
            let detail = "Device refresh failed. Select Refresh to try again. \(error.localizedDescription)"
            self.error = self.error.map { "\($0)\n\(detail)" } ?? detail
        }
    }

    private nonisolated static func inventoryAndLocks() throws -> ([ManagedDisk], [String: Bool]) {
        let disks = try DiskManagement.inventory()
        let locks = Dictionary(uniqueKeysWithValues: disks.map { ($0.identity, DiskWriteLock.isLocked($0)) })
        return (disks, locks)
    }
}
