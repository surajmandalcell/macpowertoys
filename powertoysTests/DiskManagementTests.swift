import XCTest
@testable import powertoys

final class DiskManagementTests: XCTestCase {
    private let card = ManagedDisk(
        id: "disk10", name: "SDXC Reader", size: 15_634_268_160,
        bus: "Secure Digital", scheme: "GUID_partition_scheme", devicePath: "reader", writable: true,
        manageable: true, mediaRegistryID: 1, partitions: [
            ManagedPartition(id: "disk10s1", name: "Data", content: "Microsoft Basic Data",
                             size: 4_000_000_000, mountPoint: "/Volumes/Data", uuid: "volume-id")
        ]
    )

    func testDestructiveCommandsTargetOnlyTheReviewedDevice() throws {
        let erase = DiskRequest(disk: card, partition: nil, action: .eraseDisk,
                                name: "Diskman", format: "ExFAT", scheme: "GPT", size: "4G")
        XCTAssertEqual(try erase.arguments(), ["eraseDisk", "ExFAT", "Diskman", "GPT", "disk10"])

        let partition = DiskRequest(disk: card, partition: card.partitions[0], action: .deletePartition,
                                    name: "", format: "", scheme: "", size: "")
        XCTAssertEqual(try partition.arguments(), ["eraseVolume", "free", "free", "disk10s1"])

        let wrongTarget = DiskRequest(disk: card, partition: nil, action: .eraseVolume,
                                      name: "Data", format: "ExFAT", scheme: "GPT", size: "4G")
        XCTAssertThrowsError(try wrongTarget.arguments())
    }

    func testPartitionInputRejectsMalformedSizesAndNames() throws {
        let malformed = DiskRequest(disk: card, partition: nil, action: .partitionDisk,
                                    name: "Data", format: "ExFAT", scheme: "GPT", size: "4G;eraseDisk")
        XCTAssertThrowsError(try malformed.arguments())

        let invalidName = DiskRequest(disk: card, partition: nil, action: .eraseDisk,
                                      name: "Other/Device", format: "ExFAT", scheme: "GPT", size: "4G")
        XCTAssertThrowsError(try invalidName.arguments())

        let longFATName = DiskRequest(disk: card, partition: nil, action: .addPartition,
                                      name: "DiskmanAdded", format: "ExFAT", scheme: "GPT", size: "2G")
        XCTAssertThrowsError(try longFATName.arguments())

        let tooLarge = DiskRequest(disk: card, partition: nil, action: .addPartition,
                                   name: "Small", format: "ExFAT", scheme: "GPT", size: "15G")
        XCTAssertThrowsError(try tooLarge.arguments())

        let wrongAPFSMap = DiskRequest(disk: card, partition: nil, action: .eraseDisk,
                                       name: "APFSTest", format: "APFS", scheme: "MBR", size: "")
        XCTAssertThrowsError(try wrongAPFSMap.arguments())

        let wholeDiskRepair = DiskRequest(disk: card, partition: nil, action: .repair,
                                          name: "", format: "", scheme: "", size: "")
        XCTAssertThrowsError(try wholeDiskRepair.arguments())

        let unsupportedResize = DiskRequest(disk: card, partition: card.partitions[0], action: .resizePartition,
                                            name: "", format: "", scheme: "", size: "R")
        XCTAssertThrowsError(try unsupportedResize.arguments())
    }

    func testAPFSOperationsUseContainerAndVolumeIdentifiers() throws {
        let store = ManagedPartition(id: "disk10s2", name: "APFS", content: "Apple_APFS",
                                     size: 8_000_000_000, mountPoint: nil, uuid: nil,
                                     apfsContainer: "disk13")
        let volume = ManagedPartition(id: "disk13s2", name: "Extra", content: "APFS Volume",
                                      size: 20_000_000, mountPoint: "/Volumes/Extra", uuid: "volume-id",
                                      apfsContainer: "disk13", isAPFSVolume: true)
        let add = DiskRequest(disk: card, partition: store, action: .addAPFSVolume,
                              name: "Extra", format: "APFS", scheme: "GPT", size: "")
        XCTAssertEqual(try add.arguments(), ["apfs", "addVolume", "disk13", "APFS", "Extra"])
        let delete = DiskRequest(disk: card, partition: volume, action: .deleteAPFSVolume,
                                 name: "", format: "", scheme: "", size: "")
        XCTAssertEqual(try delete.arguments(), ["apfs", "deleteVolume", "disk13s2"])
    }

    func testAPFSOperationsRejectSharedOrChangedContainers() {
        XCTAssertEqual(DiskManagement.singleAPFSStoreID([["DeviceIdentifier": "disk10s2"]]), "disk10s2")
        XCTAssertNil(DiskManagement.singleAPFSStoreID([
            ["DeviceIdentifier": "disk10s2"], ["DeviceIdentifier": "disk0s2"]
        ]))

        func disk(container: String) -> ManagedDisk {
            ManagedDisk(id: card.id, name: card.name, size: card.size, bus: card.bus,
                        scheme: card.scheme, devicePath: card.devicePath, writable: true,
                        manageable: true, mediaRegistryID: card.mediaRegistryID, partitions: [
                            ManagedPartition(id: "disk10s2", name: "APFS", content: "Apple_APFS",
                                             size: 8_000_000_000, mountPoint: nil, uuid: nil,
                                             apfsContainer: container)
                        ])
        }
        XCTAssertNotEqual(disk(container: "disk13").identity, disk(container: "disk0").identity)
    }

    func testReplacingMediaInvalidatesReviewedDiskIdentity() {
        let replacement = ManagedDisk(
            id: card.id, name: card.name, size: card.size, bus: card.bus,
            scheme: card.scheme, devicePath: card.devicePath, writable: card.writable,
            manageable: true, mediaRegistryID: 2, partitions: card.partitions
        )
        XCTAssertNotEqual(card.identity, replacement.identity)
    }

    func testMergeOnlyTargetsTheNextDataPartitionAndStatesWhetherItErases() throws {
        let first = ManagedPartition(id: "disk10s2", name: "Keep", content: "Apple_HFS",
                                     size: 4_000_000_000, mountPoint: "/Volumes/Keep", uuid: "keep",
                                     fileSystem: "Mac OS Extended (Journaled)")
        let next = ManagedPartition(id: "disk10s3", name: "Remove", content: "Microsoft Basic Data",
                                    size: 4_000_000_000, mountPoint: "/Volumes/Remove", uuid: "remove",
                                    fileSystem: "ExFAT")
        let disk = ManagedDisk(id: card.id, name: card.name, size: card.size, bus: card.bus,
                               scheme: card.scheme, devicePath: card.devicePath, writable: true,
                               manageable: true, mediaRegistryID: card.mediaRegistryID,
                               partitions: [card.partitions[0], first, next])
        let preserve = DiskRequest(disk: disk, partition: first, action: .mergePartitions,
                                   name: "Keep", format: "JHFS+", scheme: "", size: "")
        XCTAssertEqual(try preserve.arguments(),
                       ["mergePartitions", "JHFS+", "Keep", "disk10s2", "disk10s3"])

        let exfatDisk = ManagedDisk(id: disk.id, name: disk.name, size: disk.size, bus: disk.bus,
                                    scheme: disk.scheme, devicePath: disk.devicePath, writable: true,
                                    manageable: true, mediaRegistryID: disk.mediaRegistryID,
                                    partitions: [card.partitions[0], next,
                                                 ManagedPartition(id: "disk10s4", name: "Third",
                                                                  content: "Microsoft Basic Data", size: 2_000_000_000,
                                                                  mountPoint: "/Volumes/Third", uuid: "third",
                                                                  fileSystem: "ExFAT")])
        let destructive = DiskRequest(disk: exfatDisk, partition: next, action: .mergePartitions,
                                      name: "Combined", format: "ExFAT", scheme: "", size: "")
        XCTAssertEqual(try destructive.arguments(),
                       ["mergePartitions", "force", "ExFAT", "Combined", "disk10s3", "disk10s4"])
        let efi = ManagedPartition(id: "disk10s1", name: "EFI", content: "EFI",
                                   size: 209_715_200, mountPoint: nil, uuid: nil)
        let efiDisk = ManagedDisk(id: disk.id, name: disk.name, size: disk.size, bus: disk.bus,
                                  scheme: disk.scheme, devicePath: disk.devicePath, writable: true,
                                  manageable: true, mediaRegistryID: disk.mediaRegistryID,
                                  partitions: [efi, first, next])
        XCTAssertThrowsError(try DiskRequest(disk: efiDisk, partition: efi,
                                              action: .mergePartitions, name: "EFI", format: "ExFAT",
                                              scheme: "", size: "").arguments())
        XCTAssertThrowsError(try DiskRequest(disk: exfatDisk, partition: exfatDisk.partitions[2],
                                              action: .mergePartitions, name: "Last", format: "ExFAT",
                                              scheme: "", size: "").arguments())
    }
}
