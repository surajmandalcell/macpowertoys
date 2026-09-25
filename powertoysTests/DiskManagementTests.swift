import XCTest
@testable import powertoys

final class DiskManagementTests: XCTestCase {
    private let card = ManagedDisk(
        id: "disk10", name: "SDXC Reader", size: 15_634_268_160,
        bus: "Secure Digital", scheme: "GUID_partition_scheme", devicePath: "reader", writable: true,
        manageable: true, partitions: [
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
}
