import AppKit
import Darwin
import Foundation
import IOKit

nonisolated enum PartitionFileSystem: String, CaseIterable, Identifiable, Sendable {
    case apfs = "APFS", hfs = "JHFS+", exfat = "ExFAT", fat32 = "FAT32"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .apfs: "APFS"
        case .hfs: "Mac OS Extended (Journaled)"
        case .exfat: "ExFAT"
        case .fat32: "MS-DOS (FAT32)"
        }
    }
    var maxNameLength: Int {
        switch self {
        case .fat32: 11
        case .exfat: 15
        case .apfs, .hfs: 63
        }
    }
}

nonisolated enum PartitionScheme: String, CaseIterable, Identifiable, Sendable {
    case gpt = "GPT", mbr = "MBR"
    var id: String { rawValue }
    var title: String { self == .gpt ? "GUID Partition Map (GPT)" : "Master Boot Record (MBR)" }
}

nonisolated enum DiskKind: String, Sendable {
    case `internal`, external, removable, image
    var title: String {
        switch self {
        case .internal: "Internal"
        case .external: "External"
        case .removable: "Removable"
        case .image: "Disk images"
        }
    }
}

nonisolated struct ManagedVolume: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let usedBytes: Int64
    let mountPoint: String?
}

nonisolated struct ManagedPartition: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let content: String
    let offset: Int64
    let size: Int64
    let mountPoint: String?
    let fileSystem: String?
    let fileSystemType: String?
    let usedBytes: Int64?
    let apfsContainer: String?
    let volumes: [ManagedVolume]

    init(id: String, name: String, content: String, offset: Int64, size: Int64, mountPoint: String? = nil,
         fileSystem: String? = nil, fileSystemType: String? = nil, usedBytes: Int64? = nil,
         apfsContainer: String? = nil, volumes: [ManagedVolume] = []) {
        self.id = id; self.name = name; self.content = content; self.offset = offset; self.size = size
        self.mountPoint = mountPoint; self.fileSystem = fileSystem; self.fileSystemType = fileSystemType
        self.usedBytes = usedBytes; self.apfsContainer = apfsContainer; self.volumes = volumes
    }

    var isEFI: Bool { content == "EFI" }
    var isAPFS: Bool { apfsContainer != nil }
    var hasFileSystem: Bool { isAPFS || fileSystemType != nil }
    var isMounted: Bool { mountPoint != nil || volumes.contains { $0.mountPoint != nil } }
    var displayName: String {
        if isEFI { return "EFI" }
        if isAPFS { return volumes.first?.name ?? "APFS container" }
        return name.isEmpty ? id : name
    }
    var displayFileSystem: String {
        if isAPFS { return "APFS" }
        if isEFI { return "EFI system" }
        return fileSystem ?? (content.isEmpty ? "Unknown" : content)
    }
}

nonisolated struct FreeSpace: Identifiable, Sendable, Equatable {
    let diskID: String
    let offset: Int64
    let size: Int64
    let afterPartition: String?
    var id: String { "free-\(diskID)-\(afterPartition ?? "start")" }
}

nonisolated struct ManagedDisk: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let size: Int64
    let bus: String
    let scheme: String
    let kind: DiskKind
    let writable: Bool
    let smart: String?
    let imagePath: String?
    let mediaRegistryID: UInt64?
    let partitions: [ManagedPartition]
    let protectionReason: String?

    static let minimumFreeSpace: Int64 = 32_000_000

    var schemeTitle: String {
        switch scheme {
        case "GUID_partition_scheme": "GPT"
        case "FDisk_partition_scheme": "MBR"
        case "Apple_partition_scheme": "APM"
        default: "No partition map"
        }
    }
    var mountPoints: [String] {
        partitions.flatMap { [$0.mountPoint].compactMap { $0 } + $0.volumes.compactMap(\.mountPoint) }
    }
    var identity: String {
        let layout = partitions.map { "\($0.id):\($0.content):\($0.offset):\($0.size):\($0.apfsContainer ?? "")" }
        return ([id, String(size), mediaRegistryID.map(String.init) ?? "missing"] + layout).joined(separator: "|")
    }
    var freeSpaces: [FreeSpace] {
        var result: [FreeSpace] = []
        var cursor: Int64 = 0
        var previous: String?
        for partition in partitions {
            if partition.offset - cursor >= Self.minimumFreeSpace {
                result.append(FreeSpace(diskID: id, offset: cursor, size: partition.offset - cursor, afterPartition: previous))
            }
            cursor = max(cursor, partition.offset + partition.size)
            previous = partition.id
        }
        if size - cursor >= Self.minimumFreeSpace {
            result.append(FreeSpace(diskID: id, offset: cursor, size: size - cursor, afterPartition: previous))
        }
        return result
    }
    func partition(containing id: String) -> ManagedPartition? {
        partitions.first { $0.id == id || $0.apfsContainer == id || $0.volumes.contains { $0.id == id } }
    }
}

/// Facts that decide whether Partition Manager may change a disk.
nonisolated struct DiskSafetyFacts: Sendable, Equatable {
    let diskID: String
    let isInternal: Bool
    let isWritable: Bool
    let protectedReason: String?
    let mountPoints: [String]
    let imagePath: String?
}

nonisolated enum DiskSafety {
    static let reservedDiskIDs: Set<String> = ["disk6", "disk7"]
    static let ownerDataVolume = "/Volumes/External1TB"

    /// The one guard for every write. `targets` lists each identifier the command touches.
    static func blockReason(_ facts: DiskSafetyFacts, targets: [String] = []) -> String? {
        let ids = ([facts.diskID] + targets).map(wholeDiskID)
        if ids.contains(where: reservedDiskIDs.contains) {
            return "disk6 and disk7 are reserved for the External1TB data drive. Partition Manager never changes them."
        }
        if facts.mountPoints.contains(where: { $0 == ownerDataVolume || $0.hasPrefix(ownerDataVolume + "/") }) {
            return "This disk holds External1TB. Partition Manager never changes it."
        }
        if let reason = facts.protectedReason { return reason }
        if facts.isInternal { return "Internal disks are protected. Partition Manager never changes them." }
        if DiskManagement.isSystemImage(facts.imagePath) {
            return "This disk image belongs to macOS."
        }
        if !facts.isWritable { return "This disk is read-only." }
        return nil
    }

    static func wholeDiskID(_ id: String) -> String {
        guard id.hasPrefix("disk") else { return id }
        return "disk" + id.dropFirst(4).prefix(while: \.isNumber)
    }
}

nonisolated enum DiskManagementError: LocalizedError {
    case invalidDevice
    case changedDevice
    case protected(String)
    case invalidInput(String)
    case command(String)

    var errorDescription: String? {
        switch self {
        case .invalidDevice: "The disk identifier is invalid. Refresh and try again."
        case .changedDevice: "The disk or its partitions changed. Refresh before trying again."
        case .protected(let reason): reason
        case .invalidInput(let message): message
        case .command(let message): message
        }
    }
}

nonisolated struct PartitionSplit: Sendable, Equatable {
    let fileSystem: PartitionFileSystem
    let name: String
}

nonisolated enum PartitionOperation: Sendable, Equatable {
    case mount(target: String)
    case unmount(target: String)
    case eject
    case rename(target: String, name: String)
    case format(target: String, fileSystem: PartitionFileSystem, name: String)
    case delete(target: String)
    case create(after: String?, fileSystem: PartitionFileSystem, name: String, size: Int64?)
    case resize(target: String, size: Int64, split: PartitionSplit?)
    case eraseDisk(fileSystem: PartitionFileSystem, name: String, scheme: PartitionScheme)
    case verify(target: String?)
    case repair(target: String?)

    var title: String {
        switch self {
        case .mount: "Mount"
        case .unmount: "Unmount"
        case .eject: "Eject disk"
        case .rename: "Rename"
        case .format: "Format"
        case .delete: "Delete partition"
        case .create: "Create partition"
        case .resize(_, _, let split): split == nil ? "Resize" : "Resize and split"
        case .eraseDisk: "Erase disk"
        case .verify: "Verify"
        case .repair: "Repair"
        }
    }
    /// Data loss is possible. These need a confirmation sheet.
    var isDestructive: Bool {
        switch self {
        case .format, .delete, .resize, .eraseDisk: true
        default: false
        }
    }
    /// Reads and mounts are harmless. Every other operation passes the safety guard.
    var isWrite: Bool {
        switch self {
        case .mount, .verify: false
        default: true
        }
    }
    var target: String? {
        switch self {
        case .mount(let target), .unmount(let target), .rename(let target, _), .format(let target, _, _),
             .delete(let target), .resize(let target, _, _): target
        case .create(let after, _, _, _): after
        case .verify(let target), .repair(let target): target
        case .eject, .eraseDisk: nil
        }
    }

    func arguments(on disk: ManagedDisk) throws -> [String] {
        guard DiskManagement.validID(disk.id), target.map(DiskManagement.validID) ?? true,
              target.map({ disk.partition(containing: $0) != nil }) ?? true else {
            throw DiskManagementError.invalidDevice
        }
        switch self {
        case .mount(let target):
            return [disk.partitions.contains { $0.apfsContainer == target } ? "mountDisk" : "mount", target]
        case .unmount(let target):
            return [disk.partitions.contains { $0.apfsContainer == target } ? "unmountDisk" : "unmount", target]
        case .eject:
            return ["eject", disk.id]
        case .rename(let target, let name):
            let partition = disk.partition(containing: target)
            let system: PartitionFileSystem = switch partition?.fileSystemType {
            case "msdos": .fat32
            case "exfat": .exfat
            default: .apfs
            }
            return ["renameVolume", target, try Self.validName(name, for: system)]
        case .format(let target, let system, let name):
            guard let partition = disk.partitions.first(where: { $0.id == target }), !partition.isEFI else {
                throw DiskManagementError.invalidInput("Select a data partition to format.")
            }
            let validName = try Self.validName(name, for: system)
            if let container = partition.apfsContainer {
                return ["apfs", "deleteContainer", container, system.rawValue, validName, "0"]
            }
            return ["eraseVolume", system.rawValue, validName, target]
        case .delete(let target):
            guard let partition = disk.partitions.first(where: { $0.id == target }), !partition.isEFI else {
                throw DiskManagementError.invalidInput("Select a data partition to delete.")
            }
            if let container = partition.apfsContainer { return ["apfs", "deleteContainer", container] }
            return ["eraseVolume", "free", "free", target]
        case .create(let after, let system, let name, let size):
            if system == .apfs && disk.scheme != "GUID_partition_scheme" {
                throw DiskManagementError.invalidInput("APFS needs a GUID partition map.")
            }
            if let size, size < ManagedDisk.minimumFreeSpace {
                throw DiskManagementError.invalidInput("A new partition needs at least 32 MB.")
            }
            let validName = try Self.validName(name, for: system)
            guard disk.partitions.isEmpty else {
                guard disk.scheme == "GUID_partition_scheme" else {
                    throw DiskManagementError.invalidInput("macOS can add a partition only to a GUID partition map.")
                }
                return ["addPartition", after ?? disk.id, system.rawValue, validName, size.map { "\($0)B" } ?? "0"]
            }
            let scheme = disk.scheme == "FDisk_partition_scheme" ? "MBR" : "GPT"
            let first = ["partitionDisk", disk.id, scheme, system.rawValue, validName]
            return first + (size.map { ["\($0)B", "free", "free", "R"] } ?? ["R"])
        case .resize(let target, let size, let split):
            guard let partition = disk.partitions.first(where: { $0.id == target }),
                  partition.isAPFS || partition.fileSystemType == "hfs" else {
                throw DiskManagementError.invalidInput("macOS can resize only APFS and Mac OS Extended partitions.")
            }
            guard disk.scheme == "GUID_partition_scheme" else {
                throw DiskManagementError.invalidInput("macOS can resize partitions only on a GUID partition map.")
            }
            guard size >= ManagedDisk.minimumFreeSpace else { throw DiskManagementError.invalidInput("The size is too small.") }
            var arguments = partition.isAPFS ? ["apfs", "resizeContainer", target, "\(size)B"] : ["resizeVolume", target, "\(size)B"]
            if let split {
                if split.fileSystem == .apfs && disk.scheme != "GUID_partition_scheme" {
                    throw DiskManagementError.invalidInput("APFS needs a GUID partition map.")
                }
                arguments += [split.fileSystem.rawValue, try Self.validName(split.name, for: split.fileSystem), "0"]
            }
            return arguments
        case .eraseDisk(let system, let name, let scheme):
            if system == .apfs && scheme != .gpt { throw DiskManagementError.invalidInput("APFS needs a GUID partition map.") }
            return ["eraseDisk", system.rawValue, try Self.validName(name, for: system), scheme.rawValue, disk.id]
        case .verify(let target):
            return target.map { ["verifyVolume", $0] } ?? ["verifyDisk", disk.id]
        case .repair(let target):
            // Whole-disk repair can stop at an interactive prompt, so only volumes are repaired.
            guard let target else { throw DiskManagementError.invalidInput("Repair a partition or volume, not the whole disk.") }
            return ["repairVolume", target]
        }
    }

    static func validName(_ name: String, for system: PartitionFileSystem) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = system == .fat32 ? trimmed.uppercased() : trimmed
        guard !value.isEmpty, value.count <= system.maxNameLength, !value.contains("/"), !value.contains(":") else {
            throw DiskManagementError.invalidInput("Use a name of 1 to \(system.maxNameLength) characters without a slash or colon.")
        }
        return value
    }
}

nonisolated struct DiskEjectBlocker: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let started: UInt64
    let userID: UInt32
    var id: Int32 { pid }
    var canQuit: Bool {
        userID == geteuid() && pid != getpid() &&
        !["Finder", "Dock", "launchd", "kernel_task", "MacPowerToys"].contains(name)
    }
}

nonisolated enum DiskManagement {
    private static let diskutil = "/usr/sbin/diskutil"

    // MARK: Inventory

    static func inventory() throws -> [ManagedDisk] {
        let list = try plist(["list", "-plist"])
        let apfs = (try? plist(["apfs", "list", "-plist"])) ?? [:]
        let protected = try? protectedDisks()
        let entries = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        let ids = entries.flatMap { entry in
            [entry["DeviceIdentifier"] as? String].compactMap { $0 } +
                (entry["Partitions"] as? [[String: Any]] ?? []).compactMap { $0["DeviceIdentifier"] as? String }
        }.filter(validID)
        let results = ConcurrentResults(count: ids.count)
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            results.set(index, try? plist(["info", "-plist", ids[index]]))
        }
        var infos: [String: [String: Any]] = [:]
        for (index, id) in ids.enumerated() { infos[id] = results.value(index) }
        var usage: [String: Int64] = [:]
        for (id, info) in infos where info["WholeDisk"] as? Bool == false {
            if let mount = nonEmpty(info["MountPoint"]) { usage[id] = usedBytes(at: mount) }
        }
        return parseDisks(list: list, apfs: apfs, infos: infos, imagePaths: imagePaths(), usage: usage, protected: protected)
    }

    /// Builds the disk list from diskutil plists. `protected` is nil when protected disks could not be resolved.
    static func parseDisks(list: [String: Any], apfs: [String: Any], infos: [String: [String: Any]],
                           imagePaths: [String: String], usage: [String: Int64],
                           protected: [String: String]?, registryID: (String) -> UInt64? = mediaRegistryID) -> [ManagedDisk] {
        var mounts: [String: String] = [:]
        for entry in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            for volume in (entry["APFSVolumes"] as? [[String: Any]] ?? []) + (entry["Partitions"] as? [[String: Any]] ?? []) {
                if let id = volume["DeviceIdentifier"] as? String, let mount = nonEmpty(volume["MountPoint"]) { mounts[id] = mount }
            }
        }
        func mountPoint(of id: String) -> String? {
            mounts[id] ?? mounts.first { $0.key.hasPrefix(id + "s") }?.value ?? nonEmpty(infos[id]?["MountPoint"])
        }
        var containers: [String: (reference: String, volumes: [ManagedVolume], used: Int64?)] = [:]
        for container in apfs["Containers"] as? [[String: Any]] ?? [] {
            guard let reference = container["ContainerReference"] as? String, validID(reference),
                  let stores = container["PhysicalStores"] as? [[String: Any]], stores.count == 1,
                  let store = stores[0]["DeviceIdentifier"] as? String else { continue }
            let volumes = (container["Volumes"] as? [[String: Any]] ?? []).compactMap { value -> ManagedVolume? in
                guard let id = value["DeviceIdentifier"] as? String, validID(id) else { return nil }
                return ManagedVolume(id: id, name: value["Name"] as? String ?? id, usedBytes: int(value["CapacityInUse"]) ?? 0,
                                     mountPoint: mountPoint(of: id))
            }
            let ceiling = int(container["CapacityCeiling"]), free = int(container["CapacityFree"])
            containers[store] = (reference, volumes, ceiling.flatMap { c in free.map { c - $0 } })
        }
        return (list["AllDisksAndPartitions"] as? [[String: Any]] ?? []).compactMap { entry -> ManagedDisk? in
            guard let id = entry["DeviceIdentifier"] as? String, validID(id),
                  let info = infos[id], isListedWholeDisk(info), !isSystemImage(imagePaths[id]) else { return nil }
            let bus = info["BusProtocol"] as? String ?? "Unknown"
            let removableMedia = info["RemovableMedia"] as? Bool == true
            let isInternal = (info["Internal"] as? Bool == true || info["OSInternalMedia"] as? Bool == true) &&
                !(removableMedia && bus == "Secure Digital")
            let kind: DiskKind = bus == "Disk Image" ? .image : isInternal ? .internal : removableMedia ? .removable : .external
            let partitions = (entry["Partitions"] as? [[String: Any]] ?? []).compactMap { part -> ManagedPartition? in
                guard let partID = part["DeviceIdentifier"] as? String, validID(partID) else { return nil }
                let details = infos[partID] ?? [:]
                let container = containers[partID]
                return ManagedPartition(
                    id: partID, name: part["VolumeName"] as? String ?? "",
                    content: part["Content"] as? String ?? "",
                    offset: int(details["PartitionMapPartitionOffset"]) ?? 0,
                    size: int(part["Size"]) ?? 0,
                    mountPoint: container == nil ? mountPoint(of: partID) : nil,
                    fileSystem: nonEmpty(details["FilesystemUserVisibleName"]),
                    fileSystemType: container == nil ? nonEmpty(details["FilesystemType"]) : "apfs",
                    usedBytes: container?.used ?? usage[partID],
                    apfsContainer: container?.reference, volumes: container?.volumes ?? [])
            }.sorted { $0.offset < $1.offset }
            let mounts = partitions.flatMap { [$0.mountPoint].compactMap { $0 } + $0.volumes.compactMap(\.mountPoint) }
            let facts = DiskSafetyFacts(diskID: id, isInternal: isInternal, isWritable: info["Writable"] as? Bool == true,
                                        protectedReason: protected == nil ?
                                            "Protected disks could not be verified. Refresh before making changes." : protected?[id],
                                        mountPoints: mounts, imagePath: imagePaths[id])
            let imageName = imagePaths[id].map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            return ManagedDisk(id: id, name: imageName ?? nonEmpty(info["MediaName"]) ?? nonEmpty(info["IORegistryEntryName"]) ?? id,
                               size: int(info["Size"]) ?? 0, bus: bus, scheme: info["Content"] as? String ?? "",
                               kind: kind, writable: facts.isWritable, smart: nonEmpty(info["SMARTStatus"]),
                               imagePath: imagePaths[id], mediaRegistryID: registryID(id), partitions: partitions,
                               protectionReason: DiskSafety.blockReason(facts, targets: partitions.compactMap(\.apfsContainer)))
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func safetyFacts(for disk: ManagedDisk, protected: [String: String]?) -> DiskSafetyFacts {
        DiskSafetyFacts(diskID: disk.id, isInternal: disk.kind == .internal, isWritable: disk.writable,
                        protectedReason: protected == nil ? "Protected disks could not be verified." : protected?[disk.id],
                        mountPoints: disk.mountPoints, imagePath: disk.imagePath)
    }

    /// macOS attaches simulator runtimes and cryptexes as images. They are not user disks.
    static func isSystemImage(_ path: String?) -> Bool {
        guard let path else { return false }
        return path.hasPrefix("/System/") || path.hasPrefix("/Library/")
    }

    private static func isListedWholeDisk(_ info: [String: Any]) -> Bool {
        guard info["WholeDisk"] as? Bool == true, info["APFSPhysicalStores"] == nil else { return false }
        return info["VirtualOrPhysical"] as? String != "Virtual" || info["BusProtocol"] as? String == "Disk Image"
    }

    static func details(_ id: String) throws -> [(String, String)] {
        guard validID(id) else { throw DiskManagementError.invalidDevice }
        let info = try plist(["info", "-plist", id])
        let keys = ["DeviceIdentifier", "MediaName", "VolumeName", "Content", "FilesystemUserVisibleName",
                    "BusProtocol", "Size", "PartitionMapPartitionOffset", "MountPoint", "VolumeUUID",
                    "DiskUUID", "APFSContainerReference", "SMARTStatus", "Writable", "Removable", "Internal",
                    "SolidState", "DeviceBlockSize"]
        return keys.compactMap { key in
            guard let value = info[key] else { return nil }
            let text = "\(value)"
            return text.isEmpty ? nil : (key, text)
        }
    }

    static func resizeMinimum(for partition: ManagedPartition) throws -> Int64 {
        guard validID(partition.id) else { throw DiskManagementError.invalidDevice }
        let limits = try plist(partition.isAPFS ? ["apfs", "resizeContainer", partition.id, "limits", "-plist"] :
                                    ["resizeVolume", partition.id, "limits", "-plist"])
        return int(limits["MinimumSizeNoGuard"]) ?? int(limits["MinimumSizePreferred"]) ?? partition.size
    }

    // MARK: Operations

    static func run(_ operation: PartitionOperation, on disk: ManagedDisk) throws -> String {
        let arguments = try operation.arguments(on: disk)
        if operation.isWrite {
            let protected = try protectedDisks()
            guard let current = try inventory().first(where: { $0.id == disk.id }), current.identity == disk.identity else {
                throw DiskManagementError.changedDevice
            }
            let targets = [operation.target].compactMap { $0 } + current.partitions.compactMap(\.apfsContainer)
            if let reason = DiskSafety.blockReason(safetyFacts(for: current, protected: protected), targets: targets) {
                throw DiskManagementError.protected(reason)
            }
        }
        if operation == .eject, disk.kind == .image {
            return String(decoding: try executeProgram("/usr/bin/hdiutil", ["detach", disk.id], failOnError: true), as: UTF8.self)
        }
        return String(decoding: try execute(arguments), as: UTF8.self)
    }

    static func ejectBlockers(on disk: ManagedDisk) -> [DiskEjectBlocker] {
        var found: [Int32: DiskEjectBlocker] = [:]
        for mount in Set(disk.mountPoints) where mount.hasPrefix("/Volumes/") {
            guard let output = try? executeProgram("/usr/sbin/lsof", ["-nP", "-Fpc", "+f", "--", mount]) else { continue }
            for (pid, name) in parseLsofProcesses(String(decoding: output, as: UTF8.self)) {
                guard let info = processInfo(pid) else { continue }
                found[pid] = DiskEjectBlocker(pid: pid, name: name, started: info.started, userID: info.userID)
            }
        }
        return found.values.sorted { $0.name == $1.name ? $0.pid < $1.pid : $0.name < $1.name }
    }

    static func quitBlockersAndEject(_ blockers: [DiskEjectBlocker], disk: ManagedDisk, force: Bool) throws -> String {
        guard blockers.allSatisfy(\.canQuit), !blockers.isEmpty else {
            throw DiskManagementError.invalidInput("These processes cannot be closed by Partition Manager.")
        }
        let protected = try protectedDisks()
        guard let current = try inventory().first(where: { $0.id == disk.id }), current.identity == disk.identity else {
            throw DiskManagementError.changedDevice
        }
        if let reason = DiskSafety.blockReason(safetyFacts(for: current, protected: protected)) {
            throw DiskManagementError.protected(reason)
        }
        let live = Dictionary(uniqueKeysWithValues: ejectBlockers(on: current).map { ($0.pid, $0) })
        for blocker in blockers {
            guard let now = live[blocker.pid], now.started == blocker.started,
                  now.userID == blocker.userID, now.canQuit else { continue }
            let closed: Bool
            if !force, let app = NSRunningApplication(processIdentifier: blocker.pid) {
                closed = app.terminate()
            } else {
                closed = kill(blocker.pid, force ? SIGKILL : SIGTERM) == 0
            }
            guard closed else { throw DiskManagementError.command("Could not close \(blocker.name) (PID \(blocker.pid)).") }
        }
        Thread.sleep(forTimeInterval: 1)
        return try run(.eject, on: current)
    }

    static func parseLsofProcesses(_ output: String) -> [(Int32, String)] {
        var pid: Int32?
        var result: [(Int32, String)] = []
        for line in output.split(whereSeparator: \.isNewline) {
            if line.first == "p" { pid = Int32(line.dropFirst()) }
            if line.first == "c", let pid { result.append((pid, String(line.dropFirst()))) }
        }
        return result
    }

    // MARK: Helpers

    private final class ConcurrentResults: @unchecked Sendable {
        private var values: [[String: Any]?]
        private let lock = NSLock()
        init(count: Int) { values = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ value: [String: Any]?) { lock.withLock { values[index] = value } }
        func value(_ index: Int) -> [String: Any]? { lock.withLock { values[index] } }
    }

    static func validID(_ id: String) -> Bool {
        id.range(of: "^disk[0-9]+(s[0-9]+)?$", options: .regularExpression) != nil
    }

    static func physicalDiskIDs(_ info: [String: Any]) -> [String] {
        let stores = info["APFSPhysicalStores"] as? [[String: Any]] ?? []
        let ids = stores.isEmpty ? [info["ParentWholeDisk"] as? String ?? info["DeviceIdentifier"] as? String ?? ""] :
            stores.compactMap { $0["APFSPhysicalStore"] as? String }
        let physical = ids.compactMap { id -> String? in
            guard id.range(of: "^disk[0-9]+(s[0-9]+)*$", options: .regularExpression) != nil else { return nil }
            return DiskSafety.wholeDiskID(id)
        }
        return physical.count == max(1, stores.count) ? physical : []
    }

    /// Whole disks behind the startup volume, the running app, and External1TB.
    static func protectedDisks() throws -> [String: String] {
        var paths = [(URL(fileURLWithPath: "/"), "The startup disk is protected. Partition Manager never changes it."),
                     (Bundle.main.bundleURL, "This disk holds the running app. Partition Manager never changes it.")]
        if FileManager.default.fileExists(atPath: DiskSafety.ownerDataVolume) {
            paths.append((URL(fileURLWithPath: DiskSafety.ownerDataVolume), "This disk holds External1TB. Partition Manager never changes it."))
        }
        var result: [String: String] = [:]
        for (path, reason) in paths {
            guard let volume = try path.resolvingSymlinksInPath().resourceValues(forKeys: [.volumeURLKey]).volume,
                  case let ids = physicalDiskIDs(try plist(["info", "-plist", volume.path])), !ids.isEmpty else {
                throw DiskManagementError.protected("Protected disks could not be verified. Refresh before making changes.")
            }
            for id in ids where result[id] == nil { result[id] = reason }
        }
        return result
    }

    private static func imagePaths() -> [String: String] {
        guard let data = try? executeProgram("/usr/bin/hdiutil", ["info", "-plist"]),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for image in value["images"] as? [[String: Any]] ?? [] {
            guard let path = image["image-path"] as? String else { continue }
            for entity in image["system-entities"] as? [[String: Any]] ?? [] {
                if let entry = entity["dev-entry"] as? String { result[String(entry.dropFirst("/dev/".count))] = path }
            }
        }
        return result
    }

    private static func usedBytes(at mount: String) -> Int64? {
        guard let values = try? URL(fileURLWithPath: mount).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        return Int64(max(0, total - available))
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
    private static func int(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }

    static func mediaRegistryID(for diskID: String) -> UInt64? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, diskID) else { return nil }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard media != 0 else { return nil }
        defer { IOObjectRelease(media) }
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(media, &id) == KERN_SUCCESS ? id : nil
    }

    private static func processInfo(_ pid: Int32) -> (started: UInt64, userID: UInt32)? {
        var info = proc_bsdinfo()
        let bytes = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        guard bytes == MemoryLayout<proc_bsdinfo>.size else { return nil }
        return (info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec, info.pbi_uid)
    }

    private static func plist(_ arguments: [String]) throws -> [String: Any] {
        let data = try execute(arguments, plistOutput: true)
        guard let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DiskManagementError.command("Could not read disk details from macOS.")
        }
        return value
    }

    private static func execute(_ arguments: [String], plistOutput: Bool = false) throws -> Data {
        try executeProgram(diskutil, arguments, mergeErrors: !plistOutput, failOnError: true)
    }

    private static func executeProgram(_ path: String, _ arguments: [String], mergeErrors: Bool = true,
                                       failOnError: Bool = false) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = mergeErrors ? pipe : FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !failOnError || process.terminationStatus == 0 else {
            let detail = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw DiskManagementError.command(detail.isEmpty ? "macOS could not complete the operation." : detail)
        }
        return output
    }
}
