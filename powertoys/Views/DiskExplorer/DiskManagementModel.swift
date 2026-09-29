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
    var blockedEject: BlockedDiskEject?
    var selectedDiskID: String?
    var selectedPartitionID: String?
    var lockRevision = 0
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
        return !isPreview && DiskWriteLock.isLocked(disk)
    }
    func setLocked(_ locked: Bool, for disk: ManagedDisk) {
        guard !isBusy, !isPreview, disks.contains(where: { $0.identity == disk.identity }) else { return }
        DiskWriteLock.setLocked(locked, for: disk); lockRevision += 1
    }
    func updateDisks(_ current: [ManagedDisk]) {
        disks = current
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
        isBusy = true
        defer { isBusy = false }
        do {
            let current = try await Task.detached(priority: .utility) { try DiskManagement.inventory() }.value
            guard !Task.isCancelled else { return }
            updateDisks(current); error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func run(_ request: DiskRequest) async {
        guard !isBusy else { return }
        isBusy = true; error = nil; message = nil
        do {
            message = try await Task.detached(priority: .userInitiated) {
                try DiskManagement.run(request)
            }.value.trimmingCharacters(in: .whitespacesAndNewlines)
            updateDisks(try await Task.detached(priority: .utility) { try DiskManagement.inventory() }.value)
        } catch {
            self.error = error.localizedDescription
            if let current = try? await Task.detached(priority: .utility, operation: { try DiskManagement.inventory() }).value {
                updateDisks(current)
            }
        }
        isBusy = false
    }
    func eject(_ disk: ManagedDisk, closing blockers: [DiskEjectBlocker] = [], force: Bool = false) async {
        guard !isBusy, !isPreview else { return }
        let request = DiskRequest(disk: disk, partition: nil, action: .eject, name: "", format: "", scheme: "", size: "")
        isBusy = true; error = nil; message = nil; blockedEject = nil
        do {
            message = try await Task.detached(priority: .userInitiated) {
                blockers.isEmpty ? try DiskManagement.run(request) :
                    try DiskManagement.quitBlockersAndEject(blockers, request: request, force: force)
            }.value.trimmingCharacters(in: .whitespacesAndNewlines)
            updateDisks(try await Task.detached(priority: .utility) { try DiskManagement.inventory() }.value)
        } catch {
            let reason = error.localizedDescription
            let active = await Task.detached(priority: .utility) { DiskManagement.ejectBlockers(on: disk) }.value
            if !active.isEmpty && !isLocked(disk) { blockedEject = BlockedDiskEject(disk: disk, blockers: active, reason: reason) }
            else { self.error = reason }
        }
        isBusy = false
    }
}
