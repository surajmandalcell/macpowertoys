import Foundation
import IOKit

nonisolated struct ManagedPartition: Identifiable, Sendable {
    let id: String
    let name: String
    let content: String
    let size: Int64
    let mountPoint: String?
    let uuid: String?
    let fileSystem: String?
    let apfsContainer: String?
    let isAPFSVolume: Bool

    init(id: String, name: String, content: String, size: Int64,
         mountPoint: String?, uuid: String?, fileSystem: String? = nil, apfsContainer: String? = nil,
         isAPFSVolume: Bool = false) {
        self.id = id
        self.name = name
        self.content = content
        self.size = size
        self.mountPoint = mountPoint
        self.uuid = uuid
        self.fileSystem = fileSystem
        self.apfsContainer = apfsContainer
        self.isAPFSVolume = isAPFSVolume
    }

    var displayType: String {
        if isAPFSVolume { return "APFS volume" }
        if apfsContainer != nil { return "APFS container" }
        return fileSystem ?? content
    }
}

nonisolated struct ManagedDisk: Identifiable, Sendable {
    let id: String
    let name: String
    let size: Int64
    let bus: String
    let scheme: String
    let devicePath: String
    let writable: Bool
    let manageable: Bool
    let mediaRegistryID: UInt64?
    let partitions: [ManagedPartition]

    var unallocatedBytes: Int64 {
        max(0, size - partitions.filter { !$0.isAPFSVolume }.reduce(0) { $0 + $1.size })
    }

    func nextPhysicalPartition(after id: String) -> ManagedPartition? {
        let physical = partitions.filter { !$0.isAPFSVolume }
        guard let index = physical.firstIndex(where: { $0.id == id }),
              physical.indices.contains(index + 1) else { return nil }
        return physical[index + 1]
    }

    var identity: String {
        let layout = partitions.map {
            "\($0.id):\($0.content):\($0.isAPFSVolume ? 0 : $0.size):\($0.uuid ?? ""):\($0.name):\($0.apfsContainer ?? ""):\($0.isAPFSVolume)"
        }.joined(separator: ";")
        return "\(id)|\(size)|\(bus)|\(scheme)|\(devicePath)|\(name)|\(mediaRegistryID.map { String($0) } ?? "missing")|\(layout)"
    }
}

nonisolated enum DiskManagementError: LocalizedError {
    case invalidDevice
    case changedDevice
    case unsafeDevice
    case invalidInput(String)
    case command(String)

    var errorDescription: String? {
        switch self {
        case .invalidDevice: "The disk identifier is invalid. Refresh and try again."
        case .changedDevice: "The disk or its partitions changed. Refresh before trying again."
        case .unsafeDevice: "Diskman only modifies physical, writable removable or external disks."
        case .invalidInput(let message): message
        case .command(let message): message
        }
    }
}

nonisolated enum DiskAction: String, CaseIterable, Identifiable, Sendable {
    case verify = "Verify"
    case repair = "Repair"
    case mount = "Mount"
    case unmount = "Unmount"
    case eject = "Eject"
    case rename = "Rename volume"
    case eraseVolume = "Erase volume"
    case eraseDisk = "Erase disk"
    case partitionDisk = "Partition disk"
    case addPartition = "Add partition"
    case deletePartition = "Delete partition"
    case resizePartition = "Resize partition"
    case mergePartitions = "Merge with next"
    case addAPFSVolume = "Add APFS volume"
    case deleteAPFSVolume = "Delete APFS volume"
    case resizeAPFSContainer = "Resize APFS container"
    case wipeDisk = "Zero-fill disk"

    var id: String { rawValue }
    var destroysData: Bool {
        switch self {
        case .eraseVolume, .eraseDisk, .partitionDisk, .addPartition, .deletePartition,
             .resizePartition, .mergePartitions, .deleteAPFSVolume, .resizeAPFSContainer, .wipeDisk: true
        default: false
        }
    }
    var needsPartition: Bool {
        switch self {
        case .repair, .mount, .unmount, .rename, .eraseVolume, .deletePartition,
             .resizePartition, .mergePartitions, .addAPFSVolume, .deleteAPFSVolume, .resizeAPFSContainer: true
        default: false
        }
    }
    var needsWholeDisk: Bool {
        switch self {
        case .eject, .eraseDisk, .partitionDisk, .addPartition, .wipeDisk: true
        default: false
        }
    }
}

nonisolated struct DiskRequest: Sendable {
    let disk: ManagedDisk
    let partition: ManagedPartition?
    let action: DiskAction
    let name: String
    let format: String
    let scheme: String
    let size: String

    var target: String { partition?.id ?? disk.id }
    var summary: String {
        "\(action.rawValue) · \(partition?.name ?? disk.name) · /dev/\(target) · " +
        ByteCountFormatter.string(fromByteCount: partition?.size ?? disk.size, countStyle: .file)
    }

    func arguments() throws -> [String] {
        if action.needsPartition && partition == nil || action.needsWholeDisk && partition != nil {
            throw DiskManagementError.invalidInput("Select the \(action.needsPartition ? "partition" : "whole disk") for this operation.")
        }
        let validFormats = ["APFS", "APFSX", "JHFS+", "JHFSX", "HFS+", "HFSX",
                            "ExFAT", "MS-DOS", "MS-DOS FAT12", "MS-DOS FAT16", "FAT32"]
        let validSchemes = ["GPT", "MBR", "APM"]
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsName: Bool = [.rename, .eraseVolume, .eraseDisk, .partitionDisk, .addPartition,
                               .mergePartitions, .addAPFSVolume].contains(action)
        let fat = [.eraseVolume, .eraseDisk, .partitionDisk, .addPartition].contains(action) &&
            ["ExFAT", "MS-DOS", "MS-DOS FAT12", "MS-DOS FAT16", "FAT32"].contains(format) ||
            action == .rename && partition?.content == "Microsoft Basic Data" ||
            action == .mergePartitions && partition?.fileSystem == "ExFAT"
        let maxNameLength = fat ? (action == .partitionDisk ? 9 : 11) : 27
        if needsName && (safeName.isEmpty || safeName.count > maxNameLength ||
                         safeName.contains("/") || safeName.contains(":")) {
            throw DiskManagementError.invalidInput("Use a volume name of 1–\(maxNameLength) characters without a slash or colon.")
        }
        if [.eraseVolume, .eraseDisk, .partitionDisk, .addPartition].contains(action) && !validFormats.contains(format) {
            throw DiskManagementError.invalidInput("Choose a supported file system format.")
        }
        if action == .addAPFSVolume && !["APFS", "APFSX"].contains(format) {
            throw DiskManagementError.invalidInput("Choose APFS or case-sensitive APFS.")
        }
        if [.eraseDisk, .partitionDisk].contains(action) && !validSchemes.contains(scheme) {
            throw DiskManagementError.invalidInput("Choose a supported partition scheme.")
        }
        if [.eraseDisk, .partitionDisk].contains(action) && ["APFS", "APFSX"].contains(format) && scheme != "GPT" {
            throw DiskManagementError.invalidInput("APFS needs a GUID partition map.")
        }
        if action == .addPartition && ["APFS", "APFSX"].contains(format) &&
            disk.scheme != "GUID_partition_scheme" {
            throw DiskManagementError.invalidInput("APFS needs a GUID partition map.")
        }
        if [.partitionDisk, .addPartition, .resizePartition, .resizeAPFSContainer].contains(action) &&
            size.range(of: "^[1-9][0-9]*(M|G|T)$", options: .regularExpression) == nil &&
            !([.resizePartition, .resizeAPFSContainer].contains(action) && size == "R") {
            throw DiskManagementError.invalidInput("Enter a size such as 4G or 800M. Use R to fill available space when resizing.")
        }
        if size != "R", [.partitionDisk, .addPartition, .resizePartition, .resizeAPFSContainer].contains(action) {
            let multiplier: Int64 = switch size.last {
            case "M": 1_000_000
            case "G": 1_000_000_000
            default: 1_000_000_000_000
            }
            guard let number = Int64(size.dropLast()) else {
                throw DiskManagementError.invalidInput("The size is too large.")
            }
            let (bytes, overflow) = number.multipliedReportingOverflow(by: multiplier)
            guard !overflow, bytes <= disk.size else {
                throw DiskManagementError.invalidInput("The requested size exceeds this disk.")
            }
            if action == .partitionDisk && bytes > disk.size - 512_000_000 {
                throw DiskManagementError.invalidInput("Leave at least 512 MB for the second partition.")
            }
            if action == .addPartition && bytes > max(0, disk.unallocatedBytes - 20_000_000) {
                throw DiskManagementError.invalidInput("The new partition needs more unallocated space.")
            }
        }
        if [.eraseVolume, .deletePartition, .resizePartition].contains(action) && partition?.isAPFSVolume == true {
            throw DiskManagementError.invalidInput("Select the physical partition for this action.")
        }
        if [.addAPFSVolume, .resizeAPFSContainer].contains(action) &&
            (partition?.apfsContainer == nil || partition?.isAPFSVolume == true) {
            throw DiskManagementError.invalidInput("Select an APFS container partition.")
        }
        if action == .deleteAPFSVolume && partition?.isAPFSVolume != true {
            throw DiskManagementError.invalidInput("Select an APFS volume.")
        }
        if action == .resizePartition && partition?.content != "Apple_HFS" {
            throw DiskManagementError.invalidInput("macOS can resize only a Journaled HFS+ partition here.")
        }
        if action == .mergePartitions {
            guard let first = partition, let next = disk.nextPhysicalPartition(after: first.id),
                  first.content != "EFI", next.content != "EFI",
                  first.apfsContainer == nil, next.apfsContainer == nil else {
                throw DiskManagementError.invalidInput("Select a data partition followed by another data partition on this disk.")
            }
            if first.content == "Apple_HFS" {
                return ["mergePartitions", "JHFS+", safeName, first.id, next.id]
            }
            guard first.fileSystem == "ExFAT" else {
                throw DiskManagementError.invalidInput("Only Journaled HFS+ can preserve its data during a merge. ExFAT requires erasing both partitions.")
            }
            return ["mergePartitions", "force", "ExFAT", safeName, first.id, next.id]
        }
        switch action {
        case .verify: return [partition == nil ? "verifyDisk" : "verifyVolume", target]
        case .repair: return ["repairVolume", target]
        case .mount: return ["mount", target]
        case .unmount: return ["unmount", target]
        case .eject: return ["eject", target]
        case .rename: return ["renameVolume", target, safeName]
        case .eraseVolume: return ["eraseVolume", format, safeName, target]
        case .eraseDisk: return ["eraseDisk", format, safeName, scheme, target]
        case .partitionDisk: return ["partitionDisk", target, scheme, format, safeName, size,
                                     format, "\(safeName) 2", "R"]
        case .addPartition: return ["addPartition", target, format, safeName, size]
        case .deletePartition: return ["eraseVolume", "free", "free", target]
        case .resizePartition: return ["resizeVolume", target, size]
        case .mergePartitions: throw DiskManagementError.invalidInput("Choose two adjacent partitions.")
        case .addAPFSVolume:
            guard let container = partition?.apfsContainer else { throw DiskManagementError.changedDevice }
            return ["apfs", "addVolume", container, format, safeName]
        case .deleteAPFSVolume: return ["apfs", "deleteVolume", target]
        case .resizeAPFSContainer: return ["apfs", "resizeContainer", target, size == "R" ? "0" : size]
        case .wipeDisk: return ["zeroDisk", target]
        }
    }
}

nonisolated enum DiskManagement {
    private static let executable = URL(fileURLWithPath: "/usr/sbin/diskutil")

    static func inventory() throws -> [ManagedDisk] {
        let list = try plist(["list", "-plist"])
        let entries = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        let containers = (try? plist(["apfs", "list", "-plist"]))?["Containers"] as? [[String: Any]] ?? []
        var apfsByStore: [String: (reference: String, volumes: [ManagedPartition])] = [:]
        for container in containers {
            guard let reference = container["ContainerReference"] as? String, validID(reference) else { continue }
            let volumes = (container["Volumes"] as? [[String: Any]] ?? []).compactMap { value -> ManagedPartition? in
                guard let id = value["DeviceIdentifier"] as? String, validID(id) else { return nil }
                return ManagedPartition(id: id, name: value["Name"] as? String ?? id,
                                        content: "APFS Volume",
                                        size: (value["CapacityInUse"] as? NSNumber)?.int64Value ?? 0,
                                        mountPoint: nil, uuid: value["APFSVolumeUUID"] as? String,
                                        apfsContainer: reference, isAPFSVolume: true)
            }
            if let storeID = singleAPFSStoreID(container["PhysicalStores"] as? [[String: Any]] ?? []) {
                apfsByStore[storeID] = (reference, volumes)
            }
        }
        return entries.compactMap { entry -> ManagedDisk? in
            guard let id = entry["DeviceIdentifier"] as? String, validID(id),
                  let info = try? plist(["info", "-plist", id]),
                  info["WholeDisk"] as? Bool == true,
                  info["VirtualOrPhysical"] as? String == "Physical" else { return nil }
            let size = (info["Size"] as? NSNumber)?.int64Value ?? 0
            let bus = info["BusProtocol"] as? String ?? "Unknown"
            let scheme = info["Content"] as? String ?? "Unknown"
            let path = info["DeviceTreePath"] as? String ?? ""
            let name = info["MediaName"] as? String ?? id
            let writable = info["Writable"] as? Bool == true
            let removable = info["RemovableMediaOrExternalDevice"] as? Bool == true
            let internalMedia = info["OSInternalMedia"] as? Bool == true
            let internalBus = info["Internal"] as? Bool == true && bus != "Secure Digital"
            let registryID = mediaRegistryID(for: id)
            let manageable = writable && removable && !internalMedia && !internalBus && size > 0 && registryID != nil
            let partitions = (entry["Partitions"] as? [[String: Any]] ?? []).flatMap { part -> [ManagedPartition] in
                guard let partID = part["DeviceIdentifier"] as? String, validID(partID) else { return [] }
                let apfs = apfsByStore[partID]
                let mountPoint = part["MountPoint"] as? String
                let fileSystem = mountPoint.flatMap {
                    (try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]))?
                        .volumeLocalizedFormatDescription
                }
                let physical = ManagedPartition(
                    id: partID, name: part["VolumeName"] as? String ?? partID,
                    content: part["Content"] as? String ?? "Unknown",
                    size: (part["Size"] as? NSNumber)?.int64Value ?? 0,
                    mountPoint: mountPoint,
                    uuid: part["VolumeUUID"] as? String,
                    fileSystem: fileSystem,
                    apfsContainer: apfs?.reference
                )
                return [physical] + (apfs?.volumes ?? [])
            }
            return ManagedDisk(id: id, name: name, size: size, bus: bus, scheme: scheme,
                               devicePath: path, writable: writable, manageable: manageable,
                               mediaRegistryID: registryID,
                               partitions: partitions)
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func run(_ request: DiskRequest) throws -> String {
        guard validID(request.disk.id), request.partition.map({ validID($0.id) }) ?? true else {
            throw DiskManagementError.invalidDevice
        }
        let arguments = try request.arguments()
        let current = try inventory().first { $0.id == request.disk.id }
        guard let current, current.identity == request.disk.identity else {
            throw DiskManagementError.changedDevice
        }
        if let partition = request.partition {
            guard current.partitions.contains(where: {
                $0.id == partition.id && ($0.isAPFSVolume || $0.size == partition.size) &&
                    $0.content == partition.content && $0.uuid == partition.uuid &&
                    $0.apfsContainer == partition.apfsContainer && $0.isAPFSVolume == partition.isAPFSVolume
            }) else { throw DiskManagementError.changedDevice }
        }
        guard request.action == .verify || current.manageable else {
            throw DiskManagementError.unsafeDevice
        }
        let output = try execute(arguments)
        return String(decoding: output, as: UTF8.self)
    }

    private static func plist(_ arguments: [String]) throws -> [String: Any] {
        let data = try execute(arguments, plistOutput: true)
        guard let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DiskManagementError.command("Could not read disk details from macOS.")
        }
        return value
    }

    private static func execute(_ arguments: [String], plistOutput: Bool = false) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = plistOutput ? FileHandle.nullDevice : pipe
        let confirmsForcedMerge = arguments.starts(with: ["mergePartitions", "force"])
        let confirmation = confirmsForcedMerge ? Pipe() : nil
        process.standardInput = FileHandle.nullDevice
        if let confirmation { process.standardInput = confirmation }
        try process.run()
        if let confirmation {
            confirmation.fileHandleForWriting.write(Data("y\n".utf8))
            try? confirmation.fileHandleForWriting.close()
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if confirmsForcedMerge, String(decoding: output, as: UTF8.self).contains("Merge canceled") {
            throw DiskManagementError.command("macOS canceled the partition merge; the disk was not changed.")
        }
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw DiskManagementError.command(detail.isEmpty ? "Disk Utility could not complete the operation." : detail)
        }
        return output
    }

    private static func validID(_ id: String) -> Bool {
        id.range(of: "^disk[0-9]+(s[0-9]+)?$", options: .regularExpression) != nil
    }

    private static func mediaRegistryID(for diskID: String) -> UInt64? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, diskID) else { return nil }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard media != 0 else { return nil }
        defer { IOObjectRelease(media) }
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(media, &id) == KERN_SUCCESS ? id : nil
    }

    static func singleAPFSStoreID(_ stores: [[String: Any]]) -> String? {
        guard stores.count == 1, let id = stores[0]["DeviceIdentifier"] as? String,
              validID(id) else { return nil }
        return id
    }
}
