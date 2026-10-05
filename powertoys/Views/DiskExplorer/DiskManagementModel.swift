import SwiftUI

nonisolated enum PartitionSelection: Hashable, Sendable {
    case disk(String)
    case partition(disk: String, id: String)
    case volume(disk: String, partition: String, id: String)
    case free(disk: String, id: String)

    var diskID: String {
        switch self {
        case .disk(let disk), .partition(let disk, _), .volume(let disk, _, _), .free(let disk, _): disk
        }
    }
    /// The map block that carries the selection outline.
    var blockID: String {
        switch self {
        case .disk(let disk): disk
        case .partition(_, let id), .volume(_, let id, _), .free(_, let id): id
        }
    }
}

nonisolated enum PartitionAction: String, CaseIterable, Identifiable, Sendable {
    case mount = "Mount", unmount = "Unmount", rename = "Rename", format = "Format", firstAid = "First Aid", info = "Info"
    case create = "Create Partition", resize = "Resize", delete = "Delete Partition"
    case eject = "Eject Disk", eraseDisk = "Erase Disk"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .mount: "arrow.up.to.line"
        case .unmount: "arrow.down.to.line"
        case .rename: "pencil"
        case .format: "eraser"
        case .firstAid: "stethoscope"
        case .info: "info.circle"
        case .create: "plus.rectangle"
        case .resize: "arrow.left.and.right"
        case .delete: "minus.rectangle"
        case .eject: "eject"
        case .eraseDisk: "externaldrive.badge.xmark"
        }
    }
    var isDestructive: Bool { [.format, .delete, .resize, .eraseDisk].contains(self) }
    static let groups: [(String, [PartitionAction])] = [
        ("Volume", [.mount, .unmount, .rename, .format, .firstAid, .info]),
        ("Partition", [.create, .resize, .delete]),
        ("Disk", [.eject, .eraseDisk])
    ]

    /// Returns why the action is unavailable, or nil when it can run.
    static func unavailableReason(_ action: PartitionAction, selection: PartitionSelection?, disk: ManagedDisk?) -> String? {
        guard let selection, let disk else { return "Select a disk or partition." }
        let partition: ManagedPartition? = switch selection {
        case .partition(_, let id), .volume(_, let id, _): disk.partitions.first { $0.id == id }
        default: nil
        }
        let volume: ManagedVolume? = if case .volume(_, _, let id) = selection {
            partition?.volumes.first { $0.id == id }
        } else { nil }
        let mounted = volume.map { $0.mountPoint != nil } ?? partition?.isMounted ?? false
        let writeReason = disk.protectionReason
        switch action {
        case .info:
            return nil
        case .mount, .unmount:
            guard let partition else { return "Select a partition or volume." }
            if partition.isEFI { return "macOS manages the EFI system partition." }
            if !partition.hasFileSystem { return "This partition has no file system." }
            if action == .unmount, let writeReason { return writeReason }
            if action == .mount && mounted { return "Already mounted." }
            if action == .unmount && !mounted { return "Not mounted." }
            return nil
        case .firstAid:
            switch selection {
            case .free: return "Select a partition, volume, or the whole disk."
            case .disk:
                if disk.scheme == "GUID_partition_scheme" && !disk.partitions.contains(where: \.isEFI) {
                    return "macOS checks a GPT disk only when it has an EFI partition. Check each partition instead."
                }
                return nil
            default:
                guard let partition, !partition.isEFI else { return "macOS manages the EFI system partition." }
                return partition.hasFileSystem ? nil : "This partition has no file system."
            }
        default:
            break
        }
        if let writeReason { return writeReason }
        switch action {
        case .rename:
            guard let partition, !partition.isEFI, partition.hasFileSystem else { return "Select a volume or a partition with a file system." }
            if partition.isAPFS && volume == nil {
                return partition.volumes.count == 1 ? nil : "Select one volume of this APFS container."
            }
            return nil
        case .format:
            guard let partition, volume == nil else {
                return volume != nil ? "Select the container partition to format it." : "Select a partition."
            }
            return partition.isEFI ? "macOS manages the EFI system partition." : nil
        case .delete:
            guard let partition, volume == nil else { return "Select a partition." }
            return partition.isEFI ? "macOS manages the EFI system partition." : nil
        case .create:
            guard case .free(_, let id) = selection else { return "Select unallocated space." }
            if disk.freeSpaces.first(where: { $0.id == id })?.afterPartition == nil && !disk.partitions.isEmpty {
                return "macOS adds a partition only after an existing partition."
            }
            if !disk.partitions.isEmpty && disk.scheme != "GUID_partition_scheme" {
                return "macOS can add a partition only to a GUID partition map. Erase the disk with GPT first."
            }
            return nil
        case .resize:
            guard let partition, volume == nil else { return "Select an APFS or Mac OS Extended partition." }
            if disk.scheme != "GUID_partition_scheme" { return "macOS can resize partitions only on a GUID partition map." }
            if !(partition.isAPFS || partition.fileSystemType == "hfs") {
                return "macOS cannot resize \(partition.displayFileSystem) partitions. Back up, delete, and create it again."
            }
            return nil
        case .eject, .eraseDisk:
            return nil
        default:
            return nil
        }
    }
}

nonisolated enum PartitionPreview: Equatable, Sendable {
    case resize(partition: String, size: Int64, split: Bool)
    case create(free: String, size: Int64)
}

nonisolated struct PartitionMapSegment: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case partition(ManagedPartition), free(FreeSpace), pending(String) }
    let id: String
    let kind: Kind
    let bytes: Int64
}

nonisolated enum PartitionMapLayout {
    /// The ordered map blocks for one disk, with an optional resize or create preview applied.
    static func segments(for disk: ManagedDisk, preview: PartitionPreview? = nil) -> [PartitionMapSegment] {
        var items: [(offset: Int64, segment: PartitionMapSegment)] =
            disk.partitions.map { ($0.offset, PartitionMapSegment(id: $0.id, kind: .partition($0), bytes: $0.size)) } +
            disk.freeSpaces.map { ($0.offset, PartitionMapSegment(id: $0.id, kind: .free($0), bytes: $0.size)) }
        items.sort { $0.offset < $1.offset }
        var result = items.map(\.segment)
        switch preview {
        case .resize(let id, let size, let split)?:
            guard let index = result.firstIndex(where: { $0.id == id }), case .partition(let partition) = result[index].kind else { break }
            let next = result.indices.contains(index + 1) ? result[index + 1] : nil
            let room = partition.size + (next.flatMap { if case .free = $0.kind { $0.bytes } else { nil } } ?? 0)
            let newSize = min(max(size, ManagedDisk.minimumFreeSpace), room)
            result[index] = PartitionMapSegment(id: id, kind: .partition(partition), bytes: newSize)
            let remaining = room - newSize
            let freeID = next.flatMap { if case .free = $0.kind { $0.id } else { nil } } ?? "free-\(disk.id)-\(id)"
            if let next, case .free = next.kind { result.remove(at: index + 1) }
            if remaining > 0 {
                result.insert(PartitionMapSegment(id: split ? "pending" : freeID, kind: split ? .pending("New partition") :
                    .free(FreeSpace(diskID: disk.id, offset: partition.offset + newSize, size: remaining, afterPartition: id)),
                    bytes: remaining), at: index + 1)
            }
        case .create(let freeID, let size)?:
            guard let index = result.firstIndex(where: { $0.id == freeID }), case .free(let space) = result[index].kind else { break }
            let used = min(max(size, ManagedDisk.minimumFreeSpace), space.size)
            result[index] = PartitionMapSegment(id: "pending", kind: .pending("New partition"), bytes: used)
            if space.size - used > 0 {
                result.insert(PartitionMapSegment(id: freeID, kind: .free(FreeSpace(diskID: disk.id, offset: space.offset + used,
                    size: space.size - used, afterPartition: space.afterPartition)), bytes: space.size - used), at: index + 1)
            }
        case nil:
            break
        }
        return result
    }

    /// Proportional block widths. Each block gets at least `minimum`; the rest shares the remaining width by bytes.
    static func widths(_ bytes: [Int64], available: CGFloat, minimum: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard !bytes.isEmpty, available.isFinite, available > 0 else { return bytes.map { _ in 0 } }
        let usable = max(0, available - spacing * CGFloat(bytes.count - 1))
        let floor = min(minimum, usable / CGFloat(bytes.count))
        let total = bytes.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return bytes.map { _ in usable / CGFloat(bytes.count) } }
        var fixed = Set<Int>()
        while true {
            let free = usable - floor * CGFloat(fixed.count)
            let share = bytes.indices.filter { !fixed.contains($0) }.reduce(Int64(0)) { $0 + max(0, bytes[$1]) }
            let small = bytes.indices.filter { !fixed.contains($0) && share > 0 &&
                CGFloat(max(0, bytes[$0])) / CGFloat(share) * free < floor }
            if small.isEmpty {
                return bytes.indices.map { fixed.contains($0) ? floor : share > 0 ? CGFloat(max(0, bytes[$0])) / CGFloat(share) * free : floor }
            }
            fixed.formUnion(small)
        }
    }
}

struct BlockedDiskEject: Identifiable {
    let disk: ManagedDisk
    let blockers: [DiskEjectBlocker]
    let reason: String
    var id: String { disk.id }
}

struct PartitionActivity: Equatable {
    let diskID: String
    let blockID: String
    let title: String
}

@Observable
@MainActor
final class DiskManagementModel {
    private(set) var disks: [ManagedDisk] = []
    private(set) var activity: PartitionActivity?
    private(set) var isRefreshing = false
    private(set) var message: String?
    private(set) var error: String?
    var selection: PartitionSelection?
    var preview: PartitionPreview?
    var blockedEject: BlockedDiskEject?
    let isPreview: Bool

    init(disks: [ManagedDisk] = [], selection: PartitionSelection? = nil, isPreview: Bool = false) {
        self.disks = disks
        self.selection = selection ?? disks.first(where: { $0.protectionReason == nil }).map { .disk($0.id) } ?? disks.first.map { .disk($0.id) }
        self.isPreview = isPreview
    }

    var isBusy: Bool { activity != nil }
    var selectedDisk: ManagedDisk? { selection.flatMap { selection in disks.first { $0.id == selection.diskID } } }

    func unavailableReason(_ action: PartitionAction) -> String? {
        if isBusy { return "Wait for the current operation to finish." }
        if isPreview && action != .info { return "Preview data. Disk operations are off." }
        return PartitionAction.unavailableReason(action, selection: selection, disk: selectedDisk)
    }

    func clearMessages() { error = nil; message = nil }

    func refresh() async {
        guard !isRefreshing, !isPreview else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let current = try await Task.detached(priority: .utility) { try DiskManagement.inventory() }.value
            update(current)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func perform(_ operation: PartitionOperation, on disk: ManagedDisk) async {
        guard !isBusy, !isPreview else { return }
        let block = operation.target.flatMap { disk.partition(containing: $0)?.id } ?? disk.id
        activity = PartitionActivity(diskID: disk.id, blockID: block, title: "\(operation.title)...")
        clearMessages()
        preview = nil
        do {
            let output = try await Task.detached(priority: .userInitiated) { try DiskManagement.run(operation, on: disk) }.value
            message = "\(operation.title) finished on /dev/\(operation.target ?? disk.id)."
            if case .verify = operation { message = output.split(separator: "\n").last.map(String.init) ?? message }
            if case .repair = operation { message = output.split(separator: "\n").last.map(String.init) ?? message }
        } catch {
            if operation == .eject {
                let active = await Task.detached(priority: .utility) { DiskManagement.ejectBlockers(on: disk) }.value
                if !active.isEmpty { blockedEject = BlockedDiskEject(disk: disk, blockers: active, reason: error.localizedDescription) }
                else { self.error = error.localizedDescription }
            } else {
                self.error = error.localizedDescription
            }
        }
        activity = PartitionActivity(diskID: disk.id, blockID: block, title: "Reading disks...")
        let offset = selectedOffset
        do {
            let current = try await Task.detached(priority: .utility) { try DiskManagement.inventory() }.value
            update(current, keepingOffset: offset)
        } catch {
            let detail = "Disk refresh failed. Select Refresh to try again. \(error.localizedDescription)"
            self.error = self.error.map { "\($0)\n\(detail)" } ?? detail
        }
        activity = nil
    }

    func closeBlockersAndEject(_ blocked: BlockedDiskEject, force: Bool) async {
        guard !isBusy, !isPreview else { return }
        blockedEject = nil
        activity = PartitionActivity(diskID: blocked.disk.id, blockID: blocked.disk.id, title: "Ejecting...")
        clearMessages()
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try DiskManagement.quitBlockersAndEject(blocked.blockers, disk: blocked.disk, force: force)
            }.value
            message = "Ejected /dev/\(blocked.disk.id)."
        } catch { self.error = error.localizedDescription }
        if let current = try? await Task.detached(priority: .utility, operation: { try DiskManagement.inventory() }).value {
            update(current)
        }
        activity = nil
    }

    /// Partition identifiers can change after an operation, so a partition selection follows its start offset.
    private var selectedOffset: Int64? {
        guard let selection, let disk = selectedDisk else { return nil }
        switch selection {
        case .partition(_, let id), .volume(_, let id, _): return disk.partitions.first { $0.id == id }?.offset
        case .free(_, let id): return disk.freeSpaces.first { $0.id == id }?.offset
        case .disk: return nil
        }
    }

    func update(_ current: [ManagedDisk], keepingOffset offset: Int64? = nil) {
        disks = current
        guard let selection else {
            self.selection = current.first.map { .disk($0.id) }
            return
        }
        guard let disk = current.first(where: { $0.id == selection.diskID }) else {
            self.selection = current.first(where: { $0.protectionReason == nil }).map { .disk($0.id) } ?? current.first.map { .disk($0.id) }
            return
        }
        switch selection {
        case .disk:
            break
        case .partition(_, let id), .volume(_, let id, _):
            if let partition = disk.partitions.first(where: { $0.id == id }) {
                if case .volume(_, _, let volume) = selection, !partition.volumes.contains(where: { $0.id == volume }) {
                    self.selection = .partition(disk: disk.id, id: id)
                }
            } else if let offset, let moved = disk.partitions.first(where: { $0.offset == offset }) {
                self.selection = .partition(disk: disk.id, id: moved.id)
            } else if let offset, let free = disk.freeSpaces.first(where: { $0.offset == offset }) {
                self.selection = .free(disk: disk.id, id: free.id)
            } else {
                self.selection = .disk(disk.id)
            }
        case .free(_, let id):
            if !disk.freeSpaces.contains(where: { $0.id == id }) {
                if let offset, let created = disk.partitions.first(where: { $0.offset == offset }) {
                    self.selection = .partition(disk: disk.id, id: created.id)
                } else {
                    self.selection = .disk(disk.id)
                }
            }
        }
    }
}
